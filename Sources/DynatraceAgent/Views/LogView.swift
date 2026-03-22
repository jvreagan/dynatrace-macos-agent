import SwiftUI

struct LogView: View {
    @ObservedObject var logManager: LogManager

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logManager.entries) { entry in
                            Text(entry.formatted)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(colorForLevel(entry.level))
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: logManager.entries.count) { _, _ in
                    if let last = logManager.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                Text("\(logManager.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Clear") {
                    logManager.clear()
                }
                .controlSize(.small)
            }
            .padding(8)
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .yellow
        case .error: return .red
        }
    }
}
