import Observation
import SwiftUI

/// Loads the price for one card. Kept separate from identification.
@Observable
@MainActor
final class PriceLoader {
    enum State: Equatable {
        case idle
        case loading
        case loaded(PriceQuote)
        case unavailable(checkedAt: Date)
        case failed(AppError)
    }

    private(set) var state: State = .idle
    private let service: PriceService

    init(service: PriceService = TCGdexPriceService()) {
        self.service = service
    }

    func load(cardId: String) async {
        state = .loading
        do {
            let quote = try await service.price(for: cardId)
            if Task.isCancelled { return }
            state = quote.map { .loaded($0) } ?? .unavailable(checkedAt: .now)
        } catch {
            if Task.isCancelled { return }
            state = .failed(AppError.from(error))
        }
    }

    /// The outcome of a finished lookup: `.some(nil)` means checked, but no live price.
    var outcome: PriceQuote?? {
        switch state {
        case .loaded(let quote): .some(quote)
        case .unavailable: .some(nil)
        default: nil
        }
    }
}

struct PriceSection: View {
    let match: CardMatch
    let state: PriceLoader.State
    /// The printing the user has (normal, holofoil…). Drives the headline price.
    @Binding var selectedKey: String?
    let retry: () -> Void
    var onSelectVariant: (VariantPrice) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Market Value")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if case .loaded = state {
                    Button(action: retry) {
                        Image(systemName: "arrow.clockwise")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Refresh price")
                }
            }

            switch state {
            case .idle, .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking current price…").foregroundStyle(.secondary)
                }
                .frame(minHeight: 60)
                .accessibilityElement(children: .combine)

            case .loaded(let quote):
                loaded(quote)

            case .unavailable(let checkedAt):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Live price unavailable", systemImage: "tag.slash")
                        .font(.title3.weight(.semibold))
                    Text("No current USD market price is listed for this card. This is common for promos, very new releases and some older printings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Checked \(Formatters.relative(checkedAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

            case .failed(let error):
                ErrorCallout(error: error, retry: retry)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func loaded(_ quote: PriceQuote) -> some View {
        let suggested = quote.primaryVariant(rarity: match.rarity)
        let selected = quote.variants.first { $0.key == selectedKey } ?? suggested

        if let selected, let market = selected.market {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.usd(market))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text("\(selected.displayName) · market price")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Market price \(Formatters.usd(market)), \(selected.displayName)")
        } else if let selected {
            VStack(alignment: .leading, spacing: 4) {
                Label("No recent market sales", systemImage: "tag.slash")
                    .font(.title3.weight(.semibold))
                Text("for the \(selected.displayName) printing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }

        if quote.variants.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Which printing do you have?")
                    .font(.subheadline.weight(.semibold))
                Text("Holo cards have shiny artwork; reverse holos have a shiny frame instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(quote.variants) { variant in
                        Button {
                            selectedKey = variant.key
                            onSelectVariant(variant)
                        } label: {
                            VariantRow(variant: variant, isSelected: variant.key == selected?.key,
                                       isSuggested: variant.key == suggested?.key, selectable: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(variant.key == selected?.key ? .isSelected : [])
                        if variant.id != quote.variants.last?.id { Divider() }
                    }
                }
            }
            .padding(.vertical, 4)
        } else if let only = quote.variants.first, only.low != nil {
            VariantRow(variant: only, isSelected: true, isSuggested: false, selectable: false)
        }

        VStack(alignment: .leading, spacing: 4) {
            Label(quote.source, systemImage: "building.columns")
            if let updated = quote.sourceUpdated {
                Label("Price updated \(Formatters.relative(updated))", systemImage: "clock")
            }
            Label("Checked \(quote.checkedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle")
            Text("Market prices are for near-mint copies.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)

        if let url = selected?.productURL ?? quote.variants.first?.productURL {
            Link(destination: url) {
                Label("View listings on TCGplayer", systemImage: "arrow.up.right.square")
                    .frame(minHeight: 44)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

private struct VariantRow: View {
    let variant: VariantPrice
    let isSelected: Bool
    let isSuggested: Bool
    let selectable: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))

        layout {
            if selectable {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.displayName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                if isSuggested {
                    Text("Suggested for this rarity")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text(variant.market.map(Formatters.usd) ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                if let low = variant.low, let high = variant.high {
                    Text("\(Formatters.usd(low)) – \(Formatters.usd(high))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(selectable && !isSelected ? "Prices the card as this printing" : "")
    }

    private var accessibilityText: String {
        var parts = [variant.displayName]
        if isSuggested { parts.append("suggested") }
        parts.append(variant.market.map { "market \(Formatters.usd($0))" } ?? "no market price")
        if let low = variant.low, let high = variant.high {
            parts.append("listings from \(Formatters.usd(low)) to \(Formatters.usd(high))")
        }
        return parts.joined(separator: ", ")
    }
}
