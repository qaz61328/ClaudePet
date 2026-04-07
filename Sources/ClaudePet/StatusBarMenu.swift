import AppKit

/// Resolved localized sub-bundle (workaround: SPM resource bundles lack CFBundleLocalizations,
/// so Bundle.module.preferredLocalizations always falls back to the development region.
/// We manually match Locale.preferredLanguages against available .lproj directories.)
let localizedBundle: Bundle = {
    let base = Bundle.module
    let match = Bundle.preferredLocalizations(from: base.localizations,
                                              forPreferences: Locale.preferredLanguages)
    if let lang = match.first,
       let path = base.path(forResource: lang, ofType: "lproj"),
       let sub = Bundle(path: path) {
        return sub
    }
    return base
}()

/// Shorthand for localized string lookup
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: localizedBundle)
}

// MARK: - Status Bar Menu

@MainActor
class StatusBarMenu: NSObject, NSMenuDelegate {
    private static let personaMenuTag = 100
    private static let muteItemTag = 101
    private static let chatterItemTag = 102
    private static let authModeItemTag = 103

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

        let showHideItem = NSMenuItem(title: L("Show/Hide Pet"), action: #selector(toggleVisibility), keyEquivalent: "")
        showHideItem.target = self

        let sayHelloItem = NSMenuItem(title: L("Say Hello"), action: #selector(sayHello), keyEquivalent: "")
        sayHelloItem.target = self

        let quitItem = NSMenuItem(title: L("Quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(makeDisabledItem(title: "ClaudePet 🎩"))
        menu.addItem(makeDisabledItem(title: L("Version \(PersonaDirectory.appVersion)")))
        menu.addItem(.separator())
        let muteItem = NSMenuItem(title: L("Mute"), action: #selector(toggleMute), keyEquivalent: "")
        muteItem.target = self
        muteItem.tag = Self.muteItemTag

        let chatterItem = NSMenuItem(title: L("Idle Chatter"), action: #selector(toggleChatter), keyEquivalent: "")
        chatterItem.target = self
        chatterItem.tag = Self.chatterItemTag

        menu.addItem(showHideItem)
        menu.addItem(sayHelloItem)
        menu.addItem(muteItem)
        let authModeItem = NSMenuItem(title: L("Authorize in Terminal"), action: #selector(toggleAuthMode), keyEquivalent: "")
        authModeItem.target = self
        authModeItem.tag = Self.authModeItemTag

        menu.addItem(chatterItem)
        menu.addItem(authModeItem)

        let shortcutsItem = NSMenuItem(title: L("Keyboard Shortcuts..."), action: #selector(openShortcutPreferences), keyEquivalent: "")
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)
        menu.addItem(.separator())
        let personaItem = NSMenuItem(title: L("Persona"), action: nil, keyEquivalent: "")
        personaItem.submenu = NSMenu()
        personaItem.tag = Self.personaMenuTag
        menu.addItem(personaItem)
        menu.addItem(.separator())
        let upgradeItem = NSMenuItem(title: L("Check for Updates"), action: #selector(upgrade), keyEquivalent: "")
        upgradeItem.target = self
        menu.addItem(upgradeItem)
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
        // Terminal auth mode toggle check state
        if let authModeItem = menu.item(withTag: Self.authModeItemTag) {
            authModeItem.state = PetServer.isTerminalAuthMode ? .on : .off
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

        let reloadItem = NSMenuItem(title: L("Reload Personas"), action: #selector(reloadPersonas), keyEquivalent: "")
        reloadItem.target = self
        submenu.addItem(reloadItem)
    }

    // MARK: - Actions

    @objc private func toggleVisibility() {
        petWindow?.toggleVisibility()
    }

    @objc private func sayHello() {
        showBubble(DialogueBank.greeting())
    }

    @objc private func switchPersona(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        DialogueBank.switchPersona(to: id)
        showBubble(DialogueBank.greeting())
    }

    @objc private func reloadPersonas() {
        DialogueBank.reloadPersonas()
        petWindow?.petView.reloadSprites()
        showBubble(L("Loaded \(DialogueBank.allPersonas.count) persona(s)"))
    }

    @objc private func toggleMute() {
        SoundPlayer.isMuted.toggle()
    }

    @objc private func toggleChatter() {
        PetServer.isChatterEnabled.toggle()
        let enabled = PetServer.isChatterEnabled
        if enabled {
            PetServer.addChatterConfig()
            showBubble(L("Idle chatter ON."))
        } else {
            PetServer.removeChatterConfig()
            showBubble(L("Idle chatter OFF."))
        }
    }

    @objc private func toggleAuthMode() {
        PetServer.isTerminalAuthMode.toggle()
        if PetServer.isTerminalAuthMode {
            showBubble(L("Authorize in Terminal ON."))
        } else {
            showBubble(L("Authorize in Terminal OFF."))
        }
    }

    // MARK: - Keyboard Shortcuts Preferences

    private var shortcutWindow: NSWindow?

    @objc private func openShortcutPreferences() {
        if let existing = shortcutWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let winWidth: CGFloat = 400
        let rowHeight: CGFloat = 36
        let actions = HotKeyAction.allCases
        let contentHeight = CGFloat(actions.count) * rowHeight + 70 // rows + padding + button

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: contentHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Keyboard Shortcuts")
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: winWidth, height: contentHeight))
        window.contentView = contentView

        let pad: CGFloat = 20
        let labelWidth: CGFloat = 160
        let recorderWidth: CGFloat = 140

        for (i, action) in actions.enumerated() {
            let y = contentHeight - CGFloat(i + 1) * rowHeight - 10

            let label = NSTextField(labelWithString: action.localizedName)
            label.font = .systemFont(ofSize: 13)
            label.frame = NSRect(x: pad, y: y, width: labelWidth, height: 22)
            contentView.addSubview(label)

            let combo = GlobalHotKeyManager.shared?.comboForAction(action)
            let recorder = ShortcutRecorderView(combo: combo, action: action)
            recorder.frame = NSRect(x: pad + labelWidth + 10, y: y, width: recorderWidth, height: 24)
            recorder.onRecorded = { newCombo in
                GlobalHotKeyManager.shared?.updateBinding(for: action, combo: newCombo)
            }
            contentView.addSubview(recorder)
        }

        let buttonY: CGFloat = 14
        let restoreButton = NSButton(title: L("Restore Defaults"), target: self, action: #selector(restoreDefaultShortcuts(_:)))
        restoreButton.bezelStyle = .rounded
        restoreButton.frame = NSRect(x: (winWidth - 140) / 2, y: buttonY, width: 140, height: 28)
        contentView.addSubview(restoreButton)

        self.shortcutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func restoreDefaultShortcuts(_ sender: NSButton) {
        GlobalHotKeyManager.shared?.restoreDefaults()
        // Close and reopen to refresh recorder views
        shortcutWindow?.close()
        shortcutWindow = nil
        openShortcutPreferences()
    }

    private var isUpgrading = false

    /// Run a shell command synchronously, returning (exit status, stdout).
    private nonisolated static func runProcess(_ executable: String, args: [String], capture: Bool = false) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = capture ? Pipe() : nil
        process.standardOutput = capture ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let output = pipe.flatMap {
            String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        return (process.terminationStatus, output)
    }

    /// Parse "owner/repo" from git remote URL (SSH or HTTPS).
    private nonisolated static func parseGitHubRepo(in dir: String) -> String? {
        let result = runProcess("/usr/bin/git", args: ["-C", dir, "remote", "get-url", "origin"], capture: true)
        guard result.status == 0, !result.output.isEmpty else { return nil }
        let url = result.output
        // SSH: git@github.com:owner/repo.git  or  git@alias:owner/repo.git
        if let colonRange = url.range(of: ":"), url.contains("@") {
            let path = String(url[colonRange.upperBound...])
                .replacingOccurrences(of: ".git", with: "")
            return path
        }
        // HTTPS: https://github.com/owner/repo.git
        if let parsed = URL(string: url),
           parsed.pathComponents.count >= 3 {
            let owner = parsed.pathComponents[1]
            let repo = parsed.pathComponents[2].replacingOccurrences(of: ".git", with: "")
            return "\(owner)/\(repo)"
        }
        return nil
    }

    @objc private func upgrade() {
        guard !isUpgrading else { return }
        isUpgrading = true

        let projectRoot = PersonaDirectory.projectRoot
        let scriptPath = projectRoot.appendingPathComponent("scripts/upgrade.sh").path
        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            NSLog("[ClaudePet] upgrade script not found at %@", scriptPath)
            isUpgrading = false
            return
        }

        showBubble(L("Checking for updates..."))

        let gitDir = projectRoot.path
        let localVersion = PersonaDirectory.appVersion
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Resolve GitHub repo from git remote
            guard let repo = Self.parseGitHubRepo(in: gitDir) else {
                DispatchQueue.main.async {
                    self?.showBubble(L("Can't detect GitHub repo"))
                    self?.isUpgrading = false
                }
                return
            }

            // Query GitHub Releases API for latest release tag
            let apiURL = "https://api.github.com/repos/\(repo)/releases/latest"
            let curl = Self.runProcess("/usr/bin/curl", args: ["-s", "-m", "10", apiURL], capture: true)
            guard curl.status == 0, !curl.output.isEmpty,
                  let data = curl.output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                DispatchQueue.main.async {
                    self?.showBubble(L("Can't reach GitHub"))
                    self?.isUpgrading = false
                }
                return
            }

            // Strip leading "v" for comparison (tag "v0.2.0" → "0.2.0")
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            guard remoteVersion != localVersion else {
                DispatchQueue.main.async {
                    self?.showBubble(L("Already latest (v\(localVersion))"))
                    self?.isUpgrading = false
                }
                return
            }

            DispatchQueue.main.async { self?.showBubble(L("v\(localVersion) → v\(remoteVersion)")) }

            // Pull latest code
            let pull = Self.runProcess("/usr/bin/git", args: ["-C", gitDir, "pull", "--ff-only", "origin", "main"])
            guard pull.status == 0 else {
                DispatchQueue.main.async {
                    self?.showBubble(L("Pull failed (conflicts?)"))
                    self?.isUpgrading = false
                }
                return
            }

            DispatchQueue.main.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptPath]
                do {
                    try process.run()
                } catch {
                    NSLog("[ClaudePet] upgrade failed: %@", error.localizedDescription)
                    self?.isUpgrading = false
                    return
                }
                // Script handles build + config + relaunch. We terminate ourselves.
                NSApp.terminate(nil)
            }
        }
    }

    private func showBubble(_ message: String) {
        guard let petView = petWindow?.petView else { return }
        petView.showNotification(payload: NotifyPayload(project: "", message: message))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
