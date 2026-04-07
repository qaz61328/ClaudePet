import Foundation

// MARK: - Payload Types

struct NotifyPayload {
    let type: String?
    let project: String
    let message: String?

    init(type: String? = nil, project: String, message: String? = nil) {
        self.type = type
        self.project = project
        self.message = message
    }
}

enum AuthDecision: String {
    case approve
    case approveSession = "approve_session"
    case deny
}

struct AuthorizePayload {
    let tool: String
    let project: String
    let command: String?
    let toolDescription: String?
    let filePath: String?
}

// MARK: - Time Period

enum TimePeriod {
    case morning, afternoon, evening, lateNight

    static var current: TimePeriod {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<24: return .evening
        default: return .lateNight
        }
    }
}

// MARK: - Persona Protocol

/// Persona protocol. Each persona implements its own dialogue bank.
/// To add a persona: 1) Create a struct conforming to Persona  2) Add to DialogueBank.allPersonas
protocol Persona {
    /// Persona ID (used for persistence, must be unique)
    var id: String { get }
    /// Display name
    var displayName: String { get }

    // — Dialogue —
    func greeting(period: TimePeriod) -> String
    func taskComplete(project: String?) -> String
    func authorizeRequest(payload: AuthorizePayload) -> String
    var authButtonLabels: AuthButtonLabels { get }
    func authorized() -> String
    func denied() -> String
    func clicked() -> String
    func switchToTerminal() -> String
    func needsAttention(project: String?) -> String
    func planReady(project: String?) -> String
}

// MARK: - Default Fallback Persona (safety net when JSON loading fails)

struct DefaultPersona: Persona {
    let id = "default"
    let displayName = "ClaudePet"

    func greeting(period: TimePeriod) -> String {
        switch period {
        case .morning:   return "Good morning!"
        case .afternoon: return "Good afternoon!"
        case .evening:   return "Good evening!"
        case .lateNight: return "It's late, take care!"
        }
    }

    func taskComplete(project: String?) -> String {
        guard let p = project, !p.isEmpty else { return "Task complete" }
        return "\(p) is done"
    }

    func authorizeRequest(payload: AuthorizePayload) -> String {
        AuthorizeFormatter.format(payload: payload, openers: ["Authorization needed"], fileToolLabels: nil)
    }

    var authButtonLabels: AuthButtonLabels { .defaults }
    func authorized() -> String { "Got it, executing now" }
    func denied() -> String { "Understood, cancelled" }
    func clicked() -> String { "Hi!" }
    func switchToTerminal() -> String { "Right this way" }

    func needsAttention(project: String?) -> String {
        guard let p = project, !p.isEmpty else { return "Need your input" }
        return "\(p) needs your input"
    }

    func planReady(project: String?) -> String {
        guard let p = project, !p.isEmpty else { return "Plan is ready for review" }
        return "\(p) plan is ready"
    }
}

// MARK: - Dialogue Bank (unified entry point, callers don't need to change)

extension Notification.Name {
    /// Posted on persona switch, observed by PetView and StatusBarMenu
    static let personaDidChange = Notification.Name("personaDidChange")
}

@MainActor
enum DialogueBank {
    private static let selectedPersonaKey = "selectedPersonaID"
    private static let fallbackID = PersonaDirectory.builtInPersonaID

    /// All available personas (discovered from directory on startup + built-in fallback)
    private(set) static var allPersonas: [Persona] = [DefaultPersona()]

    /// Currently active persona (persisted via UserDefaults)
    static var current: Persona = {
        let savedID = UserDefaults.standard.string(forKey: selectedPersonaKey) ?? fallbackID
        return allPersonas.first { $0.id == savedID } ?? DefaultPersona()
    }()

    static func reloadPersonas() {
        var discovered: [Persona] = PersonaDirectory.discoverAll()

        if !discovered.contains(where: { $0.id == fallbackID }) {
            discovered.insert(DefaultPersona(), at: 0)
        }

        allPersonas = discovered

        if !allPersonas.contains(where: { $0.id == current.id }) {
            current = allPersonas.first { $0.id == fallbackID } ?? DefaultPersona()
            UserDefaults.standard.set(current.id, forKey: selectedPersonaKey)
        } else if let updated = allPersonas.first(where: { $0.id == current.id }) {
            current = updated
        }
    }

    static func switchPersona(to id: String) {
        if let persona = allPersonas.first(where: { $0.id == id }) {
            current = persona
            UserDefaults.standard.set(id, forKey: selectedPersonaKey)
            NotificationCenter.default.post(name: .personaDidChange, object: nil)
        }
    }

    // MARK: - Forwarding (preserves existing API)

    static func greeting() -> String {
        current.greeting(period: TimePeriod.current)
    }

    static func taskComplete(project: String?) -> String {
        current.taskComplete(project: project)
    }

    static func authorizeRequest(payload: AuthorizePayload) -> String {
        current.authorizeRequest(payload: payload)
    }

    static var authButtonLabels: AuthButtonLabels {
        current.authButtonLabels
    }

    static func authorized() -> String {
        current.authorized()
    }

    static func denied() -> String {
        current.denied()
    }

    static func clicked() -> String {
        current.clicked()
    }

    static func switchToTerminal() -> String {
        current.switchToTerminal()
    }

    static func needsAttention(project: String?) -> String {
        current.needsAttention(project: project)
    }

    static func planReady(project: String?) -> String {
        current.planReady(project: project)
    }

}
