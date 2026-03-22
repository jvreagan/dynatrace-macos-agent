import Foundation

final class DynatraceAPI: Sendable {
    private let configManager: ConfigurationManager
    private let logManager: LogManager
    private let maxBatchSize = 1000
    private let maxRetries = 3

    init(configManager: ConfigurationManager, logManager: LogManager) {
        self.configManager = configManager
        self.logManager = logManager
    }

    func send(metrics: [MetricPoint]) async -> Bool {
        guard !metrics.isEmpty else { return true }

        let lines = metrics.map { $0.toMINTLine() }

        logManager.log("--- Payload (\(lines.count) lines) ---")
        for line in lines {
            logManager.log("  \(line)")
        }

        let batches = stride(from: 0, to: lines.count, by: maxBatchSize).map {
            Array(lines[$0..<min($0 + maxBatchSize, lines.count)])
        }

        var allSuccess = true

        for (i, batch) in batches.enumerated() {
            let body = batch.joined(separator: "\n")
            let success = await sendBatch(body, batchIndex: i + 1, totalBatches: batches.count)
            if !success { allSuccess = false }
        }

        return allSuccess
    }

    func testConnection() async -> (success: Bool, message: String) {
        let urlString = await MainActor.run { configManager.environmentURL }

        guard let url = buildURL(from: urlString) else {
            return (false, "Invalid environment URL")
        }

        guard let token = KeychainService.getToken() else {
            return (false, "No API token configured")
        }

        let testLine = "macos.agent.heartbeat,test=true gauge,1 \(UInt64(Date().timeIntervalSince1970 * 1000))"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Api-Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = testLine.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return (true, "Connected (HTTP \(httpResponse.statusCode))")
            case 401:
                return (false, "Unauthorized - check API token")
            case 403:
                return (false, "Forbidden - token may lack 'metrics.ingest' scope")
            default:
                return (false, "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Private

    private func sendBatch(_ body: String, batchIndex: Int = 1, totalBatches: Int = 1, attempt: Int = 1) async -> Bool {
        let urlString = await MainActor.run { configManager.environmentURL }

        guard let url = buildURL(from: urlString) else {
            logManager.log("Invalid environment URL", level: .error)
            return false
        }

        guard let token = KeychainService.getToken() else {
            logManager.log("No API token available", level: .error)
            return false
        }

        let batchLabel = totalBatches > 1 ? " (batch \(batchIndex)/\(totalBatches))" : ""
        logManager.log("POST \(url)\(batchLabel)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Api-Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logManager.log("No HTTP response received", level: .error)
                return false
            }

            let responseBody = String(data: data, encoding: .utf8) ?? ""

            switch httpResponse.statusCode {
            case 200..<300:
                logManager.log("HTTP \(httpResponse.statusCode): \(responseBody)")
                return true
            case 429, 500..<600:
                logManager.log("HTTP \(httpResponse.statusCode): \(responseBody)", level: .warning)
                if attempt < maxRetries {
                    let delay = pow(2.0, Double(attempt))
                    logManager.log("Retrying in \(Int(delay))s (attempt \(attempt)/\(maxRetries))", level: .warning)
                    try await Task.sleep(for: .seconds(delay))
                    return await sendBatch(body, batchIndex: batchIndex, totalBatches: totalBatches, attempt: attempt + 1)
                }
                logManager.log("Failed after \(maxRetries) retries", level: .error)
                return false
            default:
                logManager.log("HTTP \(httpResponse.statusCode): \(responseBody)", level: .error)
                return false
            }
        } catch {
            if attempt < maxRetries {
                let delay = pow(2.0, Double(attempt))
                logManager.log("Network error, retrying in \(Int(delay))s: \(error.localizedDescription)", level: .warning)
                try? await Task.sleep(for: .seconds(delay))
                return await sendBatch(body, attempt: attempt + 1)
            }
            logManager.log("Network error: \(error.localizedDescription)", level: .error)
            return false
        }
    }

    private func buildURL(from urlString: String) -> URL? {
        var host = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasSuffix("/") { host.removeLast() }
        // Strip protocol if present, we always use https
        if host.hasPrefix("https://") { host = String(host.dropFirst(8)) }
        if host.hasPrefix("http://") { host = String(host.dropFirst(7)) }
        guard !host.isEmpty else { return nil }
        return URL(string: "https://\(host)/api/v2/metrics/ingest")
    }
}
