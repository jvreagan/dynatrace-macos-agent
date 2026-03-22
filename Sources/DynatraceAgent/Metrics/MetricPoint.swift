import Foundation

struct MetricPoint: Sendable {
    let key: String
    let dimensions: [String: String]
    let value: Double
    let timestamp: UInt64 // milliseconds since epoch

    init(key: String, dimensions: [String: String] = [:], value: Double, timestamp: Date = Date()) {
        self.key = key
        self.dimensions = dimensions
        self.value = value
        self.timestamp = UInt64(timestamp.timeIntervalSince1970 * 1000)
    }

    /// Serialize to MINT line protocol format:
    /// `metric.key,dim1=val1,dim2=val2 gauge,<value> <timestamp_ms>`
    func toMINTLine() -> String {
        var line = key

        if !dimensions.isEmpty {
            let dims = dimensions
                .sorted { $0.key < $1.key }
                .map { "\(escapeDimensionKey($0.key))=\(escapeDimensionValue($0.value))" }
                .joined(separator: ",")
            line += ",\(dims)"
        }

        line += " gauge,\(formatValue(value)) \(timestamp)"
        return line
    }

    private func escapeDimensionKey(_ key: String) -> String {
        key.replacingOccurrences(of: " ", with: "_")
           .replacingOccurrences(of: ",", with: "_")
           .replacingOccurrences(of: "=", with: "_")
    }

    private func escapeDimensionValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Quote if the value contains anything other than [a-zA-Z0-9_./\-]
        let needsQuoting = escaped.contains { c in
            !(c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "." || c == "/" || c == "-"))
        }
        if needsQuoting {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() && value < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
