import AppKit

// MARK: - TTS Player

/// Text-to-speech player for chatter bubbles.
/// Delegates audio generation to external scripts (Edge TTS / macOS say),
/// plays the resulting audio file via NSSound, and cleans up temp files.
/// Script resolution: Personas/<id>/tts.sh → scripts/tts.sh
@MainActor
enum TTSPlayer {

    // MARK: - UserDefaults

    private static let enabledKey = "ttsEnabled"
    private static let providerKey = "ttsProvider"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// TTS provider override: "" = auto-detect, "edge-tts", "say"
    static var provider: String {
        get { UserDefaults.standard.string(forKey: providerKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: providerKey) }
    }

    // MARK: - Playback State

    private static var currentSound: NSSound?
    private static var currentTempFile: URL?
    private static var currentTask: Task<Void, Never>?

    // MARK: - Public API

    /// Speak text aloud via TTS. Cancels any in-progress speech first.
    /// Fire-and-forget: errors are silently ignored (chatter is low priority).
    static func speak(text: String) {
        guard isEnabled, !SoundPlayer.isMuted else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Cancel previous speech
        stop()

        let personaID = DialogueBank.current.id
        let voiceConfig = (DialogueBank.current as? DataDrivenPersona)?.ttsVoiceConfig
        let providerOverride = provider

        currentTask = Task {
            guard let scriptPath = PersonaDirectory.resolveScript(
                personaID: personaID, name: "tts.sh"
            ) else { return }

            var env: [String: String] = ["TTS_TEXT": trimmed, "TTS_PERSONA": personaID]
            if let edge = voiceConfig?.edgeTTS, !edge.isEmpty { env["TTS_VOICE_EDGE"] = edge }
            if let say = voiceConfig?.say, !say.isEmpty { env["TTS_VOICE_SAY"] = say }
            if !providerOverride.isEmpty { env["TTS_PROVIDER"] = providerOverride }

            guard let audioPath = await PersonaDirectory.runScript(
                path: scriptPath, env: env, timeout: 15
            ), !Task.isCancelled, !audioPath.isEmpty else { return }

            let fileURL = URL(fileURLWithPath: audioPath)
            guard FileManager.default.fileExists(atPath: audioPath) else { return }

            guard let sound = NSSound(contentsOf: fileURL, byReference: false) else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }

            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }

            currentSound = sound
            currentTempFile = fileURL
            sound.play()

            // Schedule cleanup after estimated playback duration
            let duration = sound.duration
            Task {
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.5) * 1_000_000_000))
                cleanupTempFile(fileURL)
            }
        }
    }

    /// Stop current TTS playback and clean up
    static func stop() {
        currentTask?.cancel()
        currentTask = nil
        currentSound?.stop()
        currentSound = nil
        if let tempFile = currentTempFile {
            cleanupTempFile(tempFile)
            currentTempFile = nil
        }
    }

    // MARK: - Cleanup

    private static func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
