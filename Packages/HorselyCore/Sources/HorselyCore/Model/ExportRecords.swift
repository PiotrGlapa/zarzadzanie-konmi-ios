// ZAWARTOŚĆ GENEROWANA przez scripts/generate-export-records.js — nie edytować ręcznie.
// Rekordy pliku eksportu programu 1.5 w kształcie z Androida 2.0.1 (ExportRecords.kt). Pola z wartością domyślną mogą
// nie występować w pliku (schematy 1.0–1.4); nieznane pola są pomijane przy odczycie; kwoty to `Money` (Decimal).

import Foundation

/// Domyślny odstęp między wizytami kowala (tygodnie) — `Horse.DefaultFarrierIntervalWeeks` w programie.
public let defaultFarrierIntervalWeeks = 6


/// Lek podany lub zapisany na wizycie weterynaryjnej.
public struct LocalVetMedication: Codable, Hashable, Sendable {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var name: String
    public var dosage: String?
    public var startDate: LocalDate?
    public var endDate: LocalDate?
    public var administration: MedicationMode?
    public var notes: String?
    public var sortOrder: Int

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        name: String,
        dosage: String? = nil,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        administration: MedicationMode? = nil,
        notes: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.name = name
        self.dosage = dosage
        self.startDate = startDate
        self.endDate = endDate
        self.administration = administration
        self.notes = notes
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case name
        case dosage
        case startDate
        case endDate
        case administration
        case notes
        case sortOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        name = try c.decode(String.self, forKey: .name)
        dosage = try c.decodeIfPresent(String.self, forKey: .dosage)
        startDate = try c.decodeIfPresent(LocalDate.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(LocalDate.self, forKey: .endDate)
        administration = try c.decodeIfPresent(MedicationMode.self, forKey: .administration)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(dosage, forKey: .dosage)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encodeIfPresent(administration, forKey: .administration)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

/// Pozycja słownika.
public struct LocalDictionaryItem: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var dictionaryType: DictionaryType
    public var value: String
    public var sortOrder: Int
    public var isActive: Bool
    public var isSystem: Bool
    public var systemKey: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        dictionaryType: DictionaryType,
        value: String,
        sortOrder: Int,
        isActive: Bool = true,
        isSystem: Bool = false,
        systemKey: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.dictionaryType = dictionaryType
        self.value = value
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isSystem = isSystem
        self.systemKey = systemKey
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case dictionaryType = "type"
        case value
        case sortOrder
        case isActive
        case isSystem
        case systemKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        dictionaryType = try c.decode(DictionaryType.self, forKey: .dictionaryType)
        value = try c.decode(String.self, forKey: .value)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        isSystem = try c.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
        systemKey = try c.decodeIfPresent(String.self, forKey: .systemKey)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(dictionaryType, forKey: .dictionaryType)
        try c.encode(value, forKey: .value)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(isSystem, forKey: .isSystem)
        try c.encodeIfPresent(systemKey, forKey: .systemKey)
    }

    public var recordType: RecordType { .dictionary }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalDictionaryItem {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalDictionaryItem {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Kontakt.
public struct LocalContact: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var name: String
    public var types: [ContactType]
    public var company: String?
    public var phone: String?
    public var email: String?
    public var address: String?
    public var specialization: String?
    public var notes: String?
    public var isArchived: Bool

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        name: String,
        types: [ContactType] = [],
        company: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        specialization: String? = nil,
        notes: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.name = name
        self.types = types
        self.company = company
        self.phone = phone
        self.email = email
        self.address = address
        self.specialization = specialization
        self.notes = notes
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case name
        case types
        case company
        case phone
        case email
        case address
        case specialization
        case notes
        case isArchived
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        name = try c.decode(String.self, forKey: .name)
        types = try c.decodeIfPresent([ContactType].self, forKey: .types) ?? []
        company = try c.decodeIfPresent(String.self, forKey: .company)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        specialization = try c.decodeIfPresent(String.self, forKey: .specialization)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encode(types, forKey: .types)
        try c.encodeIfPresent(company, forKey: .company)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(specialization, forKey: .specialization)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(isArchived, forKey: .isArchived)
    }

    public var recordType: RecordType { .contact }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalContact {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalContact {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Koń.
public struct LocalHorse: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var name: String
    public var passportNumber: String?
    public var isFoal: Bool
    public var stableName: String?
    public var ueln: String?
    public var microchipNumber: String?
    public var passportIssuer: String?
    public var passportIssueDate: LocalDate?
    public var breed: String?
    public var sex: Sex?
    public var color: String?
    public var birthDate: LocalDate?
    public var birthYearOnly: Bool
    public var birthCountry: String?
    public var sire: String?
    public var dam: String?
    public var damSire: String?
    public var breeder: String?
    public var owner: String?
    public var markings: String?
    public var photoAttachmentId: String?
    public var farrierIntervalWeeks: Int
    public var status: HorseStatus
    public var statusDate: LocalDate?
    public var statusNote: String?
    public var notes: String?
    public var purchasePrice: Money?
    public var purchaseDate: LocalDate?
    public var salePrice: Money?
    public var saleDate: LocalDate?
    public var estimatedValue: Money?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        name: String,
        passportNumber: String? = nil,
        isFoal: Bool = false,
        stableName: String? = nil,
        ueln: String? = nil,
        microchipNumber: String? = nil,
        passportIssuer: String? = nil,
        passportIssueDate: LocalDate? = nil,
        breed: String? = nil,
        sex: Sex? = nil,
        color: String? = nil,
        birthDate: LocalDate? = nil,
        birthYearOnly: Bool = false,
        birthCountry: String? = nil,
        sire: String? = nil,
        dam: String? = nil,
        damSire: String? = nil,
        breeder: String? = nil,
        owner: String? = nil,
        markings: String? = nil,
        photoAttachmentId: String? = nil,
        farrierIntervalWeeks: Int = defaultFarrierIntervalWeeks,
        status: HorseStatus = .active,
        statusDate: LocalDate? = nil,
        statusNote: String? = nil,
        notes: String? = nil,
        purchasePrice: Money? = nil,
        purchaseDate: LocalDate? = nil,
        salePrice: Money? = nil,
        saleDate: LocalDate? = nil,
        estimatedValue: Money? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.name = name
        self.passportNumber = passportNumber
        self.isFoal = isFoal
        self.stableName = stableName
        self.ueln = ueln
        self.microchipNumber = microchipNumber
        self.passportIssuer = passportIssuer
        self.passportIssueDate = passportIssueDate
        self.breed = breed
        self.sex = sex
        self.color = color
        self.birthDate = birthDate
        self.birthYearOnly = birthYearOnly
        self.birthCountry = birthCountry
        self.sire = sire
        self.dam = dam
        self.damSire = damSire
        self.breeder = breeder
        self.owner = owner
        self.markings = markings
        self.photoAttachmentId = photoAttachmentId
        self.farrierIntervalWeeks = farrierIntervalWeeks
        self.status = status
        self.statusDate = statusDate
        self.statusNote = statusNote
        self.notes = notes
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
        self.salePrice = salePrice
        self.saleDate = saleDate
        self.estimatedValue = estimatedValue
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case name
        case passportNumber
        case isFoal
        case stableName
        case ueln
        case microchipNumber
        case passportIssuer
        case passportIssueDate
        case breed
        case sex
        case color
        case birthDate
        case birthYearOnly
        case birthCountry
        case sire
        case dam
        case damSire
        case breeder
        case owner
        case markings
        case photoAttachmentId
        case farrierIntervalWeeks
        case status
        case statusDate
        case statusNote
        case notes
        case purchasePrice
        case purchaseDate
        case salePrice
        case saleDate
        case estimatedValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        name = try c.decode(String.self, forKey: .name)
        passportNumber = try c.decodeIfPresent(String.self, forKey: .passportNumber)
        isFoal = try c.decodeIfPresent(Bool.self, forKey: .isFoal) ?? false
        stableName = try c.decodeIfPresent(String.self, forKey: .stableName)
        ueln = try c.decodeIfPresent(String.self, forKey: .ueln)
        microchipNumber = try c.decodeIfPresent(String.self, forKey: .microchipNumber)
        passportIssuer = try c.decodeIfPresent(String.self, forKey: .passportIssuer)
        passportIssueDate = try c.decodeIfPresent(LocalDate.self, forKey: .passportIssueDate)
        breed = try c.decodeIfPresent(String.self, forKey: .breed)
        sex = try c.decodeIfPresent(Sex.self, forKey: .sex)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        birthDate = try c.decodeIfPresent(LocalDate.self, forKey: .birthDate)
        birthYearOnly = try c.decodeIfPresent(Bool.self, forKey: .birthYearOnly) ?? false
        birthCountry = try c.decodeIfPresent(String.self, forKey: .birthCountry)
        sire = try c.decodeIfPresent(String.self, forKey: .sire)
        dam = try c.decodeIfPresent(String.self, forKey: .dam)
        damSire = try c.decodeIfPresent(String.self, forKey: .damSire)
        breeder = try c.decodeIfPresent(String.self, forKey: .breeder)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        markings = try c.decodeIfPresent(String.self, forKey: .markings)
        photoAttachmentId = try c.decodeIfPresent(String.self, forKey: .photoAttachmentId)
        farrierIntervalWeeks = try c.decodeIfPresent(Int.self, forKey: .farrierIntervalWeeks) ?? defaultFarrierIntervalWeeks
        status = try c.decodeIfPresent(HorseStatus.self, forKey: .status) ?? .active
        statusDate = try c.decodeIfPresent(LocalDate.self, forKey: .statusDate)
        statusNote = try c.decodeIfPresent(String.self, forKey: .statusNote)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        purchasePrice = try c.decodeIfPresent(Money.self, forKey: .purchasePrice)
        purchaseDate = try c.decodeIfPresent(LocalDate.self, forKey: .purchaseDate)
        salePrice = try c.decodeIfPresent(Money.self, forKey: .salePrice)
        saleDate = try c.decodeIfPresent(LocalDate.self, forKey: .saleDate)
        estimatedValue = try c.decodeIfPresent(Money.self, forKey: .estimatedValue)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(passportNumber, forKey: .passportNumber)
        try c.encode(isFoal, forKey: .isFoal)
        try c.encodeIfPresent(stableName, forKey: .stableName)
        try c.encodeIfPresent(ueln, forKey: .ueln)
        try c.encodeIfPresent(microchipNumber, forKey: .microchipNumber)
        try c.encodeIfPresent(passportIssuer, forKey: .passportIssuer)
        try c.encodeIfPresent(passportIssueDate, forKey: .passportIssueDate)
        try c.encodeIfPresent(breed, forKey: .breed)
        try c.encodeIfPresent(sex, forKey: .sex)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(birthDate, forKey: .birthDate)
        try c.encode(birthYearOnly, forKey: .birthYearOnly)
        try c.encodeIfPresent(birthCountry, forKey: .birthCountry)
        try c.encodeIfPresent(sire, forKey: .sire)
        try c.encodeIfPresent(dam, forKey: .dam)
        try c.encodeIfPresent(damSire, forKey: .damSire)
        try c.encodeIfPresent(breeder, forKey: .breeder)
        try c.encodeIfPresent(owner, forKey: .owner)
        try c.encodeIfPresent(markings, forKey: .markings)
        try c.encodeIfPresent(photoAttachmentId, forKey: .photoAttachmentId)
        try c.encode(farrierIntervalWeeks, forKey: .farrierIntervalWeeks)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(statusDate, forKey: .statusDate)
        try c.encodeIfPresent(statusNote, forKey: .statusNote)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(purchasePrice, forKey: .purchasePrice)
        try c.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
        try c.encodeIfPresent(salePrice, forKey: .salePrice)
        try c.encodeIfPresent(saleDate, forKey: .saleDate)
        try c.encodeIfPresent(estimatedValue, forKey: .estimatedValue)
    }

    public var recordType: RecordType { .horse }
    public var primaryHorseId: String? { id }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalHorse {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalHorse {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Wizyta weterynaryjna.
public struct LocalVetVisit: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var visitDateTime: LocalDateTime
    public var contactId: String?
    public var visitTypeId: String
    public var reason: String?
    public var diagnosis: String?
    public var recommendations: String?
    public var vaccineOrProduct: String?
    public var batchNumber: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var nextVisitPurpose: String?
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var medications: [LocalVetMedication]

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        visitDateTime: LocalDateTime,
        contactId: String? = nil,
        visitTypeId: String,
        reason: String? = nil,
        diagnosis: String? = nil,
        recommendations: String? = nil,
        vaccineOrProduct: String? = nil,
        batchNumber: String? = nil,
        cost: Money? = nil,
        nextVisitDate: LocalDate? = nil,
        nextVisitPurpose: String? = nil,
        originalAmount: Money? = nil,
        originalCurrency: String? = nil,
        medications: [LocalVetMedication] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.visitDateTime = visitDateTime
        self.contactId = contactId
        self.visitTypeId = visitTypeId
        self.reason = reason
        self.diagnosis = diagnosis
        self.recommendations = recommendations
        self.vaccineOrProduct = vaccineOrProduct
        self.batchNumber = batchNumber
        self.cost = cost
        self.nextVisitDate = nextVisitDate
        self.nextVisitPurpose = nextVisitPurpose
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.medications = medications
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case horseId
        case visitDateTime
        case contactId
        case visitTypeId
        case reason
        case diagnosis
        case recommendations
        case vaccineOrProduct
        case batchNumber
        case cost
        case nextVisitDate
        case nextVisitPurpose
        case originalAmount
        case originalCurrency
        case medications
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        horseId = try c.decode(String.self, forKey: .horseId)
        visitDateTime = try c.decode(LocalDateTime.self, forKey: .visitDateTime)
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        visitTypeId = try c.decode(String.self, forKey: .visitTypeId)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        diagnosis = try c.decodeIfPresent(String.self, forKey: .diagnosis)
        recommendations = try c.decodeIfPresent(String.self, forKey: .recommendations)
        vaccineOrProduct = try c.decodeIfPresent(String.self, forKey: .vaccineOrProduct)
        batchNumber = try c.decodeIfPresent(String.self, forKey: .batchNumber)
        cost = try c.decodeIfPresent(Money.self, forKey: .cost)
        nextVisitDate = try c.decodeIfPresent(LocalDate.self, forKey: .nextVisitDate)
        nextVisitPurpose = try c.decodeIfPresent(String.self, forKey: .nextVisitPurpose)
        originalAmount = try c.decodeIfPresent(Money.self, forKey: .originalAmount)
        originalCurrency = try c.decodeIfPresent(String.self, forKey: .originalCurrency)
        medications = try c.decodeIfPresent([LocalVetMedication].self, forKey: .medications) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(horseId, forKey: .horseId)
        try c.encode(visitDateTime, forKey: .visitDateTime)
        try c.encodeIfPresent(contactId, forKey: .contactId)
        try c.encode(visitTypeId, forKey: .visitTypeId)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(diagnosis, forKey: .diagnosis)
        try c.encodeIfPresent(recommendations, forKey: .recommendations)
        try c.encodeIfPresent(vaccineOrProduct, forKey: .vaccineOrProduct)
        try c.encodeIfPresent(batchNumber, forKey: .batchNumber)
        try c.encodeIfPresent(cost, forKey: .cost)
        try c.encodeIfPresent(nextVisitDate, forKey: .nextVisitDate)
        try c.encodeIfPresent(nextVisitPurpose, forKey: .nextVisitPurpose)
        try c.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try c.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
        try c.encode(medications, forKey: .medications)
    }

    public var recordType: RecordType { .vetVisit }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { visitDateTime.date }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalVetVisit {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalVetVisit {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Wizyta kowala.
public struct LocalFarrierVisit: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var visitDate: LocalDate
    public var contactId: String?
    public var serviceId: String
    public var hoofNotes: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        visitDate: LocalDate,
        contactId: String? = nil,
        serviceId: String,
        hoofNotes: String? = nil,
        cost: Money? = nil,
        nextVisitDate: LocalDate? = nil,
        originalAmount: Money? = nil,
        originalCurrency: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.visitDate = visitDate
        self.contactId = contactId
        self.serviceId = serviceId
        self.hoofNotes = hoofNotes
        self.cost = cost
        self.nextVisitDate = nextVisitDate
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case horseId
        case visitDate
        case contactId
        case serviceId
        case hoofNotes
        case cost
        case nextVisitDate
        case originalAmount
        case originalCurrency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        horseId = try c.decode(String.self, forKey: .horseId)
        visitDate = try c.decode(LocalDate.self, forKey: .visitDate)
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        serviceId = try c.decode(String.self, forKey: .serviceId)
        hoofNotes = try c.decodeIfPresent(String.self, forKey: .hoofNotes)
        cost = try c.decodeIfPresent(Money.self, forKey: .cost)
        nextVisitDate = try c.decodeIfPresent(LocalDate.self, forKey: .nextVisitDate)
        originalAmount = try c.decodeIfPresent(Money.self, forKey: .originalAmount)
        originalCurrency = try c.decodeIfPresent(String.self, forKey: .originalCurrency)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(horseId, forKey: .horseId)
        try c.encode(visitDate, forKey: .visitDate)
        try c.encodeIfPresent(contactId, forKey: .contactId)
        try c.encode(serviceId, forKey: .serviceId)
        try c.encodeIfPresent(hoofNotes, forKey: .hoofNotes)
        try c.encodeIfPresent(cost, forKey: .cost)
        try c.encodeIfPresent(nextVisitDate, forKey: .nextVisitDate)
        try c.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try c.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
    }

    public var recordType: RecordType { .farrierVisit }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { visitDate }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalFarrierVisit {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalFarrierVisit {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Wizyta fizjoterapeuty.
public struct LocalPhysioVisit: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var visitDate: LocalDate
    public var contactId: String?
    public var reason: String?
    public var bodyAreaIds: [String]
    public var techniqueIds: [String]
    public var observations: String?
    public var recommendations: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var nextVisitPurpose: String?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        visitDate: LocalDate,
        contactId: String? = nil,
        reason: String? = nil,
        bodyAreaIds: [String] = [],
        techniqueIds: [String] = [],
        observations: String? = nil,
        recommendations: String? = nil,
        cost: Money? = nil,
        nextVisitDate: LocalDate? = nil,
        nextVisitPurpose: String? = nil,
        originalAmount: Money? = nil,
        originalCurrency: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.visitDate = visitDate
        self.contactId = contactId
        self.reason = reason
        self.bodyAreaIds = bodyAreaIds
        self.techniqueIds = techniqueIds
        self.observations = observations
        self.recommendations = recommendations
        self.cost = cost
        self.nextVisitDate = nextVisitDate
        self.nextVisitPurpose = nextVisitPurpose
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case horseId
        case visitDate
        case contactId
        case reason
        case bodyAreaIds
        case techniqueIds
        case observations
        case recommendations
        case cost
        case nextVisitDate
        case nextVisitPurpose
        case originalAmount
        case originalCurrency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        horseId = try c.decode(String.self, forKey: .horseId)
        visitDate = try c.decode(LocalDate.self, forKey: .visitDate)
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        bodyAreaIds = try c.decodeIfPresent([String].self, forKey: .bodyAreaIds) ?? []
        techniqueIds = try c.decodeIfPresent([String].self, forKey: .techniqueIds) ?? []
        observations = try c.decodeIfPresent(String.self, forKey: .observations)
        recommendations = try c.decodeIfPresent(String.self, forKey: .recommendations)
        cost = try c.decodeIfPresent(Money.self, forKey: .cost)
        nextVisitDate = try c.decodeIfPresent(LocalDate.self, forKey: .nextVisitDate)
        nextVisitPurpose = try c.decodeIfPresent(String.self, forKey: .nextVisitPurpose)
        originalAmount = try c.decodeIfPresent(Money.self, forKey: .originalAmount)
        originalCurrency = try c.decodeIfPresent(String.self, forKey: .originalCurrency)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(horseId, forKey: .horseId)
        try c.encode(visitDate, forKey: .visitDate)
        try c.encodeIfPresent(contactId, forKey: .contactId)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encode(bodyAreaIds, forKey: .bodyAreaIds)
        try c.encode(techniqueIds, forKey: .techniqueIds)
        try c.encodeIfPresent(observations, forKey: .observations)
        try c.encodeIfPresent(recommendations, forKey: .recommendations)
        try c.encodeIfPresent(cost, forKey: .cost)
        try c.encodeIfPresent(nextVisitDate, forKey: .nextVisitDate)
        try c.encodeIfPresent(nextVisitPurpose, forKey: .nextVisitPurpose)
        try c.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try c.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
    }

    public var recordType: RecordType { .physioVisit }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { visitDate }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalPhysioVisit {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalPhysioVisit {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Wizyta innego specjalisty.
public struct LocalSpecialistVisit: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var visitDate: LocalDate
    public var specialistTypeId: String
    public var contactId: String?
    public var reason: String?
    public var description: String?
    public var recommendations: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var nextVisitPurpose: String?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        visitDate: LocalDate,
        specialistTypeId: String,
        contactId: String? = nil,
        reason: String? = nil,
        description: String? = nil,
        recommendations: String? = nil,
        cost: Money? = nil,
        nextVisitDate: LocalDate? = nil,
        nextVisitPurpose: String? = nil,
        originalAmount: Money? = nil,
        originalCurrency: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.visitDate = visitDate
        self.specialistTypeId = specialistTypeId
        self.contactId = contactId
        self.reason = reason
        self.description = description
        self.recommendations = recommendations
        self.cost = cost
        self.nextVisitDate = nextVisitDate
        self.nextVisitPurpose = nextVisitPurpose
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case horseId
        case visitDate
        case specialistTypeId
        case contactId
        case reason
        case description
        case recommendations
        case cost
        case nextVisitDate
        case nextVisitPurpose
        case originalAmount
        case originalCurrency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        horseId = try c.decode(String.self, forKey: .horseId)
        visitDate = try c.decode(LocalDate.self, forKey: .visitDate)
        specialistTypeId = try c.decode(String.self, forKey: .specialistTypeId)
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        recommendations = try c.decodeIfPresent(String.self, forKey: .recommendations)
        cost = try c.decodeIfPresent(Money.self, forKey: .cost)
        nextVisitDate = try c.decodeIfPresent(LocalDate.self, forKey: .nextVisitDate)
        nextVisitPurpose = try c.decodeIfPresent(String.self, forKey: .nextVisitPurpose)
        originalAmount = try c.decodeIfPresent(Money.self, forKey: .originalAmount)
        originalCurrency = try c.decodeIfPresent(String.self, forKey: .originalCurrency)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(horseId, forKey: .horseId)
        try c.encode(visitDate, forKey: .visitDate)
        try c.encode(specialistTypeId, forKey: .specialistTypeId)
        try c.encodeIfPresent(contactId, forKey: .contactId)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(recommendations, forKey: .recommendations)
        try c.encodeIfPresent(cost, forKey: .cost)
        try c.encodeIfPresent(nextVisitDate, forKey: .nextVisitDate)
        try c.encodeIfPresent(nextVisitPurpose, forKey: .nextVisitPurpose)
        try c.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try c.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
    }

    public var recordType: RecordType { .specialistVisit }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { visitDate }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalSpecialistVisit {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalSpecialistVisit {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Zawody (bez startów — w pliku eksportu są zagnieżdżone, tu osobne rekordy).
public struct LocalCompetition: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var name: String
    public var dateFrom: LocalDate
    public var dateTo: LocalDate?
    public var city: String?
    public var venue: String?
    public var organizerContactId: String?
    public var rankId: String?
    public var disciplineId: String?
    public var notes: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        name: String,
        dateFrom: LocalDate,
        dateTo: LocalDate? = nil,
        city: String? = nil,
        venue: String? = nil,
        organizerContactId: String? = nil,
        rankId: String? = nil,
        disciplineId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.name = name
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.city = city
        self.venue = venue
        self.organizerContactId = organizerContactId
        self.rankId = rankId
        self.disciplineId = disciplineId
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case name
        case dateFrom
        case dateTo
        case city
        case venue
        case organizerContactId
        case rankId
        case disciplineId
        case notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        name = try c.decode(String.self, forKey: .name)
        dateFrom = try c.decode(LocalDate.self, forKey: .dateFrom)
        dateTo = try c.decodeIfPresent(LocalDate.self, forKey: .dateTo)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        venue = try c.decodeIfPresent(String.self, forKey: .venue)
        organizerContactId = try c.decodeIfPresent(String.self, forKey: .organizerContactId)
        rankId = try c.decodeIfPresent(String.self, forKey: .rankId)
        disciplineId = try c.decodeIfPresent(String.self, forKey: .disciplineId)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encode(dateFrom, forKey: .dateFrom)
        try c.encodeIfPresent(dateTo, forKey: .dateTo)
        try c.encodeIfPresent(city, forKey: .city)
        try c.encodeIfPresent(venue, forKey: .venue)
        try c.encodeIfPresent(organizerContactId, forKey: .organizerContactId)
        try c.encodeIfPresent(rankId, forKey: .rankId)
        try c.encodeIfPresent(disciplineId, forKey: .disciplineId)
        try c.encodeIfPresent(notes, forKey: .notes)
    }

    public var recordType: RecordType { .competition }
    public var dateKey: LocalDate? { dateFrom }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalCompetition {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalCompetition {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Start w zawodach; `competitionId` nie występuje w pliku eksportu (tam start jest zagnieżdżony w zawodach).
public struct LocalCompetitionStart: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var competitionId: String
    public var horseId: String
    public var startDate: LocalDate?
    public var disciplineId: String?
    public var className: String?
    public var riderContactId: String?
    public var placement: Int?
    public var participantsCount: Int?
    public var resultStatus: ResultStatus?
    public var penaltyPoints: Money?
    public var scorePercent: Money?
    public var timeSeconds: Money?
    public var description: String?
    public var subjectiveRating: Int?
    public var entryFee: Money?
    public var otherCosts: Money?
    public var prizeMoney: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        competitionId: String = "",
        horseId: String,
        startDate: LocalDate? = nil,
        disciplineId: String? = nil,
        className: String? = nil,
        riderContactId: String? = nil,
        placement: Int? = nil,
        participantsCount: Int? = nil,
        resultStatus: ResultStatus? = nil,
        penaltyPoints: Money? = nil,
        scorePercent: Money? = nil,
        timeSeconds: Money? = nil,
        description: String? = nil,
        subjectiveRating: Int? = nil,
        entryFee: Money? = nil,
        otherCosts: Money? = nil,
        prizeMoney: Money? = nil,
        originalAmount: Money? = nil,
        originalCurrency: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.competitionId = competitionId
        self.horseId = horseId
        self.startDate = startDate
        self.disciplineId = disciplineId
        self.className = className
        self.riderContactId = riderContactId
        self.placement = placement
        self.participantsCount = participantsCount
        self.resultStatus = resultStatus
        self.penaltyPoints = penaltyPoints
        self.scorePercent = scorePercent
        self.timeSeconds = timeSeconds
        self.description = description
        self.subjectiveRating = subjectiveRating
        self.entryFee = entryFee
        self.otherCosts = otherCosts
        self.prizeMoney = prizeMoney
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case competitionId
        case horseId
        case startDate
        case disciplineId
        case className
        case riderContactId
        case placement
        case participantsCount
        case resultStatus
        case penaltyPoints
        case scorePercent
        case timeSeconds
        case description
        case subjectiveRating
        case entryFee
        case otherCosts
        case prizeMoney
        case originalAmount
        case originalCurrency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        competitionId = try c.decodeIfPresent(String.self, forKey: .competitionId) ?? ""
        horseId = try c.decode(String.self, forKey: .horseId)
        startDate = try c.decodeIfPresent(LocalDate.self, forKey: .startDate)
        disciplineId = try c.decodeIfPresent(String.self, forKey: .disciplineId)
        className = try c.decodeIfPresent(String.self, forKey: .className)
        riderContactId = try c.decodeIfPresent(String.self, forKey: .riderContactId)
        placement = try c.decodeIfPresent(Int.self, forKey: .placement)
        participantsCount = try c.decodeIfPresent(Int.self, forKey: .participantsCount)
        resultStatus = try c.decodeIfPresent(ResultStatus.self, forKey: .resultStatus)
        penaltyPoints = try c.decodeIfPresent(Money.self, forKey: .penaltyPoints)
        scorePercent = try c.decodeIfPresent(Money.self, forKey: .scorePercent)
        timeSeconds = try c.decodeIfPresent(Money.self, forKey: .timeSeconds)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        subjectiveRating = try c.decodeIfPresent(Int.self, forKey: .subjectiveRating)
        entryFee = try c.decodeIfPresent(Money.self, forKey: .entryFee)
        otherCosts = try c.decodeIfPresent(Money.self, forKey: .otherCosts)
        prizeMoney = try c.decodeIfPresent(Money.self, forKey: .prizeMoney)
        originalAmount = try c.decodeIfPresent(Money.self, forKey: .originalAmount)
        originalCurrency = try c.decodeIfPresent(String.self, forKey: .originalCurrency)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(competitionId, forKey: .competitionId)
        try c.encode(horseId, forKey: .horseId)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(disciplineId, forKey: .disciplineId)
        try c.encodeIfPresent(className, forKey: .className)
        try c.encodeIfPresent(riderContactId, forKey: .riderContactId)
        try c.encodeIfPresent(placement, forKey: .placement)
        try c.encodeIfPresent(participantsCount, forKey: .participantsCount)
        try c.encodeIfPresent(resultStatus, forKey: .resultStatus)
        try c.encodeIfPresent(penaltyPoints, forKey: .penaltyPoints)
        try c.encodeIfPresent(scorePercent, forKey: .scorePercent)
        try c.encodeIfPresent(timeSeconds, forKey: .timeSeconds)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(subjectiveRating, forKey: .subjectiveRating)
        try c.encodeIfPresent(entryFee, forKey: .entryFee)
        try c.encodeIfPresent(otherCosts, forKey: .otherCosts)
        try c.encodeIfPresent(prizeMoney, forKey: .prizeMoney)
        try c.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try c.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
    }

    public var recordType: RecordType { .competitionStart }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { startDate }
    public var parentId: String? { competitionId }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalCompetitionStart {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalCompetitionStart {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Zakup (jeden koń, kilka koni albo ogólny).
public struct LocalPurchase: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var purchaseDate: LocalDate
    public var productName: String
    public var categoryId: String
    public var supplierContactId: String?
    public var quantity: Money?
    public var unitId: String?
    public var unitPrice: Money?
    public var totalAmount: Money
    public var deliveryCost: Money
    public var assignment: PurchaseAssignment
    public var horseIds: [String]
    public var notes: String?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        purchaseDate: LocalDate,
        productName: String,
        categoryId: String,
        supplierContactId: String? = nil,
        quantity: Money? = nil,
        unitId: String? = nil,
        unitPrice: Money? = nil,
        totalAmount: Money,
        deliveryCost: Money = Money.zero,
        assignment: PurchaseAssignment,
        horseIds: [String] = [],
        notes: String? = nil,
        originalAmount: Money? = nil,
        originalCurrency: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.purchaseDate = purchaseDate
        self.productName = productName
        self.categoryId = categoryId
        self.supplierContactId = supplierContactId
        self.quantity = quantity
        self.unitId = unitId
        self.unitPrice = unitPrice
        self.totalAmount = totalAmount
        self.deliveryCost = deliveryCost
        self.assignment = assignment
        self.horseIds = horseIds
        self.notes = notes
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case purchaseDate
        case productName
        case categoryId
        case supplierContactId
        case quantity
        case unitId
        case unitPrice
        case totalAmount
        case deliveryCost
        case assignment
        case horseIds
        case notes
        case originalAmount
        case originalCurrency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        purchaseDate = try c.decode(LocalDate.self, forKey: .purchaseDate)
        productName = try c.decode(String.self, forKey: .productName)
        categoryId = try c.decode(String.self, forKey: .categoryId)
        supplierContactId = try c.decodeIfPresent(String.self, forKey: .supplierContactId)
        quantity = try c.decodeIfPresent(Money.self, forKey: .quantity)
        unitId = try c.decodeIfPresent(String.self, forKey: .unitId)
        unitPrice = try c.decodeIfPresent(Money.self, forKey: .unitPrice)
        totalAmount = try c.decode(Money.self, forKey: .totalAmount)
        deliveryCost = try c.decodeIfPresent(Money.self, forKey: .deliveryCost) ?? Money.zero
        assignment = try c.decode(PurchaseAssignment.self, forKey: .assignment)
        horseIds = try c.decodeIfPresent([String].self, forKey: .horseIds) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        originalAmount = try c.decodeIfPresent(Money.self, forKey: .originalAmount)
        originalCurrency = try c.decodeIfPresent(String.self, forKey: .originalCurrency)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(purchaseDate, forKey: .purchaseDate)
        try c.encode(productName, forKey: .productName)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encodeIfPresent(supplierContactId, forKey: .supplierContactId)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(unitId, forKey: .unitId)
        try c.encodeIfPresent(unitPrice, forKey: .unitPrice)
        try c.encode(totalAmount, forKey: .totalAmount)
        try c.encode(deliveryCost, forKey: .deliveryCost)
        try c.encode(assignment, forKey: .assignment)
        try c.encode(horseIds, forKey: .horseIds)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try c.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
    }

    public var recordType: RecordType { .purchase }
    public var dateKey: LocalDate? { purchaseDate }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalPurchase {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalPurchase {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Notatka.
public struct LocalNote: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var noteDate: LocalDate
    public var title: String
    public var content: String?
    public var isPinned: Bool

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        noteDate: LocalDate,
        title: String,
        content: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.noteDate = noteDate
        self.title = title
        self.content = content
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case horseId
        case noteDate
        case title
        case content
        case isPinned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        horseId = try c.decode(String.self, forKey: .horseId)
        noteDate = try c.decode(LocalDate.self, forKey: .noteDate)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(horseId, forKey: .horseId)
        try c.encode(noteDate, forKey: .noteDate)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encode(isPinned, forKey: .isPinned)
    }

    public var recordType: RecordType { .note }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { noteDate }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalNote {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalNote {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Trening.
public struct LocalTraining: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var trainingDate: LocalDate
    public var trainingTypeId: String
    public var durationMinutes: Int?
    public var intensity: Intensity?
    public var obstacleHeightCm: Int?
    public var riderContactId: String?
    public var rating: Int?
    public var description: String?
    public var trainerContactId: String?
    public var cost: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        trainingDate: LocalDate,
        trainingTypeId: String,
        durationMinutes: Int? = nil,
        intensity: Intensity? = nil,
        obstacleHeightCm: Int? = nil,
        riderContactId: String? = nil,
        rating: Int? = nil,
        description: String? = nil,
        trainerContactId: String? = nil,
        cost: Money? = nil,
        originalAmount: Money? = nil,
        originalCurrency: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.trainingDate = trainingDate
        self.trainingTypeId = trainingTypeId
        self.durationMinutes = durationMinutes
        self.intensity = intensity
        self.obstacleHeightCm = obstacleHeightCm
        self.riderContactId = riderContactId
        self.rating = rating
        self.description = description
        self.trainerContactId = trainerContactId
        self.cost = cost
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case horseId
        case trainingDate
        case trainingTypeId
        case durationMinutes
        case intensity
        case obstacleHeightCm
        case riderContactId
        case rating
        case description
        case trainerContactId
        case cost
        case originalAmount
        case originalCurrency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        horseId = try c.decode(String.self, forKey: .horseId)
        trainingDate = try c.decode(LocalDate.self, forKey: .trainingDate)
        trainingTypeId = try c.decode(String.self, forKey: .trainingTypeId)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        intensity = try c.decodeIfPresent(Intensity.self, forKey: .intensity)
        obstacleHeightCm = try c.decodeIfPresent(Int.self, forKey: .obstacleHeightCm)
        riderContactId = try c.decodeIfPresent(String.self, forKey: .riderContactId)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        trainerContactId = try c.decodeIfPresent(String.self, forKey: .trainerContactId)
        cost = try c.decodeIfPresent(Money.self, forKey: .cost)
        originalAmount = try c.decodeIfPresent(Money.self, forKey: .originalAmount)
        originalCurrency = try c.decodeIfPresent(String.self, forKey: .originalCurrency)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(horseId, forKey: .horseId)
        try c.encode(trainingDate, forKey: .trainingDate)
        try c.encode(trainingTypeId, forKey: .trainingTypeId)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(intensity, forKey: .intensity)
        try c.encodeIfPresent(obstacleHeightCm, forKey: .obstacleHeightCm)
        try c.encodeIfPresent(riderContactId, forKey: .riderContactId)
        try c.encodeIfPresent(rating, forKey: .rating)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(trainerContactId, forKey: .trainerContactId)
        try c.encodeIfPresent(cost, forKey: .cost)
        try c.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try c.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
    }

    public var recordType: RecordType { .training }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { trainingDate }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalTraining {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalTraining {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Termin.
public struct LocalReminder: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var kind: ReminderKind
    public var dueDate: LocalDate
    public var title: String
    public var sourceType: String?
    public var sourceId: String?
    public var specialistTypeId: String?
    public var status: ReminderStatus
    public var completedByType: String?
    public var completedById: String?
    public var completedAt: LocalDateTime?
    public var notes: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        kind: ReminderKind,
        dueDate: LocalDate,
        title: String,
        sourceType: String? = nil,
        sourceId: String? = nil,
        specialistTypeId: String? = nil,
        status: ReminderStatus = .open,
        completedByType: String? = nil,
        completedById: String? = nil,
        completedAt: LocalDateTime? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.kind = kind
        self.dueDate = dueDate
        self.title = title
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.specialistTypeId = specialistTypeId
        self.status = status
        self.completedByType = completedByType
        self.completedById = completedById
        self.completedAt = completedAt
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case horseId
        case kind
        case dueDate
        case title
        case sourceType
        case sourceId
        case specialistTypeId
        case status
        case completedByType
        case completedById
        case completedAt
        case notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        horseId = try c.decode(String.self, forKey: .horseId)
        kind = try c.decode(ReminderKind.self, forKey: .kind)
        dueDate = try c.decode(LocalDate.self, forKey: .dueDate)
        title = try c.decode(String.self, forKey: .title)
        sourceType = try c.decodeIfPresent(String.self, forKey: .sourceType)
        sourceId = try c.decodeIfPresent(String.self, forKey: .sourceId)
        specialistTypeId = try c.decodeIfPresent(String.self, forKey: .specialistTypeId)
        status = try c.decodeIfPresent(ReminderStatus.self, forKey: .status) ?? .open
        completedByType = try c.decodeIfPresent(String.self, forKey: .completedByType)
        completedById = try c.decodeIfPresent(String.self, forKey: .completedById)
        completedAt = try c.decodeIfPresent(LocalDateTime.self, forKey: .completedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(horseId, forKey: .horseId)
        try c.encode(kind, forKey: .kind)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(sourceType, forKey: .sourceType)
        try c.encodeIfPresent(sourceId, forKey: .sourceId)
        try c.encodeIfPresent(specialistTypeId, forKey: .specialistTypeId)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(completedByType, forKey: .completedByType)
        try c.encodeIfPresent(completedById, forKey: .completedById)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(notes, forKey: .notes)
    }

    public var recordType: RecordType { .reminder }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { dueDate }
    public var parentId: String? { sourceId }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalReminder {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalReminder {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

/// Załącznik (metadane; plik leży w `local_file`).
public struct LocalAttachment: LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var ownerType: AttachmentOwnerType
    public var ownerId: String
    public var horseId: String?
    public var fileName: String
    public var contentType: String
    public var sizeBytes: Int64
    public var sha256: String
    public var description: String?

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        ownerType: AttachmentOwnerType,
        ownerId: String,
        horseId: String? = nil,
        fileName: String,
        contentType: String,
        sizeBytes: Int64,
        sha256: String,
        description: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.horseId = horseId
        self.fileName = fileName
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case version
        case ownerType
        case ownerId
        case horseId
        case fileName
        case contentType
        case sizeBytes
        case sha256
        case description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(LocalDateTime.self, forKey: .createdAt)
        updatedAt = try c.decode(LocalDateTime.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        ownerType = try c.decode(AttachmentOwnerType.self, forKey: .ownerType)
        ownerId = try c.decode(String.self, forKey: .ownerId)
        horseId = try c.decodeIfPresent(String.self, forKey: .horseId)
        fileName = try c.decode(String.self, forKey: .fileName)
        contentType = try c.decode(String.self, forKey: .contentType)
        sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        sha256 = try c.decode(String.self, forKey: .sha256)
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encode(ownerType, forKey: .ownerType)
        try c.encode(ownerId, forKey: .ownerId)
        try c.encodeIfPresent(horseId, forKey: .horseId)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(sizeBytes, forKey: .sizeBytes)
        try c.encode(sha256, forKey: .sha256)
        try c.encodeIfPresent(description, forKey: .description)
    }

    public var recordType: RecordType { .attachment }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { createdAt.date }
    public var parentId: String? { ownerId }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalAttachment {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalAttachment {
        var copy = self
        copy.createdAt = time
        return copy
    }
}
