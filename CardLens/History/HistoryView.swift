import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var records: [ScanRecord]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("No Scans Yet",
                                           systemImage: "rectangle.stack.badge.plus",
                                           description: Text("Cards you identify will appear here with their last checked price."))
                } else {
                    List {
                        ForEach(records) { record in
                            NavigationLink(value: record.id) {
                                HistoryRow(record: record)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recent Scans")
            .navigationDestination(for: UUID.self) { id in
                if let record = records.first(where: { $0.id == id }) {
                    HistoryDetailView(record: record)
                }
            }
            .toolbar {
                if !records.isEmpty { EditButton() }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(records[index]) }
        try? context.save()
    }
}

struct HistoryRow: View {
    let record: ScanRecord

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize { thumbnail }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.body.weight(.semibold))
                Text("\(record.setName) · \(record.match.numberDisplay)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(record.scannedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let price = record.lastMarketPrice {
                Text(Formatters.usd(price))
                    .font(.headline.monospacedDigit())
            } else if record.lastPriceCheckedAt != nil {
                Text("No price")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = record.photoThumbnail, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(63.0 / 88.0, contentMode: .fill)
                .frame(width: 44, height: 61)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            CardArtwork(url: record.match.thumbnailURL, cornerRadius: 5)
                .frame(width: 44)
        }
    }

    private var accessibilityText: String {
        var parts = [record.name, record.setName, record.match.accessibilityNumber]
        if let price = record.lastMarketPrice {
            parts.append("last price \(Formatters.usd(price))")
        } else if record.lastPriceCheckedAt != nil {
            parts.append("no live price")
        }
        parts.append("scanned \(Formatters.relative(record.scannedAt))")
        return parts.joined(separator: ", ")
    }
}

struct HistoryDetailView: View {
    let record: ScanRecord
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardDetailContent(match: record.match,
                                  photo: record.photoThumbnail.flatMap(UIImage.init(data:)),
                                  onPriceLoaded: { quote, _ in
                                      record.update(with: quote, checkedAt: quote?.checkedAt ?? .now)
                                      try? context.save()
                                  })
                Text("Scanned \(record.scannedAt.formatted(date: .long, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
