import AppKit

// MARK: - Sound Event

enum SoundEvent: String, CaseIterable {
    case startup
    case notify
    case authorize
}

// MARK: - Sound Player

/// Persona sound player.
/// Load order: Personas/<id>/ → Bundle.module → silent (no playback).
/// Supports .aif / .wav / .mp3, tried in order.
@MainActor
enum SoundPlayer {
    /// Cached sounds (reloaded on persona switch)
    private static var sounds: [SoundEvent: NSSound] = [:]
    private static var loadedPersonaID: String?

    private static var personaObserver: Any?

    // MARK: - Setup

    static func setup() {
        guard personaObserver == nil else { return }

        loadSounds(for: DialogueBank.current.id)

        personaObserver = NotificationCenter.default.addObserver(
            forName: .personaDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                loadSounds(for: DialogueBank.current.id)
            }
        }
    }

    // MARK: - Mute

    private static let muteKey = "soundMuted"

    static var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: muteKey) }
        set { UserDefaults.standard.set(newValue, forKey: muteKey) }
    }

    // MARK: - Play

    static func play(_ event: SoundEvent) {
        guard !isMuted else { return }
        sounds[event]?.play()
    }

    // MARK: - Load

    private static func loadSounds(for personaID: String) {
        guard personaID != loadedPersonaID else { return }
        loadedPersonaID = personaID
        sounds.removeAll()

        for event in SoundEvent.allCases {
            if let sound = loadFromPersonaDir(personaID: personaID, event: event)
                ?? loadFromBundle(event: event) {
                sounds[event] = sound
            }
        }
    }

    /// Tier 1: Persona custom sounds (Personas/<id>/notify.aif etc.)
    private static func loadFromPersonaDir(personaID: String, event: SoundEvent) -> NSSound? {
        let dirURL = PersonaDirectory.baseURL.appendingPathComponent(personaID)
        for ext in PersonaDirectory.soundExtensions {
            let fileURL = dirURL.appendingPathComponent("\(event.rawValue).\(ext)")
            if let sound = NSSound(contentsOf: fileURL, byReference: false) {
                return sound
            }
        }
        return nil
    }

    /// Tier 2: Built-in sounds (Bundle.module/default/notify.aif etc.)
    private static func loadFromBundle(event: SoundEvent) -> NSSound? {
        for ext in PersonaDirectory.soundExtensions {
            if let url = Bundle.module.url(
                forResource: event.rawValue,
                withExtension: ext,
                subdirectory: PersonaDirectory.builtInPersonaID
            ), let sound = NSSound(contentsOf: url, byReference: false) {
                return sound
            }
        }
        return nil
    }
}
