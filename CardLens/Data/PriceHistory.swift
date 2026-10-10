import Foundation
import SwiftData

/// One observed market price for one printing of a card.
/// The free price source has no history, so history builds up from these snapshots.
@Model
final class PriceSnapshot {
    var cardId: String
    var variantKey: String
    var market: Double
    var sourceUpdated: Date?
    var recordedAt: Date

    init(cardId: String, variantKey: String, market: Double, sourceUpdated: Date?, recordedAt: Date) {
        self.cardId = cardId
        self.variantKey = variantKey
        self.market = market
        self.sourceUpdated = sourceUpdated
        self.recordedAt = recordedAt
    }
}

enum PriceHistory {
    /// Saves a snapshot for every priced printing in the quote, skipping repeats.
    @MainActor
    static func record(_ quote: PriceQuote, in context: ModelContext) {
        for variant in quote.variants {
            guard let market = variant.market else { continue }
            let cardId = quote.cardId
            let key = variant.key
            var descriptor = FetchDescriptor<PriceSnapshot>(
                predicate: #Predicate { $0.cardId == cardId && $0.variantKey == key },
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
            descriptor.fetchLimit = 1
            let last = try? context.fetch(descriptor).first

            if shouldRecord(lastMarket: last?.market, lastSourceUpdated: last?.sourceUpdated,
                            lastRecordedAt: last?.recordedAt, market: market,
                            sourceUpdated: quote.sourceUpdated, now: quote.checkedAt) {
                context.insert(PriceSnapshot(cardId: cardId, variantKey: key, market: market,
                                             sourceUpdated: quote.sourceUpdated, recordedAt: quote.checkedAt))
            }
        }
        try? context.save()
    }

    /// A snapshot is new information if the provider published a newer price,
    /// or (when it gives no timestamp) the price changed or six hours passed.
    static func shouldRecord(lastMarket: Double?, lastSourceUpdated: Date?, lastRecordedAt: Date?,
                             market: Double, sourceUpdated: Date?, now: Date) -> Bool {
        guard let lastRecordedAt else { return true }
        if let sourceUpdated, let lastSourceUpdated {
            return sourceUpdated > lastSourceUpdated
        }
        return lastMarket != market || now.timeIntervalSince(lastRecordedAt) > 6 * 3600
    }
}
