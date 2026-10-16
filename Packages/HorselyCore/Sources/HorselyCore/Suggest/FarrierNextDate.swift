import Foundation

/// Podpowiedzi jak w programie (FR-M-WPI-04); wartości wpisane ręcznie zawsze wygrywają.
public enum FarrierNextDate {
    /// Następna wizyta kowala: z programu (`/horses/{id}/farrier-next-date`), a bez połączenia (i w trybie samodzielnym) — data wizyty
    /// plus interwał konia. Bez interwału nie ma podpowiedzi.
    public static func suggest(online: LocalDate? = nil, visitDate: LocalDate, intervalWeeks: Int?) -> LocalDate? {
        if let online { return online }
        guard let weeks = intervalWeeks, weeks > 0 else { return nil }
        return visitDate.adding(days: weeks * 7)
    }
}
