import Foundation

// MARK: - TCGdex API payloads

/// Brief card entry returned by `/cards?…` searches.
struct CardSummary: Decodable, Hashable, Sendable {
    let id: String
    let localId: String
    let name: String
    let image: String?

    /// TCGdex ids are "<setId>-<localId>".
    var setId: String {
        guard id.hasSuffix("-" + localId) else {
            return id.components(separatedBy: "-").dropLast().joined(separator: "-")
        }
        return String(id.dropLast(localId.count + 1))
    }

    /// Pokémon TCG Pocket cards are digital-only and have no market value, so they are excluded.
    var isDigitalOnly: Bool {
        image?.contains("/tcgp/") ?? false
    }
}

struct SetSummary: Decodable, Hashable, Sendable {
    let id: String
    let name: String
    let cardCount: CardCount?
}

struct CardCount: Decodable, Hashable, Sendable {
    let official: Int?
    let total: Int?
}

struct SetInfo: Decodable, Hashable, Sendable {
    let id: String
    let name: String
    let symbol: String?
    let cardCount: CardCount?
}

/// Full card returned by `/cards/{id}`.
struct CardDetail: Decodable, Sendable {
    let id: String
    let localId: String
    let name: String
    let image: String?
    let rarity: String?
    let illustrator: String?
    let set: SetInfo
    let pricing: CardPricing?
}

struct CardPricing: Decodable, Sendable {
    let tcgplayer: TCGPlayerPricing?
}

/// TCGplayer block. Variant names ("normal", "holofoil", "reverse-holofoil", …) are dynamic keys.
struct TCGPlayerPricing: Decodable, Sendable {
    let unit: String?
    let updated: Date?
    let variants: [String: TCGPlayerVariantPrice]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(unit: String?, updated: Date?, variants: [String: TCGPlayerVariantPrice]) {
        self.unit = unit
        self.updated = updated
        self.variants = variants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var unit: String?
        var updated: Date?
        var variants: [String: TCGPlayerVariantPrice] = [:]
        for key in container.allKeys {
            switch key.stringValue {
            case "unit":
                unit = try? container.decode(String.self, forKey: key)
            case "updated":
                if let raw = try? container.decode(String.self, forKey: key) {
                    updated = ISO8601.parse(raw)
                }
            default:
                if let price = try? container.decode(TCGPlayerVariantPrice.self, forKey: key) {
                    variants[key.stringValue] = price
                }
            }
        }
        self.init(unit: unit, updated: updated, variants: variants)
    }
}

struct TCGPlayerVariantPrice: Decodable, Hashable, Sendable {
    let productId: Int?
    let lowPrice: Double?
    let midPrice: Double?
    let highPrice: Double?
    let marketPrice: Double?
}

enum ISO8601 {
    static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

// MARK: - App domain

enum ConfidenceLevel: String, Codable, Sendable {
    case high, medium, low

    var label: String {
        switch self {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }
}

/// A catalog card that may match the scanned photo.
struct CardMatch: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let number: String
    let setId: String
    let setName: String
    let setOfficialCount: Int?
    let rarity: String?
    let imageBase: String?

    /// 0…1 overall score for this candidate.
    var score: Double = 0
    /// 0…1 artwork similarity, if it could be computed.
    var visualSimilarity: Double?
    var confidence: ConfidenceLevel = .low

    var imageURL: URL? { imageBase.flatMap { URL(string: $0 + "/high.webp") } }
    var thumbnailURL: URL? { imageBase.flatMap { URL(string: $0 + "/low.jpg") } }
    var comparisonImageURL: URL? { imageBase.flatMap { URL(string: $0 + "/low.jpg") } }

    var numberDisplay: String {
        if let total = setOfficialCount { "\(number)/\(total)" } else { number }
    }

    var accessibilityNumber: String {
        if let total = setOfficialCount { "number \(number) of \(total)" } else { "number \(number)" }
    }

    init(id: String, name: String, number: String, setId: String, setName: String,
         setOfficialCount: Int?, rarity: String?, imageBase: String?) {
        self.id = id
        self.name = name
        self.number = number
        self.setId = setId
        self.setName = setName
        self.setOfficialCount = setOfficialCount
        self.rarity = rarity
        self.imageBase = imageBase
    }

    init(detail: CardDetail) {
        self.init(id: detail.id, name: detail.name, number: detail.localId, setId: detail.set.id,
                  setName: detail.set.name, setOfficialCount: detail.set.cardCount?.official,
                  rarity: detail.rarity, imageBase: detail.image)
    }
}

/// One printing (normal / holofoil / reverse holo…) with its USD prices.
struct VariantPrice: Identifiable, Hashable, Sendable {
    let key: String
    let market: Double?
    let low: Double?
    let mid: Double?
    let high: Double?
    let productId: Int?

    var id: String { key }

    var displayName: String { Self.displayName(for: key) }

    static func displayName(for key: String) -> String {
        switch key {
        case "normal": "Normal"
        case "holofoil": "Holofoil"
        case "reverse-holofoil": "Reverse Holofoil"
        case "1st-edition": "1st Edition"
        case "1st-edition-holofoil": "1st Edition Holofoil"
        case "unlimited": "Unlimited"
        case "unlimited-holofoil": "Unlimited Holofoil"
        default: key.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    var productURL: URL? {
        productId.flatMap { URL(string: "https://www.tcgplayer.com/product/\($0)") }
    }
}

struct PriceQuote: Sendable, Equatable {
    let cardId: String
    let currency: String
    let variants: [VariantPrice]
    let source: String
    /// When the provider last updated this price.
    let sourceUpdated: Date?
    /// When this app fetched it.
    let checkedAt: Date

    /// The variant to headline, chosen from the card's rarity.
    func primaryVariant(rarity: String?) -> VariantPrice? {
        let priced = variants.filter { $0.market != nil }
        guard !priced.isEmpty else { return nil }
        let isHolo = rarity?.localizedCaseInsensitiveContains("holo") == true
            || rarity?.localizedCaseInsensitiveContains("rare") == true
        let preference = isHolo
            ? ["holofoil", "unlimited-holofoil", "1st-edition-holofoil", "normal", "unlimited", "reverse-holofoil"]
            : ["normal", "unlimited", "holofoil", "reverse-holofoil", "1st-edition"]
        for key in preference {
            if let match = priced.first(where: { $0.key == key }) { return match }
        }
        return priced.first
    }
}
