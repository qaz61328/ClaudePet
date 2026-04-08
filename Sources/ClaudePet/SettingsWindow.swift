import AppKit

/// Tabbed Settings window: General settings + Keyboard Shortcuts
@MainActor
class SettingsWindow {
    private var window: NSWindow?
    private var defaultsObserver: Any?

    // Callback to show speech bubble on the pet
    var onShowBubble: ((String) -> Void)?

    // General tab controls (for bidirectional sync)
    private var muteCheckbox: NSButton?
    private var chatterCheckbox: NSButton?
    private var authModeCheckbox: NSButton?
    private var providerPopup: NSPopUpButton?
    private var ttsCheckbox: NSButton?
    private var ttsProviderPopup: NSPopUpButton?

    private static let providerValues = ["", "anthropic", "bedrock", "claude-cli"]
    private static let providerTitles = [
        "Auto-detect", "Anthropic API", "AWS Bedrock", "Claude Code CLI"
    ]
    private static let ttsProviderValues = ["", "edge-tts", "say"]
    private static let ttsProviderTitles = [
        "Auto-detect", "Edge TTS", "macOS Say"
    ]

    // MARK: - Show / Hide

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            syncFromDefaults()
            return
        }
        window = buildWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Sync from UserDefaults

    func syncFromDefaults() {
        muteCheckbox?.state = SoundPlayer.isMuted ? .on : .off
        chatterCheckbox?.state = PetServer.isChatterEnabled ? .on : .off
        authModeCheckbox?.state = PetServer.isTerminalAuthMode ? .on : .off
        ttsCheckbox?.state = TTSPlayer.isEnabled ? .on : .off

        let current = PetServer.chatterProvider
        if let idx = Self.providerValues.firstIndex(of: current) {
            providerPopup?.selectItem(at: idx)
        }
        let currentTTS = TTSPlayer.provider
        if let idx = Self.ttsProviderValues.firstIndex(of: currentTTS) {
            ttsProviderPopup?.selectItem(at: idx)
        }
    }

    // MARK: - Build Window

    private func buildWindow() -> NSWindow {
        let winWidth: CGFloat = 460
        let winHeight: CGFloat = 420

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Settings")
        window.center()
        window.isReleasedWhenClosed = false

        let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: winWidth, height: winHeight))
        tabView.autoresizingMask = [.width, .height]

        // Tab 1: General
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = L("General")
        tabView.addTabViewItem(generalTab)

        // Tab 2: Keyboard Shortcuts
        let shortcutsTab = NSTabViewItem(identifier: "shortcuts")
        shortcutsTab.label = L("Keyboard Shortcuts")
        tabView.addTabViewItem(shortcutsTab)

        window.contentView = tabView

        // Build content views AFTER adding to window so contentRect is resolved
        let contentRect = tabView.contentRect
        generalTab.view = buildGeneralTab(width: contentRect.width, height: contentRect.height)
        shortcutsTab.view = buildShortcutsTab(width: contentRect.width, height: contentRect.height)

        // Remove previous observer if window is rebuilt (e.g. Restore Defaults)
        if let obs = defaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        // Observe UserDefaults changes for bidirectional sync
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncFromDefaults() }
        }

        syncFromDefaults()
        return window
    }

    // MARK: - General Tab

    private func buildGeneralTab(width: CGFloat, height: CGFloat) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let pad: CGFloat = 20
        let contentWidth = width - pad * 2
        // y = top edge of available space (AppKit: y increases upward)
        var y = height - 20

        // --- Sound ---
        y = addSectionHeader(L("Sound"), to: view, y: y, pad: pad)

        let mute = NSButton(checkboxWithTitle: L("Mute"), target: self, action: #selector(muteToggled(_:)))
        mute.frame = NSRect(x: pad + 4, y: y - 18, width: contentWidth, height: 18)
        view.addSubview(mute)
        muteCheckbox = mute
        y -= 28

        y = addSeparator(to: view, y: y, pad: pad, width: contentWidth)

        // --- Idle Chatter ---
        y = addSectionHeader(L("Idle Chatter"), to: view, y: y, pad: pad)

        let chatter = NSButton(checkboxWithTitle: L("Enable Idle Chatter"), target: self, action: #selector(chatterToggled(_:)))
        chatter.frame = NSRect(x: pad + 4, y: y - 18, width: contentWidth, height: 18)
        view.addSubview(chatter)
        chatterCheckbox = chatter
        y -= 26

        let providerLabel = NSTextField(labelWithString: L("Provider:"))
        providerLabel.font = .systemFont(ofSize: 13)
        providerLabel.frame = NSRect(x: pad + 4, y: y - 19, width: 70, height: 18)
        view.addSubview(providerLabel)

        let popup = NSPopUpButton(frame: NSRect(x: pad + 76, y: y - 22, width: 200, height: 24), pullsDown: false)
        for title in Self.providerTitles {
            popup.addItem(withTitle: L(String.LocalizationValue(title)))
        }
        popup.target = self
        popup.action = #selector(providerChanged(_:))
        view.addSubview(popup)
        providerPopup = popup
        y -= 32

        y = addSeparator(to: view, y: y, pad: pad, width: contentWidth)

        // --- TTS (Text-to-Speech) ---
        y = addSectionHeader(L("TTS (Text-to-Speech)"), to: view, y: y, pad: pad)

        let tts = NSButton(checkboxWithTitle: L("Enable TTS for Chatter"), target: self, action: #selector(ttsToggled(_:)))
        tts.frame = NSRect(x: pad + 4, y: y - 18, width: contentWidth, height: 18)
        view.addSubview(tts)
        ttsCheckbox = tts
        y -= 26

        let ttsLabel = NSTextField(labelWithString: L("Provider:"))
        ttsLabel.font = .systemFont(ofSize: 13)
        ttsLabel.frame = NSRect(x: pad + 4, y: y - 19, width: 70, height: 18)
        view.addSubview(ttsLabel)

        let ttsPopup = NSPopUpButton(frame: NSRect(x: pad + 76, y: y - 22, width: 200, height: 24), pullsDown: false)
        for title in Self.ttsProviderTitles {
            ttsPopup.addItem(withTitle: L(String.LocalizationValue(title)))
        }
        ttsPopup.target = self
        ttsPopup.action = #selector(ttsProviderChanged(_:))
        view.addSubview(ttsPopup)
        ttsProviderPopup = ttsPopup
        y -= 32

        y = addSeparator(to: view, y: y, pad: pad, width: contentWidth)

        // --- Authorization ---
        y = addSectionHeader(L("Authorization"), to: view, y: y, pad: pad)

        let auth = NSButton(checkboxWithTitle: L("Authorize in Terminal"), target: self, action: #selector(authModeToggled(_:)))
        auth.frame = NSRect(x: pad + 4, y: y - 18, width: contentWidth, height: 18)
        view.addSubview(auth)
        authModeCheckbox = auth

        return view
    }

    // MARK: - Keyboard Shortcuts Tab

    private func buildShortcutsTab(width: CGFloat, height: CGFloat) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let pad: CGFloat = 20
        let labelWidth: CGFloat = 160
        let recorderWidth: CGFloat = 160
        let rowHeight: CGFloat = 36
        let actions = HotKeyAction.allCases

        var y = height - 36

        for action in actions {
            let label = NSTextField(labelWithString: action.localizedName)
            label.font = .systemFont(ofSize: 13)
            label.frame = NSRect(x: pad, y: y, width: labelWidth, height: 22)
            view.addSubview(label)

            let combo = GlobalHotKeyManager.shared?.comboForAction(action)
            let recorder = ShortcutRecorderView(combo: combo, action: action)
            recorder.frame = NSRect(x: pad + labelWidth + 10, y: y - 1, width: recorderWidth, height: 24)
            recorder.onRecorded = { newCombo in
                GlobalHotKeyManager.shared?.updateBinding(for: action, combo: newCombo)
            }
            view.addSubview(recorder)

            y -= rowHeight
        }

        y -= 8
        let restoreButton = NSButton(title: L("Restore Defaults"), target: self, action: #selector(restoreDefaultShortcuts(_:)))
        restoreButton.bezelStyle = .rounded
        restoreButton.frame = NSRect(x: (width - 140) / 2, y: y, width: 140, height: 28)
        view.addSubview(restoreButton)

        return view
    }

    // MARK: - Layout Helpers

    /// Add a bold section header label. y = top of available space. Returns y for next element.
    private func addSectionHeader(_ title: String, to view: NSView, y: CGFloat, pad: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: pad, y: y - 16, width: 300, height: 16)
        view.addSubview(label)
        return y - 22
    }

    /// Add a horizontal separator line. Returns the y position for the next section.
    private func addSeparator(to view: NSView, y: CGFloat, pad: CGFloat, width: CGFloat) -> CGFloat {
        let sep = NSBox(frame: NSRect(x: pad, y: y - 1, width: width, height: 1))
        sep.boxType = .separator
        view.addSubview(sep)
        return y - 10
    }

    // MARK: - Actions

    @objc private func muteToggled(_ sender: NSButton) {
        SoundPlayer.isMuted = (sender.state == .on)
    }

    @objc private func chatterToggled(_ sender: NSButton) {
        let on = (sender.state == .on)
        PetServer.isChatterEnabled = on
        onShowBubble?(L(on ? "Idle chatter ON." : "Idle chatter OFF."))
    }

    @objc private func authModeToggled(_ sender: NSButton) {
        let on = (sender.state == .on)
        PetServer.isTerminalAuthMode = on
        onShowBubble?(L(on ? "Authorize in Terminal ON." : "Authorize in Terminal OFF."))
    }

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < Self.providerValues.count else { return }
        PetServer.chatterProvider = Self.providerValues[idx]
    }

    @objc private func ttsToggled(_ sender: NSButton) {
        let on = (sender.state == .on)
        TTSPlayer.isEnabled = on
        onShowBubble?(L(on ? "TTS ON." : "TTS OFF."))
    }

    @objc private func ttsProviderChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < Self.ttsProviderValues.count else { return }
        TTSPlayer.provider = Self.ttsProviderValues[idx]
    }

    @objc private func restoreDefaultShortcuts(_ sender: NSButton) {
        GlobalHotKeyManager.shared?.restoreDefaults()
        // Rebuild window to refresh recorder views
        window?.close()
        window = nil
        show()
    }
}
