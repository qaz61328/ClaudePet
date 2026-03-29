import AppKit

// MARK: - Status Bar Menu

@MainActor
class StatusBarMenu: NSObject, NSMenuDelegate {
    private static let personaMenuTag = 100
    private static let muteItemTag = 101
    private static let chatterItemTag = 102

    private var statusItem: NSStatusItem?
    private weak var petWindow: PetWindow?

    init(petWindow: PetWindow) {
        self.petWindow = petWindow
        super.init()
        setupStatusBar()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Load custom pixel-art icon (@2x set to 18pt, Retina auto-uses 36px)
            if let url = Bundle.module.url(forResource: "statusbar_icon@2x", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                // Fallback to SF Symbol
                button.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "ClaudePet")
                button.image?.size = NSSize(width: 18, height: 18)
            }
        }

        let menu = NSMenu()
        menu.delegate = self

        let showHideItem = NSMenuItem(title: "Show/Hide Pet", action: #selector(toggleVisibility), keyEquivalent: "")
        showHideItem.target = self

        let sayHelloItem = NSMenuItem(title: "Say Hello", action: #selector(sayHello), keyEquivalent: "")
        sayHelloItem.target = self

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(makeDisabledItem(title: "ClaudePet 🎩"))
        menu.addItem(makeDisabledItem(title: "Version \(PersonaDirectory.appVersion)"))
        menu.addItem(.separator())
        let muteItem = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "")
        muteItem.target = self
        muteItem.tag = Self.muteItemTag

        let chatterItem = NSMenuItem(title: "Idle Chatter", action: #selector(toggleChatter), keyEquivalent: "")
        chatterItem.target = self
        chatterItem.tag = Self.chatterItemTag

        menu.addItem(showHideItem)
        menu.addItem(sayHelloItem)
        menu.addItem(muteItem)
        menu.addItem(chatterItem)
        menu.addItem(.separator())
        let personaItem = NSMenuItem(title: "Persona", action: nil, keyEquivalent: "")
        personaItem.submenu = NSMenu()
        personaItem.tag = Self.personaMenuTag
        menu.addItem(personaItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func makeDisabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Mute toggle check state
        if let muteItem = menu.item(withTag: Self.muteItemTag) {
            muteItem.state = SoundPlayer.isMuted ? .on : .off
        }
        // Idle chatter toggle check state
        if let chatterItem = menu.item(withTag: Self.chatterItemTag) {
            chatterItem.state = PetServer.isChatterEnabled ? .on : .off
        }

        guard let personaItem = menu.item(withTag: Self.personaMenuTag),
              let submenu = personaItem.submenu else { return }
        rebuildPersonaSubmenu(submenu)
    }

    private func rebuildPersonaSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()

        let currentID = DialogueBank.current.id
        for persona in DialogueBank.allPersonas {
            let item = NSMenuItem(title: persona.displayName, action: #selector(switchPersona(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = persona.id
            item.state = (persona.id == currentID) ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())

        let reloadItem = NSMenuItem(title: "Reload Personas", action: #selector(reloadPersonas), keyEquivalent: "")
        reloadItem.target = self
        submenu.addItem(reloadItem)
    }

    // MARK: - Actions

    @objc private func toggleVisibility() {
        petWindow?.toggleVisibility()
    }

    @objc private func sayHello() {
        guard let petView = petWindow?.petView else { return }
        let payload = NotifyPayload(project: "", message: DialogueBank.greeting())
        petView.showNotification(payload: payload)
    }

    @objc private func switchPersona(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        DialogueBank.switchPersona(to: id)

        guard let petView = petWindow?.petView else { return }
        let payload = NotifyPayload(project: "", message: DialogueBank.greeting())
        petView.showNotification(payload: payload)
    }

    @objc private func reloadPersonas() {
        DialogueBank.reloadPersonas()
        petWindow?.petView.reloadSprites()

        guard let petView = petWindow?.petView else { return }
        let count = DialogueBank.allPersonas.count
        let payload = NotifyPayload(project: "", message: "Loaded \(count) persona(s)")
        petView.showNotification(payload: payload)
    }

    @objc private func toggleMute() {
        SoundPlayer.isMuted.toggle()
    }

    @objc private func toggleChatter() {
        PetServer.isChatterEnabled.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
