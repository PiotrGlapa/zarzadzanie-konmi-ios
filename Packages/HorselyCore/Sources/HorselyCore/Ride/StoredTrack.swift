import Foundation

/// Trasa nagrania (tabela `local_track`, Android `StoredTrack`): bajty `trackData` w formacie `format` (np. `zk-track/1`) i wersja
/// nagrania, z którą je pobrano. Trzymana osobno od rekordu nagrania — rekord nie niesie `trackData` (decyzja A4). W rdzeniu, bo
/// niesie ją też plik eksportu 1.6 (`ExportedRecord.track`) — kopia zapasowa i pełne pobranie z programu.
public struct StoredTrack: Sendable, Hashable {
    public var recordingId: String
    public var version: Int
    public var format: String
    public var data: Data

    public init(recordingId: String, version: Int, format: String, data: Data) {
        self.recordingId = recordingId
        self.version = version
        self.format = format
        self.data = data
    }
}
