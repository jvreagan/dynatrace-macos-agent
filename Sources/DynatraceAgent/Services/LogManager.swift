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
    private let maxFileSize: UInt64 = 5 * 1024 * 1024  // 5 MB
    private let osLog = Logger(subsystem: "com.dynatrace.macosagent", category: "agent")
    private let lock = NSLock()
    private let fileQueue = DispatchQueue(label: "com.dynatrace.macosagent.logfile", qos: .background)
    private var logFileURL: URL?

    @Published private(set) var entries: [LogEntry] = []

    init() {
        setupLogFile()
    }

    private func setupLogFile() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs/DynatraceAgent")
        guard let dir = logsDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("agent.log")
    }

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func writeToFile(_ entry: LogEntry) {
        guard let url = logFileURL else { return }
        let line = "[\(Self.fileDateFormatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }

        fileQueue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            // Rotate if file exceeds max size
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64, size >= self.maxFileSize {
                let backup = url.deletingLastPathComponent().appendingPathComponent("agent.log.1")
                try? fm.removeItem(at: backup)
                try? fm.moveItem(at: url, to: backup)
            }
            if fm.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)

        switch level {
        case .info: osLog.info("\(message)")
        case .warning: osLog.warning("\(message)")
        case .error: osLog.error("\(message)")
        }

        writeToFile(entry)

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
