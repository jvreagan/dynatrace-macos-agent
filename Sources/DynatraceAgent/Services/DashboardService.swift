import Foundation

struct DashboardService {
    let logManager: LogManager

    // MARK: - Public API

    /// Creates the macOS metrics dashboard and returns the new document ID.
    func createDashboard(
        oauthManager: OAuthManager,
        environmentURL: String,
        clientId: String,
        clientSecret: String,
        tokenURL: String,
        dashboardName: String
    ) async throws -> String {
        let token = try await oauthManager.getAccessToken(
            clientId: clientId,
            clientSecret: clientSecret,
            tokenURL: tokenURL
        )

        let appsHost = appsHost(from: environmentURL)
        let endpoint = "https://\(appsHost)/platform/document/v1/documents"

        guard let url = URL(string: endpoint) else {
            throw DashboardError.invalidURL(endpoint)
        }

        let contentJSON = buildDashboardContentJSON()

        // Documents API requires multipart/form-data with metadata as query params
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name", value: dashboardName),
            URLQueryItem(name: "type", value: "dashboard"),
            URLQueryItem(name: "isPrivate", value: "false")
        ]
        guard let finalURL = components.url else {
            throw DashboardError.invalidURL(endpoint)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let contentData = contentJSON.data(using: .utf8) ?? Data()
        var bodyData = Data()
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"content\"; filename=\"dashboard.json\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        bodyData.append(contentData)
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        logManager.log("[Dashboard] POST \(finalURL.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DashboardError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        logManager.log("[Dashboard] Response (\(httpResponse.statusCode)): \(responseBody)")

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DashboardError.httpError(httpResponse.statusCode, responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw DashboardError.parseError("Could not extract document ID from response")
        }

        logManager.log("[Dashboard] Created with ID: \(id)")
        return id
    }

    /// Checks whether a previously-created dashboard still exists.
    func dashboardExists(
        id: String,
        oauthManager: OAuthManager,
        environmentURL: String,
        clientId: String,
        clientSecret: String,
        tokenURL: String
    ) async -> Bool {
        do {
            let token = try await oauthManager.getAccessToken(
                clientId: clientId,
                clientSecret: clientSecret,
                tokenURL: tokenURL
            )
            let appsHost = appsHost(from: environmentURL)
            let endpoint = "https://\(appsHost)/platform/document/v1/documents/\(id)"

            guard let url = URL(string: endpoint) else { return false }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            logManager.log("[Dashboard] Existence check failed: \(error.localizedDescription)", level: .warning)
            return false
        }
    }

    /// Returns the URL to open the dashboard in the Dynatrace UI.
    func dashboardURL(id: String, environmentURL: String) -> URL? {
        let appsHost = appsHost(from: environmentURL)
        return URL(string: "https://\(appsHost)/ui/document/\(id)")
    }

    // MARK: - Private helpers

    private func appsHost(from liveURL: String) -> String {
        liveURL.replacingOccurrences(of: ".live.dynatrace.com", with: ".apps.dynatrace.com")
    }

    // MARK: - Dashboard tile definitions
    // Update these if Dynatrace metric keys or DQL syntax changes.
    // Each entry: (title, DQL query)
    private static let tiles: [(title: String, query: String)] = [
        // Row 1 — CPU & Memory
        ("CPU Usage %",
         "timeseries cpu=avg(macos.cpu.usage), by:{host.name}"),
        ("Memory Usage %",
         "timeseries mem=avg(macos.memory.usage), by:{host.name}"),
        // Row 2 — Disk & Swap
        ("Disk Usage %",
         "timeseries disk=avg(macos.disk.usage), by:{device, host.name}"),
        ("Swap Usage %",
         "timeseries swap=avg(macos.swap.usage), by:{host.name}"),
        // Row 3 — Disk I/O (full width)
        ("Disk I/O (bytes/s)",
         "timeseries read=avg(macos.disk.io.read_bytes), write=avg(macos.disk.io.write_bytes), by:{device, host.name}"),
        // Row 4 — Network
        ("Network Traffic (bytes/s)",
         "timeseries net_in=avg(macos.network.bytes_in), net_out=avg(macos.network.bytes_out), by:{interface, host.name}"),
        ("Network Errors & Drops",
         "timeseries err_in=avg(macos.network.errors_in), err_out=avg(macos.network.errors_out), drops=avg(macos.network.drops_in), by:{interface, host.name}"),
        // Row 5 — GPU & Thermal
        ("GPU Usage %",
         "timeseries gpu=avg(macos.gpu.usage), by:{host.name}"),
        ("Thermal State (0=nominal 3=critical)",
         "timeseries thermal=avg(macos.thermal.state), by:{host.name}"),
        // Row 6 — Load & Processes
        ("System Load Average",
         "timeseries load1=avg(macos.load.1m), load5=avg(macos.load.5m), load15=avg(macos.load.15m), by:{host.name}"),
        ("Process Count",
         "timeseries procs=avg(macos.process.count), by:{host.name}"),
        // Row 7 — Battery & Top Processes
        ("Battery Level %",
         "timeseries battery=avg(macos.battery.level), by:{host.name}"),
        ("Top Processes by Memory",
         "timeseries mem=avg(macos.process.top_memory_bytes), by:{process, host.name}"),
    ]

    private func buildDashboardContentJSON() -> String {
        var tilesDict: [String: Any] = [:]
        for (index, tile) in Self.tiles.enumerated() {
            tilesDict["\(index)"] = [
                "type": "data",
                "title": tile.title,
                "query": tile.query,
                "visualization": "lineChart"
            ]
        }

        // Tile 4 (Disk I/O) spans full width; all others are half-width (w=6)
        let fullWidthTiles: Set<Int> = [4]
        var layouts: [String: Any] = [:]
        var y = 0
        var col = 0
        for index in 0..<Self.tiles.count {
            let fullWidth = fullWidthTiles.contains(index)
            let w = fullWidth ? 12 : 6
            layouts["\(index)"] = ["x": col, "y": y, "w": w, "h": 4]
            if fullWidth || col == 6 {
                y += 4
                col = 0
            } else {
                col = 6
            }
        }

        let content: [String: Any] = [
            "version": "6",
            "variables": [],
            "tiles": tilesDict,
            "layouts": layouts
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: content),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

enum DashboardError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .invalidResponse: return "Invalid response from API"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
