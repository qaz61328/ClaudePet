@preconcurrency import CFNetwork
import Foundation
import Network

// MARK: - Pet Server

@MainActor
class PetServer {
    private var listener: NWListener?
    private weak var petWindow: PetWindow?

    // Pending authorization: connection + continuation for async hold
    private var pendingAuthConn: NWConnection?
    private var pendingAuthContinuation: CheckedContinuation<AuthDecision, Never>?

    // Queue for concurrent authorize requests
    private var waitingAuthRequests: [(conn: NWConnection, payload: AuthorizePayload)] = []

    // MARK: - Session Tracking (multi-session working state)

    /// Set of active Claude Code session IDs
    private var activeSessions: Set<String> = []

    /// Per-session timeout timers (3 min inactivity auto-expiry, handles crashes)
    private var sessionTimeouts: [String: Timer] = [:]

    /// Session timeout interval (seconds)
    private static let sessionTimeoutInterval: TimeInterval = 180

    // MARK: - Auth Token (prevents unauthorized local process access)

    /// Random token generated per launch, written to $TMPDIR/claudepet-token (mode 0600)
    static let authToken = UUID().uuidString
    static let tokenPath = FileManager.default.temporaryDirectory.appendingPathComponent("claudepet-token").path

    /// Valid Host header values (rejects DNS rebinding)
    private static let allowedHosts: Set<String> = ["127.0.0.1:23987", "localhost:23987", "127.0.0.1", "localhost"]

    init(petWindow: PetWindow) {
        self.petWindow = petWindow
    }

    // MARK: - Start / Stop

    func start(port: UInt16 = 23987) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!
        )

        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in
                self?.handleConnection(conn)
            }
        }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[PetServer] Listening on 127.0.0.1:\(port)")
            case .failed(let error):
                print("[PetServer] Listener failed: \(error)")
            default:
                break
            }
        }
        l.start(queue: .main)
        self.listener = l

        // Write auth token to $TMPDIR (mode 0600, owner-only read/write)
        FileManager.default.createFile(
            atPath: Self.tokenPath,
            contents: Self.authToken.data(using: .utf8),
            attributes: [.posixPermissions: 0o600]
        )
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .main)
        receiveHTTPRequest(conn) { [weak self] method, path, body, host, token in
            guard let self else { conn.cancel(); return }
            self.route(conn: conn, method: method, path: path, body: body, host: host, token: token)
        }
    }

    private func receiveHTTPRequest(_ conn: NWConnection, completion: @escaping @MainActor (String, String, Data?, String?, String?) -> Void) {
        let msg = CFHTTPMessageCreateEmpty(nil, true).takeRetainedValue()

        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    print("[PetServer] Receive error: \(error)")
                    conn.cancel()
                    return
                }

                if let data, !data.isEmpty {
                    let bytes = [UInt8](data)
                    CFHTTPMessageAppendBytes(msg, bytes, bytes.count)
                }

                if CFHTTPMessageIsHeaderComplete(msg) {
                    let contentLength: Int
                    if let clHeader = CFHTTPMessageCopyHeaderFieldValue(msg, "Content-Length" as CFString)?.takeRetainedValue() as String? {
                        contentLength = Int(clHeader) ?? 0
                    } else {
                        contentLength = 0
                    }

                    let bodyData = CFHTTPMessageCopyBody(msg)?.takeRetainedValue() as Data?
                    let bodyLength = bodyData?.count ?? 0

                    if bodyLength >= contentLength {
                        let method = CFHTTPMessageCopyRequestMethod(msg)?.takeRetainedValue() as String? ?? "GET"
                        let url = CFHTTPMessageCopyRequestURL(msg)?.takeRetainedValue() as URL?
                        let path = url?.path ?? "/"
                        let host = CFHTTPMessageCopyHeaderFieldValue(msg, "Host" as CFString)?.takeRetainedValue() as String?
                        let token = CFHTTPMessageCopyHeaderFieldValue(msg, "X-ClaudePet-Token" as CFString)?.takeRetainedValue() as String?
                        Task { @MainActor in
                            completion(method, path, bodyData, host, token)
                        }
                        return
                    }
                }

                if isComplete {
                    conn.cancel()
                    return
                }

                Task { @MainActor in readMore() }
            }
        }

        readMore()
    }

    // MARK: - Routing

    private func route(conn: NWConnection, method: String, path: String, body: Data?, host: String?, token: String?) {
        // Auth token + Host validation for all POST endpoints (prevents unauthorized access & DNS rebinding)
        if method == "POST" {
            guard let token, token == Self.authToken else {
                sendJSON(conn, status: 403, body: ErrorResponse(error: "forbidden"))
                return
            }
            guard let host, Self.allowedHosts.contains(host) else {
                sendJSON(conn, status: 403, body: ErrorResponse(error: "forbidden"))
                return
            }
        }

        // Reject oversized request bodies (64KB limit, prevents memory exhaustion)
        if let body, body.count > 65_536 {
            sendJSON(conn, status: 413, body: ErrorResponse(error: "body too large"))
            return
        }

        switch (method, path) {
        case ("GET", "/health"):
            let personaID = DialogueBank.current.id
            let sessionCount = activeSessions.count
            let chatterOn = Self.isChatterEnabled
            let termAuth = Self.isTerminalAuthMode
            sendJSON(conn, status: 200, body: HealthResponse(
                version: PersonaDirectory.appVersion, persona: personaID,
                activeSessions: sessionCount, chatterEnabled: chatterOn, terminalAuthMode: termAuth
            ))

        case ("POST", "/notify"):
            handleNotify(conn: conn, body: body)

        case ("POST", "/authorize"):
            handleAuthorize(conn: conn, body: body)

        case ("POST", "/chatter"):
            handleChatter(conn: conn, body: body)

        case ("POST", "/working"):
            handleWorking(conn: conn, body: body)

        default:
            sendJSON(conn, status: 404, body: ErrorResponse(error: "not found"))
        }
    }

    // MARK: - /notify

    private func handleNotify(conn: NWConnection, body: Data?) {
        sendJSON(conn, status: 200, body: StatusResponse(status: "received"))

        guard petWindow?.isVisible == true else { return }

        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return
        }

        let project = json["project"] as? String ?? ""
        let payload = NotifyPayload(
            type: json["type"] as? String,
            project: project,
            message: json["message"] as? String
        )

        TerminalActivator.trackProject(project)
        petWindow?.petView.showNotification(payload: payload)
    }

    // MARK: - /authorize (async hold)

    private func handleAuthorize(conn: NWConnection, body: Data?) {
        // Fall through to Claude Code native auth when pet is hidden
        guard petWindow?.isVisible == true else {
            sendJSON(conn, status: 503, body: ErrorResponse(error: "pet hidden"))
            return
        }

        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            sendJSON(conn, status: 400, body: ErrorResponse(error: "invalid body"))
            return
        }

        let project = json["project"] as? String ?? ""
        let payload = AuthorizePayload(
            tool: json["tool"] as? String ?? "unknown",
            project: project,
            command: json["command"] as? String,
            toolDescription: json["description"] as? String,
            filePath: json["file_path"] as? String
        )

        TerminalActivator.trackProject(project)

        // Already processing an authorization — queue this one, don't cancel
        if pendingAuthContinuation != nil {
            // Detect queued client disconnect — remove from queue
            conn.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .failed, .cancelled:
                        self.waitingAuthRequests.removeAll { $0.conn === conn }
                    default:
                        break
                    }
                }
            }
            waitingAuthRequests.append((conn: conn, payload: payload))
            return
        }

        processAuth(conn: conn, payload: payload)
    }

    private func processAuth(conn: NWConnection, payload: AuthorizePayload) {
        pendingAuthConn = conn

        // Detect client disconnect to avoid permanently suspended continuation
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .failed, .cancelled:
                    if let cont = self.pendingAuthContinuation {
                        self.pendingAuthContinuation = nil
                        cont.resume(returning: .deny)
                    }
                    self.pendingAuthConn = nil
                    self.petWindow?.petView.cancelPendingAuthorization()
                    self.processNextAuth()
                default:
                    break
                }
            }
        }

        // Use Task + withCheckedContinuation for async hold
        Task { @MainActor [weak self] in
            guard let self else { return }

            let decision = await withCheckedContinuation { (continuation: CheckedContinuation<AuthDecision, Never>) in
                self.pendingAuthContinuation = continuation

                self.petWindow?.petView.showAuthorization(payload: payload) { [weak self] decision in
                    guard let self else { return }
                    if let cont = self.pendingAuthContinuation {
                        self.pendingAuthContinuation = nil
                        cont.resume(returning: decision)
                    }
                }
            }

            // Decision made, clear disconnect handler
            // Prevent conn.cancel() from triggering cancelPendingAuthorization() killing the response bubble timer
            self.pendingAuthConn?.stateUpdateHandler = nil

            if let c = self.pendingAuthConn {
                let tool = payload.tool
                let response: AuthDecisionResponse
                switch decision {
                case .approve:
                    response = AuthDecisionResponse(decision: decision.rawValue)
                case .approveSession:
                    response = AuthDecisionResponse(decision: decision.rawValue, tool: tool)
                case .deny:
                    response = AuthDecisionResponse(decision: decision.rawValue, reason: "User denied")
                }
                self.sendJSON(c, status: 200, body: response)
                self.pendingAuthConn = nil
            }

            // Process next queued authorization request
            self.processNextAuth()
        }
    }

    /// Dequeue and process the next authorization request
    private func processNextAuth() {
        guard !waitingAuthRequests.isEmpty else { return }
        let next = waitingAuthRequests.removeFirst()
        processAuth(conn: next.conn, payload: next.payload)
    }

    // MARK: - /working (session working state tracking)

    private func handleWorking(conn: NWConnection, body: Data?) {
        sendJSON(conn, status: 200, body: StatusResponse(status: "received"))

        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let sessionID = json["session"] as? String,
              !sessionID.isEmpty else {
            return
        }

        let active = json["active"] as? Bool ?? true

        if active {
            let wasEmpty = activeSessions.isEmpty
            activeSessions.insert(sessionID)

            // Reset this session's timeout timer
            sessionTimeouts[sessionID]?.invalidate()
            sessionTimeouts[sessionID] = Timer.scheduledTimer(withTimeInterval: Self.sessionTimeoutInterval, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.expireSession(sessionID)
                }
            }

            if wasEmpty {
                petWindow?.petView.startWorking()
            }
        } else {
            removeSession(sessionID)
        }
    }

    /// Remove session and notify PetView when all sessions have ended
    private func removeSession(_ sessionID: String) {
        activeSessions.remove(sessionID)
        sessionTimeouts[sessionID]?.invalidate()
        sessionTimeouts.removeValue(forKey: sessionID)

        if activeSessions.isEmpty {
            petWindow?.petView.stopWorking()
        }
    }

    /// Session auto-expiry on timeout (handles crash / abnormal disconnect)
    private func expireSession(_ sessionID: String) {
        guard activeSessions.contains(sessionID) else { return }
        print("[PetServer] Session \(sessionID.prefix(8))... timed out")
        removeSession(sessionID)
    }

    // MARK: - /chatter (idle chatter, no sound, low priority)

    private static let chatterEnabledKey = "chatterEnabled"

    static var isChatterEnabled: Bool {
        get {
            (UserDefaults.standard.object(forKey: chatterEnabledKey) as? Bool) ?? false
        }
        set { UserDefaults.standard.set(newValue, forKey: chatterEnabledKey) }
    }

    // MARK: - CLAUDE.md chatter config management

    private static let chatterMarkerStart = "<!-- claudepet-chatter-start -->"
    private static let chatterMarkerEnd = "<!-- claudepet-chatter-end -->"
    private static let claudeMDPath = NSHomeDirectory() + "/.claude/CLAUDE.md"

    /// Check if the chatter config block exists in ~/.claude/CLAUDE.md
    static var isChatterConfigPresent: Bool {
        guard let content = try? String(contentsOfFile: claudeMDPath, encoding: .utf8) else { return false }
        return content.contains(chatterMarkerStart)
    }

    /// Append chatter config block to ~/.claude/CLAUDE.md (with start/end markers)
    static func addChatterConfig() {
        let projectPath = PersonaDirectory.projectRoot.path
        let block = """

        \(chatterMarkerStart)
        ## ClaudePet Idle Chatter

        At the start of each session, proactively set up an idle chatter schedule using CronCreate:
        - Cron minute field: randomly pick 3 different minutes (0-59), comma-separated (e.g. `7,31,48 * * * *`). Randomize per session to avoid multiple sessions triggering simultaneously.
        - prompt: `First run touch $TMPDIR/claudepet-chatter-lock (prevents Stop hook from sending extra "work complete" notifications). Then run curl -s -m 1 http://127.0.0.1:23987/health — if it fails, stop. On success, check the chatterEnabled field in the returned JSON; if false, stop (do not launch subagent). If true, use the Agent tool (model: haiku) to launch a subagent with a prompt that includes: (1) a one-sentence summary of the current conversation and the current time (2) instructions for the subagent to read \(projectPath)/Personas/<persona-id>/chatter-prompt.md (persona ID from the health JSON) and follow all rules therein to decide whether to send idle chatter.`
        - After sending chatter (whether cron-triggered or spontaneous), do not report the result to the user — complete silently
        - Additionally, you may spontaneously send chatter at appropriate moments during conversation (no need to wait for cron); spontaneous chatter does not require a subagent or the lock file
        \(chatterMarkerEnd)
        """

        guard !isChatterConfigPresent else { return }

        let claudeDir = NSHomeDirectory() + "/.claude"
        try? FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        if let fh = FileHandle(forWritingAtPath: claudeMDPath) {
            fh.seekToEndOfFile()
            if let data = block.data(using: .utf8) { fh.write(data) }
            fh.closeFile()
        } else {
            try? block.data(using: .utf8)?.write(to: URL(fileURLWithPath: claudeMDPath))
        }
    }

    /// Remove chatter config block from ~/.claude/CLAUDE.md (between start/end markers)
    static func removeChatterConfig() {
        guard let content = try? String(contentsOfFile: claudeMDPath, encoding: .utf8) else { return }
        guard let startRange = content.range(of: chatterMarkerStart),
              let endRange = content.range(of: chatterMarkerEnd) else { return }

        // Include preceding newlines before the start marker
        var removeStart = startRange.lowerBound
        while removeStart > content.startIndex {
            let prev = content.index(before: removeStart)
            if content[prev] == "\n" { removeStart = prev } else { break }
        }

        // Include trailing newline after end marker
        var removeEnd = endRange.upperBound
        if removeEnd < content.endIndex && content[removeEnd] == "\n" {
            removeEnd = content.index(after: removeEnd)
        }

        var newContent = String(content[..<removeStart]) + String(content[removeEnd...])
        // Trim excess trailing newlines
        while newContent.hasSuffix("\n\n\n") { newContent.removeLast() }

        try? newContent.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Authorization Mode

    private static let terminalAuthModeKey = "terminalAuthMode"
    static let passthroughAuthFlagPath = FileManager.default.temporaryDirectory.appendingPathComponent("claudepet-passthrough-auth").path

    /// true = Terminal handles auth (hook sends notification only, exits 0)
    /// false = Pet handles auth (hook calls /authorize, pet shows bubble)
    static var isTerminalAuthMode: Bool {
        get {
            (UserDefaults.standard.object(forKey: terminalAuthModeKey) as? Bool) ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: terminalAuthModeKey)
            syncPassthroughAuthFlag()
        }
    }

    /// Sync file flag to match UserDefaults (called on toggle and on launch)
    static func syncPassthroughAuthFlag() {
        let fm = FileManager.default
        if isTerminalAuthMode {
            fm.createFile(atPath: passthroughAuthFlagPath, contents: nil)
        } else {
            try? fm.removeItem(atPath: passthroughAuthFlagPath)
        }
    }

    private func handleChatter(conn: NWConnection, body: Data?) {
        sendJSON(conn, status: 200, body: StatusResponse(status: "received"))

        guard petWindow?.isVisible == true else { return }
        guard Self.isChatterEnabled else { return }

        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty else {
            return
        }

        petWindow?.petView.showChatter(text: message)
    }

    // MARK: - HTTP Response

    private static let jsonEncoder = JSONEncoder()

    private func sendJSON<T: Encodable>(_ conn: NWConnection, status: Int, body: T) {
        let bodyData = (try? Self.jsonEncoder.encode(body)) ?? Data("{}".utf8)
        sendRawData(conn, status: status, bodyData: bodyData)
    }

    private func sendRawData(_ conn: NWConnection, status: Int, bodyData: Data) {
        let resp = CFHTTPMessageCreateResponse(nil, CFIndex(status), nil, kCFHTTPVersion1_1).takeRetainedValue()
        CFHTTPMessageSetHeaderFieldValue(resp, "Content-Type" as CFString, "application/json; charset=utf-8" as CFString)
        CFHTTPMessageSetHeaderFieldValue(resp, "Content-Length" as CFString, "\(bodyData.count)" as CFString)
        CFHTTPMessageSetHeaderFieldValue(resp, "Connection" as CFString, "close" as CFString)
        CFHTTPMessageSetBody(resp, bodyData as CFData)

        guard let wireData = CFHTTPMessageCopySerializedMessage(resp)?.takeRetainedValue() as Data? else {
            conn.cancel()
            return
        }

        conn.send(content: wireData, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}

// MARK: - Response Types (Codable, prevents JSON injection via string interpolation)

private struct HealthResponse: Encodable {
    let status = "ok"
    let version: String
    let persona: String
    let activeSessions: Int
    let chatterEnabled: Bool
    let terminalAuthMode: Bool
}

private struct StatusResponse: Encodable { let status: String }
private struct ErrorResponse: Encodable { let error: String }

private struct AuthDecisionResponse: Encodable {
    let decision: String
    var tool: String?
    var reason: String?
}
