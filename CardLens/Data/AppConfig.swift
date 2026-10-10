import Foundation

/// Central configuration for remote services.
///
/// The app talks to the public TCGdex API (https://tcgdex.dev), which needs no API key.
/// If you later move to a keyed provider (for example Scrydex), do NOT put the key in the app.
/// Instead, run a small backend proxy that adds the key server-side, and point `catalogBaseURL`
/// at that proxy. See README.md › "Using a keyed pricing provider".
enum AppConfig {
    static let catalogBaseURL = URL(string: "https://api.tcgdex.net/v2/en")!

    /// Human-readable price source shown next to every price.
    static let priceSourceName = "TCGplayer market price (via TCGdex)"

    static let requestTimeout: TimeInterval = 15

    /// Maximum number of candidates that get a visual (artwork) comparison.
    static let maxVisualCandidates = 10
}
