import SwiftData
import SwiftUI

struct ResultView: View {
    let session: ScanFlowModel.ScanSession
    let onSelect: (CardMatch) -> Void
    let onPriceLoaded: (PriceQuote?, CardMatch) -> Void
    let onScanAnother: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardDetailContent(match: session.selected, photo: session.photo, onPriceLoaded: onPriceLoaded)
                    .id(session.selected.id)

                if session.selected.confidence != .high || session.matches.count > 1 {
                    AlternativesList(matches: session.matches, selectedID: session.selectedID,
                                     selectedConfidence: session.selected.confidence, onSelect: onSelect)
                }

                CenteringSection(photo: session.photo)

                Button(action: onScanAnother) {
                    Label("Scan Another Card", systemImage: "camera.viewfinder")
                }
                .buttonStyle(ProminentButtonStyle())
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: onScanAnother)
            }
        }
    }
}

/// Card header, ownership, price, collection action and price history.
/// Shared by the scan result, Recent Scans and Collection screens.
struct CardDetailContent: View {
    let match: CardMatch
    var photo: UIImage?
    var showsCollectionActions: Bool
    var onPriceLoaded: (PriceQuote?, CardMatch) -> Void
    var onVariantSelected: (VariantPrice) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var prices = PriceLoader()
    @State private var reloadToken = 0
    @State private var variantKey: String?
    @State private var showAddSheet = false
    @Query private var owned: [CollectionItem]

    init(match: CardMatch, photo: UIImage? = nil, initialVariantKey: String? = nil,
         showsCollectionActions: Bool = true,
         onPriceLoaded: @escaping (PriceQuote?, CardMatch) -> Void = { _, _ in },
         onVariantSelected: @escaping (VariantPrice) -> Void = { _ in }) {
        self.match = match
        self.photo = photo
        self.showsCollectionActions = showsCollectionActions
        self.onPriceLoaded = onPriceLoaded
        self.onVariantSelected = onVariantSelected
        _variantKey = State(initialValue: initialVariantKey)
        let cardId = match.id
        _owned = Query(filter: #Predicate<CollectionItem> { $0.cardId == cardId }, sort: \.addedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            artwork
            header

            if showsCollectionActions, !owned.isEmpty {
                OwnedBanner(items: owned)
            }

            PriceSection(match: match, state: prices.state, selectedKey: $variantKey,
                         retry: { reloadToken += 1 }, onSelectVariant: onVariantSelected)

            if showsCollectionActions {
                Button {
                    showAddSheet = true
                } label: {
                    Label(owned.isEmpty ? "Add to Collection" : "Add Another Copy", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLoadingPrice)
            }

            if let variantKey {
                PriceHistoryChart(cardId: match.id, variantKey: variantKey)
            }
        }
        .task(id: "\(match.id)#\(reloadToken)") {
            await prices.load(cardId: match.id)
            if case .loaded(let quote) = prices.state {
                PriceHistory.record(quote, in: context)
                if variantKey == nil || !quote.variants.contains(where: { $0.key == variantKey }) {
                    variantKey = quote.primaryVariant(rarity: match.rarity)?.key ?? quote.variants.first?.key
                }
            }
            if let outcome = prices.outcome {
                onPriceLoaded(outcome, match)
                announcePrice(outcome)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddToCollectionSheet(match: match, quote: loadedQuote, initialVariantKey: variantKey)
        }
    }

    private var loadedQuote: PriceQuote? {
        if case .loaded(let quote) = prices.state { return quote }
        return nil
    }

    private var isLoadingPrice: Bool {
        switch prices.state {
        case .idle, .loading: true
        default: false
        }
    }

    private var artwork: some View {
        HStack(alignment: .bottom, spacing: 12) {
            CardArtwork(url: match.imageURL, cornerRadius: 14)
                .frame(maxWidth: photo == nil ? 280 : 230)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            if let photo, !typeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Your photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(match.name)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Label(match.setName, systemImage: "square.stack.3d.up")
                Label("No. \(match.numberDisplay)", systemImage: "number")
                if let rarity = match.rarity {
                    Label(rarity, systemImage: "sparkles")
                }
            }
            .font(.body)
            .foregroundStyle(.secondary)

            if match.score > 0 {
                ConfidenceBadge(level: match.confidence, score: match.score)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerAccessibilityLabel: String {
        var parts = [match.name, match.setName, match.accessibilityNumber]
        if let rarity = match.rarity { parts.append(rarity) }
        if match.score > 0 { parts.append(match.confidence.label) }
        return parts.joined(separator: ", ")
    }

    private func announcePrice(_ quote: PriceQuote?) {
        let message: String
        if let primary = quote?.primaryVariant(rarity: match.rarity), let market = primary.market {
            message = "Market price \(Formatters.usd(market))"
        } else {
            message = "Live price unavailable"
        }
        AccessibilityNotification.Announcement(message).post()
    }
}

/// "You already own this" — helps avoid buying duplicates.
private struct OwnedBanner: View {
    let items: [CollectionItem]

    var body: some View {
        let copies = items.reduce(0) { $0 + $1.quantity }
        let detail = items.map { "\($0.variantName) \($0.condition.rawValue) ×\($0.quantity)" }.joined(separator: ", ")
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("In your collection: \(copies) \(copies == 1 ? "copy" : "copies")")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "checkmark.rectangle.stack.fill")
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
