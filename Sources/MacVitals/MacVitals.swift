import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var sharedDelegate: AppDelegate?
    private var statusBarController: StatusBarController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.sharedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}
