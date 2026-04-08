import AppKit

// MARK: - Animation State

enum AnimationState {
    case idle
    case bow
    case talking
    case alert
    case happy
    case working
}

// MARK: - Pet View

class PetView: NSView {
    // MARK: - State

    private(set) var animationState: AnimationState = .idle
    private var frameIndex: Int = 0
    private var animationTimer: Timer?
    private var speechTimer: Timer?
    private var authDismissTimer: Timer?

    private var sprites: [String: NSImage] = [:]
    private var frameCounts: [String: Int] = [:]

    private var speechBubble: SpeechBubbleView?
    private var authBubble: AuthBubbleView?
    private var personaObserver: Any?

    /// Cached auth content and callback after bubble dismissal (re-shown when character is clicked)
    private var pendingAuth: (text: String, buttonLabels: AuthButtonLabels, onDecision: (AuthDecision) -> Void)?

    /// Whether any session is actively working (controlled by PetServer via startWorking/stopWorking)
    private(set) var isWorking = false

    /// Drag tracking: screen-space mouse position at mouseDown
    private var dragStartScreenPos: NSPoint?
    /// Drag tracking: window origin at mouseDown
    private var dragStartWindowOrigin: NSPoint?
    /// Whether a drag gesture was detected (distinguishes drag from click)
    private var didDrag = false
    /// Minimum distance to count as a drag instead of a click
    private let dragThreshold: CGFloat = 3

    // MARK: - Constants

    private let spriteDisplaySize: CGFloat = 96
    private let spriteYOffset: CGFloat = 0
    private let bubbleGap: CGFloat = 4
    private let speechBubbleWidth: CGFloat = 280
    private let authBubbleWidth: CGFloat = 300
    private let bubbleShadowMargin: CGFloat = 20

    // MARK: - State

    /// Original window width before auth bubble expansion
    private var savedWindowWidth: CGFloat?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        loadSprites()
        startIdleAnimation()

        personaObserver = NotificationCenter.default.addObserver(
            forName: .personaDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSprites()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
        speechTimer?.invalidate()
        authDismissTimer?.invalidate()
        if let observer = personaObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Sprite Loading

    private func loadSprites() {
        sprites.removeAll()

        if let personaSprites = PersonaDirectory.loadSprites(for: DialogueBank.current.id),
           !personaSprites.isEmpty {
            sprites = personaSprites
        } else {
            // Bundle fallback (built-in default sprites)
            let bundleSprites = PersonaDirectory.loadBundleSprites()
            if !bundleSprites.isEmpty {
                sprites = bundleSprites
            } else {
                generatePlaceholderSprites()
            }
        }

        computeFrameCounts()
    }

    /// Compute frame count per state from loaded sprites
    private func computeFrameCounts() {
        frameCounts.removeAll()
        for state in PersonaDirectory.spriteStates {
            let prefix = "\(state)_"
            let count = sprites.keys.filter { $0.hasPrefix(prefix) }.count
            frameCounts[state] = max(count, 1)
        }
    }

    func reloadSprites() {
        loadSprites()
        needsDisplay = true
    }

    private func generatePlaceholderSprites() {
        let size = NSSize(width: 32, height: 32)

        func makeSprite(bodyColor: NSColor, headOffset: CGFloat = 0) -> NSImage {
            let image = NSImage(size: size)
            image.lockFocus()

            // Body (tailcoat)
            bodyColor.setFill()
            NSBezierPath(rect: NSRect(x: 8, y: 2, width: 16, height: 14)).fill()

            // Shirt
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 12, y: 6, width: 8, height: 10)).fill()

            // Bow tie
            NSColor.red.setFill()
            NSBezierPath(rect: NSRect(x: 13, y: 14, width: 6, height: 2)).fill()

            // Head
            NSColor(red: 0.96, green: 0.8, blue: 0.68, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 9, y: 16 + headOffset, width: 14, height: 14)).fill()

            // Hair
            NSColor.black.setFill()
            NSBezierPath(rect: NSRect(x: 9, y: 26 + headOffset, width: 14, height: 4)).fill()

            // Eyes
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12, y: 21 + headOffset, width: 3, height: 3)).fill()
            NSBezierPath(ovalIn: NSRect(x: 19, y: 21 + headOffset, width: 3, height: 3)).fill()

            image.unlockFocus()
            return image
        }

        // idle: two frames with slight movement
        sprites["idle_1"] = makeSprite(bodyColor: .black)
        sprites["idle_2"] = makeSprite(bodyColor: .black, headOffset: 1)

        // bow: darker color to indicate bowing (simplified placeholder)
        sprites["bow_1"] = makeSprite(bodyColor: NSColor(white: 0.15, alpha: 1))
        sprites["bow_2"] = makeSprite(bodyColor: NSColor(white: 0.2, alpha: 1))

        // alert: slightly brighter color to distinguish
        sprites["alert_1"] = makeSprite(bodyColor: NSColor(white: 0.1, alpha: 1), headOffset: 1)
        sprites["alert_2"] = makeSprite(bodyColor: NSColor(white: 0.1, alpha: 1), headOffset: 2)

        // happy: jumping up
        sprites["happy_1"] = makeSprite(bodyColor: .black, headOffset: 3)
        sprites["happy_2"] = makeSprite(bodyColor: .black, headOffset: 1)

        // working: slight lean forward (typing), 4 frames + dots appearing above head
        let workingColor = NSColor(white: 0.05, alpha: 1)
        for (i, dots) in [[1], [1, 2], [1, 2, 3], [Int]()].enumerated() {
            let frame = makeSprite(bodyColor: workingColor, headOffset: i % 2 == 1 ? -1 : 0)
            frame.lockFocus()
            NSColor.white.setFill()
            for dot in dots {
                let dx: CGFloat = CGFloat(dot - 2) * 5
                NSBezierPath(rect: NSRect(x: 14 + dx, y: 30, width: 2, height: 2)).fill()
            }
            frame.unlockFocus()
            sprites["working_\(i + 1)"] = frame
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Fully transparent background
        NSColor.clear.set()
        dirtyRect.fill()

        let key = "\(currentStatePrefix)_\(frameIndex + 1)"
        guard let sprite = sprites[key] else { return }

        // Pixel-art rendering: disable interpolation
        let context = NSGraphicsContext.current
        let prevInterpolation = context?.imageInterpolation
        context?.imageInterpolation = .none

        let drawRect = NSRect(
            x: (bounds.width - spriteDisplaySize) / 2,
            y: spriteYOffset,
            width: spriteDisplaySize,
            height: spriteDisplaySize
        )
        sprite.draw(in: drawRect)

        context?.imageInterpolation = prevInterpolation ?? .default
    }

    // MARK: - Hit Test

    override func hitTest(_ point: NSPoint) -> NSView? {
        // hitTest point is in superview coordinates
        // Convert to self's coordinate system
        let local = convert(point, from: superview)

        // Auth bubble takes priority (buttons must be clickable)
        if let auth = authBubble, auth.frame.contains(local) {
            // Pass self's coordinates (= auth's superview coordinates) to auth.hitTest
            if let hit = auth.hitTest(local) { return hit }
        }
        // Character area
        let spriteRect = NSRect(
            x: (bounds.width - spriteDisplaySize) / 2,
            y: spriteYOffset,
            width: spriteDisplaySize,
            height: spriteDisplaySize
        )
        if spriteRect.contains(local) { return self }
        return nil
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // Record drag start position (screen coordinates)
        dragStartScreenPos = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startScreen = dragStartScreenPos,
              let startOrigin = dragStartWindowOrigin else { return }
        let currentScreen = NSEvent.mouseLocation
        let dx = currentScreen.x - startScreen.x
        let dy = currentScreen.y - startScreen.y
        if !didDrag && (dx * dx + dy * dy) < dragThreshold * dragThreshold { return }
        didDrag = true
        let newOrigin = NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
        window?.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartScreenPos = nil
            dragStartWindowOrigin = nil
            didDrag = false
        }
        // If it was a drag, no click action
        if didDrag { return }

        // Auth bubble dismissed but request still pending — click character to re-show
        if animationState == .alert, authBubble == nil, let pending = pendingAuth {
            showAuthBubble(text: pending.text, buttonLabels: pending.buttonLabels, onDecision: pending.onDecision)
            scheduleAuthBubbleDismiss()
            return
        }

        // Don't handle clicks during auth bubble or short animations (idle/working/talking are clickable)
        guard animationState == .idle || animationState == .working || animationState == .talking else { return }

        // If a speech bubble is showing, dismiss it first (timer cleaned up by subsequent transitionTo)
        if animationState == .talking || animationState == .working {
            dismissSpeechBubble()
        }

        // Try to switch to terminal
        let didSwitch = TerminalActivator.activate()
        let text = didSwitch ? DialogueBank.switchToTerminal() : DialogueBank.clicked()

        transitionTo(.bow)
        scheduleStateTransition(to: .talking, after: 0.5) { [weak self] in
            self?.showSpeechBubble(text: text)
            self?.scheduleStateTransition(to: self?.restingState ?? .idle, after: 3.0) { [weak self] in
                self?.dismissSpeechBubble()
            }
        }
    }

    // MARK: - Animation

    /// Sprite state prefix for the current animation state
    private var currentStatePrefix: String {
        switch animationState {
        case .idle, .talking: return "idle"
        case .bow:     return "bow"
        case .alert:   return "alert"
        case .happy:   return "happy"
        case .working: return "working"
        }
    }

    /// Resting state when no events: .working if a session is active, otherwise .idle
    private var restingState: AnimationState {
        isWorking ? .working : .idle
    }

    /// Called by PetServer: a session started working
    func startWorking() {
        isWorking = true
        if animationState == .idle { transitionTo(.working) }
    }

    /// Called by PetServer: all sessions have stopped
    func stopWorking() {
        isWorking = false
        if animationState == .working { transitionTo(.idle) }
    }

    private func startIdleAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let count = self.frameCounts[self.currentStatePrefix] ?? 2
            self.frameIndex = (self.frameIndex + 1) % count
            self.needsDisplay = true
        }
    }

    // MARK: - State Transitions

    private func transitionTo(_ newState: AnimationState) {
        guard newState != animationState else { return }
        speechTimer?.invalidate()
        speechTimer = nil
        animationState = newState
        frameIndex = 0
        needsDisplay = true
    }

    private func scheduleStateTransition(to state: AnimationState, after interval: TimeInterval, then: (() -> Void)? = nil) {
        speechTimer?.invalidate()
        speechTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.transitionTo(state)
            then?()
        }
    }

    // MARK: - Notify (from server)

    func showNotification(payload: NotifyPayload, sound: SoundEvent = .notify) {
        // Auth bubble or pending auth takes priority — silently discard notification
        guard authBubble == nil && pendingAuth == nil else { return }

        let text: String
        let style: BubbleStyle
        var effectiveSound = sound
        if let message = payload.message {
            text = message
            style = .normal
        } else if payload.type == "ask" {
            text = DialogueBank.needsAttention(project: payload.project)
            style = .attention
            effectiveSound = .authorize
        } else if payload.type == "plan" {
            text = DialogueBank.planReady(project: payload.project)
            style = .plan
        } else {
            text = DialogueBank.taskComplete(project: payload.project)
            style = .normal
        }
        SoundPlayer.play(effectiveSound)
        showTemporaryBubble(text: text, state: .talking, duration: 4.0, style: style)
    }

    // MARK: - Chatter (idle chatter, no sound, low priority)

    /// Chatter bubble: no sound effect, TTS if enabled, silently discarded if not idle/working or a bubble is showing
    func showChatter(text: String) {
        guard (animationState == .idle || animationState == .working),
              authBubble == nil, speechBubble == nil,
              pendingAuth == nil else { return }
        TTSPlayer.speak(text: text)
        showTemporaryBubble(text: text, state: .talking, duration: 3.5)
    }

    /// Show bubble, auto-dismiss after duration and return to restingState (working or idle)
    private func showTemporaryBubble(text: String, state: AnimationState, duration: TimeInterval, style: BubbleStyle = .normal) {
        transitionTo(state)
        showSpeechBubble(text: text, style: style)
        scheduleStateTransition(to: restingState, after: duration) { [weak self] in
            self?.dismissSpeechBubble()
        }
    }

    // MARK: - Authorize (from server)

    func showAuthorization(payload: AuthorizePayload, completion: @escaping (AuthDecision) -> Void) {
        let text = DialogueBank.authorizeRequest(payload: payload)
        let buttonLabels = DialogueBank.authButtonLabels
        transitionTo(.alert)

        let onDecision: (AuthDecision) -> Void = { [weak self] decision in
            guard let self else { return }
            self.pendingAuth = nil
            self.cancelAuthDismissTimer()
            self.dismissAuthBubble()

            switch decision {
            case .approve, .approveSession:
                self.showTemporaryBubble(text: DialogueBank.authorized(), state: .happy, duration: 1.5)
            case .deny:
                self.showTemporaryBubble(text: DialogueBank.denied(), state: .idle, duration: 2.0)
            }

            completion(decision)
        }

        pendingAuth = (text: text, buttonLabels: buttonLabels, onDecision: onDecision)
        showAuthBubble(text: text, buttonLabels: buttonLabels, onDecision: onDecision)

        // Dismiss bubble after 60s but keep alert state (request preserved, click character to re-show)
        scheduleAuthBubbleDismiss()
    }

    /// Whether an authorization request is pending (for global hotkey guard)
    var hasPendingAuth: Bool { pendingAuth != nil }

    /// Trigger an auth decision programmatically (from global hotkey)
    func invokeAuthDecision(_ decision: AuthDecision) {
        guard let pending = pendingAuth else { return }
        pendingAuth = nil  // Prevent re-entry from concurrent hotkey + button click
        pending.onDecision(decision)
    }

    func cancelPendingAuthorization() {
        pendingAuth = nil
        cancelAuthDismissTimer()
        dismissAuthBubble()
        transitionTo(restingState)
    }

    private func cancelAuthDismissTimer() {
        authDismissTimer?.invalidate()
        authDismissTimer = nil
    }

    private func scheduleAuthBubbleDismiss() {
        cancelAuthDismissTimer()
        authDismissTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            self?.dismissAuthBubble()
        }
    }

    // MARK: - Speech Bubble

    private func showSpeechBubble(text: String, style: BubbleStyle = .normal) {
        dismissSpeechBubble(animated: false)
        removeStale(SpeechBubbleView.self)
        let bubble = SpeechBubbleView(text: text, style: style)
        let width = bubble.fittingWidth(maxWidth: speechBubbleWidth)
        positionBubble(bubble, width: width)
        addSubview(bubble)
        speechBubble = bubble
        fadeIn(bubble)
    }

    private func dismissSpeechBubble(animated: Bool = true) {
        dismissBubble(&speechBubble, animated: animated)
    }

    // MARK: - Auth Bubble

    private func showAuthBubble(text: String, buttonLabels: AuthButtonLabels, onDecision: @escaping (AuthDecision) -> Void) {
        dismissAuthBubble(animated: false)
        dismissSpeechBubble(animated: false)
        removeStale(AuthBubbleView.self)
        let bubble = AuthBubbleView(text: text, buttonLabels: buttonLabels, onDecision: onDecision)
        let width = bubble.fittingWidth(maxWidth: authBubbleWidth)

        let neededWidth = width + bubbleShadowMargin * 2
        if let win = window, neededWidth > win.frame.width {
            savedWindowWidth = win.frame.width
            let delta = neededWidth - win.frame.width
            var newFrame = win.frame
            newFrame.origin.x -= delta / 2
            newFrame.size.width += delta
            win.setFrame(newFrame, display: false)
        }

        positionBubble(bubble, width: width)
        addSubview(bubble)
        authBubble = bubble
        fadeIn(bubble)
        SoundPlayer.play(.authorize)
        window?.makeKeyAndOrderFront(nil)
    }

    private func dismissAuthBubble(animated: Bool = true) {
        dismissBubble(&authBubble, animated: animated)
        if let original = savedWindowWidth, let win = window {
            let delta = win.frame.width - original
            var newFrame = win.frame
            newFrame.origin.x += delta / 2
            newFrame.size.width = original
            win.setFrame(newFrame, display: false)
            savedWindowWidth = nil
        }
    }

    // MARK: - Bubble Helpers

    private func positionBubble(_ bubble: NSView & BubbleSizable, width: CGFloat) {
        let height = bubble.fittingHeight(forWidth: width)
        bubble.frame = NSRect(
            x: (bounds.width - width) / 2,
            y: spriteYOffset + spriteDisplaySize + bubbleGap,
            width: width,
            height: height
        )
    }

    private func dismissBubble<T: NSView>(_ ref: inout T?, animated: Bool) {
        guard let view = ref else { return }
        ref = nil
        if animated { fadeOut(view) } else { view.removeFromSuperview() }
    }

    /// Remove stale bubbles still in fade-out animation (race condition guard)
    private func removeStale<T: NSView>(_ type: T.Type) {
        subviews.filter { $0 is T }.forEach { $0.removeFromSuperview() }
    }

    // MARK: - Bubble Animation

    private static let springTiming = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)

    private func fadeIn(_ view: NSView) {
        view.alphaValue = 0
        let originalY = view.frame.origin.y
        view.frame.origin.y = originalY - 8
        view.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.95, y: 0.95))

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = Self.springTiming
            ctx.allowsImplicitAnimation = true
            view.animator().alphaValue = 1
            view.animator().frame.origin.y = originalY
            view.layer?.setAffineTransform(.identity)
        }
    }

    private func fadeOut(_ view: NSView) {
        let targetY = view.frame.origin.y - 4
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            view.animator().alphaValue = 0
            view.animator().frame.origin.y = targetY
        }, completionHandler: {
            view.removeFromSuperview()
        })
    }
}
