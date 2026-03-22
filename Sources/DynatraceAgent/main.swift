import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = { @MainActor in AppDelegate() }()
app.delegate = delegate
app.run()
