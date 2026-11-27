//
//  DecadeMiniWindow.swift
//  J2MEEmulator
//
//  Created for Vạn Trần idol J2me NSV IOS
//  Resizable and draggable floating mini-window ("cửa sổ màn hình nhỏ kéo to nhỏ tuỳ ý").
//

import UIKit

final class DecadeMiniWindow: UIView, UIGestureRecognizerDelegate {
    static let shared = DecadeMiniWindow()

    // Callbacks
    var onTogglePiP: (() -> Void)?
    var onSwitchTab: (() -> Void)?
    var onRestoreFullScreen: (() -> Void)?
    var onShowMenu: (() -> Void)?
    var onMinimizeToBubble: (() -> Void)?

    // UI Elements
    private let blurBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let headerBar = UIView()
    private let titleLabel = UILabel()
    private let canvasImageView = UIImageView()
    private let resizeHandle = UIView()
    private let gripIcon = UILabel()

    // Gestures
    private var panStartOrigin: CGPoint = .zero
    private var resizeStartBounds: CGRect = .zero
    private var initialPinchSize: CGSize = .zero

    private var currentTabNumber: Int = 1
    private var minWidth: CGFloat = 160
    private var minHeight: CGFloat = 120

    private init() {
        let initialW: CGFloat = 240
        let initialH: CGFloat = 180
        super.init(frame: CGRect(x: 20, y: 120, width: initialW, height: initialH))
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .clear
        layer.cornerRadius = 16
        layer.masksToBounds = false
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(red: 0.12, green: 0.53, blue: 0.90, alpha: 0.9).cgColor

        // Shadow for floating elevation
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 6)

        // Frosted Blur background
        blurBackground.layer.cornerRadius = 16
        blurBackground.layer.masksToBounds = true
        blurBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurBackground)

        // 1. Header Bar
        headerBar.backgroundColor = UIColor(white: 0.08, alpha: 0.85)
        headerBar.layer.cornerRadius = 16
        headerBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        titleLabel.text = "🎮 Vạn Trần - Tab 1"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(minimizeTapped)))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(titleLabel)

        // Header Buttons: 📺 (PiP outside), 🔄 (Switch tab), ✕ (Close)
        let btnStack = UIStackView()
        btnStack.axis = .horizontal
        btnStack.spacing = 6
        btnStack.alignment = .center
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(btnStack)

        let pipBtn = UIButton(type: .system)
        pipBtn.setTitle("📺", for: .normal)
        pipBtn.titleLabel?.font = .systemFont(ofSize: 12)
        pipBtn.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        btnStack.addArrangedSubview(pipBtn)

        let tabBtn = UIButton(type: .system)
        tabBtn.setTitle("🔄", for: .normal)
        tabBtn.titleLabel?.font = .systemFont(ofSize: 12)
        tabBtn.addTarget(self, action: #selector(tabTapped), for: .touchUpInside)
        btnStack.addArrangedSubview(tabBtn)

        let menuBtn = UIButton(type: .system)
        menuBtn.setTitle("⚙", for: .normal)
        menuBtn.titleLabel?.font = .systemFont(ofSize: 12)
        menuBtn.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        btnStack.addArrangedSubview(menuBtn)

        let bubbleBtn = UIButton(type: .system)
        bubbleBtn.setTitle("💬", for: .normal)
        bubbleBtn.titleLabel?.font = .systemFont(ofSize: 12)
        bubbleBtn.addTarget(self, action: #selector(minimizeTapped), for: .touchUpInside)
        btnStack.addArrangedSubview(bubbleBtn)

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        btnStack.addArrangedSubview(closeBtn)

        // 2. Canvas Image View
        canvasImageView.backgroundColor = .black
        canvasImageView.contentMode = .scaleAspectFit
        canvasImageView.layer.magnificationFilter = .nearest
        canvasImageView.layer.minificationFilter = .nearest
        canvasImageView.layer.cornerRadius = 8
        canvasImageView.layer.masksToBounds = true
        canvasImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasImageView)

        // 3. Resize Grip Handle at bottom-right corner
        resizeHandle.backgroundColor = UIColor(white: 0.2, alpha: 0.6)
        resizeHandle.layer.cornerRadius = 10
        resizeHandle.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMaxYCorner]
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeHandle)

        gripIcon.text = "◢"
        gripIcon.textColor = UIColor(red: 0.20, green: 0.65, blue: 1.0, alpha: 0.9)
        gripIcon.font = .systemFont(ofSize: 13, weight: .bold)
        gripIcon.textAlignment = .center
        gripIcon.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.addSubview(gripIcon)

        NSLayoutConstraint.activate([
            blurBackground.topAnchor.constraint(equalTo: topAnchor),
            blurBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: btnStack.leadingAnchor, constant: -4),

            btnStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -6),
            btnStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            canvasImageView.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 2),
            canvasImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            canvasImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            canvasImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 26),
            resizeHandle.heightAnchor.constraint(equalToConstant: 26),

            gripIcon.centerXAnchor.constraint(equalTo: resizeHandle.centerXAnchor),
            gripIcon.centerYAnchor.constraint(equalTo: resizeHandle.centerYAnchor),
        ])

        // Gestures
        // 1. Move Window Gesture (Pan on header / body)
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        movePan.delegate = self
        addGestureRecognizer(movePan)

        // 2. Resize Corner Drag Gesture
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        resizeHandle.addGestureRecognizer(resizePan)

        // 3. Pinch to Resize Gesture (kéo to nhỏ bằng 2 ngón tay)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        // 4. Double tap to toggle size (nhấn 2 lần đổi nhanh cỡ to / nhỏ)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    func setTabInfo(tabNumber: Int) {
        self.currentTabNumber = tabNumber
        self.titleLabel.text = "🎮 Vạn Trần - Tab \(tabNumber)"
    }

    func updateFrame(_ cgImage: CGImage) {
        guard superview != nil, !isHidden else { return }
        DispatchQueue.main.async { [weak self] in
            self?.canvasImageView.layer.contents = cgImage
        }
    }

    func show(in window: UIWindow?) {
        guard let window = window else { return }
        if superview == nil {
            let screen = window.bounds
            let initialW: CGFloat = 240
            let initialH: CGFloat = 180
            frame = CGRect(x: screen.width - initialW - 16, y: 110, width: initialW, height: initialH)
            alpha = 0.0
            transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            window.addSubview(self)
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
                self.alpha = 1.0
                self.transform = .identity
            })
        }
        window.bringSubviewToFront(self)
        isHidden = false
    }

    func hide() {
        guard superview != nil else { return }
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0.0
            self.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        }) { _ in
            self.removeFromSuperview()
            self.transform = .identity
            self.alpha = 1.0
            self.isHidden = true
        }
    }

    func toggle(in window: UIWindow?) {
        if superview != nil && !isHidden {
            hide()
        } else {
            show(in: window)
        }
    }

    // MARK: - Actions
    @objc private func pipTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onTogglePiP?()
    }

    @objc private func tabTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSwitchTab?()
    }

    @objc private func menuTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onShowMenu?()
    }

    @objc private func minimizeTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let onMin = onMinimizeToBubble {
            onMin()
        } else {
            hide()
        }
    }

    @objc private func closeTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let onMin = onMinimizeToBubble {
            onMin()
        } else {
            hide()
        }
    }

    // MARK: - Gestures
    @objc private func handleMovePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = superview else { return }
        let translation = gesture.translation(in: window)

        switch gesture.state {
        case .began:
            panStartOrigin = frame.origin
        case .changed:
            let newX = panStartOrigin.x + translation.x
            let newY = panStartOrigin.y + translation.y
            frame.origin = CGPoint(x: newX, y: newY)
        case .ended, .cancelled:
            clampInsideScreen(window: window)
        default:
            break
        }
    }

    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = superview else { return }
        let translation = gesture.translation(in: window)

        switch gesture.state {
        case .began:
            resizeStartBounds = frame
        case .changed:
            let screen = window.bounds
            let maxW = screen.width - 20
            let maxH = screen.height - 100

            let newW = max(minWidth, min(maxW, resizeStartBounds.width + translation.x))
            let newH = max(minHeight, min(maxH, resizeStartBounds.height + translation.y))
            frame = CGRect(x: frame.origin.x, y: frame.origin.y, width: newW, height: newH)
        case .ended, .cancelled:
            clampInsideScreen(window: window)
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let window = superview else { return }
        switch gesture.state {
        case .began:
            initialPinchSize = frame.size
        case .changed:
            let scale = gesture.scale
            let screen = window.bounds
            let maxW = screen.width - 20
            let maxH = screen.height - 100

            let targetW = max(minWidth, min(maxW, initialPinchSize.width * scale))
            let targetH = max(minHeight, min(maxH, initialPinchSize.height * scale))

            let deltaW = targetW - frame.width
            let deltaH = targetH - frame.height
            frame = CGRect(
                x: frame.origin.x - deltaW / 2,
                y: frame.origin.y - deltaH / 2,
                width: targetW,
                height: targetH
            )
        case .ended, .cancelled:
            clampInsideScreen(window: window)
        default:
            break
        }
    }

    @objc private func handleDoubleTap() {
        guard let window = superview else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let isSmall = frame.width <= 200
        let targetW: CGFloat = isSmall ? 320 : 180
        let targetH: CGFloat = isSmall ? 240 : 135

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: .curveEaseInOut, animations: {
            self.frame = CGRect(x: self.frame.origin.x, y: self.frame.origin.y, width: targetW, height: targetH)
            self.clampInsideScreen(window: window)
        })
    }

    private func clampInsideScreen(window: UIView) {
        let screen = window.bounds
        let safeTop = window.safeAreaInsets.top + 10
        let safeBottom = screen.height - window.safeAreaInsets.bottom - 20

        var newX = frame.origin.x
        var newY = frame.origin.y

        if newX < 10 { newX = 10 }
        if newX + frame.width > screen.width - 10 { newX = screen.width - frame.width - 10 }
        if newY < safeTop { newY = safeTop }
        if newY + frame.height > safeBottom { newY = safeBottom - frame.height }

        UIView.animate(withDuration: 0.25) {
            self.frame.origin = CGPoint(x: newX, y: newY)
        }
    }

    // Don't intercept touches on resize handle for move pan
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view == resizeHandle || touch.view == gripIcon {
            return false
        }
        return true
    }
}
