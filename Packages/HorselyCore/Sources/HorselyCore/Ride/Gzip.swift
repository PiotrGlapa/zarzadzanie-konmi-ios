import Compression
import Foundation

/// Gzip (RFC 1952) na systemowym `Compression` — bez zależności zewnętrznych. `COMPRESSION_ZLIB` to surowy strumień deflate (RFC 1951)
/// bez nagłówka i stopki, więc nagłówek (10 B), sumę kontrolną CRC32 i długość ISIZE dokładamy sami: wynik jest zwykłym plikiem gzip
/// (`1f 8b 08 …`), który czyta Android (`GZIPInputStream`) i każdy inny czytnik.
enum Gzip {
    /// Gzip z `data`. Bajty zależą od kompresora (poziom, wersja zlib); stabilny jest tylko dokument po rozpakowaniu.
    static func compress(_ data: Data) throws -> Data {
        let input = [UInt8](data)
        let deflated = try process(input, encode: true, limit: Int.max)
        var out: [UInt8] = []
        out.reserveCapacity(deflated.count + 18)
        // ID1 ID2, CM = 8 (deflate), FLG = 0, MTIME = 0 (4 B), XFL = 0, OS = 0 (jak `GZIPOutputStream` w Javie)
        out += [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        out += deflated
        appendLittleEndian(&out, crc32(input))
        appendLittleEndian(&out, UInt32(truncatingIfNeeded: input.count))
        return Data(out)
    }

    /// Rozpakowuje gzip (jeden element, tak jak zapisują Android i iOS). Rzuca `ZkTrackError`, gdy dane nie są poprawnym gzipem,
    /// suma kontrolna albo długość w stopce się nie zgadza, albo wynik przekroczyłby `limit` bajtów („bomba” gzip).
    static func decompress(_ data: Data, limit: Int) throws -> Data {
        let input = [UInt8](data)
        guard input.count >= 18, input[0] == 0x1F, input[1] == 0x8B else { throw ZkTrackError.notGzip }
        guard input[2] == 8 else { throw ZkTrackError.notGzip }
        let flags = input[3]
        var position = 10
        if flags & 0x04 != 0 { // FEXTRA: długość (2 B) i dane
            guard position + 2 <= input.count else { throw ZkTrackError.notGzip }
            position += 2 + (Int(input[position]) | Int(input[position + 1]) << 8)
        }
        if flags & 0x08 != 0 { position = try skipZeroTerminated(input, from: position) } // FNAME
        if flags & 0x10 != 0 { position = try skipZeroTerminated(input, from: position) } // FCOMMENT
        if flags & 0x02 != 0 { position += 2 } // FHCRC
        let trailerStart = input.count - 8
        guard position < trailerStart else { throw ZkTrackError.notGzip }

        let output = try process(Array(input[position ..< trailerStart]), encode: false, limit: limit)
        guard readLittleEndian(input, at: trailerStart) == crc32(output),
              readLittleEndian(input, at: trailerStart + 4) == UInt32(truncatingIfNeeded: output.count)
        else { throw ZkTrackError("Trasa jest uszkodzona (zła suma kontrolna gzip).") }
        return Data(output)
    }

    // MARK: - CRC32 (wielomian 0xEDB88320, jak w RFC 1952)

    private static let crcTable: [UInt32] = (0 ..< 256).map { (n: Int) -> UInt32 in
        var c = UInt32(n)
        for _ in 0 ..< 8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }

    // MARK: - Pomocnicze

    private static func appendLittleEndian(_ out: inout [UInt8], _ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            out.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private static func readLittleEndian(_ bytes: [UInt8], at index: Int) -> UInt32 {
        var value: UInt32 = 0
        for offset in 0 ..< 4 {
            value |= UInt32(bytes[index + offset]) << UInt32(8 * offset)
        }
        return value
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < bytes.count {
            if bytes[index] == 0 { return index + 1 }
            index += 1
        }
        throw ZkTrackError.notGzip
    }

    /// Surowy deflate przez `compression_stream`; całe wejście podajemy naraz, wyjście odbieramy porcjami po 64 KiB.
    /// Przy rozpakowaniu przerywa, gdy wynik przekroczy `limit`.
    private static func process(_ input: [UInt8], encode: Bool, limit: Int) throws -> [UInt8] {
        let chunkSize = 64 * 1024
        let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer {
            scratch.deallocate()
            destination.deallocate()
        }
        var stream = compression_stream(dst_ptr: scratch, dst_size: 0, src_ptr: UnsafePointer(scratch), src_size: 0, state: nil)
        let operation = encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw ZkTrackError("Nie udało się uruchomić kompresji.")
        }
        defer { compression_stream_destroy(&stream) }

        let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
        var output: [UInt8] = []
        try input.withUnsafeBufferPointer { source in
            stream.src_ptr = source.baseAddress ?? UnsafePointer(scratch)
            stream.src_size = source.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = chunkSize
                let status = compression_stream_process(&stream, flags)
                let produced = chunkSize - stream.dst_size
                if produced > 0 {
                    output.append(contentsOf: UnsafeBufferPointer(start: destination, count: produced))
                    if output.count > limit { throw ZkTrackError.tooLarge }
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return
                case COMPRESSION_STATUS_OK:
                    if produced == 0 && stream.src_size == 0 {
                        // Przy rozpakowaniu: całe wejście zużyte, a koniec strumienia niezgłoszony. Ucięty strumień wyłapie
                        // sprawdzenie CRC32 i ISIZE w `decompress`; przy kompresji to błąd.
                        if encode { throw ZkTrackError("Kompresja nie zakończyła się.") }
                        return
                    }
                default:
                    throw ZkTrackError.notGzip
                }
            }
        }
        return output
    }
}
