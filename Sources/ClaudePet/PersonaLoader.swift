import AppKit
import Foundation

// MARK: - Authorize Formatter (shared authorization text assembly logic)

/// Assembles the multi-line display text for authorization requests.
/// Structural logic lives here; personas only provide openers and toolLabels.
enum AuthorizeFormatter {
    /// Known multi-word tools (take first two words)
    static let multiWordTools: Set<String> = [
        "git", "swift", "npm", "npx", "docker", "kubectl",
        "cargo", "pip", "pip3", "brew", "go", "dotnet", "gh",
    ]

    /// Default file tool icon mappings (fallback when no JSON customization)
    static let defaultFileToolLabels: [String: FileToolLabel] = [
        "Edit":         FileToolLabel(pathIcon: "📄", actionLabel: "✏️ Edit File"),
        "Write":        FileToolLabel(pathIcon: "📄", actionLabel: "📝 Write File"),
        "NotebookEdit": FileToolLabel(pathIcon: "📓", actionLabel: "✏️ Edit Notebook"),
    ]

    /// Assemble multi-line authorization request text
    static func format(
        payload: AuthorizePayload,
        openers: [String],
        fileToolLabels: [String: FileToolLabel]?
    ) -> String {
        let labels = fileToolLabels ?? defaultFileToolLabels

        let toolLine: String
        if !payload.project.isEmpty {
            toolLine = "🔧 \(payload.tool) · \(payload.project)"
        } else {
            toolLine = "🔧 \(payload.tool)"
        }

        var lines = [openers.randomElement() ?? "Authorization needed", toolLine]

        switch payload.tool {
        case "Bash":
            if let cmd = payload.command, !cmd.isEmpty {
                lines.append("💻 \(simplifyCommand(cmd))")
            }
            if let desc = payload.toolDescription, !desc.isEmpty {
                let short = desc.count > 40 ? String(desc.prefix(37)) + "..." : desc
                lines.append("📋 \(short)")
            }
        default:
            if let info = labels[payload.tool] {
                if let path = payload.filePath, !path.isEmpty {
                    lines.append("\(info.pathIcon) \(URL(fileURLWithPath: path).lastPathComponent)")
                }
                lines.append(info.actionLabel)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Extract command core: `swift build -c release 2>&1` → `swift build`
    static func simplifyCommand(_ command: String) -> String {
        let segments = command
            .replacingOccurrences(of: "&&", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let segment = segments.first { seg in
            let first = seg.split(separator: " ").first.map(String.init) ?? ""
            return first != "cd"
        } ?? segments.last ?? command

        let words = segment.split(separator: " ").map(String.init)

        // Skip environment variables (KEY=value)
        var i = 0
        while i < words.count && words[i].contains("=") && !words[i].hasPrefix("-") {
            i += 1
        }
        guard i < words.count else { return command }

        let program = words[i]
        if multiWordTools.contains(program),
           i + 1 < words.count,
           !words[i + 1].hasPrefix("-") {
            return "\(program) \(words[i + 1])"
        }
        return program
    }

}

// MARK: - Persona JSON Data Model

/// Icon and action label for a file tool
struct FileToolLabel: Codable {
    let pathIcon: String
    let actionLabel: String
}

/// JSON structure for the authorize section
struct AuthorizeData: Codable {
    let openers: [String]
    let fileToolLabels: [String: FileToolLabel]?
}

/// Dialogue section with generic and withProject variants
struct ProjectDialogue: Codable {
    let generic: [String]
    let withProject: [String]
}

/// Greeting dialogue for four time periods
struct GreetingData: Codable {
    let morning: [String]
    let afternoon: [String]
    let evening: [String]
    let lateNight: [String]
}

/// Complete data structure for persona.json
struct PersonaData: Codable {
    let id: String
    let displayName: String
    let greeting: GreetingData
    let taskComplete: ProjectDialogue
    let authorize: AuthorizeData
    let authorized: [String]
    let denied: [String]
    let clicked: [String]
    let switchToTerminal: [String]
    let needsAttention: ProjectDialogue
    let planReady: ProjectDialogue
}

// MARK: - Data-Driven Persona

/// Persona implementation loaded from JSON
struct DataDrivenPersona: Persona {
    let id: String
    let displayName: String

    private let data: PersonaData

    init?(data: PersonaData) {
        // Basic validation: every required field must have at least one line
        guard !data.greeting.morning.isEmpty,
              !data.greeting.afternoon.isEmpty,
              !data.greeting.evening.isEmpty,
              !data.greeting.lateNight.isEmpty,
              !data.taskComplete.generic.isEmpty,
              !data.authorize.openers.isEmpty,
              !data.authorized.isEmpty,
              !data.denied.isEmpty,
              !data.clicked.isEmpty,
              !data.switchToTerminal.isEmpty,
              !data.needsAttention.generic.isEmpty,
              !data.planReady.generic.isEmpty else {
            return nil
        }

        self.id = data.id
        self.displayName = data.displayName
        self.data = data
    }

    func greeting(period: TimePeriod) -> String {
        let pool: [String]
        switch period {
        case .morning:   pool = data.greeting.morning
        case .afternoon: pool = data.greeting.afternoon
        case .evening:   pool = data.greeting.evening
        case .lateNight: pool = data.greeting.lateNight
        }
        return pool.randomElement()!
    }

    func taskComplete(project: String?) -> String {
        selectProjectLine(from: data.taskComplete, project: project)
    }

    func authorizeRequest(payload: AuthorizePayload) -> String {
        AuthorizeFormatter.format(
            payload: payload,
            openers: data.authorize.openers,
            fileToolLabels: data.authorize.fileToolLabels
        )
    }

    func authorized() -> String {
        data.authorized.randomElement()!
    }

    func denied() -> String {
        data.denied.randomElement()!
    }

    func clicked() -> String {
        data.clicked.randomElement()!
    }

    func switchToTerminal() -> String {
        data.switchToTerminal.randomElement()!
    }

    func needsAttention(project: String?) -> String {
        selectProjectLine(from: data.needsAttention, project: project)
    }

    func planReady(project: String?) -> String {
        selectProjectLine(from: data.planReady, project: project)
    }

    /// Select a line from ProjectDialogue; uses withProject template with {project} replacement when project name exists
    private func selectProjectLine(from dialogue: ProjectDialogue, project: String?) -> String {
        guard let p = project, !p.isEmpty, !dialogue.withProject.isEmpty else {
            return dialogue.generic.randomElement()!
        }
        let line = dialogue.withProject.randomElement()!
        return line.replacingOccurrences(of: "{project}", with: p)
    }
}

// MARK: - Persona Directory (discovery and loading)

@MainActor
enum PersonaDirectory {
    static let builtInPersonaID = "butler"

    /// Sprite state names (idle/bow/alert/happy/working)
    static let spriteStates = ["idle", "bow", "alert", "happy", "working"]

    /// Standard sprite names (4 frames per state)
    static let allSpriteNames: [String] = spriteStates.flatMap { s in (1...4).map { "\(s)_\($0)" } }

    /// Supported sound file extensions (in priority order)
    static let soundExtensions = ["aif", "wav", "mp3"]

    /// Persona directory (Personas/ under project root)
    static var baseURL: URL {
        _projectRoot.appendingPathComponent("Personas")
    }

    /// Computed once: walk up from executable location to find Package.swift to locate project root
    private static let _projectRoot: URL = {
        var dir = Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: ".")
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: ".")
    }()

    /// Scan persona directory and load all valid personas
    static func discoverAll() -> [DataDrivenPersona] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: baseURL.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var personas: [DataDrivenPersona] = []

        for dirURL in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let jsonURL = dirURL.appendingPathComponent("persona.json")
            guard let jsonData = try? Data(contentsOf: jsonURL),
                  let data = try? JSONDecoder().decode(PersonaData.self, from: jsonData),
                  let persona = DataDrivenPersona(data: data) else { continue }

            personas.append(persona)
        }

        return personas
    }

    /// Load all sprite PNGs from persona folder (dynamically detects frame count per state)
    static func loadSprites(for personaID: String) -> [String: NSImage]? {
        let dirURL = baseURL.appendingPathComponent(personaID)
        var sprites: [String: NSImage] = [:]

        for state in spriteStates {
            var frame = 1
            while true {
                let name = "\(state)_\(frame)"
                let fileURL = dirURL.appendingPathComponent("\(name).png")
                guard let image = NSImage(contentsOf: fileURL) else { break }
                sprites[name] = image
                frame += 1
            }
        }

        return sprites.isEmpty ? nil : sprites
    }

    /// Load all sprite PNGs from Bundle (dynamically detects frame count)
    static func loadBundleSprites() -> [String: NSImage] {
        var sprites: [String: NSImage] = [:]

        for state in spriteStates {
            var frame = 1
            while true {
                let name = "\(state)_\(frame)"
                guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: builtInPersonaID),
                      let image = NSImage(contentsOf: url) else { break }
                sprites[name] = image
                frame += 1
            }
        }

        return sprites
    }

    static func exportBuiltIn() {
        let fm = FileManager.default
        let butlerDir = baseURL.appendingPathComponent(builtInPersonaID)

        let jsonDest = butlerDir.appendingPathComponent("persona.json")
        if fm.fileExists(atPath: jsonDest.path) { return }

        try? fm.createDirectory(at: butlerDir, withIntermediateDirectories: true)

        if let bundledJSON = Bundle.module.url(forResource: "persona", withExtension: "json", subdirectory: builtInPersonaID) {
            try? fm.copyItem(at: bundledJSON, to: jsonDest)
        }

        // Dynamically export all sprite frames from bundle
        for state in spriteStates {
            var frame = 1
            while true {
                let name = "\(state)_\(frame)"
                guard let bundledPNG = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: builtInPersonaID) else { break }
                let dest = butlerDir.appendingPathComponent("\(name).png")
                try? fm.copyItem(at: bundledPNG, to: dest)
                frame += 1
            }
        }

        // Export sound files
        for event in SoundEvent.allCases {
            for ext in soundExtensions {
                if let bundledSound = Bundle.module.url(forResource: event.rawValue, withExtension: ext, subdirectory: builtInPersonaID) {
                    let dest = butlerDir.appendingPathComponent("\(event.rawValue).\(ext)")
                    try? fm.copyItem(at: bundledSound, to: dest)
                }
            }
        }

        // Export chatter prompt
        if let bundledChatter = Bundle.module.url(forResource: "chatter-prompt", withExtension: "md", subdirectory: builtInPersonaID) {
            let chatterDest = butlerDir.appendingPathComponent("chatter-prompt.md")
            try? fm.copyItem(at: bundledChatter, to: chatterDest)
        }

        print("[PersonaLoader] Built-in persona exported to \(butlerDir.path)")
    }
}
