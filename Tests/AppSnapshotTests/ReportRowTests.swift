import HorselyCore
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Horsely

/// Układ karty wiersza raportu (T105, FR-027/028): długie „Uwagi” zawijają się pod etykietę przy tekście 200 % na ekranie
/// szerokości 320 pt; karta rozwinięta („Więcej szczegółów”) pokazuje wszystkie kolumny.
@MainActor
final class ReportRowTests: XCTestCase {
    private let columns = [
        ReportColumn(ReportTexts.horse), ReportColumn(ReportTexts.balanceStatus), ReportColumn(ReportTexts.balancePurchase, .money),
        ReportColumn(ReportTexts.costs, .money), ReportColumn(ReportTexts.balancePrizes, .money), ReportColumn(ReportTexts.balanceSale, .money),
        ReportColumn(ReportTexts.balanceResult, .money), ReportColumn(ReportTexts.balanceRemarks),
    ]

    private var cells: [ReportValue?] {
        [
            .text("Źrebak Łatek"), .text(ReportTexts.status(.active)), nil, .number(Money(4250.5)), .number(Money(300)), nil,
            .number(Money(-3950.5)),
            .text([ReportTexts.balanceLoss, ReportTexts.balanceNoPurchase, ReportTexts.balanceNotSold].joined(separator: "; ")),
        ]
    }

    func testExpandedRowWithRemarksAtLargeText() {
        for variant in SnapshotVariant.allCases {
            let view = ScrollView {
                ReportRowCard(columns: columns, cells: cells, expanded: true).padding(Spacing.screenEdge)
            }
            .background(HorselyColor.background)
            let controller = UIHostingController(rootView: view.tint(HorselyColor.primary))
            assertSnapshot(
                of: controller,
                as: .image(drawHierarchyInKeyWindow: true, precision: 0.98, perceptualPrecision: 0.98, size: CGSize(width: 320, height: 1400), traits: variant.traits),
                named: "report-row-expanded-\(variant.rawValue)"
            )
        }
    }

    func testCollapsedRowShowsThreeValues() {
        let view = ScrollView { ReportRowCard(columns: columns, cells: cells).padding(Spacing.screenEdge) }.background(HorselyColor.background)
        let controller = UIHostingController(rootView: view.tint(HorselyColor.primary))
        assertSnapshot(
            of: controller,
            as: .image(drawHierarchyInKeyWindow: true, precision: 0.98, perceptualPrecision: 0.98, size: CGSize(width: 320, height: 400),
                       traits: SnapshotVariant.light.traits),
            named: "report-row-collapsed"
        )
    }
}
