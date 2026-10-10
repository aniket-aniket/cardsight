import Observation
import SwiftData
import SwiftUI

/// Drives the scan flow: pick photo → review & crop → identify → result.
@Observable
@MainActor
final class ScanFlowModel {
    enum Stage {
        case home
        case review(UIImage)
        case identifying(UIImage, IdentificationStep)
        case result(ScanSession)
        case failed(UIImage, AppError)
    }

    struct ScanSession {
        let photo: UIImage
        var matches: [CardMatch]
        var selectedID: String
        var recordID: UUID?
        var parsed: ParsedCardText

        var selected: CardMatch { matches.first { $0.id == selectedID } ?? matches[0] }
    }

    private(set) var stage: Stage = .home
    private var identifyTask: Task<Void, Never>?
    private let identifier: CardIdentifier

    init(identifier: CardIdentifier = CardIdentifier()) {
        self.identifier = identifier
    }

    func begin(with image: UIImage) {
        stage = .review(image.normalizedForProcessing())
    }

    func reset() {
        identifyTask?.cancel()
        identifyTask = nil
        stage = .home
    }

    func identify(_ cropped: UIImage, context: ModelContext) {
        identifyTask?.cancel()
        stage = .identifying(cropped, .readingText)
        announce("Identifying card")

        identifyTask = Task { [identifier] in
            do {
                let result = try await identifier.identify(cropped) { [weak self] step in
                    guard let self, case .identifying(let image, _) = self.stage else { return }
                    self.stage = .identifying(image, step)
                }
                guard !Task.isCancelled else { return }

                let best = result.matches[0]
                let record = ScanRecord(match: best, photoThumbnail: cropped.thumbnailData())
                context.insert(record)
                try? context.save()

                stage = .result(ScanSession(photo: cropped, matches: result.matches, selectedID: best.id,
                                            recordID: record.id, parsed: result.parsed))
                announce("Match found: \(best.name), \(best.setName). \(best.confidence.label).")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let appError = AppError.from(error)
                stage = .failed(cropped, appError)
                announce("\(appError.title). \(appError.errorDescription ?? "")")
            }
        }
    }

    func retry() {
        if case .failed(let image, _) = stage { stage = .review(image) }
    }

    func select(_ match: CardMatch, context: ModelContext) {
        guard case .result(var session) = stage else { return }
        session.selectedID = match.id
        stage = .result(session)
        if let record = record(for: session, in: context) {
            record.update(with: match)
            try? context.save()
        }
        announce("Selected \(match.name), \(match.setName)")
    }

    func priceLoaded(_ quote: PriceQuote?, for match: CardMatch, context: ModelContext) {
        guard case .result(let session) = stage, session.selectedID == match.id,
              let record = record(for: session, in: context) else { return }
        record.update(with: quote, checkedAt: quote?.checkedAt ?? .now)
        try? context.save()
    }

    private func record(for session: ScanSession, in context: ModelContext) -> ScanRecord? {
        guard let id = session.recordID else { return nil }
        let descriptor = FetchDescriptor<ScanRecord>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
