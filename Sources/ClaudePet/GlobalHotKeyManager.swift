import AppKit
import Carbon

// MARK: - Hotkey Action

enum HotKeyAction: UInt32, CaseIterable {
    case togglePet = 1
    case authAllow = 2
    case authAlwaysAllow = 3
    case authDeny = 4

    var userDefaultsKey: String {
        switch self {
        case .togglePet:      return "hotkey.togglePet"
        case .authAllow:      return "hotkey.authAllow"
        case .authAlwaysAllow: return "hotkey.authAlwaysAllow"
        case .authDeny:       return "hotkey.authDeny"
        }
    }

    var defaultCombo: KeyCombo {
        // All default to Ctrl+Opt prefix
        let mods = KeyCombo.carbonControl | KeyCombo.carbonOption
        switch self {
        case .togglePet:      return KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: mods) // ^⌥P
        case .authAllow:      return KeyCombo(keyCode: UInt32(kVK_ANSI_Y), modifiers: mods) // ^⌥Y
        case .authAlwaysAllow: return KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: mods) // ^⌥A
        case .authDeny:       return KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: mods) // ^⌥N
        }
    }

    var localizedName: String {
        switch self {
        case .togglePet:      return L("Toggle Pet")
        case .authAllow:      return L("Allow (Auth)")
        case .authAlwaysAllow: return L("Always Allow (Auth)")
        case .authDeny:       return L("Deny (Auth)")
        }
    }
}

// MARK: - Key Combo

struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    // Carbon modifier constants
    static let carbonCommand: UInt32 = UInt32(cmdKey)
    static let carbonShift: UInt32   = UInt32(shiftKey)
    static let carbonOption: UInt32  = UInt32(optionKey)
    static let carbonControl: UInt32 = UInt32(controlKey)

    // MARK: - Display

    /// Human-readable symbol string (e.g. "⌃⌥P")
    var displayString: String {
        var s = ""
        // Standard macOS modifier symbol ordering: ⌃ ⌥ ⇧ ⌘
        if modifiers & Self.carbonControl != 0 { s += "⌃" }
        if modifiers & Self.carbonOption != 0  { s += "⌥" }
        if modifiers & Self.carbonShift != 0   { s += "⇧" }
        if modifiers & Self.carbonCommand != 0 { s += "⌘" }
        s += Self.keyCodeToString(keyCode)
        return s
    }

    // MARK: - Cocoa ↔ Carbon Conversion

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command)  { m |= carbonCommand }
        if flags.contains(.shift)    { m |= carbonShift }
        if flags.contains(.option)   { m |= carbonOption }
        if flags.contains(.control)  { m |= carbonControl }
        return m
    }

    static func cocoaModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & carbonCommand != 0 { flags.insert(.command) }
        if carbon & carbonShift != 0   { flags.insert(.shift) }
        if carbon & carbonOption != 0  { flags.insert(.option) }
        if carbon & carbonControl != 0 { flags.insert(.control) }
        return flags
    }

    // MARK: - Persistence

    func save(for action: HotKeyAction) {
        UserDefaults.standard.set(["keyCode": keyCode, "modifiers": modifiers], forKey: action.userDefaultsKey)
    }

    static func load(for action: HotKeyAction) -> KeyCombo? {
        guard let dict = UserDefaults.standard.dictionary(forKey: action.userDefaultsKey),
              let kc = dict["keyCode"] as? UInt32,
              let mods = dict["modifiers"] as? UInt32 else {
            return nil
        }
        return KeyCombo(keyCode: kc, modifiers: mods)
    }

    static func loadOrDefault(for action: HotKeyAction) -> KeyCombo {
        load(for: action) ?? action.defaultCombo
    }

    static func clear(for action: HotKeyAction) {
        UserDefaults.standard.removeObject(forKey: action.userDefaultsKey)
    }

    // MARK: - Key Name Lookup

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        // Map Carbon virtual key codes to display characters
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "?"
        }
    }
}

// MARK: - Carbon Event Handler (C callback)

/// Top-level C-convention function for Carbon event dispatch
private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    // Dispatch to main actor
    let actionID = hotKeyID.id
    DispatchQueue.main.async {
        GlobalHotKeyManager.shared?.handleHotKey(id: actionID)
    }
    return noErr
}

// MARK: - Global HotKey Manager

@MainActor
class GlobalHotKeyManager {
    static var shared: GlobalHotKeyManager?

    private weak var petWindow: PetWindow?
    private var handlerRef: EventHandlerRef?
    private var bindings: [HotKeyAction: (ref: EventHotKeyRef, combo: KeyCombo)] = [:]
    private let signature: FourCharCode = 0x43504554 // "CPET"

    init(petWindow: PetWindow) {
        self.petWindow = petWindow
        Self.shared = self
        installHandler()
        registerAll()
    }

    // MARK: - Setup

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }

    private func registerAll() {
        for action in HotKeyAction.allCases {
            let combo = KeyCombo.loadOrDefault(for: action)
            register(action: action, combo: combo)
        }
    }

    // MARK: - Register / Unregister

    private func register(action: HotKeyAction, combo: KeyCombo) {
        unregister(action: action)

        let hotKeyID = EventHotKeyID(signature: signature, id: action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            bindings[action] = (ref, combo)
        } else {
            print("[GlobalHotKeyManager] Failed to register \(action): \(status)")
        }
    }

    private func unregister(action: HotKeyAction) {
        if let binding = bindings.removeValue(forKey: action) {
            UnregisterEventHotKey(binding.ref)
        }
    }

    // MARK: - Dispatch

    func handleHotKey(id: UInt32) {
        guard let action = HotKeyAction(rawValue: id) else { return }

        switch action {
        case .togglePet:
            petWindow?.toggleVisibility()
        case .authAllow:
            petWindow?.petView.invokeAuthDecision(.approve)
        case .authAlwaysAllow:
            petWindow?.petView.invokeAuthDecision(.approveSession)
        case .authDeny:
            petWindow?.petView.invokeAuthDecision(.deny)
        }
    }

    // MARK: - Public API

    func comboForAction(_ action: HotKeyAction) -> KeyCombo? {
        bindings[action]?.combo
    }

    func updateBinding(for action: HotKeyAction, combo: KeyCombo?) {
        if let combo {
            combo.save(for: action)
            register(action: action, combo: combo)
        } else {
            unregister(action: action)
            KeyCombo.clear(for: action)
        }
    }

    func restoreDefaults() {
        for action in HotKeyAction.allCases {
            KeyCombo.clear(for: action)
            register(action: action, combo: action.defaultCombo)
        }
    }

    func conflictingAction(for combo: KeyCombo, excluding: HotKeyAction) -> HotKeyAction? {
        for (action, binding) in bindings where action != excluding && binding.combo == combo {
            return action
        }
        return nil
    }

    // MARK: - Cleanup

    func teardown() {
        for action in HotKeyAction.allCases {
            unregister(action: action)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        Self.shared = nil
    }
}
