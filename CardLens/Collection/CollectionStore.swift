import Foundation
import SwiftData

/// Collection rules: merging, valuation, price updates and value history.
enum CollectionStore {
    /// Adds copies, merging with an existing entry of the same card, printing and condition.
    @MainActor
    @discardableResult
    static func add(match: CardMatch, variantKey: String, condition: CardCondition, quantity: Int,
                    unitPrice: Double?, checkedAt: Date?, context: ModelContext) -> CollectionItem {
        let cardId = match.id
        let conditionRaw = condition.rawValue
        let descriptor = FetchDescriptor<CollectionItem>(predicate: #Predicate {
            $0.cardId == cardId && $0.variantKey == variantKey && $0.conditionRaw == conditionRaw
        })
        if let existing = try? context.fetch(descriptor).first {
            existing.quantity += quantity
            if let unitPrice {
                existing.unitPrice = unitPrice
                existing.priceCheckedAt = checkedAt
            }
            try? context.save()
            return existing
        }
        let item = CollectionItem(match: match, variantKey: variantKey, condition: condition,
                                  quantity: quantity, unitPrice: unitPrice, priceCheckedAt: checkedAt)
        context.insert(item)
        try? context.save()
        return item
    }

    /// Updates each item's price from a fresh quote for its card.
    /// An item whose printing has no market price gets `nil`, never a guess.
    @MainActor
    static func apply(_ quote: PriceQuote?, to items: [CollectionItem], checkedAt: Date) {
        for item in items {
            item.unitPrice = quote?.variants.first(where: { $0.key == item.variantKey })?.market
            item.priceCheckedAt = checkedAt
        }
    }

    struct Summary: Equatable {
        var totalValue: Double
        var copies: Int
        var unique: Int
        var unpricedCopies: Int
    }

    static func summary(of items: [(quantity: Int, unitPrice: Double?)]) -> Summary {
        var summary = Summary(totalValue: 0, copies: 0, unique: items.count, unpricedCopies: 0)
        for item in items {
            summary.copies += item.quantity
            if let price = item.unitPrice {
                summary.totalValue += price * Double(item.quantity)
            } else {
                summary.unpricedCopies += item.quantity
            }
        }
        return summary
    }

    // MARK: Value history

    struct Holding {
        let cardId: String
        let variantKey: String
        let quantity: Int
        let addedAt: Date
    }

    struct Observation {
        let cardId: String
        let variantKey: String
        let market: Double
        let date: Date
    }

    struct ValuePoint: Equatable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Daily collection value, using only prices actually observed on or before each day
    /// and only cards already in the collection by then.
    static func valueHistory(holdings: [Holding], observations: [Observation],
                             calendar: Calendar = .current) -> [ValuePoint] {
        let owned = Set(holdings.map { "\($0.cardId)|\($0.variantKey)" })
        let relevant = observations
            .filter { owned.contains("\($0.cardId)|\($0.variantKey)") }
            .sorted { $0.date < $1.date }
        guard !relevant.isEmpty else { return [] }

        // A point for every day a price was observed or a card was added.
        let firstDay = calendar.startOfDay(for: relevant[0].date)
        let days = Set(relevant.map { calendar.startOfDay(for: $0.date) }
                       + holdings.map { calendar.startOfDay(for: $0.addedAt) }.filter { $0 >= firstDay }).sorted()
        var points: [ValuePoint] = []
        for day in days {
            guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            var latest: [String: Double] = [:]
            for observation in relevant where observation.date < end {
                latest["\(observation.cardId)|\(observation.variantKey)"] = observation.market
            }
            var value = 0.0
            var anyPriced = false
            for holding in holdings where holding.addedAt < end {
                if let price = latest["\(holding.cardId)|\(holding.variantKey)"] {
                    value += price * Double(holding.quantity)
                    anyPriced = true
                }
            }
            if anyPriced { points.append(ValuePoint(date: day, value: value)) }
        }
        return points
    }
}

/// Re-prices every card in the collection.
@MainActor
enum CollectionRefresher {
    struct Outcome { var updated = 0; var failed = 0 }

    static func refresh(_ items: [CollectionItem], context: ModelContext,
                        service: PriceService = TCGdexPriceService()) async -> Outcome {
        let cardIds = Array(Set(items.map(\.cardId)))
        var outcome = Outcome()
        // Small batches keep the free API happy.
        for batch in stride(from: 0, to: cardIds.count, by: 4).map({ Array(cardIds[$0..<min($0 + 4, cardIds.count)]) }) {
            let results = await withTaskGroup(of: (String, Result<PriceQuote?, Error>).self) { group in
                for id in batch {
                    group.addTask {
                        do { return (id, .success(try await service.price(for: id))) } catch { return (id, .failure(error)) }
                    }
                }
                var collected: [(String, Result<PriceQuote?, Error>)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for (id, result) in results {
                switch result {
                case .success(let quote):
                    if let quote { PriceHistory.record(quote, in: context) }
                    CollectionStore.apply(quote, to: items.filter { $0.cardId == id }, checkedAt: quote?.checkedAt ?? .now)
                    outcome.updated += 1
                case .failure:
                    outcome.failed += 1
                }
            }
        }
        try? context.save()
        return outcome
    }
}
