import HorselyCore
import HorselyKit
import Observation
import SwiftUI

/// Stan formularza konia (nowy i edycja): wartości, błędy z reguł programu, zdjęcie czekające na zapis, potwierdzenie porzucenia zmian.
@MainActor
@Observable
final class HorseFormModel {
    /// Edytowany koń; `nil` — nowy.
    let horse: LocalHorse?

    var draft: HorseDraft
    var intervalText: String
    /// Kwoty konia jako tekst (pola formularza); trafiają do `draft.finance` tylko, gdy użytkownik je zmienił.
    var purchasePriceText: String
    var salePriceText: String
    var estimatedValueText: String
    var purchaseDate: LocalDate?
    var saleDate: LocalDate?
    private(set) var financeTouched = false

    var errors: [String: [String]] = [:]
    var errorOrder: [String] = []
    var warnings: [String: [String]] = [:]
    var isSaving = false
    var failure: String?
    /// Zdjęcie wybrane przed zapisem konia („Zdjęcie zostanie zapisane razem z koniem”).
    var pendingPhoto: PreparedImage?
    var pendingPhotoRemoval = false

    @ObservationIgnored private let initial: Snapshot

    private struct Snapshot: Equatable {
        var draft: HorseDraft
        var interval: String
        var purchasePrice: String
        var salePrice: String
        var estimatedValue: String
        var purchaseDate: LocalDate?
        var saleDate: LocalDate?
    }

    init(horse: LocalHorse?) {
        self.horse = horse
        let draft = horse.map { HorseDraft(horse: $0) } ?? HorseDraft()
        self.draft = draft
        intervalText = String(draft.farrierIntervalWeeks ?? defaultFarrierIntervalWeeks)
        purchasePriceText = MoneyInput.format(horse?.purchasePrice)
        salePriceText = MoneyInput.format(horse?.salePrice)
        estimatedValueText = MoneyInput.format(horse?.estimatedValue)
        purchaseDate = horse?.purchaseDate
        saleDate = horse?.saleDate
        initial = Snapshot(
            draft: draft, interval: intervalText, purchasePrice: purchasePriceText, salePrice: salePriceText, estimatedValue: estimatedValueText,
            purchaseDate: purchaseDate, saleDate: saleDate
        )
    }

    var isEditing: Bool { horse != nil }

    /// Są niezapisane zmiany — przy wyjściu pytamy o porzucenie.
    var isDirty: Bool {
        pendingPhoto != nil || pendingPhotoRemoval
            || Snapshot(
                draft: draft, interval: intervalText, purchasePrice: purchasePriceText, salePrice: salePriceText, estimatedValue: estimatedValueText,
                purchaseDate: purchaseDate, saleDate: saleDate
            ) != initial
    }

    func markFinanceTouched() { financeTouched = true }

    func errors(for key: String) -> [String] { errors[key] ?? [] }

    /// Składa wartości formularza w szkic do reguł: interwał i kwoty z pól tekstowych, `finance` tylko po zmianie kwot.
    private func buildDraft() -> (draft: HorseDraft, parseErrors: [String: [String]]) {
        var result = draft
        var parseErrors: [String: [String]] = [:]

        let interval = intervalText.trimmingCharacters(in: .whitespaces)
        if interval.isEmpty {
            result.farrierIntervalWeeks = nil
        } else if let weeks = Int(interval) {
            result.farrierIntervalWeeks = weeks
        } else {
            result.farrierIntervalWeeks = 0 // poza zakresem 1–26 → komunikat reguły
        }

        if financeTouched {
            func amount(_ text: String, _ key: String) -> Money? {
                switch MoneyInput.parse(text) {
                case .empty: return nil
                case let .valid(money): return money
                case let .invalid(reason):
                    parseErrors[key] = [reason.message]
                    return nil
                }
            }
            result.finance = HorseFinanceDraft(
                purchasePrice: amount(purchasePriceText, "finance.purchasePrice"), purchaseDate: purchaseDate,
                salePrice: amount(salePriceText, "finance.salePrice"), saleDate: saleDate,
                estimatedValue: amount(estimatedValueText, "finance.estimatedValue")
            )
        }
        return (result, parseErrors)
    }

    /// Zapisuje konia; `true` po powodzeniu. Błędy walidacji i konfliktu zostają w `errors` przy polach, dane formularza są zachowane.
    func save(using environment: AppEnvironment) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        failure = nil
        let (built, parseErrors) = buildDraft()
        if !parseErrors.isEmpty {
            errors = parseErrors
            errorOrder = Array(parseErrors.keys)
            return false
        }
        do {
            let outcome = try await environment.horses.save(built, id: horse?.id)
            switch outcome {
            case let .saved(saved, warnings):
                self.warnings = warnings
                errors = [:]
                errorOrder = []
                try await applyPhoto(to: saved.id, using: environment)
                return true
            case let .invalid(report):
                errors = report.errors
                errorOrder = report.errorOrder
                warnings = report.warnings
                return false
            case let .conflict(problem):
                errors = [problem.field: [problem.message]]
                errorOrder = [problem.field]
                return false
            }
        } catch {
            environment.log.log("horse-form", "Zapis konia nie powiódł się: \(error.localizedDescription)")
            failure = error.localizedDescription
            return false
        }
    }

    private func applyPhoto(to horseId: String, using environment: AppEnvironment) async throws {
        if let pendingPhoto {
            try await environment.horses.setPhoto(horseId: horseId, image: pendingPhoto)
        } else if pendingPhotoRemoval {
            try await environment.horses.clearPhoto(horseId: horseId)
        }
    }
}
