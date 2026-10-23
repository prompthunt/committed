import Foundation

/// Authenticated, read-only GitHub identity and roster queries.
struct GitHubAccountClient: Sendable {
    let token: String
    var session: URLSession = .shared
    var apiBaseURL: URL = URL(string: "https://api.github.com")!

    enum RequestError: Error, LocalizedError {
        case response(Int)
        case invalidResponse
        var errorDescription: String? {
            switch self {
            case .response(401): return "Your GitHub session expired. Sign out and sign in again."
            case .response(403): return "GitHub denied access. Check organization access or try again later."
            case .response(429): return "GitHub is limiting requests. Try again later."
            case .response(let status): return "GitHub couldn’t load your people (HTTP \(status))."
            case .invalidResponse: return "GitHub returned an unexpected response."
            }
        }
    }

    private struct Account: Decodable { let login: String }
    struct Profile: Decodable, Sendable { let login: String; let name: String? }

    private func get<T: Decodable>(_ path: String, page: Int? = nil, as type: T.Type) async throws -> T {
        var url = apiBaseURL.appendingPathComponent(path)
        if let page {
            url.append(queryItems: [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))])
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CommitStandings/0.1 (+https://github.com)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RequestError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw RequestError.response(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func profile() async throws -> Profile { try await get("user", as: Profile.self) }

    /// Compatibility for identity-only callers; roster queries always propagate errors.
    func currentUserProfile() async -> (login: String, name: String?)? {
        guard let profile = try? await profile() else { return nil }
        return (profile.login, profile.name)
    }

    /// Fetch every page. A failed later page fails the whole source, never a partial list.
    private func accounts(_ path: String) async throws -> [String] {
        var result: [String] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let accounts = try await get(path, page: page, as: [Account].self)
            result.append(contentsOf: accounts.map(\.login))
            if accounts.count < 100 { return result }
            page += 1
        }
    }

    func following() async throws -> [String] { try await accounts("user/following") }
    func organizations() async throws -> [String] { try await accounts("user/orgs") }
    func orgMembers(_ org: String) async throws -> [String] { try await accounts("orgs/\(org)/members") }

    func roster() async throws -> GitHubRosterSnapshot {
        let profile = try await profile()
        let organizations = try await organizations()
        var sources: [GitHubRosterSource] = []
        for organization in organizations.sorted() {
            sources.append(GitHubRosterSource(id: "org:\(organization.lowercased())", title: organization,
                                             members: try await orgMembers(organization)))
        }
        sources.append(GitHubRosterSource(id: "following", title: "People you follow", members: try await following()))
        return GitHubRosterSnapshot(owner: profile.login.lowercased(), sources: sources, updatedAt: Date())
    }
}
