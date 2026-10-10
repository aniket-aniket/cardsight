import Foundation
import SwiftData

/// A saved scan shown in Recent Scans.
@Model
final class ScanRecord {
    var id: UUID
    var scannedAt: Date

    var cardId: String
    var name: String
    var number: String
    var setId: String
    var setName: String
    var setOfficialCount: Int?
    var rarity: String?
    var imageBase: String?
    var confidenceRaw: String

    @Attribute(.externalStorage) var photoThumbnail: Data?

    var lastMarketPrice: Double?
    var lastPriceVariant: String?
    var lastPriceCheckedAt: Date?

    init(match: CardMatch, photoThumbnail: Data?, scannedAt: Date = .now) {
        id = UUID()
        self.scannedAt = scannedAt
        cardId = match.id
        name = match.name
        number = match.number
        setId = match.setId
        setName = match.setName
        setOfficialCount = match.setOfficialCount
        rarity = match.rarity
        imageBase = match.imageBase
        confidenceRaw = match.confidence.rawValue
        self.photoThumbnail = photoThumbnail
    }

    var confidence: ConfidenceLevel { ConfidenceLevel(rawValue: confidenceRaw) ?? .low }

    var match: CardMatch {
        var match = CardMatch(id: cardId, name: name, number: number, setId: setId, setName: setName,
                              setOfficialCount: setOfficialCount, rarity: rarity, imageBase: imageBase)
        match.confidence = confidence
        return match
    }

    /// Called when the user picks a different candidate for this scan.
    func update(with match: CardMatch) {
        guard match.id != cardId else { return }
        cardId = match.id
        name = match.name
        number = match.number
        setId = match.setId
        setName = match.setName
        setOfficialCount = match.setOfficialCount
        rarity = match.rarity
        imageBase = match.imageBase
        confidenceRaw = match.confidence.rawValue
        lastMarketPrice = nil
        lastPriceVariant = nil
        lastPriceCheckedAt = nil
    }

    func update(with quote: PriceQuote?, checkedAt: Date) {
        let primary = quote?.primaryVariant(rarity: rarity)
        lastMarketPrice = primary?.market
        lastPriceVariant = primary?.displayName
        lastPriceCheckedAt = checkedAt
    }
}
