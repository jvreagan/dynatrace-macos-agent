import Foundation

@MainActor
final class ConfigurationManager: ObservableObject {
    static let oauthTokenURL = "https://sso.dynatrace.com/sso/oauth2/token"

    private enum Keys {
        static let environmentURL = "dynatrace.environmentURL"
        static let collectionInterval = "dynatrace.collectionInterval"
        static let hostnameOverride = "dynatrace.hostnameOverride"
        static let oauthClientId = "dynatrace.oauthClientId"
        static let dashboardName = "dynatrace.dashboardName"
        static let dashboardId = "dynatrace.dashboardId"
    }

    @Published var environmentURL: String {
        didSet { UserDefaults.standard.set(environmentURL, forKey: Keys.environmentURL) }
    }

    @Published var collectionInterval: Int {
        didSet { UserDefaults.standard.set(collectionInterval, forKey: Keys.collectionInterval) }
    }

    @Published var hostnameOverride: String {
        didSet { UserDefaults.standard.set(hostnameOverride, forKey: Keys.hostnameOverride) }
    }

    @Published var oauthClientId: String {
        didSet { UserDefaults.standard.set(oauthClientId, forKey: Keys.oauthClientId) }
    }

    @Published var dashboardName: String {
        didSet { UserDefaults.standard.set(dashboardName, forKey: Keys.dashboardName) }
    }

    var dashboardId: String? {
        get { UserDefaults.standard.string(forKey: Keys.dashboardId) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.dashboardId) }
    }

    var hostname: String {
        hostnameOverride.isEmpty ? Host.current().localizedName ?? "unknown" : hostnameOverride
    }

    var isConfigured: Bool {
        !environmentURL.isEmpty && KeychainService.getToken() != nil
    }

    var isOAuthConfigured: Bool {
        !oauthClientId.isEmpty && KeychainService.getOAuthSecret() != nil
    }

    init() {
        self.environmentURL = UserDefaults.standard.string(forKey: Keys.environmentURL) ?? ""
        let stored = UserDefaults.standard.integer(forKey: Keys.collectionInterval)
        self.collectionInterval = stored > 0 ? stored : 60
        self.hostnameOverride = UserDefaults.standard.string(forKey: Keys.hostnameOverride) ?? ""
        self.oauthClientId = UserDefaults.standard.string(forKey: Keys.oauthClientId) ?? ""
        self.dashboardName = UserDefaults.standard.string(forKey: Keys.dashboardName) ?? "macOS Metrics"
    }
}
