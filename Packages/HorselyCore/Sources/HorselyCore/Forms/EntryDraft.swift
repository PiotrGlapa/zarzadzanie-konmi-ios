import Foundation

/// Lek wpisany w formularzu wizyty weterynaryjnej.
public struct MedicationDraft: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var name = ""
    public var dosage = ""
    public var startDate: LocalDate?
    public var endDate: LocalDate?
    public var administration: MedicationMode?

    public init() {}

    public init(_ medication: LocalVetMedication) {
        name = medication.name
        dosage = medication.dosage ?? ""
        startDate = medication.startDate
        endDate = medication.endDate
        administration = medication.administration
    }

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && startDate == nil && endDate == nil && administration == nil
    }
}

/// Wynik budowania treści zapisu z formularza: treść i błędy odczytu pól liczbowych (zanim reguły programu ocenią resztę).
public struct BuiltInput<Input: Sendable>: Sendable {
    public let input: Input
    public let parseErrors: [String: [String]]
}

/// Wszystkie pola formularzy wpisów jako tekst i proste wartości — jedno miejsce dla dziewięciu formularzy (FormSpec w aplikacji
/// wybiera, które pola pokazać). Zamiana na treść zapisu (`*Input`) i z powrotem z rekordu nie zależy od interfejsu, więc jest
/// testowana w rdzeniu. Kwoty to teksty z pola (przecinek lub kropka), puste = brak.
public struct EntryDraft: Equatable, Sendable {
    public var horseId: String?
    /// Kilka koni: kowal „Kilka koni” (osobny wpis na konia) i zakup „kilka koni” (podział kosztu).
    public var horseIds: [String] = []
    /// Kowal: przełącznik „Kilka koni”.
    public var manyHorses = false
    public var date: LocalDate?
    public var hour = 12
    public var minute = 0
    public var startDate: LocalDate?

    // Słowniki
    public var visitTypeId: String?
    public var farrierServiceId: String?
    public var specialistTypeId: String?
    public var trainingTypeId: String?
    public var categoryId: String?
    public var unitId: String?
    public var rankId: String?
    public var disciplineId: String?

    // Kontakty
    public var contactId: String?
    public var supplierId: String?
    public var organizerId: String?
    public var riderId: String?
    public var trainerId: String?
    public var bodyAreaIds: [String] = []
    public var techniqueIds: [String] = []

    // Teksty
    public var reason = ""
    public var diagnosis = ""
    public var recommendations = ""
    public var vaccineOrProduct = ""
    public var batchNumber = ""
    public var hoofNotes = ""
    public var observations = ""
    public var descriptionText = ""
    public var nextVisitPurpose = ""
    public var title = ""
    public var content = ""
    public var productName = ""
    public var notes = ""
    public var className = ""
    public var competitionName = ""
    public var city = ""
    public var venue = ""
    public var pinned = false
    public var medications: [MedicationDraft] = []

    // Kwoty i liczby jako tekst
    public var cost = ""
    public var originalAmount = ""
    public var originalCurrency = ""
    public var quantity = ""
    public var unitPrice = ""
    public var amount = ""
    public var deliveryCost = ""
    public var entryFee = ""
    public var otherCosts = ""
    public var prizeMoney = ""
    public var penaltyPoints = ""
    public var scorePercent = ""
    public var timeSeconds = ""
    public var placement = ""
    public var participants = ""
    public var duration = ""
    public var obstacleHeight = ""

    public var nextVisitDate: LocalDate?
    public var intensity: Intensity?
    public var resultStatus: ResultStatus?
    public var rating: Int?
    public var assignment: PurchaseAssignment = .singleHorse

    /// Start w zawodach: istniejące zawody (`competitionId`) albo nowe (`newCompetition`, nazwa + data + miejscowość).
    public var competitionId: String?
    public var newCompetition = false
    public var dateFrom: LocalDate?
    public var dateTo: LocalDate?

    public init() {}

    // MARK: Odczyt pól

    private struct Reader {
        var errors: [String: [String]] = [:]

        mutating func fail(_ key: String, _ message: String) {
            var list = errors[key] ?? []
            if !list.contains(message) { list.append(message) }
            errors[key] = list
        }

        /// Kwota w złotych do grosza.
        mutating func money(_ text: String, _ key: String) -> Money? {
            switch MoneyInput.parse(text) {
            case .empty: return nil
            case let .valid(value): return value
            case let .invalid(reason): fail(key, reason.message); return nil
            }
        }

        /// Liczba dziesiętna bez zaokrąglania (ilość, cena jednostkowa, punkty, czas).
        mutating func decimal(_ text: String, _ key: String, scale: Int = 4) -> Money? {
            switch MoneyInput.parseDecimal(text, maxScale: scale) {
            case .empty: return nil
            case let .valid(value): return value
            case let .invalid(reason): fail(key, reason.message); return nil
            }
        }

        mutating func integer(_ text: String, _ key: String) -> Int? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            guard let value = Int(trimmed) else { fail(key, Messages.invalidValue); return nil }
            return value
        }
    }

    private static func text(_ value: String) -> String? { HorseRules.clean(value) }

    private static func currency(_ value: String) -> String? { text(value)?.uppercased() }

    private static func id(_ value: String?) -> String? { HorseRules.clean(value) }

    // MARK: Treść zapisu

    public var visitDateTime: LocalDateTime? { date.flatMap { LocalDateTime(date: $0, hour: hour, minute: minute) } }

    public func vetInput() -> BuiltInput<VetVisitInput> {
        var reader = Reader()
        var input = VetVisitInput()
        input.horseId = Self.id(horseId)
        input.visitDateTime = visitDateTime
        input.contactId = Self.id(contactId)
        input.visitTypeId = Self.id(visitTypeId)
        input.reason = Self.text(reason)
        input.diagnosis = Self.text(diagnosis)
        input.recommendations = Self.text(recommendations)
        input.vaccineOrProduct = Self.text(vaccineOrProduct)
        input.batchNumber = Self.text(batchNumber)
        input.cost = reader.money(cost, "cost")
        input.nextVisitDate = nextVisitDate
        input.nextVisitPurpose = Self.text(nextVisitPurpose)
        input.originalAmount = reader.money(originalAmount, "originalAmount")
        input.originalCurrency = Self.currency(originalCurrency)
        input.medications = medications.filter { !$0.isEmpty }.map { draft in
            VetMedicationInput(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), dosage: Self.text(draft.dosage), startDate: draft.startDate,
                endDate: draft.endDate, administration: draft.administration
            )
        }
        return BuiltInput(input: input, parseErrors: reader.errors)
    }

    /// Wizyta kowala dla jednego konia; „Kilka koni” woła to dla każdego zaznaczonego konia.
    public func farrierInput(horseId override: String? = nil) -> BuiltInput<FarrierVisitInput> {
        var reader = Reader()
        var input = FarrierVisitInput()
        input.horseId = Self.id(override ?? horseId)
        input.visitDate = date
        input.contactId = Self.id(contactId)
        input.serviceId = Self.id(farrierServiceId)
        input.hoofNotes = Self.text(hoofNotes)
        input.cost = reader.money(cost, "cost")
        input.nextVisitDate = nextVisitDate
        input.originalAmount = reader.money(originalAmount, "originalAmount")
        input.originalCurrency = Self.currency(originalCurrency)
        return BuiltInput(input: input, parseErrors: reader.errors)
    }

    public func physioInput() -> BuiltInput<PhysioVisitInput> {
        var reader = Reader()
        var input = PhysioVisitInput()
        input.horseId = Self.id(horseId)
        input.visitDate = date
        input.contactId = Self.id(contactId)
        input.reason = Self.text(reason)
        input.bodyAreaIds = bodyAreaIds
        input.techniqueIds = techniqueIds
        input.observations = Self.text(observations)
        input.recommendations = Self.text(recommendations)
        input.cost = reader.money(cost, "cost")
        input.nextVisitDate = nextVisitDate
        input.nextVisitPurpose = Self.text(nextVisitPurpose)
        input.originalAmount = reader.money(originalAmount, "originalAmount")
        input.originalCurrency = Self.currency(originalCurrency)
        return BuiltInput(input: input, parseErrors: reader.errors)
    }

    public func specialistInput() -> BuiltInput<SpecialistVisitInput> {
        var reader = Reader()
        var input = SpecialistVisitInput()
        input.horseId = Self.id(horseId)
        input.visitDate = date
        input.specialistTypeId = Self.id(specialistTypeId)
        input.contactId = Self.id(contactId)
        input.reason = Self.text(reason)
        input.description = Self.text(descriptionText)
        input.recommendations = Self.text(recommendations)
        input.cost = reader.money(cost, "cost")
        input.nextVisitDate = nextVisitDate
        input.nextVisitPurpose = Self.text(nextVisitPurpose)
        input.originalAmount = reader.money(originalAmount, "originalAmount")
        input.originalCurrency = Self.currency(originalCurrency)
        return BuiltInput(input: input, parseErrors: reader.errors)
    }

    public func noteInput() -> BuiltInput<NoteInput> {
        var input = NoteInput()
        input.horseId = Self.id(horseId)
        input.noteDate = date
        input.title = Self.text(title)
        input.content = Self.text(content)
        input.isPinned = pinned
        return BuiltInput(input: input, parseErrors: [:])
    }

    /// Zakup; „jeden koń” bierze `horseId`, „kilka koni” — `horseIds`, „ogólny” — żadnego konia.
    public func purchaseInput() -> BuiltInput<PurchaseInput> {
        var reader = Reader()
        var input = PurchaseInput()
        input.purchaseDate = date
        input.productName = Self.text(productName)
        input.categoryId = Self.id(categoryId)
        input.supplierContactId = Self.id(supplierId)
        input.quantity = reader.decimal(quantity, "quantity")
        input.unitId = Self.id(unitId)
        input.unitPrice = reader.decimal(unitPrice, "unitPrice")
        input.totalAmount = reader.money(amount, "totalAmount") ?? .zero
        input.deliveryCost = reader.money(deliveryCost, "deliveryCost") ?? .zero
        input.assignment = assignment
        switch assignment {
        case .singleHorse: input.horseIds = Self.id(horseId).map { [$0] } ?? []
        case .multipleHorses: input.horseIds = horseIds
        case .general: input.horseIds = []
        }
        input.notes = Self.text(notes)
        input.originalAmount = reader.money(originalAmount, "originalAmount")
        input.originalCurrency = Self.currency(originalCurrency)
        return BuiltInput(input: input, parseErrors: reader.errors)
    }

    /// Trening; wysokość przeszkód tylko dla rodzaju „Skoki” (`isJumping`), trener i koszt zawsze w `coaching`.
    public func trainingInput(isJumping: Bool) -> BuiltInput<TrainingInput> {
        var reader = Reader()
        var input = TrainingInput()
        input.horseId = Self.id(horseId)
        input.trainingDate = date
        input.trainingTypeId = Self.id(trainingTypeId)
        input.durationMinutes = reader.integer(duration, "durationMinutes")
        input.intensity = intensity
        input.obstacleHeightCm = isJumping ? reader.integer(obstacleHeight, "obstacleHeightCm") : nil
        input.riderContactId = Self.id(riderId)
        input.rating = rating
        input.description = Self.text(descriptionText)
        input.coaching = TrainingCoachingInput(
            trainerContactId: Self.id(trainerId), cost: reader.money(cost, "cost"), originalAmount: reader.money(originalAmount, "originalAmount"),
            originalCurrency: Self.currency(originalCurrency)
        )
        return BuiltInput(input: input, parseErrors: reader.errors)
    }

    public func competitionInput() -> BuiltInput<CompetitionInput> {
        var input = CompetitionInput()
        input.name = Self.text(competitionName)
        input.dateFrom = dateFrom
        input.dateTo = dateTo
        input.city = Self.text(city)
        input.venue = Self.text(venue)
        input.organizerContactId = Self.id(organizerId)
        input.rankId = Self.id(rankId)
        input.disciplineId = Self.id(disciplineId)
        input.notes = Self.text(notes)
        return BuiltInput(input: input, parseErrors: [:])
    }

    /// Zawody tworzone razem ze startem („Nowe zawody”): nazwa, dzień zawodów i miejscowość.
    public func inlineCompetitionInput() -> BuiltInput<CompetitionInput> {
        var input = CompetitionInput()
        input.name = Self.text(competitionName)
        input.dateFrom = dateFrom
        input.city = Self.text(city)
        return BuiltInput(input: input, parseErrors: [:])
    }

    public func startInput() -> BuiltInput<CompetitionStartInput> {
        var reader = Reader()
        var input = CompetitionStartInput()
        input.horseId = Self.id(horseId)
        input.startDate = startDate
        input.disciplineId = Self.id(disciplineId)
        input.className = Self.text(className)
        input.riderContactId = Self.id(riderId)
        input.placement = reader.integer(placement, "placement")
        input.participantsCount = reader.integer(participants, "participantsCount")
        input.resultStatus = resultStatus
        input.penaltyPoints = reader.decimal(penaltyPoints, "penaltyPoints", scale: 2)
        input.scorePercent = reader.decimal(scorePercent, "scorePercent", scale: 2)
        input.timeSeconds = reader.decimal(timeSeconds, "timeSeconds", scale: 2)
        input.description = Self.text(descriptionText)
        input.subjectiveRating = rating
        input.entryFee = reader.money(entryFee, "entryFee")
        input.otherCosts = reader.money(otherCosts, "otherCosts")
        input.prizeMoney = reader.money(prizeMoney, "prizeMoney")
        input.originalAmount = reader.money(originalAmount, "originalAmount")
        input.originalCurrency = Self.currency(originalCurrency)
        return BuiltInput(input: input, parseErrors: reader.errors)
    }

    // MARK: Z rekordu (edycja, szczegóły, „Powtórz zakup”)

    private static func number(_ value: Money?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value.value).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    private static func integer(_ value: Int?) -> String { value.map(String.init) ?? "" }

    public init(vet visit: LocalVetVisit) {
        horseId = visit.horseId
        date = visit.visitDateTime.date
        hour = visit.visitDateTime.hour
        minute = visit.visitDateTime.minute
        contactId = visit.contactId
        visitTypeId = visit.visitTypeId
        reason = visit.reason ?? ""
        diagnosis = visit.diagnosis ?? ""
        recommendations = visit.recommendations ?? ""
        vaccineOrProduct = visit.vaccineOrProduct ?? ""
        batchNumber = visit.batchNumber ?? ""
        cost = MoneyInput.format(visit.cost)
        nextVisitDate = visit.nextVisitDate
        nextVisitPurpose = visit.nextVisitPurpose ?? ""
        originalAmount = MoneyInput.format(visit.originalAmount)
        originalCurrency = visit.originalCurrency ?? ""
        medications = visit.medications.sorted { $0.sortOrder < $1.sortOrder }.map(MedicationDraft.init)
    }

    public init(farrier visit: LocalFarrierVisit) {
        horseId = visit.horseId
        date = visit.visitDate
        contactId = visit.contactId
        farrierServiceId = visit.serviceId
        hoofNotes = visit.hoofNotes ?? ""
        cost = MoneyInput.format(visit.cost)
        nextVisitDate = visit.nextVisitDate
        originalAmount = MoneyInput.format(visit.originalAmount)
        originalCurrency = visit.originalCurrency ?? ""
    }

    public init(physio visit: LocalPhysioVisit) {
        horseId = visit.horseId
        date = visit.visitDate
        contactId = visit.contactId
        reason = visit.reason ?? ""
        bodyAreaIds = visit.bodyAreaIds
        techniqueIds = visit.techniqueIds
        observations = visit.observations ?? ""
        recommendations = visit.recommendations ?? ""
        cost = MoneyInput.format(visit.cost)
        nextVisitDate = visit.nextVisitDate
        nextVisitPurpose = visit.nextVisitPurpose ?? ""
        originalAmount = MoneyInput.format(visit.originalAmount)
        originalCurrency = visit.originalCurrency ?? ""
    }

    public init(specialist visit: LocalSpecialistVisit) {
        horseId = visit.horseId
        date = visit.visitDate
        specialistTypeId = visit.specialistTypeId
        contactId = visit.contactId
        reason = visit.reason ?? ""
        descriptionText = visit.description ?? ""
        recommendations = visit.recommendations ?? ""
        cost = MoneyInput.format(visit.cost)
        nextVisitDate = visit.nextVisitDate
        nextVisitPurpose = visit.nextVisitPurpose ?? ""
        originalAmount = MoneyInput.format(visit.originalAmount)
        originalCurrency = visit.originalCurrency ?? ""
    }

    public init(note: LocalNote) {
        horseId = note.horseId
        date = note.noteDate
        title = note.title
        content = note.content ?? ""
        pinned = note.isPinned
    }

    public init(purchase: LocalPurchase) {
        date = purchase.purchaseDate
        productName = purchase.productName
        categoryId = purchase.categoryId
        supplierId = purchase.supplierContactId
        quantity = Self.number(purchase.quantity)
        unitId = purchase.unitId
        unitPrice = Self.number(purchase.unitPrice)
        amount = MoneyInput.format(purchase.totalAmount)
        deliveryCost = purchase.deliveryCost.value == 0 ? "" : MoneyInput.format(purchase.deliveryCost)
        assignment = purchase.assignment
        horseId = purchase.assignment == .singleHorse ? purchase.horseIds.first : nil
        horseIds = purchase.assignment == .multipleHorses ? purchase.horseIds : []
        notes = purchase.notes ?? ""
        originalAmount = MoneyInput.format(purchase.originalAmount)
        originalCurrency = purchase.originalCurrency ?? ""
    }

    public init(training: LocalTraining) {
        horseId = training.horseId
        date = training.trainingDate
        trainingTypeId = training.trainingTypeId
        duration = Self.integer(training.durationMinutes)
        intensity = training.intensity
        obstacleHeight = Self.integer(training.obstacleHeightCm)
        riderId = training.riderContactId
        rating = training.rating
        descriptionText = training.description ?? ""
        trainerId = training.trainerContactId
        cost = MoneyInput.format(training.cost)
        originalAmount = MoneyInput.format(training.originalAmount)
        originalCurrency = training.originalCurrency ?? ""
    }

    public init(competition: LocalCompetition) {
        competitionName = competition.name
        dateFrom = competition.dateFrom
        dateTo = competition.dateTo
        city = competition.city ?? ""
        venue = competition.venue ?? ""
        organizerId = competition.organizerContactId
        rankId = competition.rankId
        disciplineId = competition.disciplineId
        notes = competition.notes ?? ""
    }

    public init(start: LocalCompetitionStart) {
        competitionId = start.competitionId
        horseId = start.horseId
        startDate = start.startDate
        disciplineId = start.disciplineId
        className = start.className ?? ""
        riderId = start.riderContactId
        placement = Self.integer(start.placement)
        participants = Self.integer(start.participantsCount)
        resultStatus = start.resultStatus
        penaltyPoints = Self.number(start.penaltyPoints)
        scorePercent = Self.number(start.scorePercent)
        timeSeconds = Self.number(start.timeSeconds)
        descriptionText = start.description ?? ""
        rating = start.subjectiveRating
        entryFee = MoneyInput.format(start.entryFee)
        otherCosts = MoneyInput.format(start.otherCosts)
        prizeMoney = MoneyInput.format(start.prizeMoney)
        originalAmount = MoneyInput.format(start.originalAmount)
        originalCurrency = start.originalCurrency ?? ""
    }
}
