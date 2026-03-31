import AppKit
import Carbon

/// A custom view for recording keyboard shortcut combinations.
/// Click to enter recording mode, press a modifier+key combo to set, Esc to cancel, Delete to clear.
class ShortcutRecorderView: NSView {

    // MARK: - State

    private var isRecording = false
    private var currentCombo: KeyCombo?
    private var localMonitor: Any?

    /// Called when a new combo is recorded (nil = cleared)
    var onRecorded: ((KeyCombo?) -> Void)?

    /// The action this recorder is bound to (for conflict detection)
    var action: HotKeyAction?

    /// Warning text shown on conflict
    private var warningText: String?

    // MARK: - UI

    private let displayLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        tf.textColor = .labelColor
        tf.alignment = .center
        return tf
    }()

    private let clearButton: NSButton = {
        let btn = NSButton(title: "✕", target: nil, action: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 10)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    private let warningLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = .systemFont(ofSize: 10)
        tf.textColor = .systemOrange
        tf.alignment = .center
        tf.isHidden = true
        return tf
    }()

    // MARK: - Init

    init(combo: KeyCombo?, action: HotKeyAction) {
        self.currentCombo = combo
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateAppearance()

        clearButton.target = self
        clearButton.action = #selector(clearClicked)

        addSubview(displayLabel)
        addSubview(clearButton)
        addSubview(warningLabel)

        updateDisplay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 24)
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let clearW: CGFloat = 18
        let pad: CGFloat = 6

        displayLabel.frame = NSRect(x: pad, y: 0, width: bounds.width - clearW - pad * 2, height: h)
        clearButton.frame = NSRect(x: bounds.width - clearW - pad, y: (h - 16) / 2, width: clearW, height: 16)
        warningLabel.frame = NSRect(x: 0, y: -16, width: bounds.width, height: 14)
    }

    // MARK: - Appearance

    private func updateAppearance() {
        if isRecording {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        } else {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    private func updateDisplay() {
        if isRecording {
            displayLabel.stringValue = L("Press shortcut...")
            displayLabel.textColor = .secondaryLabelColor
            clearButton.isHidden = true
        } else if let combo = currentCombo {
            displayLabel.stringValue = combo.displayString
            displayLabel.textColor = .labelColor
            clearButton.isHidden = false
        } else {
            displayLabel.stringValue = "—"
            displayLabel.textColor = .tertiaryLabelColor
            clearButton.isHidden = true
        }
    }

    // MARK: - Mouse Interaction

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        hideWarning()
        updateAppearance()
        updateDisplay()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil // Consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        updateAppearance()
        updateDisplay()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Esc = cancel recording
        if keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Delete/Backspace = clear binding
        if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) {
            currentCombo = nil
            stopRecording()
            onRecorded?(nil)
            return
        }

        // Must have at least one modifier
        let hasModifier = flags.contains(.command) || flags.contains(.control) ||
                          flags.contains(.option) || flags.contains(.shift)
        guard hasModifier else {
            NSSound.beep()
            return
        }

        let carbonMods = KeyCombo.carbonModifiers(from: flags)
        let combo = KeyCombo(keyCode: UInt32(keyCode), modifiers: carbonMods)

        // Check for conflicts with other ClaudePet shortcuts
        if let action, let conflict = GlobalHotKeyManager.shared?.conflictingAction(for: combo, excluding: action) {
            showWarning(conflict)
            return
        }

        currentCombo = combo
        stopRecording()
        onRecorded?(combo)
    }

    // MARK: - Warning

    private func showWarning(_ conflictAction: HotKeyAction) {
        warningLabel.stringValue = L("Used by \"\(conflictAction.localizedName)\"")
        warningLabel.isHidden = false
        NSSound.beep()
    }

    private func hideWarning() {
        warningLabel.isHidden = true
    }

    // MARK: - Clear

    @objc private func clearClicked() {
        currentCombo = nil
        hideWarning()
        updateDisplay()
        onRecorded?(nil)
    }

    // MARK: - Resign

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil && isRecording {
            stopRecording()
        }
    }
}
