import HorselyCore
import HorselyKit
import SwiftUI

/// Paszport konia: dane z paszportu (numer, UELN, chip, rasa, maść, data urodzenia, interwał kowala) i lista szczepień.
struct PassportTab: View {
    @Environment(AppEnvironment.self) private var environment
    let horse: LocalHorse
    @State private var vaccinations: [LocalVetVisit]?

    private var rows: [(LocalizedStringKey, String)] {
        var list: [(LocalizedStringKey, String)] = []
        list.append(("horse_form_passport", HorseRules.clean(horse.passportNumber) ?? tr("horse_passport_none")))
        if let ueln = HorseRules.clean(horse.ueln) { list.append(("horse_form_ueln", ueln)) }
        if let chip = HorseRules.clean(horse.microchipNumber) { list.append(("horse_form_microchip", chip)) }
        if let breed = HorseRules.clean(horse.breed) { list.append(("horse_field_breed", breed)) }
        if let color = HorseRules.clean(horse.color) { list.append(("horse_field_color", color)) }
        if let sex = horse.sex { list.append(("horse_form_sex", tr(sex.labelKey))) }
        if let birth = horse.birthDate { list.append(("horse_field_birth", horse.birthYearOnly ? String(birth.year) : Formats.date(birth))) }
        list.append(("horse_field_farrier_interval_label", tr("horse_field_weeks", horse.farrierIntervalWeeks)))
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("horse_passport_section")
            InfoCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { DividerLine(inset: 0).padding(.vertical, 6) }
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.0).font(.subheadline)
                            Spacer(minLength: Spacing.between)
                            Text(row.1).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            SectionHeader("horse_passport_vaccinations")
            if let vaccinations {
                if vaccinations.isEmpty {
                    Text("horse_passport_no_vaccinations").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant).padding(.vertical, Spacing.between)
                } else {
                    DividedList(vaccinations) { visit in
                        NavigationLink(value: EntryRoute(recordType: .vetVisit, id: visit.id)) {
                            AccentRow(color: EntryAccent.vet.color) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(HorseRules.clean(visit.vaccineOrProduct) ?? tr("timeline_type_vet_visit")).font(.body.weight(.semibold))
                                        if let batch = HorseRules.clean(visit.batchNumber) {
                                            Text(batch).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                                        }
                                    }
                                    Spacer(minLength: Spacing.between)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(Formats.date(visit.visitDateTime.date)).font(.footnote)
                                        if let next = visit.nextVisitDate {
                                            Text(tr("reminders_due", Formats.date(next))).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                                        }
                                    }
                                }
                                .padding(.vertical, Spacing.between)
                            }
                            .frame(minHeight: Spacing.minTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .task(id: environment.dataRevision) {
            vaccinations = try? await environment.entries.vaccinations(horseId: horse.id)
        }
    }
}
