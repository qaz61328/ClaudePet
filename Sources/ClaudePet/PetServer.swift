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
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .main)
        receiveHTTPRequest(conn) { [weak self] method, path, body in
            guard let self else { conn.cancel(); return }
            self.route(conn: conn, method: method, path: path, body: body)
        }
    }

    private func receiveHTTPRequest(_ conn: NWConnection, completion: @escaping @MainActor (String, String, Data?) -> Void) {
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
                        Task { @MainActor in
                            completion(method, path, bodyData)
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

    private func route(conn: NWConnection, method: String, path: String, body: Data?) {
        switch (method, path) {
        case ("GET", "/health"):
            let personaID = DialogueBank.current.id
            let sessionCount = activeSessions.count
            let chatterOn = Self.isChatterEnabled
            let termAuth = Self.isTerminalAuthMode
            sendResponse(conn, status: 200, body: #"{"status":"ok","version":"\#(PersonaDirectory.appVersion)","persona":"\#(personaID)","activeSessions":\#(sessionCount),"chatterEnabled":\#(chatterOn),"terminalAuthMode":\#(termAuth)}"#)

        case ("POST", "/notify"):
            handleNotify(conn: conn, body: body)

        case ("POST", "/authorize"):
            handleAuthorize(conn: conn, body: body)

        case ("POST", "/chatter"):
            handleChatter(conn: conn, body: body)

        case ("POST", "/working"):
            handleWorking(conn: conn, body: body)

        default:
            sendResponse(conn, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - /notify

    private func handleNotify(conn: NWConnection, body: Data?) {
        sendResponse(conn, status: 200, body: #"{"status":"received"}"#)

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
            sendResponse(conn, status: 503, body: #"{"error":"pet hidden"}"#)
            return
        }

        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            sendResponse(conn, status: 400, body: #"{"error":"invalid body"}"#)
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
            // Prevent sendResponse → conn.cancel() from triggering cancelPendingAuthorization() killing the response bubble timer
            self.pendingAuthConn?.stateUpdateHandler = nil

            if let c = self.pendingAuthConn {
                let tool = payload.tool
                let responseBody: String
                switch decision {
                case .approve:
                    responseBody = #"{"decision":"approve"}"#
                case .approveSession:
                    responseBody = #"{"decision":"approve_session","tool":"\#(tool)"}"#
                case .deny:
                    responseBody = #"{"decision":"deny","reason":"User denied"}"#
                }
                self.sendResponse(c, status: 200, body: responseBody)
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
        sendResponse(conn, status: 200, body: #"{"status":"received"}"#)

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
            (UserDefaults.standard.object(forKey: chatterEnabledKey) as? Bool) ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: chatterEnabledKey) }
    }

    // MARK: - Authorization Mode

    private static let terminalAuthModeKey = "terminalAuthMode"
    static let passthroughAuthFlagPath = "/tmp/claudepet-passthrough-auth"

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
        sendResponse(conn, status: 200, body: #"{"status":"received"}"#)

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

    private func sendResponse(_ conn: NWConnection, status: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
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
