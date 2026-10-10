import Foundation

/// The card catalog lookups identification needs. A protocol so tests can use canned data.
protocol CardCatalog: Sendable {
    func searchCards(name: String) async throws -> [CardSummary]
    func searchCards(number: String) async throws -> [CardSummary]
    func card(id: String) async throws -> CardDetail
    func sets() async throws -> [SetSummary]
}

/// Minimal client for the public TCGdex REST API (https://tcgdex.dev). No API key required.
final class TCGdexClient: CardCatalog, @unchecked Sendable {
    static let shared = TCGdexClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let setCache = SetCache()

    init(baseURL: URL = AppConfig.catalogBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = AppConfig.requestTimeout
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// Case-insensitive "contains" search on card name.
    func searchCards(name: String) async throws -> [CardSummary] {
        try await get([CardSummary].self, path: "cards", query: [URLQueryItem(name: "name", value: name)])
            .filter { !$0.isDigitalOnly }
    }

    /// Exact match on collector number.
    func searchCards(number: String) async throws -> [CardSummary] {
        try await get([CardSummary].self, path: "cards", query: [URLQueryItem(name: "localId", value: "eq:\(number)")])
            .filter { !$0.isDigitalOnly }
    }

    func card(id: String) async throws -> CardDetail {
        try await get(CardDetail.self, path: "cards/\(id)", query: [])
    }

    func sets() async throws -> [SetSummary] {
        if let cached = await setCache.value { return cached }
        let sets = try await get([SetSummary].self, path: "sets", query: [])
        await setCache.store(sets)
        return sets
    }

    private func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw AppError.other("Invalid request.") }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.from(error)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 429: throw AppError.rateLimited
            default: throw AppError.server(status: http.statusCode)
            }
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding
        }
    }
}

private actor SetCache {
    var value: [SetSummary]?
    func store(_ sets: [SetSummary]) { value = sets }
}
