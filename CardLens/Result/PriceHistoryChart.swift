import Charts
import SwiftData
import SwiftUI

/// Price trend for one printing, built from snapshots saved on each price check.
struct PriceHistoryChart: View {
    let variantKey: String
    @Query private var snapshots: [PriceSnapshot]

    init(cardId: String, variantKey: String) {
        self.variantKey = variantKey
        _snapshots = Query(filter: #Predicate<PriceSnapshot> { $0.cardId == cardId && $0.variantKey == variantKey },
                           sort: \.recordedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Price History")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(VariantPrice.displayName(for: variantKey))
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshots.count >= 2, let first = snapshots.first, let last = snapshots.last {
                TrendLabel(from: first.market, to: last.market, since: first.recordedAt)
                Chart(snapshots) { snapshot in
                    LineMark(x: .value("Date", snapshot.recordedAt), y: .value("Price", snapshot.market))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", snapshot.recordedAt), y: .value("Price", snapshot.market))
                        .symbolSize(24)
                }
                .foregroundStyle(Color.accentColor)
                .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel(format: .currency(code: "USD")) } }
                .frame(height: 160)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Price history chart with \(snapshots.count) checks, from \(Formatters.usd(first.market)) to \(Formatters.usd(last.market))")
            } else {
                Label("History starts from your first check. Each time the price is checked, a point is added here.",
                      systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct TrendLabel: View {
    let from: Double
    let to: Double
    let since: Date

    var body: some View {
        let change = to - from
        let percent = from > 0 ? change / from * 100 : 0
        let up = change >= 0
        Label {
            Text("\(up ? "+" : "−")\(Formatters.usd(abs(change))) (\(String(format: "%.1f", abs(percent)))%) since \(since.formatted(date: .abbreviated, time: .omitted))")
        } icon: {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(change == 0 ? Color.secondary : (up ? Color.green : Color.red))
        .accessibilityLabel("\(up ? "Up" : "Down") \(Formatters.usd(abs(change))), \(String(format: "%.1f", abs(percent))) percent since \(since.formatted(date: .abbreviated, time: .omitted))")
    }
}
