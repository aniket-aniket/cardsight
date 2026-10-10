import CoreGraphics
import Foundation
import Vision

enum IdentificationStep: String, Sendable {
    case readingText = "Reading the card…"
    case searching = "Searching the card database…"
    case comparingArtwork = "Comparing artwork…"
}

struct IdentificationResult: Sendable {
    /// Ranked best first. Never empty.
    let matches: [CardMatch]
    let parsed: ParsedCardText
}

/// Identifies a card from a cropped photo. This step finds *which* card it is and does no pricing.
///
/// 1. Reads the name and collector number on-device (Vision OCR).
/// 2. Looks those up in the TCGdex catalog.
/// 3. Re-ranks candidates by comparing the photo with each official card image.
struct CardIdentifier {
    var catalog: CardCatalog = TCGdexClient.shared
    var imageSession: URLSession = .shared

    /// - Parameters:
    ///   - photo: The cropped, upright card photo.
    ///   - ocrImage: The same photo, upscaled if small, for text recognition.
    func identify(photo: CGImage, ocrImage: CGImage,
                  progress: @escaping @MainActor (IdentificationStep) -> Void) async throws -> IdentificationResult {
        await progress(.readingText)
        let lines = try await TextRecognizer.recognize(in: ocrImage)
        let parsed = CardTextParser.parse(lines)
        guard !parsed.isEmpty else { throw AppError.noTextFound }
        try Task.checkCancellation()

        await progress(.searching)
        let summaries = try await findCandidates(for: parsed)
        let setsById = Dictionary((try? await catalog.sets())?.map { ($0.id, $0) } ?? [], uniquingKeysWith: { a, _ in a })

        var scored: [(summary: CardSummary, text: Double)] = summaries.map { summary in
            let official = setsById[summary.setId]?.cardCount?.official
            let text = ConfidenceScorer.textScore(name: summary.name, number: summary.localId,
                                                  setOfficialCount: official, parsed: parsed)
            return (summary, text)
        }
        scored = scored.filter { $0.text >= ConfidenceScorer.minimumTextScore }
        scored.sort { $0.text > $1.text }
        guard !scored.isEmpty else { throw AppError.noMatch }
        try Task.checkCancellation()

        // Without a collector number there can be many same-name cards; compare more of them.
        let visualLimit = parsed.number == nil ? AppConfig.maxVisualCandidates * 2 : AppConfig.maxVisualCandidates
        let shortlist = Array(scored.prefix(visualLimit))

        await progress(.comparingArtwork)
        let visual = await visualSimilarities(photo: photo, candidates: shortlist.map(\.summary))
        try Task.checkCancellation()

        var matches: [CardMatch] = shortlist.map { item in
            let set = setsById[item.summary.setId]
            var match = CardMatch(id: item.summary.id, name: item.summary.name, number: item.summary.localId,
                                  setId: item.summary.setId, setName: set?.name ?? item.summary.setId,
                                  setOfficialCount: set?.cardCount?.official, rarity: nil,
                                  imageBase: item.summary.image)
            match.visualSimilarity = visual[item.summary.id]
            match.score = ConfidenceScorer.combined(text: item.text, visual: match.visualSimilarity)
            match.confidence = ConfidenceScorer.level(forCandidate: match.score)
            return match
        }
        matches.sort { $0.score > $1.score }
        matches = Array(matches.prefix(8))

        if !matches.isEmpty {
            matches[0].confidence = ConfidenceScorer.level(best: matches[0].score,
                                                           runnerUp: matches.dropFirst().first?.score,
                                                           numberRead: parsed.number != nil)
        }

        matches = await withRarity(matches)
        try Task.checkCancellation()
        return IdentificationResult(matches: matches, parsed: parsed)
    }

    // MARK: Candidate search

    private func findCandidates(for parsed: ParsedCardText) async throws -> [CardSummary] {
        var found: [String: CardSummary] = [:]
        var lastError: Error?

        func add(_ list: [CardSummary]) { for s in list { found[s.id] = s } }

        for name in parsed.names.prefix(3) {
            do {
                var results = try await catalog.searchCards(name: name)
                if results.isEmpty, let word = longestWord(in: name), word.lowercased() != name.lowercased() {
                    results = try await catalog.searchCards(name: word)
                }
                add(results)
            } catch {
                lastError = error
            }
        }

        if let number = parsed.number {
            let wanted = ConfidenceScorer.normalizeNumber(number)
            let hasNumberMatch = found.values.contains { ConfidenceScorer.normalizeNumber($0.localId) == wanted }
            if !hasNumberMatch {
                // The name may have been misread; fall back to the collector number.
                for variant in numberSpellings(number) {
                    do { add(try await catalog.searchCards(number: variant)) } catch { lastError = error }
                }
            }
        }

        if found.isEmpty, let lastError { throw AppError.from(lastError) }
        return Array(found.values)
    }

    private func longestWord(in name: String) -> String? {
        name.split(separator: " ").map(String.init).filter { $0.count >= 4 }.max(by: { $0.count < $1.count })
    }

    /// Catalogs print "6", "06" and "006" for the same card in different eras.
    private func numberSpellings(_ number: String) -> [String] {
        let normalized = ConfidenceScorer.normalizeNumber(number)
        var spellings = [number, normalized]
        if Int(normalized) != nil {
            spellings.append(String(repeating: "0", count: max(0, 3 - normalized.count)) + normalized)
        }
        var seen = Set<String>()
        return spellings.filter { seen.insert($0).inserted }
    }

    // MARK: Visual comparison

    private func visualSimilarities(photo: CGImage, candidates: [CardSummary]) async -> [String: Double] {
        guard let photoPrint = try? await VisualMatcher.featurePrint(for: photo) else { return [:] }
        let session = imageSession

        return await withTaskGroup(of: (String, Double?).self) { group in
            for candidate in candidates {
                guard let base = candidate.image, let url = URL(string: base + "/low.jpg") else { continue }
                group.addTask {
                    guard let (data, response) = try? await session.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let image = VisualMatcher.cgImage(from: data),
                          let print = try? await VisualMatcher.featurePrint(for: image) else {
                        return (candidate.id, nil)
                    }
                    return (candidate.id, VisualMatcher.similarity(photoPrint, print))
                }
            }
            var result: [String: Double] = [:]
            for await (id, similarity) in group {
                if let similarity { result[id] = similarity }
            }
            return result
        }
    }

    // MARK: Details

    /// Search results lack rarity, so it is fetched for the leading candidates.
    private func withRarity(_ matches: [CardMatch]) async -> [CardMatch] {
        let catalog = self.catalog
        let details = await withTaskGroup(of: (String, CardDetail?).self) { group in
            for match in matches.prefix(5) {
                group.addTask { (match.id, try? await catalog.card(id: match.id)) }
            }
            var result: [String: CardDetail] = [:]
            for await (id, detail) in group { if let detail { result[id] = detail } }
            return result
        }
        return matches.map { match in
            guard let detail = details[match.id] else { return match }
            var updated = CardMatch(detail: detail)
            updated.score = match.score
            updated.visualSimilarity = match.visualSimilarity
            updated.confidence = match.confidence
            return updated
        }
    }
}
