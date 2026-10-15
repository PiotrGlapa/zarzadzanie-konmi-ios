// Generuje Packages/HorselyCore/Sources/HorselyCore/Model/ExportRecords.swift — rekordy pliku eksportu programu 1.5
// (odpowiednik ExportRecords.kt z Androida, 2.0.1). Specyfikacja pól jest w tablicy TYPES poniżej; po jej zmianie uruchom:
//   node scripts/generate-export-records.js
// Wynik jest zatwierdzany w repozytorium (kod generowany, nie edytować ręcznie).
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const COMMON = [
  ['id', 'String'],
  ['createdAt', 'LocalDateTime'],
  ['updatedAt', 'LocalDateTime'],
  ['version', 'Int', '0'],
];

// [nazwa, typ Swift, wartość domyślna (gdy brak w JSON), klucz JSON (gdy inny niż nazwa)]; typ z „?” = opcjonalne (domyślnie nil).
const TYPES = [
  {
    name: 'LocalDictionaryItem', record: 'dictionary', docs: 'Pozycja słownika.',
    fields: [['dictionaryType', 'DictionaryType', undefined, 'type'], ['value', 'String'], ['sortOrder', 'Int'], ['isActive', 'Bool', 'true'], ['isSystem', 'Bool', 'false'], ['systemKey', 'String?']],
  },
  {
    name: 'LocalContact', record: 'contact', docs: 'Kontakt.',
    fields: [['name', 'String'], ['types', '[ContactType]', '[]'], ['company', 'String?'], ['phone', 'String?'], ['email', 'String?'], ['address', 'String?'], ['specialization', 'String?'], ['notes', 'String?'], ['isArchived', 'Bool', 'false']],
  },
  {
    name: 'LocalHorse', record: 'horse', docs: 'Koń.', horseId: 'id',
    fields: [
      ['name', 'String'], ['passportNumber', 'String?'], ['isFoal', 'Bool', 'false'], ['stableName', 'String?'], ['ueln', 'String?'], ['microchipNumber', 'String?'],
      ['passportIssuer', 'String?'], ['passportIssueDate', 'LocalDate?'], ['breed', 'String?'], ['sex', 'Sex?'], ['color', 'String?'], ['birthDate', 'LocalDate?'],
      ['birthYearOnly', 'Bool', 'false'], ['birthCountry', 'String?'], ['sire', 'String?'], ['dam', 'String?'], ['damSire', 'String?'], ['breeder', 'String?'],
      ['owner', 'String?'], ['markings', 'String?'], ['photoAttachmentId', 'String?'], ['farrierIntervalWeeks', 'Int', 'defaultFarrierIntervalWeeks'],
      ['status', 'HorseStatus', '.active'], ['statusDate', 'LocalDate?'], ['statusNote', 'String?'], ['notes', 'String?'], ['purchasePrice', 'Money?'],
      ['purchaseDate', 'LocalDate?'], ['salePrice', 'Money?'], ['saleDate', 'LocalDate?'], ['estimatedValue', 'Money?'],
    ],
  },
  {
    name: 'LocalVetVisit', record: 'vetVisit', docs: 'Wizyta weterynaryjna.', horseId: 'horseId', dateKey: 'visitDateTime.date',
    fields: [
      ['horseId', 'String'], ['visitDateTime', 'LocalDateTime'], ['contactId', 'String?'], ['visitTypeId', 'String'], ['reason', 'String?'], ['diagnosis', 'String?'],
      ['recommendations', 'String?'], ['vaccineOrProduct', 'String?'], ['batchNumber', 'String?'], ['cost', 'Money?'], ['nextVisitDate', 'LocalDate?'],
      ['nextVisitPurpose', 'String?'], ['originalAmount', 'Money?'], ['originalCurrency', 'String?'], ['medications', '[LocalVetMedication]', '[]'],
    ],
  },
  {
    name: 'LocalFarrierVisit', record: 'farrierVisit', docs: 'Wizyta kowala.', horseId: 'horseId', dateKey: 'visitDate',
    fields: [['horseId', 'String'], ['visitDate', 'LocalDate'], ['contactId', 'String?'], ['serviceId', 'String'], ['hoofNotes', 'String?'], ['cost', 'Money?'], ['nextVisitDate', 'LocalDate?'], ['originalAmount', 'Money?'], ['originalCurrency', 'String?']],
  },
  {
    name: 'LocalPhysioVisit', record: 'physioVisit', docs: 'Wizyta fizjoterapeuty.', horseId: 'horseId', dateKey: 'visitDate',
    fields: [
      ['horseId', 'String'], ['visitDate', 'LocalDate'], ['contactId', 'String?'], ['reason', 'String?'], ['bodyAreaIds', '[String]', '[]'], ['techniqueIds', '[String]', '[]'],
      ['observations', 'String?'], ['recommendations', 'String?'], ['cost', 'Money?'], ['nextVisitDate', 'LocalDate?'], ['nextVisitPurpose', 'String?'], ['originalAmount', 'Money?'], ['originalCurrency', 'String?'],
    ],
  },
  {
    name: 'LocalSpecialistVisit', record: 'specialistVisit', docs: 'Wizyta innego specjalisty.', horseId: 'horseId', dateKey: 'visitDate',
    fields: [
      ['horseId', 'String'], ['visitDate', 'LocalDate'], ['specialistTypeId', 'String'], ['contactId', 'String?'], ['reason', 'String?'], ['description', 'String?'],
      ['recommendations', 'String?'], ['cost', 'Money?'], ['nextVisitDate', 'LocalDate?'], ['nextVisitPurpose', 'String?'], ['originalAmount', 'Money?'], ['originalCurrency', 'String?'],
    ],
  },
  {
    name: 'LocalCompetition', record: 'competition', docs: 'Zawody (bez startów — w pliku eksportu są zagnieżdżone, tu osobne rekordy).', dateKey: 'dateFrom',
    fields: [['name', 'String'], ['dateFrom', 'LocalDate'], ['dateTo', 'LocalDate?'], ['city', 'String?'], ['venue', 'String?'], ['organizerContactId', 'String?'], ['rankId', 'String?'], ['disciplineId', 'String?'], ['notes', 'String?']],
  },
  {
    name: 'LocalCompetitionStart', record: 'competitionStart', docs: 'Start w zawodach; `competitionId` nie występuje w pliku eksportu (tam start jest zagnieżdżony w zawodach).',
    horseId: 'horseId', dateKey: 'startDate', parentId: 'competitionId',
    fields: [
      ['competitionId', 'String', '""'], ['horseId', 'String'], ['startDate', 'LocalDate?'], ['disciplineId', 'String?'], ['className', 'String?'], ['riderContactId', 'String?'],
      ['placement', 'Int?'], ['participantsCount', 'Int?'], ['resultStatus', 'ResultStatus?'], ['penaltyPoints', 'Money?'], ['scorePercent', 'Money?'], ['timeSeconds', 'Money?'],
      ['description', 'String?'], ['subjectiveRating', 'Int?'], ['entryFee', 'Money?'], ['otherCosts', 'Money?'], ['prizeMoney', 'Money?'], ['originalAmount', 'Money?'], ['originalCurrency', 'String?'],
    ],
  },
  {
    name: 'LocalPurchase', record: 'purchase', docs: 'Zakup (jeden koń, kilka koni albo ogólny).', dateKey: 'purchaseDate',
    fields: [
      ['purchaseDate', 'LocalDate'], ['productName', 'String'], ['categoryId', 'String'], ['supplierContactId', 'String?'], ['quantity', 'Money?'], ['unitId', 'String?'],
      ['unitPrice', 'Money?'], ['totalAmount', 'Money'], ['deliveryCost', 'Money', 'Money.zero'], ['assignment', 'PurchaseAssignment'], ['horseIds', '[String]', '[]'],
      ['notes', 'String?'], ['originalAmount', 'Money?'], ['originalCurrency', 'String?'],
    ],
  },
  {
    name: 'LocalNote', record: 'note', docs: 'Notatka.', horseId: 'horseId', dateKey: 'noteDate',
    fields: [['horseId', 'String'], ['noteDate', 'LocalDate'], ['title', 'String'], ['content', 'String?'], ['isPinned', 'Bool', 'false']],
  },
  {
    name: 'LocalTraining', record: 'training', docs: 'Trening.', horseId: 'horseId', dateKey: 'trainingDate',
    fields: [
      ['horseId', 'String'], ['trainingDate', 'LocalDate'], ['trainingTypeId', 'String'], ['durationMinutes', 'Int?'], ['intensity', 'Intensity?'], ['obstacleHeightCm', 'Int?'],
      ['riderContactId', 'String?'], ['rating', 'Int?'], ['description', 'String?'], ['trainerContactId', 'String?'], ['cost', 'Money?'], ['originalAmount', 'Money?'], ['originalCurrency', 'String?'],
    ],
  },
  {
    name: 'LocalReminder', record: 'reminder', docs: 'Termin.', horseId: 'horseId', dateKey: 'dueDate', parentId: 'sourceId',
    fields: [
      ['horseId', 'String'], ['kind', 'ReminderKind'], ['dueDate', 'LocalDate'], ['title', 'String'], ['sourceType', 'String?'], ['sourceId', 'String?'], ['specialistTypeId', 'String?'],
      ['status', 'ReminderStatus', '.open'], ['completedByType', 'String?'], ['completedById', 'String?'], ['completedAt', 'LocalDateTime?'], ['notes', 'String?'],
    ],
  },
  {
    name: 'LocalAttachment', record: 'attachment', docs: 'Załącznik (metadane; plik leży w `local_file`).', horseId: 'horseId?', dateKey: 'createdAt.date', parentId: 'ownerId',
    fields: [
      ['ownerType', 'AttachmentOwnerType'], ['ownerId', 'String'], ['horseId', 'String?'], ['fileName', 'String'], ['contentType', 'String'], ['sizeBytes', 'Int64'], ['sha256', 'String'], ['description', 'String?'],
    ],
  },
];

const MEDICATION = {
  name: 'LocalVetMedication', docs: 'Lek podany lub zapisany na wizycie weterynaryjnej.',
  fields: [
    ['id', 'String'], ['createdAt', 'LocalDateTime'], ['updatedAt', 'LocalDateTime'], ['version', 'Int', '0'], ['name', 'String'], ['dosage', 'String?'],
    ['startDate', 'LocalDate?'], ['endDate', 'LocalDate?'], ['administration', 'MedicationMode?'], ['notes', 'String?'], ['sortOrder', 'Int', '0'],
  ],
};

const isOptional = (type) => type.endsWith('?');
const defaultOf = (field) => (isOptional(field[1]) ? 'nil' : field[2]);

function generate(type, isRecord) {
  const fields = isRecord ? [...COMMON.map((f) => [...f]), ...type.fields] : type.fields;
  const lines = [];
  lines.push(`/// ${type.docs}`);
  lines.push(`public struct ${type.name}: ${isRecord ? 'LocalRecord' : 'Codable, Hashable, Sendable'} {`);
  for (const [name, swiftType] of fields) lines.push(`    public var ${name}: ${swiftType}`);
  lines.push('');
  const params = fields.map((f) => {
    const def = defaultOf(f);
    return `${f[0]}: ${f[1]}${def === undefined ? '' : ` = ${def}`}`;
  });
  lines.push('    public init(');
  params.forEach((p, i) => lines.push(`        ${p}${i < params.length - 1 ? ',' : ''}`));
  lines.push('    ) {');
  for (const f of fields) lines.push(`        self.${f[0]} = ${f[0]}`);
  lines.push('    }');
  lines.push('');
  lines.push('    private enum CodingKeys: String, CodingKey {');
  for (const f of fields) lines.push(f[3] ? `        case ${f[0]} = "${f[3]}"` : `        case ${f[0]}`);
  lines.push('    }');
  lines.push('');
  lines.push('    public init(from decoder: Decoder) throws {');
  lines.push('        let c = try decoder.container(keyedBy: CodingKeys.self)');
  for (const f of fields) {
    const [name, t] = f;
    if (isOptional(t)) lines.push(`        ${name} = try c.decodeIfPresent(${t.slice(0, -1)}.self, forKey: .${name})`);
    else if (f[2] !== undefined) lines.push(`        ${name} = try c.decodeIfPresent(${t}.self, forKey: .${name}) ?? ${f[2]}`);
    else lines.push(`        ${name} = try c.decode(${t}.self, forKey: .${name})`);
  }
  lines.push('    }');
  lines.push('');
  lines.push('    public func encode(to encoder: Encoder) throws {');
  lines.push('        var c = encoder.container(keyedBy: CodingKeys.self)');
  for (const [name, t] of fields) lines.push(isOptional(t) ? `        try c.encodeIfPresent(${name}, forKey: .${name})` : `        try c.encode(${name}, forKey: .${name})`);
  lines.push('    }');
  if (isRecord) {
    lines.push('');
    lines.push(`    public var recordType: RecordType { .${type.record} }`);
    if (type.horseId === 'id') lines.push('    public var primaryHorseId: String? { id }');
    else if (type.horseId) lines.push(`    public var primaryHorseId: String? { horseId }`);
    if (type.dateKey) lines.push(`    public var dateKey: LocalDate? { ${type.dateKey} }`);
    if (type.parentId) lines.push(`    public var parentId: String? { ${type.parentId} }`);
    lines.push('');
    lines.push(`    public func withAudit(version: Int, updatedAt: LocalDateTime) -> ${type.name} {`);
    lines.push('        var copy = self');
    lines.push('        copy.version = version');
    lines.push('        copy.updatedAt = updatedAt');
    lines.push('        return copy');
    lines.push('    }');
  }
  lines.push('}');
  return lines.join('\n');
}

const header = `// ZAWARTOŚĆ GENEROWANA przez scripts/generate-export-records.js — nie edytować ręcznie.
// Rekordy pliku eksportu programu 1.5 w kształcie z Androida 2.0.1 (ExportRecords.kt). Pola z wartością domyślną mogą
// nie występować w pliku (schematy 1.0–1.4); nieznane pola są pomijane przy odczycie; kwoty to \`Money\` (Decimal).

import Foundation

/// Domyślny odstęp między wizytami kowala (tygodnie) — \`Horse.DefaultFarrierIntervalWeeks\` w programie.
public let defaultFarrierIntervalWeeks = 6
`;

const out = [header, generate(MEDICATION, false), ...TYPES.map((t) => generate(t, true))].join('\n\n') + '\n';
const target = path.join(__dirname, '..', 'Packages', 'HorselyCore', 'Sources', 'HorselyCore', 'Model', 'ExportRecords.swift');
fs.writeFileSync(target, out);
console.log(`Zapisano ${target}`);
