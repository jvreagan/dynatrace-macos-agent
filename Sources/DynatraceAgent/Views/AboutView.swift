import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.accentColor, Color.accentColor.opacity(0.4))
                .font(.system(size: 64))

            VStack(spacing: 4) {
                Text("Dynatrace Agent")
                    .font(.title2.weight(.semibold))
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Collects macOS system metrics and sends them\nto your Dynatrace environment.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            Link("View on GitHub",
                 destination: URL(string: "https://github.com/jvreagan/dynatrace-macos-agent")!)
                .font(.callout)
        }
        .padding(32)
        .frame(width: 340)
    }
}
