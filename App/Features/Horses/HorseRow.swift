import HorselyCore
import SwiftUI
import UIKit

/// Opisy konia w listach i kaflach (FR-M-KON-01/04): imię stajenne w cudzysłowie, podtytuł paszportu, źrebię bez paszportu.
enum HorseDescription {
    /// „Gromek” w cudzysłowie; `nil`, gdy koń nie ma imienia stajennego (nie ma pustego wiersza).
    static func stableName(_ horse: LocalHorse) -> String? {
        HorseRules.clean(horse.stableName).map { "„\($0)”" }
    }

    /// Podtytuł listy: „Paszport: PL-1”, „źrebak, bez paszportu od N mies.” albo „brak paszportu” (nigdy puste nawiasy ani „null”).
    static func passportLine(_ horse: LocalHorse, today: LocalDate) -> String {
        if let number = HorseRules.clean(horse.passportNumber) { return tr("horse_passport_number", number) }
        if horse.isFoal {
            if let months = HorseRules.monthsWithoutPassport(of: horse, on: today) { return trPlural("foal_months_without_passport", months) }
            return tr("horse_foal_no_passport")
        }
        return tr("horse_passport_none")
    }

    /// Miesięcy bez paszportu od progu ostrzeżenia (kafel Pulpitu: tło ostrzegawcze od 12 mies.).
    static let foalWarningMonths = 12

    static func isForgottenPassport(_ horse: LocalHorse, today: LocalDate) -> Bool {
        (HorseRules.monthsWithoutPassport(of: horse, on: today) ?? 0) >= foalWarningMonths
    }

    /// Etykieta dla VoiceOver: „<imię>, kontuzjowany”.
    static func accessibilityName(_ horse: LocalHorse) -> String {
        horse.status == .injured ? tr("horse_injured_tile_description", horse.name) : horse.name
    }
}

/// Wiersz listy koni: miniatura 40 pt, imię, imię stajenne, podtytuł paszportu, plakietka kontuzji.
struct HorseRow: View {
    let horse: LocalHorse
    let photo: UIImage?
    let today: LocalDate

    var body: some View {
        HStack(spacing: Spacing.between + 4) {
            HorseAvatar(photo: photo, diameter: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.between) {
                    Text(horse.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HorselyColor.onBackground)
                    if horse.status == .injured { InjuredBadge() }
                }
                if let stable = HorseDescription.stableName(horse) {
                    Text(stable).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                Text(HorseDescription.passportLine(horse, today: today))
                    .font(.footnote)
                    .foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HorselyColor.onSurfaceVariant)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(HorseDescription.accessibilityName(horse) + ", " + HorseDescription.passportLine(horse, today: today))
    }
}
