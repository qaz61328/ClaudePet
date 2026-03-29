import AppKit

// MARK: - Click-Through Window

/// Window that allows click-through on transparent areas
class ClickThroughWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - Pet Window

@MainActor
class PetWindow {
    private static let posXKey = "petWindowOriginX"
    private static let posYKey = "petWindowOriginY"

    let window: ClickThroughWindow
    let petView: PetView

    init() {
        let size = NSSize(width: 320, height: 380) // Character + bubble space (incl. 3-button auth bubble, 8 lines of text)
        let origin = PetWindow.savedOrigin() ?? PetWindow.defaultOrigin(size: size)
        let frame = NSRect(origin: origin, size: size)

        window = ClickThroughWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true

        petView = PetView()
        window.contentView = petView

        // Observe window movement, persist position
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.savePosition()
            }
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    var isVisible: Bool {
        window.isVisible
    }

    func toggleVisibility() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - Position Persistence

    private func savePosition() {
        let origin = window.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: PetWindow.posXKey)
        UserDefaults.standard.set(Double(origin.y), forKey: PetWindow.posYKey)
    }

    private static func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: posXKey) != nil else { return nil }
        let x = defaults.double(forKey: posXKey)
        let y = defaults.double(forKey: posYKey)
        let point = NSPoint(x: x, y: y)

        // Ensure point is within a visible screen
        for screen in NSScreen.screens {
            if screen.visibleFrame.contains(point) {
                return point
            }
        }
        return nil
    }

    private static func defaultOrigin(size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        let visibleFrame = screen.visibleFrame
        return NSPoint(
            x: visibleFrame.maxX - size.width - 20,
            y: visibleFrame.minY + 20
        )
    }
}
