import AppKit

// MARK: - Terminal Activator

/// Detects and activates the user's terminal, preferring the tab running Claude Code.
/// PetServer calls trackProject(_:) on each request to track the active project.
/// PetView.mouseDown calls activate() to switch.
@MainActor
enum TerminalActivator {
    /// Most recently active project name
    private static var lastActiveProject: String?

    /// Bundle ID of the frontmost app before click (tracked via NSWorkspace notifications)
    private static var previousFrontmostBundleID: String?

    /// Supported terminal Bundle IDs (in priority order)
    private static let terminalBundleIDs = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
    ]

    /// Track the most recently active project (called by PetServer on each request)
    static func trackProject(_ project: String) {
        if !project.isEmpty {
            lastActiveProject = project
        }
    }

    /// Start observing app activation events, tracking the last non-self frontmost app (called from AppDelegate)
    static func startObserving() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Only track non-self app switches
            if app.processIdentifier != myPID {
                Task { @MainActor in
                    previousFrontmostBundleID = app.bundleIdentifier
                }
            }
        }
    }

    /// Activate the terminal and try to switch to the Claude Code tab
    /// - Returns: `true` if a switch occurred (terminal was not already frontmost)
    @discardableResult
    static func activate() -> Bool {
        let running = NSWorkspace.shared.runningApplications

        // Find a running terminal
        guard let (app, bundleID) = findRunningTerminal(in: running) else {
            return false
        }

        // Terminal was already frontmost before click — no switch needed
        if previousFrontmostBundleID == bundleID { return false }

        // Activate the terminal immediately
        if #available(macOS 14.0, *) {
            app.activate(from: NSRunningApplication.current)
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // Switch to Claude's tab via AppleScript in background
        switchToClaudeTab(bundleID: bundleID, project: lastActiveProject)

        return true
    }

    // MARK: - Private Helpers

    private static func findRunningTerminal(in apps: [NSRunningApplication]) -> (NSRunningApplication, String)? {
        for bundleID in terminalBundleIDs {
            if let app = apps.first(where: { $0.bundleIdentifier == bundleID }) {
                return (app, bundleID)
            }
        }
        return nil
    }

    /// Escape string for AppleScript (prevent injection from project names containing quotes)
    private static func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Search keyword list: project name first, "claude" as fallback
    private static func searchKeywords(project: String?) -> [String] {
        var keywords: [String] = []
        if let p = project, !p.isEmpty { keywords.append(escapeForAppleScript(p)) }
        keywords.append("claude")
        return keywords
    }

    // MARK: - AppleScript Tab Switching

    /// Switch to the tab containing Claude via osascript in background (non-blocking)
    private static func switchToClaudeTab(bundleID: String, project: String?) {
        let script: String
        switch bundleID {
        case "com.googlecode.iterm2":
            script = iTerm2Script(project: project)
        case "com.apple.Terminal":
            script = terminalAppScript(project: project)
        default:
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    /// iTerm2 AppleScript: search project name first, then "claude"
    private static func iTerm2Script(project: String?) -> String {
        let searchBlocks = searchKeywords(project: project).map { keyword in
            """
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if name of s contains "\(keyword)" then
                                select t
                                select w
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            """
        }.joined(separator: "\n")

        return """
        tell application "iTerm2"
        \(searchBlocks)
        end tell
        """
    }

    /// Terminal.app AppleScript: search project name first, then "claude"
    private static func terminalAppScript(project: String?) -> String {
        let searchBlocks = searchKeywords(project: project).map { keyword in
            """
                repeat with w in windows
                    set tabList to tabs of w
                    repeat with t in tabList
                        if processes of t contains "\(keyword)" then
                            set selected tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            """
        }.joined(separator: "\n")

        return """
        tell application "Terminal"
        \(searchBlocks)
        end tell
        """
    }
}
