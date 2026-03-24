import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigurationManager
    let dynatraceAPI: DynatraceAPI
    let logManager: LogManager
    let oauthManager: OAuthManager
    var onSave: (() -> Void)? = nil

    @State private var apiToken: String = ""
    @State private var oauthClientSecret: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String = ""
    @State private var saveIsError = false

    private var isFirstRun: Bool {
        !configManager.isConfigured
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(isFirstRun ? "Welcome to Dynatrace Agent" : "Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                    if isFirstRun {
                        Text("Enter your Dynatrace credentials to start running on your Mac.")
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Step 1 — Dynatrace Connection
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        label("1", "Connect to Dynatrace")

                        field("Environment URL", hint: "abc12345.live.dynatrace.com") {
                            TextField("abc12345.live.dynatrace.com", text: $configManager.environmentURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        field("API Token", hint: "Requires metrics.ingest scope — create one in Dynatrace → Access Tokens") {
                            TextField("dt0c01.XXXX.YYYY", text: $apiToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding(8)
                }

                // MARK: Step 2 — Dashboard
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        label("2", "Configure Dashboard")

                        field("Dashboard Name", hint: "Name for the auto-created Dynatrace dashboard") {
                            TextField("macOS Metrics", text: $configManager.dashboardName)
                                .textFieldStyle(.roundedBorder)
                        }

                        field("OAuth Client ID", hint: "Create an OAuth client in Dynatrace → OAuth Clients with document:documents:write scope") {
                            TextField("dt0s01.XXXX", text: $configManager.oauthClientId)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        field("OAuth Client Secret", hint: nil) {
                            TextField("dt0s01.XXXX.YYYY...", text: $oauthClientSecret)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding(8)
                }

                // MARK: Advanced
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Collection Interval")
                                .font(.headline)
                            Spacer()
                            Picker("", selection: $configManager.collectionInterval) {
                                Text("10s").tag(10)
                                Text("30s").tag(30)
                                Text("1 min").tag(60)
                                Text("2 min").tag(120)
                                Text("5 min").tag(300)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)
                        }

                        Toggle("Launch at login", isOn: $configManager.launchAtLogin)

                        field("Hostname Override", hint: "Leave blank to use \"\(Host.current().localizedName ?? "system hostname")\"") {
                            TextField("", text: $configManager.hostnameOverride)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 4)

                // MARK: Actions
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button(isFirstRun ? "Save & Start Running" : "Save") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || !canSave)

                        if let dashboardId = configManager.dashboardId, !isFirstRun {
                            Button("Open Dashboard") {
                                let service = DashboardService(logManager: logManager)
                                if let url = service.dashboardURL(id: dashboardId, environmentURL: configManager.environmentURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }

                        if !isFirstRun {
                            Button(configManager.dashboardId == nil ? "Create Dashboard" : "Re-create Dashboard") {
                                createDashboard()
                            }
                            .disabled(isSaving || configManager.oauthClientId.isEmpty || oauthClientSecret.isEmpty)
                        }

                        if isSaving {
                            ProgressView().controlSize(.small)
                        }

                        Spacer()
                    }

                    if !saveMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: saveIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(saveIsError ? .red : .green)
                            Text(saveMessage)
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 500)
        .onAppear {
            apiToken = KeychainService.getToken() ?? ""
            oauthClientSecret = KeychainService.getOAuthSecret() ?? ""
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func label(_ step: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(title)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, hint: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            content()
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSave: Bool {
        !configManager.environmentURL.isEmpty && !apiToken.isEmpty
    }

    // MARK: - Actions

    private func createDashboard() {
        isSaving = true
        saveMessage = ""
        if !oauthClientSecret.isEmpty && !KeychainService.saveOAuthSecret(oauthClientSecret) {
            isSaving = false
            saveIsError = true
            saveMessage = "Failed to save OAuth secret to Keychain"
            return
        }
        Task { @MainActor in
            let service = DashboardService(logManager: logManager)
            do {
                let id = try await service.createDashboard(
                    oauthManager: oauthManager,
                    environmentURL: configManager.environmentURL,
                    clientId: configManager.oauthClientId,
                    clientSecret: oauthClientSecret,
                    tokenURL: ConfigurationManager.oauthTokenURL,
                    dashboardName: configManager.dashboardName
                )
                configManager.dashboardId = id
                saveIsError = false
                saveMessage = "Dashboard created"
            } catch {
                saveIsError = true
                saveMessage = "Dashboard error: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    private func save() {
        isSaving = true
        saveMessage = ""

        // Clean URL
        var cleaned = configManager.environmentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)) }
        }
        if let slash = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[cleaned.startIndex..<slash])
        }
        configManager.environmentURL = cleaned

        guard KeychainService.saveToken(apiToken) else {
            isSaving = false
            saveIsError = true
            saveMessage = "Failed to save API token to Keychain"
            return
        }
        if !oauthClientSecret.isEmpty {
            guard KeychainService.saveOAuthSecret(oauthClientSecret) else {
                isSaving = false
                saveIsError = true
                saveMessage = "Failed to save OAuth secret to Keychain"
                return
            }
        }
        logManager.log("Settings saved")

        // Test connection then callback
        Task { @MainActor in
            let (success, message) = await dynatraceAPI.testConnection()
            isSaving = false
            if success {
                saveIsError = false
                saveMessage = "Connected successfully"
                onSave?()
            } else {
                saveIsError = true
                saveMessage = "Connection failed: \(message)"
            }
        }
    }
}
