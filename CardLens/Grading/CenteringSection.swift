import SwiftUI

/// Centering estimate from the straightened scan photo.
struct CenteringSection: View {
    let photo: UIImage

    @State private var state: LoadState = .measuring

    enum LoadState: Equatable {
        case measuring
        case measured(CenteringResult)
        case unmeasurable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Centering")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Estimate")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }

            switch state {
            case .measuring:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Measuring borders…").foregroundStyle(.secondary)
                }
            case .measured(let result):
                measured(result)
            case .unmeasurable:
                Label("Couldn't measure centering from this photo. Crop tightly to the card's edges and shoot straight-on. Full-art cards without a plain border can't be measured.",
                      systemImage: "square.dashed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Measures front centering only. Corners, edges and surface also affect a grade, and need an in-hand inspection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: ObjectIdentifier(photo)) {
            guard let cgImage = photo.normalizedForProcessing().cgImage else {
                state = .unmeasurable
                return
            }
            let result = await Task.detached(priority: .utility) { CenteringAnalyzer.measure(cgImage) }.value
            state = result.map { .measured($0) } ?? .unmeasurable
        }
    }

    @ViewBuilder
    private func measured(_ result: CenteringResult) -> some View {
        let h = result.horizontalSplit, v = result.verticalSplit
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                CenteringDiagram(result: result).frame(width: 90)
                splits(h: h, v: v)
            }
            VStack(alignment: .leading, spacing: 12) {
                splits(h: h, v: v)
            }
        }

        if let grade = result.bestPSAGrade {
            let limit = CenteringAnalyzer.psaFrontLimits.first { $0.grade == grade }!.maxSide
            Label {
                Text(grade == 10
                     ? "Within PSA 10 centering (\(Int(limit))/\(100 - Int(limit)) or better)"
                     : "Centering would cap this card at about PSA \(grade) (\(Int(limit))/\(100 - Int(limit)) limit)")
            } icon: {
                Image(systemName: grade >= 9 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(grade >= 9 ? Color.green : Color.orange)
        } else {
            Label("Well off-centre: outside PSA's limits for grades 3 and above", systemImage: "xmark.octagon.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
        }
    }

    private func splits(h: (Int, Int), v: (Int, Int)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Left / Right", value: "\(h.0)/\(h.1)")
                .accessibilityLabel("Left to right \(h.0) to \(h.1)")
            LabeledContent("Top / Bottom", value: "\(v.0)/\(v.1)")
                .accessibilityLabel("Top to bottom \(v.0) to \(v.1)")
        }
        .font(.body.monospacedDigit())
    }
}

/// A card outline with the inner frame drawn at the measured offsets.
private struct CenteringDiagram: View {
    let result: CenteringResult

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            // Draw the borders by their split (not true size) so off-centering is easy to see.
            let horizontalBorder = w * 0.32, verticalBorder = h * 0.26
            let l = horizontalBorder * result.left / (result.left + result.right), r = horizontalBorder - l
            let t = verticalBorder * result.top / (result.top + result.bottom), b = verticalBorder - t
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.85))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray4))
                    .frame(width: max(0, w - l - r), height: max(0, h - t - b))
                    .offset(x: l, y: t)
            }
        }
        .aspectRatio(63.0 / 88.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
