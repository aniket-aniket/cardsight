import SwiftData
import XCTest
@testable import CardLens

@MainActor
final class CollectionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(for: CollectionItem.self, PriceSnapshot.self, ScanRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private let charizard = CardMatch(id: "base1-4", name: "Charizard", number: "4", setId: "base1",
                                      setName: "Base Set", setOfficialCount: 102, rarity: "Rare",
                                      imageBase: "https://assets.tcgdex.net/en/base/base1/4")

    private func quote(_ prices: [String: Double?], updated: Date?, checked: Date = .now) -> PriceQuote {
        PriceQuote(cardId: "base1-4", currency: "USD",
                   variants: prices.map { VariantPrice(key: $0.key, market: $0.value, low: nil, mid: nil, high: nil, productId: nil) },
                   source: "test", sourceUpdated: updated, checkedAt: checked)
    }

    func testAddingSameCardMergesQuantity() throws {
        CollectionStore.add(match: charizard, variantKey: "holofoil", condition: .nearMint, quantity: 1,
                            unitPrice: 900, checkedAt: .now, context: context)
        CollectionStore.add(match: charizard, variantKey: "holofoil", condition: .nearMint, quantity: 2,
                            unitPrice: 910, checkedAt: .now, context: context)
        // Different condition is a separate entry.
        CollectionStore.add(match: charizard, variantKey: "holofoil", condition: .lightlyPlayed, quantity: 1,
                            unitPrice: 910, checkedAt: .now, context: context)

        let items = try context.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 2)
        let nm = try XCTUnwrap(items.first { $0.condition == .nearMint })
        XCTAssertEqual(nm.quantity, 3)
        XCTAssertEqual(nm.unitPrice, 910)
        XCTAssertEqual(nm.totalValue, 2730)
    }

    func testApplyNeverInventsPrice() {
        let item = CollectionStore.add(match: charizard, variantKey: "reverse-holofoil", condition: .nearMint,
                                       quantity: 1, unitPrice: 5, checkedAt: .now, context: context)
        CollectionStore.apply(quote(["holofoil": 900], updated: .now), to: [item], checkedAt: .now)
        XCTAssertNil(item.unitPrice, "A printing missing from the quote must become unpriced, not keep a stale or other price")
    }

    func testSummaryExcludesUnpriced() {
        let summary = CollectionStore.summary(of: [(2, 10), (1, nil), (3, 1.5)])
        XCTAssertEqual(summary.totalValue, 24.5, accuracy: 0.001)
        XCTAssertEqual(summary.copies, 6)
        XCTAssertEqual(summary.unique, 3)
        XCTAssertEqual(summary.unpricedCopies, 1)
    }

    func testSnapshotsSkipRepeatsOfSameProviderUpdate() throws {
        let published = Date(timeIntervalSince1970: 1_800_000_000)
        PriceHistory.record(quote(["holofoil": 900], updated: published), in: context)
        PriceHistory.record(quote(["holofoil": 900], updated: published), in: context)
        PriceHistory.record(quote(["holofoil": 920], updated: published.addingTimeInterval(86_400)), in: context)
        let snapshots = try context.fetch(FetchDescriptor<PriceSnapshot>())
        XCTAssertEqual(snapshots.count, 2)
    }

    func testShouldRecordWithoutProviderTimestamp() {
        let now = Date()
        XCTAssertTrue(PriceHistory.shouldRecord(lastMarket: nil, lastSourceUpdated: nil, lastRecordedAt: nil,
                                                market: 1, sourceUpdated: nil, now: now))
        XCTAssertFalse(PriceHistory.shouldRecord(lastMarket: 1, lastSourceUpdated: nil, lastRecordedAt: now.addingTimeInterval(-60),
                                                 market: 1, sourceUpdated: nil, now: now))
        XCTAssertTrue(PriceHistory.shouldRecord(lastMarket: 1, lastSourceUpdated: nil, lastRecordedAt: now.addingTimeInterval(-60),
                                                market: 2, sourceUpdated: nil, now: now))
    }

    func testValueHistoryUsesOnlyObservedPricesAndOwnedCards() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let day3 = day2.addingTimeInterval(86_400)

        let holdings: [CollectionStore.Holding] = [
            .init(cardId: "a", variantKey: "normal", quantity: 2, addedAt: day1),
            .init(cardId: "b", variantKey: "holofoil", quantity: 1, addedAt: day2),  // bought on day 2
        ]
        let observations: [CollectionStore.Observation] = [
            .init(cardId: "a", variantKey: "normal", market: 10, date: day1),
            .init(cardId: "b", variantKey: "holofoil", market: 100, date: day1),     // not owned yet on day 1
            .init(cardId: "a", variantKey: "normal", market: 12, date: day3),
            .init(cardId: "z", variantKey: "normal", market: 999, date: day2),       // not owned at all
        ]
        let points = CollectionStore.valueHistory(holdings: holdings, observations: observations, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [20, 120, 124])
    }
}
