import Foundation

/// Komunikaty reguł wpisów — dosłowne teksty z zasobów programu (`ValidationMessages.resx`), jak w Androidzie (`Messages.kt`).
public extension Messages {
    static let foreignAmountIncomplete = "Podaj kwotę i walutę oryginalną razem albo zostaw oba pola puste."
    static let currencyFormat = "Kod waluty to 3 wielkie litery, np. EUR."
    static let currencyNotPln = "Kwota w walucie oryginalnej dotyczy walut innych niż PLN."
    static let nextVisitAfterVisit = "Następna wizyta musi być późniejsza niż data wizyty."
    static let medicationEndBeforeStart = "Data końca podawania leku nie może być wcześniejsza niż data początku."
    static let invalidDictionaryValue = "Wybrana wartość nie należy do właściwego słownika."
    static let horseNotFound = "Wybrany koń nie istnieje lub jest w koszu."
    static let contactNotTrainer = "Wybrany kontakt nie ma typu Trener."
    static let contactNotRider = "Wskazany kontakt nie ma typu „Jeździec”."
    static let contactNotFound = "Wybrany kontakt nie istnieje lub jest w koszu."
    static let batchHorsesDuplicated = "Każdy koń może wystąpić na liście tylko raz."
    static let specialistTypeRequired = "Dla terminu specjalisty wybierz rodzaj specjalisty."
    static let reminderNotOpen = "Tę operację można wykonać tylko dla otwartego terminu."
    static let purchaseSingleHorse = "Dla zakupu „jeden koń” wybierz dokładnie jednego konia."
    static let purchaseMultipleHorses = "Dla zakupu „kilka koni” wybierz co najmniej dwa konie."
    static let purchaseGeneralHorses = "Zakup ogólny (cała stajnia) nie może mieć przypisanych koni."
    static let amountPositive = "Kwota musi być większa od zera."
    static let quantityPositive = "Ilość musi być większa od zera."
    static let dateToBeforeFrom = "Data zakończenia nie może być wcześniejsza niż data rozpoczęcia."
    static let placementOnlyCompleted = "Miejsce można podać tylko dla ukończonego startu."
    static let participantsBelowPlacement = "Liczba startujących nie może być mniejsza niż zajęte miejsce."
    static let atLeastOne = "Wartość musi wynosić co najmniej 1."
    static let nonNegative = "Wartość nie może być ujemna."
    static let percentRange = "Wynik procentowy musi mieścić się w zakresie 0–100."
    static let positiveNumber = "Wartość musi być większa od zera."
    static let ratingRange = "Ocena musi mieścić się w zakresie 1–5."
    static let competitionNotFound = "Wybrane zawody nie istnieją lub są w koszu."
    static let trainingDateInFuture = "Data treningu nie może być z przyszłości."
    static let trainingDurationRange = "Czas treningu musi mieścić się w zakresie 1–600 minut."
    static let obstacleHeightRange = "Wysokość przeszkód musi mieścić się w zakresie 10–200 cm."
    static let obstacleHeightOnlyJumping = "Wysokość przeszkód można podać tylko dla treningu „Skoki”."
    static let invalidTrainingType = "Wybrany rodzaj treningu nie istnieje, nie jest aktywny albo nie należy do słownika rodzajów treningu."
    static let trainingBeforeBirth = "Data treningu jest wcześniejsza niż data urodzenia konia."
    static let contactInUse = "Kontakt jest używany we wpisach, więc nie można go usunąć. Możesz go zarchiwizować."
    static let trashBatchNotFound = "Nie znaleziono pozycji w koszu."
    static let reminderKindFarrier = "Kowal"
    static let reminderKindPhysio = "Fizjoterapeuta"

    static func startDateOutsideCompetition(from: LocalDate, to: LocalDate) -> String {
        "Dzień startu musi przypadać w dniach zawodów (\(Formats.date(from))–\(Formats.date(to)))."
    }

    static func startsOutsideCompetition(_ list: String) -> String {
        "Nowe daty zawodów pomijają starty: \(list). Najpierw zmień ich dzień startu."
    }

    static func reminderTitle(subject: String, horse: String) -> String {
        "\(subject) — \(horse)"
    }
}

extension ValidationReport {
    mutating func required<T>(_ field: String, _ value: T?) {
        if value == nil { error(field, Messages.required) }
    }

    mutating func required(_ field: String, text: String?) {
        if HorseRules.clean(text) == nil { error(field, Messages.required) }
    }

    /// Kwota w walucie oryginalnej: obie wartości razem albo żadna; kod ISO 4217 wielkimi literami, nie PLN.
    mutating func foreignAmount(_ amount: Money?, _ currency: String?, prefix: String = "") {
        let hasCurrency = !(currency?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        if amount != nil, !hasCurrency { error(prefix + "originalCurrency", Messages.foreignAmountIncomplete) }
        if hasCurrency, amount == nil { error(prefix + "originalAmount", Messages.foreignAmountIncomplete) }
        money(prefix + "originalAmount", amount)
        if hasCurrency, let currency {
            if currency.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) == nil { error(prefix + "originalCurrency", Messages.currencyFormat) }
            if currency == "PLN" { error(prefix + "originalCurrency", Messages.currencyNotPln) }
        }
    }
}

/// Walidacja pól wpisów (bez zapytań do bazy) — port walidatorów programu (`**/*Validator.cs`). Komunikaty i klucze pól jak w programie;
/// reguły wymagające bazy (istnienie konia, rodzaj słownika, unikalność) są w `RuleEngine`.
public enum EntryValidation {
    // MARK: Wizyty

    public static func vet(_ input: VetVisitInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.required("visitDateTime", input.visitDateTime)
        report.required("visitTypeId", text: input.visitTypeId)
        if let next = input.nextVisitDate, let at = input.visitDateTime, !(next > at.date) { report.error("nextVisitDate", Messages.nextVisitAfterVisit) }
        report.maxLength("nextVisitPurpose", input.nextVisitPurpose, 200)
        report.maxLength("vaccineOrProduct", input.vaccineOrProduct, 200)
        report.maxLength("batchNumber", input.batchNumber, 50)
        report.money("cost", input.cost)
        report.foreignAmount(input.originalAmount, input.originalCurrency)
        for (index, medication) in (input.medications ?? []).enumerated() {
            let prefix = "medications[\(index)]."
            report.notBlank(prefix + "name", medication.name)
            report.maxLength(prefix + "name", medication.name, 200)
            report.maxLength(prefix + "dosage", medication.dosage, 200)
            if let start = medication.startDate, let end = medication.endDate, end < start { report.error(prefix + "endDate", Messages.medicationEndBeforeStart) }
        }
        return report
    }

    public static func farrier(_ input: FarrierVisitInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.required("visitDate", input.visitDate)
        report.required("serviceId", text: input.serviceId)
        if let next = input.nextVisitDate, let date = input.visitDate, !(next > date) { report.error("nextVisitDate", Messages.nextVisitAfterVisit) }
        report.money("cost", input.cost)
        report.foreignAmount(input.originalAmount, input.originalCurrency)
        return report
    }

    public static func physio(_ input: PhysioVisitInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.required("visitDate", input.visitDate)
        if let next = input.nextVisitDate, let date = input.visitDate, !(next > date) { report.error("nextVisitDate", Messages.nextVisitAfterVisit) }
        report.maxLength("nextVisitPurpose", input.nextVisitPurpose, 200)
        report.money("cost", input.cost)
        report.foreignAmount(input.originalAmount, input.originalCurrency)
        return report
    }

    public static func specialist(_ input: SpecialistVisitInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.required("visitDate", input.visitDate)
        report.required("specialistTypeId", text: input.specialistTypeId)
        if let next = input.nextVisitDate, let date = input.visitDate, !(next > date) { report.error("nextVisitDate", Messages.nextVisitAfterVisit) }
        report.maxLength("nextVisitPurpose", input.nextVisitPurpose, 200)
        report.money("cost", input.cost)
        report.foreignAmount(input.originalAmount, input.originalCurrency)
        return report
    }

    // MARK: Zawody i starty

    public static func competition(_ input: CompetitionInput) -> ValidationReport {
        var report = ValidationReport()
        report.notBlank("name", input.name)
        report.maxLength("name", input.name, 200)
        report.required("dateFrom", input.dateFrom)
        if let to = input.dateTo, let from = input.dateFrom, to < from { report.error("dateTo", Messages.dateToBeforeFrom) }
        report.maxLength("city", input.city, 100)
        report.maxLength("venue", input.venue, 200)
        return report
    }

    /// Status wyniku bez statusu, ale z miejscem/punktami/wynikiem/czasem oznacza start ukończony (`CompetitionStartRules.Normalize`).
    public static func normalizedStatus(_ input: CompetitionStartInput) -> ResultStatus? {
        let hasResult = input.placement != nil || input.penaltyPoints != nil || input.scorePercent != nil || input.timeSeconds != nil
        return input.resultStatus ?? (hasResult ? .completed : nil)
    }

    public static func start(_ input: CompetitionStartInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.maxLength("className", input.className, 100)
        let status = normalizedStatus(input)
        if let placement = input.placement {
            if placement < 1 { report.error("placement", Messages.atLeastOne) }
            if let status, status != .completed { report.error("placement", Messages.placementOnlyCompleted) }
        }
        if let participants = input.participantsCount {
            if participants < 1 { report.error("participantsCount", Messages.atLeastOne) }
            if let placement = input.placement, participants < placement { report.error("participantsCount", Messages.participantsBelowPlacement) }
        }
        if let points = input.penaltyPoints, points.value < 0 { report.error("penaltyPoints", Messages.nonNegative) }
        if let score = input.scorePercent, score.value < 0 || score.value > 100 { report.error("scorePercent", Messages.percentRange) }
        if let time = input.timeSeconds, time.value <= 0 { report.error("timeSeconds", Messages.positiveNumber) }
        if let rating = input.subjectiveRating, !(1...5).contains(rating) { report.error("subjectiveRating", Messages.ratingRange) }
        report.money("entryFee", input.entryFee)
        report.money("otherCosts", input.otherCosts)
        report.money("prizeMoney", input.prizeMoney)
        report.foreignAmount(input.originalAmount, input.originalCurrency)
        return report
    }

    // MARK: Zakup, notatka, trening, termin

    public static func purchase(_ input: PurchaseInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("purchaseDate", input.purchaseDate)
        report.notBlank("productName", input.productName)
        report.maxLength("productName", input.productName, 200)
        report.required("categoryId", text: input.categoryId)
        let total = input.totalAmount ?? .zero
        let delivery = input.deliveryCost ?? .zero
        if delivery.value <= 0, total.value <= 0 { report.error("totalAmount", Messages.amountPositive) }
        if total.value < 0 { report.error("totalAmount", Messages.nonNegative) }
        report.money("totalAmount", total)
        if delivery.value < 0 { report.error("deliveryCost", Messages.nonNegative) }
        report.money("deliveryCost", delivery)
        if let quantity = input.quantity, quantity.value <= 0 { report.error("quantity", Messages.quantityPositive) }
        report.money("unitPrice", input.unitPrice)
        report.required("assignment", input.assignment)
        let ids = input.horseIds ?? []
        if Set(ids).count != ids.count { report.error("horseIds", Messages.batchHorsesDuplicated) }
        switch input.assignment {
        case .singleHorse where ids.count != 1: report.error("horseIds", Messages.purchaseSingleHorse)
        case .multipleHorses where ids.count < 2: report.error("horseIds", Messages.purchaseMultipleHorses)
        case .general where !ids.isEmpty: report.error("horseIds", Messages.purchaseGeneralHorses)
        default: break
        }
        report.foreignAmount(input.originalAmount, input.originalCurrency)
        return report
    }

    public static func note(_ input: NoteInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.notBlank("title", input.title)
        report.maxLength("title", input.title, 200)
        return report
    }

    public static func training(_ input: TrainingInput, today: LocalDate) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.required("trainingTypeId", text: input.trainingTypeId)
        report.required("trainingDate", input.trainingDate)
        report.futureDate("trainingDate", input.trainingDate, today: today, message: Messages.trainingDateInFuture)
        if let minutes = input.durationMinutes, !(1...600).contains(minutes) { report.error("durationMinutes", Messages.trainingDurationRange) }
        if let height = input.obstacleHeightCm, !(10...200).contains(height) { report.error("obstacleHeightCm", Messages.obstacleHeightRange) }
        if let rating = input.rating, !(1...5).contains(rating) { report.error("rating", Messages.ratingRange) }
        if let coaching = input.coaching {
            report.money("coaching.cost", coaching.cost)
            report.foreignAmount(coaching.originalAmount, coaching.originalCurrency, prefix: "coaching.")
        }
        return report
    }

    public static func reminder(_ input: ReminderInput) -> ValidationReport {
        var report = ValidationReport()
        report.required("horseId", text: input.horseId)
        report.required("dueDate", input.dueDate)
        if HorseRules.clean(input.title) == nil { report.error("title", Messages.required) }
        report.maxLength("title", input.title, 200)
        if (input.kind ?? .other) == .specialist, HorseRules.clean(input.specialistTypeId) == nil { report.error("specialistTypeId", Messages.specialistTypeRequired) }
        return report
    }
}
