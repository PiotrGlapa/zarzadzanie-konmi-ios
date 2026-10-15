/// Ocena (treningu, startu) jako gwiazdki — tak jak w programie (`StarRating.Format`): „★” × ocena + „☆” × reszta do pięciu.
/// Zmienia się tylko prezentacja: wartość z programu zostaje liczbą 1–5, a średnie ocen — liczbami ułamkowymi.
public enum Stars {
    public static let max = 5

    /// „★★★☆☆” dla 3; `nil` dla braku oceny i wartości spoza 1–5 (UI pokazuje wtedy „—”).
    public static func format(_ rating: Int?) -> String? {
        guard let rating, (1...max).contains(rating) else { return nil }
        return String(repeating: "★", count: rating) + String(repeating: "☆", count: max - rating)
    }
}
