import Foundation

/// Koń uczestniczący w zakupie (id i imię do porządku podziału).
public struct HorseName: Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Udział konia w koszcie zakupu; `horseId` = `nil` dla zakupu ogólnego (stajnia).
public struct CostShare: Sendable, Equatable {
    public let horseId: String?
    public let amount: Money

    public init(horseId: String?, amount: Money) {
        self.horseId = horseId
        self.amount = amount
    }
}

/// Podział zakupu na konie (`CostAllocator`, FR-RAP-03): jeden koń — cała kwota; kilka koni — równe części w groszach, reszta groszowa
/// do pierwszego konia wg imienia (pl-PL); ogólny — jeden udział bez konia. Kwota to `totalAmount + deliveryCost`.
public enum PurchaseSplit {
    public static func allocate(_ total: Money, assignment: PurchaseAssignment, horses: [HorseName]) -> [CostShare] {
        if assignment == .general || horses.isEmpty { return [CostShare(horseId: nil, amount: total)] }
        let ordered = horses.sorted { lhs, rhs in
            let order = PolishNames.compare(lhs.name, rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
        if assignment == .singleHorse || ordered.count == 1 { return [CostShare(horseId: ordered[0].id, amount: total)] }

        var grosze = Decimal()
        var source = total.value * 100
        NSDecimalRound(&grosze, &source, 0, .plain)
        let count = Decimal(ordered.count)
        var share = grosze / count
        var roundedShare = Decimal()
        NSDecimalRound(&roundedShare, &share, 0, .down)
        let remainder = grosze - roundedShare * count
        return ordered.enumerated().map { index, horse in
            let cents = roundedShare + (index == 0 ? remainder : 0)
            return CostShare(horseId: horse.id, amount: Money(cents / 100))
        }
    }
}
