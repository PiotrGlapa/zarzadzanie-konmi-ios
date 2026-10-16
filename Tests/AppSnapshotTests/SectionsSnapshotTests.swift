import HorselyCore
import HorselyKit
import SwiftUI
import XCTest
@testable import Horsely

/// Testy migawkowe działów (T103): Treningi, Zakupy, Zawody i Kontakty na danych `SnapshotEntries` (dziś 2026-10-05);
/// jasny / ciemny / tekst 200 %.
@MainActor
final class SectionsSnapshotTests: XCTestCase {
    private func environment(_ variant: SnapshotVariant) async throws -> AppEnvironment {
        let env = makeEnvironment(mode: .standalone, variant: variant)
        _ = try await SnapshotEntries.seed(env)
        _ = try await env.entries.saveContact(ContactInput(name: "Anna Trenerka", types: [.trainer], phone: "600 100 200", email: "anna@stajnia.pl"))
        _ = try await env.entries.saveContact(ContactInput(name: "Sklep Jeździecki", types: [.shop], address: "ul. Polna 1, Warszawa"))
        return env
    }

    func testTrainingsSection() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(TrainingsSectionView().environment(env), name: "section-trainings", variant: variant)
        }
    }

    func testPurchasesSection() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(NavigationStack { PurchasesView() }.environment(env), name: "section-purchases", variant: variant)
        }
    }

    func testCompetitionsSection() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(NavigationStack { CompetitionsView() }.environment(env), name: "section-competitions", variant: variant)
        }
    }

    func testContacts() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(NavigationStack { ContactsView() }.environment(env), name: "section-contacts", variant: variant)
        }
    }
}
