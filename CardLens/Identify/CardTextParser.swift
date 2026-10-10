import CoreGraphics
import Foundation

/// One line of text found on the card.
/// `box` is normalized (0…1) with the origin at the top-left of the card.
struct RecognizedLine: Equatable, Sendable {
    let text: String
    let box: CGRect
    let confidence: Float
}

/// What could be read from the card's printed text.
struct ParsedCardText: Equatable, Sendable {
    /// Likely card names, best guess first.
    var names: [String] = []
    /// Collector number as printed, e.g. "006", "TG05", "SWSH050".
    var number: String?
    /// The "/198" part of the collector number, if printed.
    var setTotal: String?
    var hp: Int?

    var isEmpty: Bool { names.isEmpty && number == nil }
}

enum CardTextParser {
    /// Words printed near the card name that are never part of it.
    private static let stopWords: Set<String> = [
        "basic", "stage", "stage1", "stage2", "evolves", "from", "put", "on", "the", "of",
        "hp", "trainer", "supporter", "item", "stadium", "tool", "pokemon", "pokémon", "tool",
        "energy", "special", "rule", "ability", "poke-power", "poke-body", "restored", "level", "lv",
        "mega", "evolution", "tera", "ace", "spec", "radiant"
    ]

    /// Suffixes that ARE part of card names in the catalog ("Charizard ex", "Pikachu VMAX").
    private static let nameSuffixes: Set<String> = ["ex", "gx", "v", "vmax", "vstar", "break", "lv.x", "prime", "δ", "star"]

    static func parse(_ lines: [RecognizedLine]) -> ParsedCardText {
        var result = ParsedCardText()
        let (number, total) = collectorNumber(in: lines)
        result.number = number
        result.setTotal = total
        result.hp = hitPoints(in: lines)
        result.names = nameCandidates(in: lines)
        return result
    }

    // MARK: Collector number

    private static let fractionRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])([A-Z]{0,4}\d{1,3}[a-z]?)\s*/\s*([A-Z]{0,4}\d{1,3})(?!\d)"#)

    private static let promoRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])(SWSH|SVP|SV|SM|XY|BW|DP|HGSS)\s?-?\s?(\d{2,3})(?!\d)"#,
        options: [.caseInsensitive])

    static func collectorNumber(in lines: [RecognizedLine]) -> (String?, String?) {
        // The number sits at the bottom of the card, so search bottom lines first.
        let ordered = lines.sorted { $0.box.midY > $1.box.midY }
        for line in ordered {
            let text = line.text
            let range = NSRange(text.startIndex..., in: text)
            if let match = fractionRegex.firstMatch(in: text, range: range),
               let numberRange = Range(match.range(at: 1), in: text),
               let totalRange = Range(match.range(at: 2), in: text) {
                let number = String(text[numberRange])
                let total = String(text[totalRange])
                // Ignore damage counters like "30/60" that are not collector numbers.
                if line.box.midY > 0.55 || lines.count < 4 {
                    return (number, total)
                }
            }
        }
        for line in ordered where line.box.midY > 0.55 || lines.count < 4 {
            let text = line.text
            let range = NSRange(text.startIndex..., in: text)
            if let match = promoRegex.firstMatch(in: text, range: range),
               let prefixRange = Range(match.range(at: 1), in: text),
               let digitsRange = Range(match.range(at: 2), in: text) {
                return (text[prefixRange].uppercased() + text[digitsRange], nil)
            }
        }
        return (nil, nil)
    }

    // MARK: HP

    private static let hpRegex = try! NSRegularExpression(
        pattern: #"(?:HP\s*(\d{2,3}))|(?:(\d{2,3})\s*HP)"#, options: [.caseInsensitive])

    static func hitPoints(in lines: [RecognizedLine]) -> Int? {
        for line in lines.sorted(by: { $0.box.midY < $1.box.midY }) {
            let text = line.text
            let range = NSRange(text.startIndex..., in: text)
            guard let match = hpRegex.firstMatch(in: text, range: range) else { continue }
            for group in 1...2 {
                if let r = Range(match.range(at: group), in: text), let value = Int(text[r]) {
                    return value
                }
            }
        }
        return nil
    }

    // MARK: Name

    static func nameCandidates(in lines: [RecognizedLine]) -> [String] {
        let topBand = lines.filter { $0.box.minY < 0.22 }
        let pool = topBand.isEmpty ? lines : topBand
        // The card name uses the largest type in the header.
        let sorted = pool.sorted { $0.box.height > $1.box.height }

        var seen = Set<String>()
        var names: [String] = []
        for line in sorted {
            guard let cleaned = cleanName(line.text) else { continue }
            let key = cleaned.lowercased()
            if seen.insert(key).inserted { names.append(cleaned) }
            if names.count == 3 { break }
        }
        return names
    }

    /// Strips HP values, stage labels and stray symbols. Returns nil if nothing name-like remains.
    static func cleanName(_ raw: String) -> String? {
        var text = raw
        text = text.replacingOccurrences(of: #"(?i)HP\s*\d+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)\d+\s*HP"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[^\p{L}\s'’\.\-&♀♂δ]"#, with: " ", options: .regularExpression)

        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let kept = tokens.filter { token in
            let lower = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".-'’"))
            if nameSuffixes.contains(lower) { return true }
            if stopWords.contains(lower) { return false }
            return lower.count >= 2
        }
        // A name needs at least one real word, not just a suffix.
        guard kept.contains(where: { !nameSuffixes.contains($0.lowercased()) && $0.count >= 3 }) else { return nil }
        let name = kept.joined(separator: " ")
        return name.count >= 3 ? name : nil
    }
}
