import AppKit
import CoreText

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var petWindow: PetWindow!
    var statusBarMenu: StatusBarMenu!
    var server: PetServer!
    var hotKeyManager: GlobalHotKeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't show in Dock
        NSApp.setActivationPolicy(.accessory)

        // Startup cleanup: remove stale session-allow files from previous unclean exit
        AppDelegate.cleanupSessionAllowFiles()

        // Register bundled font (jf-openhuninn)
        if let fontURL = Bundle.module.url(forResource: "jf-openhuninn-2.1", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }

        // Export built-in persona to user directory + load all personas
        PersonaDirectory.exportBuiltIn()
        DialogueBank.reloadPersonas()

        // Create desktop window + character
        petWindow = PetWindow()
        petWindow.show()

        // Status bar menu
        statusBarMenu = StatusBarMenu(petWindow: petWindow)

        // Initialize sound system
        SoundPlayer.setup()

        // Observe app switching (for click-to-switch-terminal)
        TerminalActivator.startObserving()

        // Startup greeting (uses startup sound)
        let greeting = NotifyPayload(project: "", message: DialogueBank.greeting())
        petWindow.petView.showNotification(payload: greeting, sound: .startup)

        // Sync passthrough auth flag file on launch
        PetServer.syncPassthroughAuthFlag()

        // Start HTTP Server
        server = PetServer(petWindow: petWindow)
        do {
            try server.start()
            print("[ClaudePet] v\(PersonaDirectory.appVersion) — HTTP Server started on port 23987")
        } catch {
            print("[ClaudePet] Failed to start server: \(error)")
        }

        // Global keyboard shortcuts
        hotKeyManager = GlobalHotKeyManager(petWindow: petWindow)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.teardown()
        AppDelegate.cleanupSessionAllowFiles()
        try? FileManager.default.removeItem(atPath: PetServer.passthroughAuthFlagPath)
        try? FileManager.default.removeItem(atPath: PetServer.tokenPath)
    }

    private static func cleanupSessionAllowFiles() {
        let tmpDir = FileManager.default.temporaryDirectory.path
        if let tmpContents = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) {
            for file in tmpContents where file.hasPrefix("claudepet-session-allow-") {
                try? FileManager.default.removeItem(atPath: "\(tmpDir)/\(file)")
            }
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
