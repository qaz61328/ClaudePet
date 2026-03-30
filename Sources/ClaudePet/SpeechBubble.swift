import AppKit
import QuartzCore

// MARK: - BubbleSizable Protocol

protocol BubbleSizable {
    func fittingHeight(forWidth width: CGFloat) -> CGFloat
}

// MARK: - Bubble Style

enum BubbleStyle {
    case normal      // Regular notification — dark
    case attention   // needsAttention — sky blue
    case plan        // planReady — green
    case authorize   // Authorization request — blue

    var overlayColor: NSColor {
        switch self {
        case .normal:    return NSColor(white: 0.12, alpha: 0.75)
        case .attention: return NSColor(red: 0.12, green: 0.38, blue: 0.65, alpha: 0.72)
        case .plan:      return NSColor(red: 0.08, green: 0.42, blue: 0.32, alpha: 0.72)
        case .authorize: return NSColor(white: 0.12, alpha: 0.75)
        }
    }

    var borderColor: NSColor {
        switch self {
        case .normal:    return NSColor.white.withAlphaComponent(0.15)
        case .attention: return NSColor.systemCyan.withAlphaComponent(0.5)
        case .plan:      return NSColor.systemGreen.withAlphaComponent(0.5)
        case .authorize: return NSColor.systemBlue.withAlphaComponent(0.35)
        }
    }
}

// MARK: - Shared Constants

private let bubbleFontSize: CGFloat = 14
private let buttonFontSize: CGFloat = 13
private let bubblePadding: CGFloat = 10
private let bubbleCornerRadius: CGFloat = 12
private let tailHeight: CGFloat = 8
private let tailWidth: CGFloat = 16
private let minBubbleWidth: CGFloat = 60

// MARK: - Shared Helpers

/// jf-openhuninn font, falls back to system font if not installed
private func bubbleFont(ofSize size: CGFloat) -> NSFont {
    NSFont(name: "jf-openhuninn-2.1", size: size) ?? .systemFont(ofSize: size)
}

private func makeBubbleLabel(text: String, maxLines: Int) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = bubbleFont(ofSize: bubbleFontSize)
    label.textColor = .white
    label.backgroundColor = .clear
    label.isEditable = false
    label.isSelectable = false
    label.isBezeled = false
    label.maximumNumberOfLines = maxLines
    label.lineBreakMode = .byWordWrapping
    return label
}

/// Calculate label height after wrapping for a given width and padding
private func labelFittingHeight(_ label: NSTextField, forWidth width: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
    let labelWidth = width - horizontalPadding * 2
    let rect = (label.stringValue as NSString).boundingRect(
        with: NSSize(width: labelWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: label.font!]
    )
    let maxLines = CGFloat(label.maximumNumberOfLines)
    let lineHeight = label.font!.ascender - label.font!.descender + label.font!.leading
    let maxLabelHeight = maxLines * lineHeight
    return min(ceil(rect.height), maxLabelHeight)
}

/// Create bubble shape path (rounded rect + bottom triangle tail)
private func bubbleShapePath(in rect: NSRect) -> CGPath {
    let bodyRect = NSRect(
        x: rect.minX,
        y: rect.minY + tailHeight,
        width: rect.width,
        height: rect.height - tailHeight
    )
    let path = CGMutablePath()

    path.addRoundedRect(in: bodyRect, cornerWidth: bubbleCornerRadius, cornerHeight: bubbleCornerRadius)

    let midX = bodyRect.midX
    path.move(to: CGPoint(x: midX - tailWidth / 2, y: bodyRect.minY))
    path.addLine(to: CGPoint(x: midX, y: rect.minY))
    path.addLine(to: CGPoint(x: midX + tailWidth / 2, y: bodyRect.minY))
    path.closeSubpath()

    return path
}

/// Set up shared bubble appearance: vibrancy background + tint overlay + shadow
private func setupBubbleAppearance(on view: NSView, style: BubbleStyle = .normal) -> (NSVisualEffectView, CAShapeLayer, CAShapeLayer) {
    view.wantsLayer = true

    // CALayer shadow
    view.layer?.shadowColor = NSColor.black.cgColor
    view.layer?.shadowOpacity = 0.4
    view.layer?.shadowRadius = 8
    view.layer?.shadowOffset = CGSize(width: 0, height: -2)

    let effectView = NSVisualEffectView()
    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    view.addSubview(effectView, positioned: .below, relativeTo: view.subviews.first)

    let tintLayer = CAShapeLayer()
    tintLayer.fillColor = style.overlayColor.cgColor
    effectView.layer?.addSublayer(tintLayer)

    let borderLayer = CAShapeLayer()
    borderLayer.fillColor = nil
    borderLayer.strokeColor = style.borderColor.cgColor
    borderLayer.lineWidth = 1.0
    view.layer?.addSublayer(borderLayer)

    return (effectView, tintLayer, borderLayer)
}

/// Update vibrancy view frame, mask shape, and tint layer
private func updateEffectViewMask(_ effectView: NSVisualEffectView, in bounds: NSRect, path: CGPath, tintLayer: CAShapeLayer? = nil) {
    effectView.frame = bounds
    if let maskLayer = effectView.layer?.mask as? CAShapeLayer {
        maskLayer.path = path
    } else {
        let maskLayer = CAShapeLayer()
        maskLayer.path = path
        effectView.layer?.mask = maskLayer
    }
    tintLayer?.path = path
}

/// Pill-shaped button with hover / press feedback
private class HoverPillButton: NSButton {
    private let baseColor: NSColor

    init(title: String, color: NSColor) {
        self.baseColor = color
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        font = bubbleFont(ofSize: buttonFontSize)
        contentTintColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        layer?.cornerRadius = 14
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func animateLayer(duration: TimeInterval, alpha: CGFloat, scale: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            layer?.backgroundColor = baseColor.withAlphaComponent(alpha).cgColor
            layer?.setAffineTransform(scale == 1.0 ? .identity : CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        animateLayer(duration: 0.15, alpha: 0.30, scale: 1.02)
    }

    override func mouseExited(with event: NSEvent) {
        animateLayer(duration: 0.15, alpha: 0.15, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        animateLayer(duration: 0.08, alpha: 0.40, scale: 0.95)
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(local)
        animateLayer(duration: 0.12, alpha: isInside ? 0.30 : 0.15, scale: isInside ? 1.02 : 1.0)
        if isInside {
            sendAction(action, to: target)
        }
    }
}

/// Create a pill-shaped button (with hover / press feedback)
private func makePillButton(title: String, color: NSColor) -> NSButton {
    HoverPillButton(title: title, color: color)
}

// MARK: - Speech Bubble View (Notification)

class SpeechBubbleView: NSView, BubbleSizable {
    private let label: NSTextField
    private var effectView: NSVisualEffectView?
    private var tintLayer: CAShapeLayer?
    private var styleBorderLayer: CAShapeLayer?

    init(text: String, style: BubbleStyle = .normal) {
        label = makeBubbleLabel(text: text, maxLines: 8)
        super.init(frame: .zero)

        let (ev, tl, bl) = setupBubbleAppearance(on: self, style: style)
        effectView = ev
        tintLayer = tl
        styleBorderLayer = bl
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let path = bubbleShapePath(in: bounds)
        if let ev = effectView {
            updateEffectViewMask(ev, in: bounds, path: path, tintLayer: tintLayer)
        }
        styleBorderLayer?.path = path
        let bodyY = tailHeight
        let bodyHeight = bounds.height - tailHeight
        let verticalInset: CGFloat = 10
        label.frame = NSRect(
            x: bubblePadding,
            y: bodyY + verticalInset,
            width: bounds.width - bubblePadding * 2,
            height: bodyHeight - verticalInset * 2
        )
    }

    /// Calculate fitting bubble width based on text length (narrow for short, wide for long)
    func fittingWidth(maxWidth: CGFloat) -> CGFloat {
        guard let cell = label.cell else { return maxWidth }
        let cellSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let naturalWidth = ceil(cellSize.width) + bubblePadding * 2
        return max(minBubbleWidth, min(naturalWidth, maxWidth))
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        labelFittingHeight(label, forWidth: width, horizontalPadding: bubblePadding) + 20 + tailHeight
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - Auth Bubble View (Authorization)

class AuthBubbleView: NSView, BubbleSizable {
    private static let buttonHeight: CGFloat = 28
    private static let buttonPaddingH: CGFloat = 16
    private static let minButtonWidth: CGFloat = 64
    private static let buttonSpacing: CGFloat = 8
    private static let bottomPad: CGFloat = 12
    private static let textButtonGap: CGFloat = 12

    private let label: NSTextField
    private let approveButton: NSButton
    private let approveSessionButton: NSButton
    private let denyButton: NSButton
    private let onDecision: (AuthDecision) -> Void
    private var decided = false
    private var effectView: NSVisualEffectView?
    private var tintLayer: CAShapeLayer?
    private var borderLayer: CAShapeLayer?
    /// Cached button widths (text is static, computed once)
    private let buttonWidths: (CGFloat, CGFloat, CGFloat)
    /// Minimum width needed to fit all three buttons in a row
    private let minimumWidth: CGFloat

    init(text: String, buttonLabels: AuthButtonLabels, onDecision: @escaping (AuthDecision) -> Void) {
        self.onDecision = onDecision

        label = makeBubbleLabel(text: text, maxLines: 8)

        approveButton = makePillButton(title: buttonLabels.approve, color: .systemGreen)
        approveSessionButton = makePillButton(title: buttonLabels.approveSession, color: .systemBlue)
        denyButton = makePillButton(title: buttonLabels.deny, color: .systemRed)

        let w1 = Self.fittingButtonWidth(for: approveButton)
        let w2 = Self.fittingButtonWidth(for: approveSessionButton)
        let w3 = Self.fittingButtonWidth(for: denyButton)
        buttonWidths = (w1, w2, w3)
        minimumWidth = w1 + w2 + w3 + Self.buttonSpacing * 2 + bubblePadding * 2

        super.init(frame: .zero)

        let (ev, tl, bl) = setupBubbleAppearance(on: self, style: .authorize)
        effectView = ev
        tintLayer = tl
        borderLayer = bl

        approveButton.target = self
        approveButton.action = #selector(approveClicked)
        approveSessionButton.target = self
        approveSessionButton.action = #selector(approveSessionClicked)
        denyButton.target = self
        denyButton.action = #selector(denyClicked)

        addSubview(label)
        addSubview(approveButton)
        addSubview(approveSessionButton)
        addSubview(denyButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Calculate fitting width based on button text
    private static func fittingButtonWidth(for button: NSButton) -> CGFloat {
        guard let cell = button.cell else { return minButtonWidth }
        let textWidth = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
        return max(minButtonWidth, ceil(textWidth) + buttonPaddingH * 2)
    }

    override func layout() {
        super.layout()
        let shapePath = bubbleShapePath(in: bounds)
        if let ev = effectView {
            updateEffectViewMask(ev, in: bounds, path: shapePath, tintLayer: tintLayer)
        }
        borderLayer?.path = shapePath

        let bh = Self.buttonHeight
        let buttonY = tailHeight + Self.bottomPad
        let gap = Self.textButtonGap

        label.frame = NSRect(
            x: bubblePadding,
            y: buttonY + bh + gap,
            width: bounds.width - bubblePadding * 2,
            height: bounds.height - tailHeight - bh - Self.bottomPad - gap - bubblePadding
        )

        let sp = Self.buttonSpacing
        let (w1, w2, w3) = buttonWidths
        let totalW = w1 + sp + w2 + sp + w3
        let startX = (bounds.width - totalW) / 2

        approveButton.frame = NSRect(x: startX, y: buttonY, width: w1, height: bh)
        approveSessionButton.frame = NSRect(x: startX + w1 + sp, y: buttonY, width: w2, height: bh)
        denyButton.frame = NSRect(x: startX + w1 + sp + w2 + sp, y: buttonY, width: w3, height: bh)
    }

    func fittingWidth(maxWidth: CGFloat) -> CGFloat {
        max(minimumWidth, maxWidth)
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        labelFittingHeight(label, forWidth: width, horizontalPadding: bubblePadding) + Self.buttonHeight + Self.bottomPad + Self.textButtonGap + bubblePadding + tailHeight
    }

    @objc private func approveClicked() {
        guard !decided else { return }
        decided = true
        onDecision(.approve)
    }

    @objc private func approveSessionClicked() {
        guard !decided else { return }
        decided = true
        onDecision(.approveSession)
    }

    @objc private func denyClicked() {
        guard !decided else { return }
        decided = true
        onDecision(.deny)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if approveButton.frame.contains(local) { return approveButton }
        if approveSessionButton.frame.contains(local) { return approveSessionButton }
        if denyButton.frame.contains(local) { return denyButton }
        if bounds.contains(local) { return self }
        return nil
    }
}
