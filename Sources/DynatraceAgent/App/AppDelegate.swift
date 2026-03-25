import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBarManager: MenuBarManager!
    private var configManager: ConfigurationManager!
    private var logManager: LogManager!
    private var metricsCollector: MetricsCollector!
    private var dynatraceAPI: DynatraceAPI!
    private var oauthManager: OAuthManager!
    private var collectionTimer: Timer?
    private var isMonitoring = false
    private var consecutiveFailures = 0
    private let failureNotificationThreshold = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        configManager = ConfigurationManager()
        logManager = LogManager.shared
        oauthManager = OAuthManager(logManager: logManager)
        metricsCollector = MetricsCollector(logManager: logManager, hostnameProvider: { [weak configManager] in
            MainActor.assumeIsolated {
                configManager?.hostname ?? Host.current().localizedName ?? "unknown"
            }
        })
        dynatraceAPI = DynatraceAPI(configManager: configManager, logManager: logManager)

        menuBarManager = MenuBarManager(
            onConfigure: { [weak self] in self?.showSettings() },
            onViewLogs: { [weak self] in self?.showLogs() },
            onQuit: { NSApp.terminate(nil) }
        )

        setupMainMenu()

        logManager.log("Dynatrace Agent started")

        requestNotificationPermission()

        if configManager.isConfigured {
            startMonitoring()
        } else {
            menuBarManager.updateStatus(.idle)
            showSettings()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard configManager.isConfigured else {
            logManager.log("Cannot start: missing Dynatrace URL or API token", level: .error)
            menuBarManager.updateStatus(.error)
            showSettings()
            return
        }

        isMonitoring = true
        menuBarManager.updateStatus(.collecting)
        logManager.log("Monitoring started (interval: \(configManager.collectionInterval)s)")

        ensureDashboardExists()
        collectAndSend()

        let interval = TimeInterval(configManager.collectionInterval)
        collectionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collectAndSend()
            }
        }
    }

    private func stopMonitoring() {
        collectionTimer?.invalidate()
        collectionTimer = nil
        isMonitoring = false
        menuBarManager.updateStatus(.idle)
        logManager.log("Monitoring stopped")
    }

    private func collectAndSend() {
        let metrics = metricsCollector.collect()
        logManager.log("Collected \(metrics.count) metrics")

        Task {
            let success = await dynatraceAPI.send(metrics: metrics)
            if success {
                let wasFailing = self.consecutiveFailures >= self.failureNotificationThreshold
                self.consecutiveFailures = 0
                self.menuBarManager.updateStatus(.collecting)
                self.logManager.log("Metrics sent successfully")
                if wasFailing {
                    self.sendRecoveryNotification()
                }
            } else {
                self.consecutiveFailures += 1
                self.menuBarManager.updateStatus(.error)
                self.logManager.log("Failed to send metrics", level: .error)
                if self.consecutiveFailures == self.failureNotificationThreshold {
                    self.sendFailureNotification()
                }
            }
        }
    }

    // MARK: - Dashboard auto-creation

    private func ensureDashboardExists() {
        guard configManager.isOAuthConfigured else { return }

        let existingId = configManager.dashboardId
        let clientId = configManager.oauthClientId
        let clientSecret = KeychainService.getOAuthSecret() ?? ""
        let tokenURL = ConfigurationManager.oauthTokenURL
        let envURL = configManager.environmentURL
        let name = configManager.dashboardName

        Task {
            let service = DashboardService(logManager: logManager)

            // If we have a stored ID, verify it still exists
            if let id = existingId {
                let exists = await service.dashboardExists(
                    id: id,
                    oauthManager: oauthManager,
                    environmentURL: envURL,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    tokenURL: tokenURL
                )
                if exists {
                    logManager.log("Dashboard already exists (ID: \(id))")
                    return
                }
                logManager.log("Stored dashboard not found, recreating...", level: .warning)
            }

            // Create a new dashboard
            logManager.log("Creating macOS metrics dashboard...")
            do {
                let id = try await service.createDashboard(
                    oauthManager: oauthManager,
                    environmentURL: envURL,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    tokenURL: tokenURL,
                    dashboardName: name
                )
                await MainActor.run { configManager.dashboardId = id }
                logManager.log("Dashboard created (ID: \(id))")
            } catch {
                logManager.log("Dashboard creation failed: \(error.localizedDescription)", level: .error)
                await MainActor.run { self.menuBarManager.updateStatus(.warning) }
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendFailureNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Dynatrace Agent"
        content.body = "Metrics have failed to send \(failureNotificationThreshold) times in a row. Check your settings."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "metrics-failure",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func sendRecoveryNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Dynatrace Agent"
        content.body = "Metrics are sending successfully again."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "metrics-recovery",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Windows

    private var settingsWindow: NSWindow?
    private var logWindow: NSWindow?

    private func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            configManager: configManager,
            dynatraceAPI: dynatraceAPI,
            logManager: logManager,
            oauthManager: oauthManager,
            onSave: { [weak self] in
                guard let self else { return }
                self.consecutiveFailures = 0
                self.settingsWindow?.close()
                self.settingsWindow = nil
                if !self.isMonitoring {
                    self.startMonitoring()
                }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dynatrace Agent"
        window.contentViewController = NSHostingController(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func showLogs() {
        if let window = logWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let logView = LogView(logManager: logManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dynatrace Agent Logs"
        window.contentViewController = NSHostingController(rootView: logView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        logWindow = window
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            if window === settingsWindow { settingsWindow = nil }
            else if window === logWindow { logWindow = nil }
        }
    }
}
