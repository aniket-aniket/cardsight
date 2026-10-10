import Foundation
import SwiftData

enum CardCondition: String, CaseIterable, Identifiable, Codable {
    case nearMint = "NM"
    case lightlyPlayed = "LP"
    case moderatelyPlayed = "MP"
    case heavilyPlayed = "HP"
    case damaged = "DMG"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nearMint: "Near Mint"
        case .lightlyPlayed: "Lightly Played"
        case .moderatelyPlayed: "Moderately Played"
        case .heavilyPlayed: "Heavily Played"
        case .damaged: "Damaged"
        }
    }
}

/// A card the user owns.
@Model
final class CollectionItem {
    var id: UUID
    var addedAt: Date

    var cardId: String
    var name: String
    var number: String
    var setId: String
    var setName: String
    var setOfficialCount: Int?
    var rarity: String?
    var imageBase: String?

    var variantKey: String
    var conditionRaw: String
    var quantity: Int

    /// Latest market price for one copy of this printing, if known.
    var unitPrice: Double?
    var priceCheckedAt: Date?

    init(match: CardMatch, variantKey: String, condition: CardCondition, quantity: Int,
         unitPrice: Double?, priceCheckedAt: Date?, addedAt: Date = .now) {
        id = UUID()
        self.addedAt = addedAt
        cardId = match.id
        name = match.name
        number = match.number
        setId = match.setId
        setName = match.setName
        setOfficialCount = match.setOfficialCount
        rarity = match.rarity
        imageBase = match.imageBase
        self.variantKey = variantKey
        conditionRaw = condition.rawValue
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.priceCheckedAt = priceCheckedAt
    }

    var condition: CardCondition {
        get { CardCondition(rawValue: conditionRaw) ?? .nearMint }
        set { conditionRaw = newValue.rawValue }
    }

    var variantName: String { VariantPrice.displayName(for: variantKey) }

    var totalValue: Double? { unitPrice.map { $0 * Double(quantity) } }

    var match: CardMatch {
        var match = CardMatch(id: cardId, name: name, number: number, setId: setId, setName: setName,
                              setOfficialCount: setOfficialCount, rarity: rarity, imageBase: imageBase)
        match.confidence = .high
        return match
    }
}
