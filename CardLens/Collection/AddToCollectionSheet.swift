import SwiftData
import SwiftUI

struct AddToCollectionSheet: View {
    let match: CardMatch
    let quote: PriceQuote?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var variantKey: String
    @State private var condition: CardCondition = .nearMint
    @State private var quantity = 1

    init(match: CardMatch, quote: PriceQuote?, initialVariantKey: String?) {
        self.match = match
        self.quote = quote
        _variantKey = State(initialValue: initialVariantKey ?? quote?.variants.first?.key ?? "unknown")
    }

    private var variants: [VariantPrice] { quote?.variants ?? [] }
    private var unitPrice: Double? { variants.first { $0.key == variantKey }?.market }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CardArtwork(url: match.thumbnailURL, cornerRadius: 6).frame(width: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.name).font(.headline)
                            Text("\(match.setName) · \(match.numberDisplay)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    if variants.isEmpty {
                        LabeledContent("Printing", value: "Unknown")
                    } else {
                        Picker("Printing", selection: $variantKey) {
                            ForEach(variants) { variant in
                                Text(variant.displayName).tag(variant.key)
                            }
                        }
                    }
                    Picker("Condition", selection: $condition) {
                        ForEach(CardCondition.allCases) { condition in
                            Text(condition.label).tag(condition)
                        }
                    }
                    Stepper(value: $quantity, in: 1...999) {
                        LabeledContent("Quantity", value: "\(quantity)")
                    }
                } footer: {
                    Text("Market prices are for near-mint copies. Played cards usually sell for less.")
                }

                Section("Value") {
                    if let unitPrice {
                        LabeledContent("Each", value: Formatters.usd(unitPrice))
                        LabeledContent("Total", value: Formatters.usd(unitPrice * Double(quantity)))
                            .fontWeight(.semibold)
                    } else {
                        Label("No live price for this printing. It will be added without a value, and refreshed later.",
                              systemImage: "tag.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        CollectionStore.add(match: match, variantKey: variantKey, condition: condition,
                                            quantity: quantity, unitPrice: unitPrice,
                                            checkedAt: quote?.checkedAt, context: context)
                        AccessibilityNotification.Announcement("Added \(quantity) \(match.name) to your collection").post()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
