import Foundation
import os.log

enum LogLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "[\(formatter.string(from: timestamp))] [\(level.rawValue)] \(message)"
    }
}

final class LogManager: ObservableObject, @unchecked Sendable {
    static let shared = LogManager()

    private let maxEntries = 500
    private let osLog = Logger(subsystem: "com.dynatrace.macosagent", category: "agent")
    private let lock = NSLock()

    @Published private(set) var entries: [LogEntry] = []

    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)

        switch level {
        case .info: osLog.info("\(message)")
        case .warning: osLog.warning("\(message)")
        case .error: osLog.error("\(message)")
        }

        lock.lock()
        defer { lock.unlock() }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }
}
