import Foundation

/// Links into the iPhone app. `committed://board?window=<daily|weekly|monthly>` opens the Board on
/// that Window; Live rank's tap target uses the same URL. Pure Foundation so the app, the Live
/// Activity extension, and the Mac tests can all share it.
enum DeepLink: Equatable, Sendable {
    /// Open the Board. A nil window keeps whichever Window is selected.
    case board(window: ContributionWindow?)

    static let scheme = "committed"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "board",
              components.path.isEmpty || components.path == "/" else { return nil }
        let window = components.queryItems?
            .first(where: { $0.name == "window" })?.value
            .flatMap(ContributionWindow.init(rawValue:))
        self = .board(window: window)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .board(let window):
            components.host = "board"
            if let window { components.queryItems = [URLQueryItem(name: "window", value: window.rawValue)] }
        }
        return components.url!
    }
}
