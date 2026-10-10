import SwiftUI

// MARK: - Confidence

struct ConfidenceBadge: View {
    let level: ConfidenceLevel
    var score: Double?

    var body: some View {
        Label {
            Text(level.label)
                + Text(score.map { " · \(Int(($0 * 100).rounded()))%" } ?? "")
        } icon: {
            Image(systemName: level.symbol)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(level.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(level.color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.label)
    }
}

extension ConfidenceLevel {
    var color: Color {
        switch self {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }

    var symbol: String {
        switch self {
        case .high: "checkmark.seal.fill"
        case .medium: "exclamationmark.triangle.fill"
        case .low: "questionmark.circle.fill"
        }
    }
}

// MARK: - Card artwork

/// Official card image from the catalog, with a card-shaped placeholder while it loads.
struct CardArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 12

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
            case .failure:
                placeholder(systemImage: "photo")
            default:
                placeholder(systemImage: nil)
            }
        }
        .aspectRatio(63.0 / 88.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func placeholder(systemImage: String?) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let systemImage {
                    Image(systemName: systemImage).font(.title).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
    }
}

// MARK: - Banners & messages

struct OfflineBanner: View {
    var body: some View {
        Label("You're offline. Identification and prices need an internet connection.", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.primary)
            .accessibilityElement(children: .combine)
    }
}

struct ErrorCallout: View {
    let error: AppError
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            if let message = error.errorDescription {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            if let retry, error.isRetryable {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Buttons

struct ProminentButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal)
            .foregroundStyle(.white)
            .background(tint.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: - Formatting

enum Formatters {
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
