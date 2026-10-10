import Foundation

/// Looks up the current market value for an already-identified card.
/// Kept separate from identification so the pricing provider can change on its own.
protocol PriceService: Sendable {
    func price(for cardId: String) async throws -> PriceQuote?
}

/// Reads TCGplayer USD prices that TCGdex publishes for each card.
/// Returns `nil` when no live USD price exists. It never guesses.
struct TCGdexPriceService: PriceService {
    var catalog: CardCatalog = TCGdexClient.shared
    var now: @Sendable () -> Date = { Date() }

    func price(for cardId: String) async throws -> PriceQuote? {
        let detail = try await catalog.card(id: cardId)
        return Self.quote(from: detail, checkedAt: now())
    }

    static func quote(from detail: CardDetail, checkedAt: Date) -> PriceQuote? {
        guard let tcgplayer = detail.pricing?.tcgplayer,
              (tcgplayer.unit ?? "USD").uppercased() == "USD" else { return nil }

        let variants = tcgplayer.variants
            .map { key, value in
                VariantPrice(key: key, market: value.marketPrice, low: value.lowPrice,
                             mid: value.midPrice, high: value.highPrice, productId: value.productId)
            }
            .filter { $0.market != nil || $0.low != nil || $0.mid != nil }
            .sorted { ($0.market ?? 0) > ($1.market ?? 0) }

        guard !variants.isEmpty else { return nil }

        return PriceQuote(cardId: detail.id, currency: "USD", variants: variants,
                          source: AppConfig.priceSourceName, sourceUpdated: tcgplayer.updated,
                          checkedAt: checkedAt)
    }
}
