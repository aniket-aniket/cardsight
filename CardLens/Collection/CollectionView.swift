import Charts
import SwiftData
import SwiftUI

struct CollectionView: View {
    enum SortOrder: String, CaseIterable, Identifiable {
        case value = "Value"
        case name = "Name"
        case recent = "Recently Added"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(NetworkMonitor.self) private var network
    @Query(sort: \CollectionItem.addedAt, order: .reverse) private var items: [CollectionItem]
    @Query(sort: \PriceSnapshot.recordedAt) private var snapshots: [PriceSnapshot]

    @State private var sortOrder: SortOrder = .value
    @State private var refreshing = false
    @State private var refreshMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No Cards Yet",
                                           systemImage: "rectangle.stack",
                                           description: Text("Scan a card, then tap Add to Collection to track what you own and what it's worth."))
                } else {
                    List {
                        Section {
                            CollectionSummaryCard(summary: summary, history: history, lastChecked: lastChecked)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        if !network.isOnline {
                            Section { OfflineBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                        }
                        Section("\(summary.copies) \(summary.copies == 1 ? "card" : "cards")") {
                            ForEach(sorted) { item in
                                NavigationLink(value: item.id) { CollectionRow(item: item) }
                            }
                            .onDelete(perform: delete)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("Collection")
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) {
                    CollectionItemDetailView(item: item)
                }
            }
            .toolbar {
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Sort By", selection: $sortOrder) {
                                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if refreshing {
                            ProgressView()
                        } else {
                            Button {
                                Task { await refresh() }
                            } label: {
                                Label("Refresh Prices", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .alert("Prices refreshed", isPresented: Binding(get: { refreshMessage != nil }, set: { if !$0 { refreshMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(refreshMessage ?? "")
            }
        }
    }

    private var summary: CollectionStore.Summary {
        CollectionStore.summary(of: items.map { ($0.quantity, $0.unitPrice) })
    }

    private var history: [CollectionStore.ValuePoint] {
        CollectionStore.valueHistory(
            holdings: items.map { .init(cardId: $0.cardId, variantKey: $0.variantKey, quantity: $0.quantity, addedAt: $0.addedAt) },
            observations: snapshots.map { .init(cardId: $0.cardId, variantKey: $0.variantKey, market: $0.market, date: $0.recordedAt) })
    }

    private var lastChecked: Date? { items.compactMap(\.priceCheckedAt).max() }

    private var sorted: [CollectionItem] {
        switch sortOrder {
        case .value: items.sorted { ($0.totalValue ?? -1) > ($1.totalValue ?? -1) }
        case .name: items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent: items
        }
    }

    private func delete(at offsets: IndexSet) {
        let list = sorted
        for index in offsets { context.delete(list[index]) }
        try? context.save()
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        AccessibilityNotification.Announcement("Refreshing prices").post()
        let outcome = await CollectionRefresher.refresh(items, context: context)
        refreshing = false
        if outcome.failed > 0 {
            refreshMessage = "Updated \(outcome.updated) cards. \(outcome.failed) couldn't be updated. Check your connection and try again."
        } else {
            AccessibilityNotification.Announcement("Prices updated. Collection value \(Formatters.usd(summary.totalValue))").post()
        }
    }
}

private struct CollectionSummaryCard: View {
    let summary: CollectionStore.Summary
    let history: [CollectionStore.ValuePoint]
    let lastChecked: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collection Value")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Formatters.usd(summary.totalValue))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Collection value \(Formatters.usd(summary.totalValue))")

            if history.count >= 2, let first = history.first, let last = history.last {
                TrendLabel(from: first.value, to: last.value, since: first.date)
                Chart(history) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(Color.accentColor.opacity(0.15).gradient)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.monotone)
                }
                .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel(format: .currency(code: "USD")) } }
                .frame(height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Collection value over \(history.count) days, from \(Formatters.usd(first.value)) to \(Formatters.usd(last.value))")
            } else {
                Text("A value chart appears once prices have been checked on two different days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(summary.copies) \(summary.copies == 1 ? "card" : "cards") · \(summary.unique) unique")
                if summary.unpricedCopies > 0 {
                    Text("\(summary.unpricedCopies) without a live price (not counted)")
                }
                if let lastChecked {
                    Text("Prices checked \(Formatters.relative(lastChecked)) · TCGplayer market, near mint")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CollectionRow: View {
    let item: CollectionItem
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                CardArtwork(url: item.match.thumbnailURL, cornerRadius: 5).frame(width: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.semibold))
                Text("\(item.setName) · \(item.match.numberDisplay)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("\(item.variantName) · \(item.condition.rawValue) · ×\(item.quantity)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.totalValue.map(Formatters.usd) ?? "No price")
                .font(item.totalValue == nil ? .subheadline : .headline.monospacedDigit())
                .foregroundStyle(item.totalValue == nil ? .secondary : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.setName), \(item.match.accessibilityNumber), \(item.variantName), \(item.condition.label), quantity \(item.quantity), \(item.totalValue.map { "worth \(Formatters.usd($0))" } ?? "no live price")")
    }
}

struct CollectionItemDetailView: View {
    @Bindable var item: CollectionItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardDetailContent(
                    match: item.match,
                    initialVariantKey: item.variantKey,
                    showsCollectionActions: false,
                    onPriceLoaded: { quote, _ in
                        CollectionStore.apply(quote, to: [item], checkedAt: quote?.checkedAt ?? .now)
                        try? context.save()
                    },
                    onVariantSelected: { variant in
                        item.variantKey = variant.key
                        item.unitPrice = variant.market
                        try? context.save()
                    })

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Copies")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Stepper(value: $item.quantity, in: 1...999) {
                        LabeledContent("Quantity", value: "\(item.quantity)")
                    }
                    Picker("Condition", selection: $item.condition) {
                        ForEach(CardCondition.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Printing", value: item.variantName)
                    LabeledContent("Value", value: item.totalValue.map(Formatters.usd) ?? "No live price")
                        .fontWeight(.semibold)
                    LabeledContent("Added", value: item.addedAt.formatted(date: .abbreviated, time: .omitted))
                    Button("Remove from Collection", role: .destructive) { confirmRemove = true }
                        .frame(minHeight: 44)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item.quantity) { try? context.save() }
        .onChange(of: item.conditionRaw) { try? context.save() }
        .confirmationDialog("Remove \(item.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                context.delete(item)
                try? context.save()
                dismiss()
            }
        }
    }
}
