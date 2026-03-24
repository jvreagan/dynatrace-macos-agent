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

    private func buildDashboardContentJSON() -> String {
        let tiles: [String: Any] = [
            // Row 1 — CPU & Memory
            "0": ["type": "data", "title": "CPU Usage %",
                  "query": "timeseries cpu=avg(macos.cpu.usage), by:{host.name}",
                  "visualization": "lineChart"],
            "1": ["type": "data", "title": "Memory Usage %",
                  "query": "timeseries mem=avg(macos.memory.usage), by:{host.name}",
                  "visualization": "lineChart"],
            // Row 2 — Disk & Swap
            "2": ["type": "data", "title": "Disk Usage %",
                  "query": "timeseries disk=avg(macos.disk.usage), by:{device, host.name}",
                  "visualization": "lineChart"],
            "3": ["type": "data", "title": "Swap Usage %",
                  "query": "timeseries swap=avg(macos.swap.usage), by:{host.name}",
                  "visualization": "lineChart"],
            // Row 3 — Disk I/O
            "4": ["type": "data", "title": "Disk I/O (bytes/s)",
                  "query": "timeseries read=avg(macos.disk.io.read_bytes), write=avg(macos.disk.io.write_bytes), by:{device, host.name}",
                  "visualization": "lineChart"],
            // Row 4 — Network
            "5": ["type": "data", "title": "Network Traffic (bytes/s)",
                  "query": "timeseries net_in=avg(macos.network.bytes_in), net_out=avg(macos.network.bytes_out), by:{interface, host.name}",
                  "visualization": "lineChart"],
            "6": ["type": "data", "title": "Network Errors & Drops",
                  "query": "timeseries err_in=avg(macos.network.errors_in), err_out=avg(macos.network.errors_out), drops=avg(macos.network.drops_in), by:{interface, host.name}",
                  "visualization": "lineChart"],
            // Row 5 — GPU & Thermal
            "7": ["type": "data", "title": "GPU Usage %",
                  "query": "timeseries gpu=avg(macos.gpu.usage), by:{host.name}",
                  "visualization": "lineChart"],
            "8": ["type": "data", "title": "Thermal State (0=nominal 3=critical)",
                  "query": "timeseries thermal=avg(macos.thermal.state), by:{host.name}",
                  "visualization": "lineChart"],
            // Row 6 — Load & Processes
            "9": ["type": "data", "title": "System Load Average",
                  "query": "timeseries load1=avg(macos.load.1m), load5=avg(macos.load.5m), load15=avg(macos.load.15m), by:{host.name}",
                  "visualization": "lineChart"],
            "10": ["type": "data", "title": "Process Count",
                   "query": "timeseries procs=avg(macos.process.count), by:{host.name}",
                   "visualization": "lineChart"],
            // Row 7 — Battery
            "11": ["type": "data", "title": "Battery Level %",
                   "query": "timeseries battery=avg(macos.battery.level), by:{host.name}",
                   "visualization": "lineChart"],
            "12": ["type": "data", "title": "Top Processes by Memory",
                   "query": "timeseries mem=avg(macos.process.top_memory_bytes), by:{process, host.name}",
                   "visualization": "lineChart"],
        ]

        let layouts: [String: Any] = [
            "0":  ["x": 0,  "y": 0,  "w": 6,  "h": 4],
            "1":  ["x": 6,  "y": 0,  "w": 6,  "h": 4],
            "2":  ["x": 0,  "y": 4,  "w": 6,  "h": 4],
            "3":  ["x": 6,  "y": 4,  "w": 6,  "h": 4],
            "4":  ["x": 0,  "y": 8,  "w": 12, "h": 4],
            "5":  ["x": 0,  "y": 12, "w": 6,  "h": 4],
            "6":  ["x": 6,  "y": 12, "w": 6,  "h": 4],
            "7":  ["x": 0,  "y": 16, "w": 6,  "h": 4],
            "8":  ["x": 6,  "y": 16, "w": 6,  "h": 4],
            "9":  ["x": 0,  "y": 20, "w": 6,  "h": 4],
            "10": ["x": 6,  "y": 20, "w": 6,  "h": 4],
            "11": ["x": 0,  "y": 24, "w": 6,  "h": 4],
            "12": ["x": 6,  "y": 24, "w": 6,  "h": 4],
        ]

        let content: [String: Any] = [
            "version": "6",
            "variables": [],
            "tiles": tiles,
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
