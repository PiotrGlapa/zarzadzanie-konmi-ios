import Foundation

/// Co zrobić z filmem przed wysłaniem (decyzja A10).
public enum VideoDecision: Equatable, Sendable {
    /// Film idzie bez zmian (przy `VideoPolicy.afterTranscode` — „wynik przekodowania jest w porządku”).
    case keepOriginal
    /// Film trzeba zmniejszyć do 720p (krótszy bok), H.264/AAC.
    case transcode
    /// Film nie zmieści się w limicie nawet po zmniejszeniu; komunikat po polsku do pokazania użytkownikowi.
    case reject(String)
}

/// Reguły filmów (decyzja A10, ZAT-03, `VideoPolicy.kt` Androida): przekodowanie do 720p, gdy krótszy bok > 720 px albo plik ma 100 MB
/// lub więcej (limit załącznika serwera to „mniej niż 100 MB” — `canSendOriginal`); mniejsze filmy idą bez zmian. Wynik przekodowania
/// większy niż limit jest odrzucany. Czysta logika — samo przekodowanie robi `VideoPreparer` w HorselyKit.
public enum VideoPolicy {
    /// Krótszy bok po zmniejszeniu (piksele).
    public static let targetShortSidePx = 720

    private static let megabyte: Int64 = 1024 * 1024
    private static let maxBytes: Int64 = FilePolicy.maxBytes

    /// Przełącznik „Wyślij oryginał” ma sens tylko poniżej 100 MB — większego pliku program nie przyjmie.
    public static func canSendOriginal(sizeBytes: Int64) -> Bool { sizeBytes < maxBytes }

    /// Decyzja dla filmu o krótszym boku `shortSidePx` (po uwzględnieniu obrotu) i rozmiarze `sizeBytes`. „Wyślij oryginał”
    /// (`sendOriginal`) zostawia plik tylko wtedy, gdy mieści się w limicie.
    public static func decide(shortSidePx: Int, sizeBytes: Int64, sendOriginal: Bool) -> VideoDecision {
        if !canSendOriginal(sizeBytes: sizeBytes) { return .transcode }
        if sendOriginal { return .keepOriginal }
        return shortSidePx > targetShortSidePx ? .transcode : .keepOriginal
    }

    /// Sprawdzenie wyniku przekodowania: `.keepOriginal` (plik gotowy) albo `.reject` z komunikatem, gdy film po zmniejszeniu nadal nie
    /// mieści się w 100 MB. Komunikat jest stały: najdłuższy film to ok. 5 min (typowy film 720p z nagrywania); `durationSeconds` zostaje
    /// w podpisie dla wołających, ale nie wpływa na tekst (jak w Androidzie).
    public static func afterTranscode(sizeBytes: Int64, durationSeconds: Int) -> VideoDecision {
        if canSendOriginal(sizeBytes: sizeBytes) { return .keepOriginal }
        let sizeMegabytes = (sizeBytes + megabyte - 1) / megabyte
        return .reject("Film jest za długi — nawet po zmniejszeniu do 720p ma \(sizeMegabytes) MB (najwięcej 100 MB). Najdłuższy film to ok. 5 min.")
    }
}
