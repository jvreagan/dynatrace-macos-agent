import Foundation

actor OAuthManager {
    private struct CachedToken {
        let value: String
        let expiresAt: Date
    }

    private var cachedToken: CachedToken?
    private let logManager: LogManager

    init(logManager: LogManager) {
        self.logManager = logManager
    }

    func getAccessToken(clientId: String, clientSecret: String, tokenURL: String) async throws -> String {
        // Return cached token if it won't expire in the next 60 seconds
        if let cached = cachedToken, cached.expiresAt > Date().addingTimeInterval(60) {
            return cached.value
        }
        return try await fetchToken(clientId: clientId, clientSecret: clientSecret, tokenURL: tokenURL)
    }

    func invalidate() {
        cachedToken = nil
    }

    private func fetchToken(clientId: String, clientSecret: String, tokenURL: String) async throws -> String {
        guard let url = URL(string: tokenURL) else {
            throw OAuthError.invalidURL(tokenURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let scope = "document:documents:write document:documents:read"
        let params = [
            "grant_type=client_credentials",
            "client_id=\(clientId.urlEncoded)",
            "client_secret=\(clientSecret.urlEncoded)",
            "scope=\(scope.urlEncoded)"
        ]
        request.httpBody = params.joined(separator: "&").data(using: .utf8)

        logManager.log("[OAuth] Requesting token from \(tokenURL)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }

        let body = String(data: data, encoding: .utf8) ?? ""

        guard httpResponse.statusCode == 200 else {
            logManager.log("[OAuth] Token request failed (\(httpResponse.statusCode)): \(body)", level: .error)
            throw OAuthError.httpError(httpResponse.statusCode, body)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        cachedToken = CachedToken(value: tokenResponse.accessToken, expiresAt: expiry)
        logManager.log("[OAuth] Token obtained, expires in \(tokenResponse.expiresIn)s")

        return tokenResponse.accessToken
    }
}

enum OAuthError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid OAuth token URL: \(url)"
        case .invalidResponse: return "Invalid response from OAuth server"
        case .httpError(let code, let body): return "OAuth HTTP \(code): \(body)"
        case .missingCredentials: return "OAuth Client ID or Secret not configured"
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
