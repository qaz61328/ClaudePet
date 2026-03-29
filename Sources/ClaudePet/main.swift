import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var petWindow: PetWindow!
    var statusBarMenu: StatusBarMenu!
    var server: PetServer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't show in Dock
        NSApp.setActivationPolicy(.accessory)

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

        // Start HTTP Server
        server = PetServer(petWindow: petWindow)
        do {
            try server.start()
            print("[ClaudePet] HTTP Server started on port 23987")
        } catch {
            print("[ClaudePet] Failed to start server: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up session authorization memory
        try? FileManager.default.removeItem(atPath: "/tmp/claudepet-session-allow")
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
