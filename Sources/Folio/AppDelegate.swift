import AppKit

/// Application delegate. Deliberately thin: NSDocumentController does the file
/// handling, and each window controller owns its own state.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(appDelegate: self)
        // Apply a saved Light/Dark override before any window exists.
        NSApp.appearance = Prefs.appearance.nsAppearance
        // Instantiating the shared controller early makes Finder opens and the
        // Open Recent menu work from the first event loop pass.
        _ = NSDocumentController.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    // Launching with no document, or clicking the Dock icon with no windows
    // open, shows the Open panel -- the way Preview behaves.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Menu actions

    @objc func setAppearance(_ sender: NSMenuItem) {
        guard let mode = AppearanceMode(rawValue: sender.tag) else { return }
        Prefs.appearance = mode
    }

    @objc func toggleInvertInDarkMode(_ sender: NSMenuItem) {
        Prefs.invertInDarkMode.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(setAppearance(_:)):
            menuItem.state = (menuItem.tag == Prefs.appearance.rawValue) ? .on : .off
        case #selector(toggleInvertInDarkMode(_:)):
            menuItem.state = Prefs.invertInDarkMode ? .on : .off
        default:
            break
        }
        return true
    }
}
