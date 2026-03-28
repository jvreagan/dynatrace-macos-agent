import AppKit

enum AgentStatus {
    case idle
    case collecting
    case warning
    case error
}

@MainActor
final class MenuBarManager {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let statusMenuItem: NSMenuItem
    private let startStopMenuItem: NSMenuItem
    private var _handler: MenuActionHandler?
    private var currentStatus: AgentStatus = .idle

    init(
        onConfigure: @escaping @MainActor () -> Void,
        onViewLogs: @escaping @MainActor () -> Void,
        onOpenLogFile: @escaping @MainActor () -> Void,
        onAbout: @escaping @MainActor () -> Void,
        onQuit: @escaping @MainActor () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false

        startStopMenuItem = NSMenuItem()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionItem = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false

        menu.addItem(statusMenuItem)
        menu.addItem(versionItem)
        menu.addItem(.separator())

        let configItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
        menu.addItem(configItem)

        let logsItem = NSMenuItem(title: "Live Log...", action: nil, keyEquivalent: "l")
        menu.addItem(logsItem)

        let openLogFileItem = NSMenuItem(title: "Open Log File", action: nil, keyEquivalent: "")
        menu.addItem(openLogFileItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About Dynatrace Agent", action: nil, keyEquivalent: "")
        menu.addItem(aboutItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu

        let handler = MenuActionHandler(
            onConfigure: onConfigure,
            onViewLogs: onViewLogs,
            onOpenLogFile: onOpenLogFile,
            onAbout: onAbout,
            onQuit: onQuit
        )
        _handler = handler

        configItem.target = handler
        configItem.action = #selector(MenuActionHandler.configure)
        logsItem.target = handler
        logsItem.action = #selector(MenuActionHandler.viewLogs)
        openLogFileItem.target = handler
        openLogFileItem.action = #selector(MenuActionHandler.openLogFile)
        aboutItem.target = handler
        aboutItem.action = #selector(MenuActionHandler.about)
        quitItem.target = handler
        quitItem.action = #selector(MenuActionHandler.quit)

        updateIcon(for: .idle)
    }

    func updateStatus(_ status: AgentStatus) {
        currentStatus = status
        updateIcon(for: status)

        switch status {
        case .idle:
            statusMenuItem.title = "Status: Idle"
        case .collecting:
            statusMenuItem.title = "Status: Running"
        case .warning:
            statusMenuItem.title = "Status: Warning"
        case .error:
            statusMenuItem.title = "Status: Error — check Settings"
        }
    }

    private func updateIcon(for status: AgentStatus) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let tintColor: NSColor

        switch status {
        case .idle:
            symbolName = "chart.bar"
            tintColor = .secondaryLabelColor
        case .collecting:
            symbolName = "chart.bar.fill"
            tintColor = .systemGreen
        case .warning:
            symbolName = "chart.bar.fill"
            tintColor = .systemYellow
        case .error:
            symbolName = "chart.bar.fill"
            tintColor = .systemRed
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Dynatrace Agent") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [tintColor]))
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = false
            button.image = configured
            button.contentTintColor = nil
        }
    }
}

@MainActor
final class MenuActionHandler: NSObject {
    private let onConfigure: @MainActor () -> Void
    private let onViewLogs: @MainActor () -> Void
    private let onOpenLogFile: @MainActor () -> Void
    private let onAbout: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void

    init(
        onConfigure: @escaping @MainActor () -> Void,
        onViewLogs: @escaping @MainActor () -> Void,
        onOpenLogFile: @escaping @MainActor () -> Void,
        onAbout: @escaping @MainActor () -> Void,
        onQuit: @escaping @MainActor () -> Void
    ) {
        self.onConfigure = onConfigure
        self.onViewLogs = onViewLogs
        self.onOpenLogFile = onOpenLogFile
        self.onAbout = onAbout
        self.onQuit = onQuit
    }

    @objc func configure() { onConfigure() }
    @objc func viewLogs() { onViewLogs() }
    @objc func openLogFile() { onOpenLogFile() }
    @objc func about() { onAbout() }
    @objc func quit() { onQuit() }
}
