import UIKit

/// Exact 1:1 port of `J2me.iOS.Ui.MicroController.KeyboardView` + `NstKeyboard` multi-touch & repeat handling.
@MainActor
final class NstKeyboardView: UIView {
    let model = NstKeyboardModel()
    var config: GameConfig = GameConfig() {
        didSet { setNeedsDisplay() }
    }

    var onKeyPress: ((Int) -> Void)?
    var onKeyRelease: ((Int) -> Void)?
    var onKeyRepeat: ((Int) -> Void)?
    var onTabAction: (() -> Void)?
    var onSizeAction: (() -> Void)?

    private var activeTouches: [ObjectIdentifier: VKey] = [:]
    private var repeatTimers: [ObjectIdentifier: Timer] = [:]
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func updateLayout(screen: CGRect, game: CGRect, tabBar: CGFloat = PlayLayout.tabBar) {
        model.layout(screen: screen, game: game, tabBar: tabBar)
        setNeedsDisplay()
    }

    func cancelAllTouches() {
        for timer in repeatTimers.values {
            timer.invalidate()
        }
        repeatTimers.removeAll()

        let keys = Array(activeTouches.values)
        activeTouches.removeAll()
        for k in keys {
            releaseKey(k, triggerAction: false)
        }
        for k in model.keys where k.pressed {
            k.pressed = false
        }
        setNeedsDisplay()
    }

    // Pass touches outside keys cleanly through to the game canvas!
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha > 0.01 else { return false }
        return model.hitTest(point) != nil
    }

    // MARK: - CoreGraphics Drawing (1:1 port of `KeyboardView.Draw`)

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)

        let gap = model.keyGap
        for key in model.keys where key.visible {
            let alphaByte: Int
            if !model.keyObscuresGame(key) || config.vkForceOpacity {
                alphaByte = 255
            } else {
                alphaByte = config.vkAlpha
            }

            let drawRect = key.rect.insetBy(dx: gap, dy: gap)
            guard drawRect.width > 2, drawRect.height > 2 else { continue }

            let corner = model.corner(for: key)
            let path = UIBezierPath(roundedRect: drawRect, cornerRadius: corner)

            let bgHex = key.pressed ? config.vkBgColorSelected : config.vkBgColor
            UIColor.argb(rgb: bgHex, alphaByte: alphaByte).setFill()
            path.fill()

            UIColor.argb(rgb: config.vkOutlineColor, alphaByte: alphaByte).setStroke()
            path.lineWidth = 1.0
            path.stroke()

            let fontSize = max(10.0, min(drawRect.width, drawRect.height) * 0.34)
            let fgHex = key.pressed ? config.vkFgColorSelected : config.vkFgColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.argb(rgb: fgHex, alphaByte: alphaByte),
            ]
            let label = key.label as NSString
            let textSize = label.size(withAttributes: attrs)
            let textRect = CGRect(
                x: drawRect.midX - textSize.width * 0.5,
                y: drawRect.midY - textSize.height * 0.5,
                width: textSize.width,
                height: textSize.height
            )
            label.draw(in: textRect, withAttributes: attrs)
        }
    }

    // MARK: - Multi-Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for touch in touches {
            let pt = touch.location(in: self)
            guard let key = model.hitTest(pt) else { continue }
            let id = ObjectIdentifier(touch)
            activeTouches[id] = key
            pressKey(key, touchId: id)
            changed = true
        }
        if changed { setNeedsDisplay() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let pt = touch.location(in: self)
            let newKey = model.hitTest(pt)
            let oldKey = activeTouches[id]

            if oldKey === newKey { continue }
            if let oldKey {
                stopRepeat(for: id)
                activeTouches.removeValue(forKey: id)
                if !activeTouches.values.contains(where: { $0 === oldKey }) {
                    releaseKey(oldKey, triggerAction: false)
                }
                changed = true
            }
            if let newKey {
                activeTouches[id] = newKey
                pressKey(newKey, touchId: id)
                changed = true
            }
        }
        if changed { setNeedsDisplay() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            stopRepeat(for: id)
            if let oldKey = activeTouches.removeValue(forKey: id) {
                let stillHeld = activeTouches.values.contains(where: { $0 === oldKey })
                if !stillHeld {
                    let pt = touch.location(in: self)
                    let endedInside = oldKey.rect.insetBy(dx: -8, dy: -8).contains(pt)
                    releaseKey(oldKey, triggerAction: endedInside)
                }
                changed = true
            }
        }
        if changed { setNeedsDisplay() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            stopRepeat(for: id)
            if let oldKey = activeTouches.removeValue(forKey: id) {
                if !activeTouches.values.contains(where: { $0 === oldKey }) {
                    releaseKey(oldKey, triggerAction: false)
                }
                changed = true
            }
        }
        if changed { setNeedsDisplay() }
    }

    private func pressKey(_ key: VKey, touchId: ObjectIdentifier) {
        let wasPressed = key.pressed
        key.pressed = true

        if config.vkFeedback {
            haptic.impactOccurred()
        }

        if key.action == NstKeyboardModel.actionNone && !wasPressed {
            if key.code != 0 { onKeyPress?(key.code) }
            if key.code2 != 0 { onKeyPress?(key.code2) }

            // Start repeat timer (400ms initial delay, 85ms interval matching J2ME NST)
            stopRepeat(for: touchId)
            let timer = Timer.scheduledTimer(withTimeInterval: 0.40, repeats: false) { [weak self, weak key] _ in
                Task { @MainActor [weak self, weak key] in
                    guard let self, let key, key.pressed, self.activeTouches[touchId] === key else { return }
                    self.fireRepeat(key)
                    let loop = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self, weak key] t in
                        Task { @MainActor [weak self, weak key] in
                            guard let self, let key, key.pressed, self.activeTouches[touchId] === key else {
                                t.invalidate()
                                return
                            }
                            self.fireRepeat(key)
                        }
                    }
                    self.repeatTimers[touchId] = loop
                }
            }
            repeatTimers[touchId] = timer
        }
    }

    private func fireRepeat(_ key: VKey) {
        if key.code != 0 { onKeyRepeat?(key.code) }
        if key.code2 != 0 { onKeyRepeat?(key.code2) }
    }

    private func releaseKey(_ key: VKey, triggerAction: Bool) {
        let wasPressed = key.pressed
        key.pressed = false

        if key.action == NstKeyboardModel.actionNone {
            if wasPressed {
                if key.code != 0 { onKeyRelease?(key.code) }
                if key.code2 != 0 { onKeyRelease?(key.code2) }
            }
        } else if triggerAction {
            switch key.action {
            case NstKeyboardModel.actionTab:
                onTabAction?()
            case NstKeyboardModel.actionSize:
                onSizeAction?()
            default:
                break
            }
        }
    }

    private func stopRepeat(for id: ObjectIdentifier) {
        repeatTimers.removeValue(forKey: id)?.invalidate()
    }
}
