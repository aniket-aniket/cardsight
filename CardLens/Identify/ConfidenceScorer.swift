import Foundation

/// Pure scoring rules for ranking catalog candidates against what was read from the photo.
enum ConfidenceScorer {
    static let nameWeight = 0.5
    static let numberWeight = 0.35
    static let setTotalWeight = 0.15
    static let textWeightInCombined = 0.6

    /// Minimum text score for a candidate to be shown at all.
    static let minimumTextScore = 0.35

    // MARK: Normalization

    static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "006" → "6", "TG05" → "TG5", "swsh050" → "SWSH50".
    static func normalizeNumber(_ number: String) -> String {
        let upper = number.uppercased().trimmingCharacters(in: .whitespaces)
        let prefix = upper.prefix(while: { $0.isLetter })
        let rest = upper.dropFirst(prefix.count)
        let digits = rest.prefix(while: { $0.isNumber })
        let suffix = rest.dropFirst(digits.count)
        let trimmedDigits = String(digits.drop(while: { $0 == "0" }))
        let numberPart = trimmedDigits.isEmpty && !digits.isEmpty ? "0" : trimmedDigits
        return String(prefix) + numberPart + String(suffix)
    }

    // MARK: Name similarity

    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let x = fold(a), y = fold(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 1 }
        let distance = levenshtein(Array(x), Array(y))
        let ratio = 1 - Double(distance) / Double(max(x.count, y.count))

        // "Charizard" read from a "Charizard ex" card: the read name is a whole-word part of the candidate.
        let xWords = Set(x.split(separator: " ")), yWords = Set(y.split(separator: " "))
        let containment = (xWords.isSubset(of: yWords) || yWords.isSubset(of: xWords)) ? 0.85 : 0
        return max(ratio, containment)
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: Scores

    /// 0…1 score from printed text alone. Only signals that were actually read are weighted.
    static func textScore(name: String, number: String, setOfficialCount: Int?, parsed: ParsedCardText) -> Double {
        var weighted = 0.0
        var totalWeight = 0.0

        if !parsed.names.isEmpty {
            let best = parsed.names.map { nameSimilarity($0, name) }.max() ?? 0
            weighted += nameWeight * best
            totalWeight += nameWeight
        }
        if let read = parsed.number {
            weighted += numberWeight * (normalizeNumber(read) == normalizeNumber(number) ? 1 : 0)
            totalWeight += numberWeight
        }
        if let readTotal = parsed.setTotal, let official = setOfficialCount {
            let matches = Int(normalizeNumber(readTotal)) == official
            weighted += setTotalWeight * (matches ? 1 : 0)
            totalWeight += setTotalWeight
        }
        guard totalWeight > 0 else { return 0 }
        return weighted / totalWeight
    }

    static func combined(text: Double, visual: Double?) -> Double {
        guard let visual else { return text * 0.9 }
        return textWeightInCombined * text + (1 - textWeightInCombined) * visual
    }

    /// Confidence for the best match. A close runner-up (e.g. a reprint with identical artwork)
    /// or a missing collector number keeps confidence from being "high".
    static func level(best: Double, runnerUp: Double?, numberRead: Bool) -> ConfidenceLevel {
        let margin = best - (runnerUp ?? 0)
        if best >= 0.78 && margin >= 0.06 && numberRead { return .high }
        if best >= 0.55 && margin >= 0.02 { return .medium }
        if best >= 0.7 { return .medium }
        return .low
    }

    static func level(forCandidate score: Double) -> ConfidenceLevel {
        score >= 0.78 ? .high : (score >= 0.55 ? .medium : .low)
    }
}
