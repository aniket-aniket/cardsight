import SwiftUI

/// Other candidates, for when the best match is uncertain or a reprint shares the artwork.
struct AlternativesList: View {
    let matches: [CardMatch]
    let selectedID: String
    let selectedConfidence: ConfidenceLevel
    let onSelect: (CardMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(matches.count > 1 ? "Not the right card?" : "Only one match found")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(matches) { match in
                Button {
                    onSelect(match)
                } label: {
                    AlternativeRow(match: match, isSelected: match.id == selectedID)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(match.id == selectedID ? .isSelected : [])
                .accessibilityHint(match.id == selectedID ? "" : "Shows this card and its price")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var hint: String {
        if matches.count == 1 {
            return "Check that the set and number match your card."
        }
        if selectedConfidence == .high {
            return "Pick another match if this isn't your card."
        }
        return "Cards can share artwork across sets. Compare the set symbol and number in the bottom corner of your card, then pick the match."
    }
}

private struct AlternativeRow: View {
    let match: CardMatch
    let isSelected: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                CardArtwork(url: match.thumbnailURL, cornerRadius: 6)
                    .frame(width: 52)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(match.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(match.setName) · \(match.numberDisplay)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let rarity = match.rarity {
                    Text(rarity).font(.caption).foregroundStyle(.secondary)
                }
                Label("\(Int((match.score * 100).rounded()))% match", systemImage: match.confidence.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(match.confidence.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(10)
        .frame(minHeight: 44)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(match.name), \(match.setName), \(match.accessibilityNumber)\(match.rarity.map { ", \($0)" } ?? ""), \(Int((match.score * 100).rounded())) percent match")
    }
}
