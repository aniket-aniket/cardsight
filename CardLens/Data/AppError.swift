import Foundation

enum AppError: Error, Equatable, LocalizedError {
    case offline
    case timedOut
    case rateLimited
    case server(status: Int)
    case decoding
    case unreadableImage
    case noTextFound
    case noMatch
    case other(String)

    var title: String {
        switch self {
        case .offline: "You're offline"
        case .timedOut: "The request timed out"
        case .rateLimited: "Too many requests"
        case .server: "The card database is having trouble"
        case .decoding: "Unexpected response"
        case .unreadableImage: "Couldn't read this photo"
        case .noTextFound, .noMatch: "Couldn't identify this card"
        case .other: "Something went wrong"
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline:
            "Connect to Wi-Fi or mobile data, then try again."
        case .timedOut:
            "The card database took too long to respond. Check your connection and try again."
        case .rateLimited:
            "The card database is limiting requests right now. Wait a moment and try again."
        case .server(let status):
            "The server returned an error (\(status)). Try again in a little while."
        case .decoding:
            "The card database sent data the app didn't understand. Try again later."
        case .unreadableImage:
            "Try another photo, or retake it with the whole card in view."
        case .noTextFound:
            "No card name or number could be read. Try a sharper photo with less glare, and make sure the card fills the frame."
        case .noMatch:
            "The text on the card didn't match any card in the database. Check the crop includes the name at the top and the number at the bottom."
        case .other(let message):
            message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited, .server, .decoding, .other: true
        case .unreadableImage, .noTextFound, .noMatch: false
        }
    }

    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .timedOut:
                return .timedOut
            default:
                return .other(urlError.localizedDescription)
            }
        }
        if error is DecodingError { return .decoding }
        return .other(error.localizedDescription)
    }
}
