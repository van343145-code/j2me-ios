//
//  DecadeFloatingBubble.swift
//  J2MEEmulator
//
//  Draggable AssistiveTouch-style floating bubble with quick action popup menu.
//  Appears automatically when running in background / treo tat man.
//

import UIKit

final class DecadeFloatingBubble: UIView {
    static let shared = DecadeFloatingBubble()

    var onRestoreGame: (() -> Void)?
    var onAssignProxy: (() -> Void)?
    var onToggleTreo: (() -> Void)?
    var onToggleHeadless: (() -> Void)?
    var onSelectTabPrompt: (() -> Void)?
    var onTogglePiP: (() -> Void)?
    var onToggleMiniWindow: (() -> Void)?

    private let bubbleImageView = UIImageView()
    private let badgeLabel = UILabel()
    private var panStartCenter: CGPoint = .zero
    private var gameName: String = "J2ME Game"
    private var currentTab: Int = 1

    private init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 54, height: 54))
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor(white: 0.12, alpha: 0.90)
        layer.cornerRadius = 27
        layer.borderWidth = 2.0
        layer.borderColor = UIColor(red: 0.20, green: 0.60, blue: 1.0, alpha: 0.85).cgColor

        // Shadow for prominent floating appearance
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)

        // Logo inside bubble
        bubbleImageView.contentMode = .scaleAspectFit
        bubbleImageView.clipsToBounds = true
        bubbleImageView.layer.cornerRadius = 20
        bubbleImageView.translatesAutoresizingMaskIntoConstraints = false
        if let logo = UIImage(named: "bubble_logo") {
            bubbleImageView.image = logo
        } else if let appIcon = UIImage(named: "AppIcon") {
            bubbleImageView.image = appIcon
        }
        addSubview(bubbleImageView)

        // Tab badge in bottom-right corner
        badgeLabel.backgroundColor = UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1.0)
        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 9
        badgeLabel.layer.masksToBounds = true
        badgeLabel.layer.borderWidth = 1.5
        badgeLabel.layer.borderColor = UIColor.white.cgColor
        badgeLabel.text = "1"
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            bubbleImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bubbleImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            bubbleImageView.widthAnchor.constraint(equalToConstant: 40),
            bubbleImageView.heightAnchor.constraint(equalToConstant: 40),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 2),
            badgeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 2),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])

        // Gestures
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPress)
    }

    func setGameInfo(name: String, icon: UIImage?, tabNumber: Int) {
        self.gameName = name
        self.currentTab = tabNumber
        self.badgeLabel.text = "\(tabNumber)"
        if let icon = icon {
            self.bubbleImageView.image = icon
        }
    }

    func show(in window: UIWindow?) {
        // Bubble mode disabled — using only resizable outside-Home-Screen PiP small window.
        isHidden = true
    }

    func hide() {
        guard superview != nil else { return }
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0.0
            self.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }) { _ in
            self.removeFromSuperview()
            self.transform = .identity
            self.alpha = 1.0
            self.isHidden = true
        }
    }

    func dismissAssistiveTouchMenu(animated: Bool) {
        topMostPresentedViewController?.dismiss(animated: animated)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = superview else { return }
        let translation = gesture.translation(in: window)

        switch gesture.state {
        case .began:
            panStartCenter = center
            UIView.animate(withDuration: 0.15) {
                self.alpha = 1.0
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            }
        case .changed:
            center = CGPoint(x: panStartCenter.x + translation.x, y: panStartCenter.y + translation.y)
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
                self.transform = .identity
                self.snapToClosestEdge(in: window)
            })
        default:
            break
        }
    }

    private func snapToClosestEdge(in window: UIView) {
        let screen = window.bounds
        let safeTop = window.safeAreaInsets.top + 60
        let safeBottom = screen.height - window.safeAreaInsets.bottom - 70
        let margin: CGFloat = 10

        let clampedY = max(safeTop, min(center.y, safeBottom))
        let targetX: CGFloat = (center.x < screen.midX) ? (margin + 27) : (screen.width - margin - 27)
        center = CGPoint(x: targetX, y: clampedY)
    }

    @objc private func handleTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onToggleMiniWindow?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        showActionSheetMenu()
    }

    func showActionSheetMenu() {
        guard let parentVC = self.topMostPresentedViewController else { return }

        let alert = UIAlertController(
            title: "⚡ Vạn Trần J2ME — Đang chạy nền",
            message: "\(gameName) — Tab \(currentTab)",
            preferredStyle: .actionSheet
        )

        // 1. Return to game
        alert.addAction(UIAlertAction(title: "🎮 Quay lại game / Sáng màn", style: .default) { [weak self] _ in
            self?.onRestoreGame?()
        })

        // 2. PiP outside overlay over other apps
        alert.addAction(UIAlertAction(title: "📺 Cửa sổ nổi ngoài màn hình (PiP - Đè ứng dụng khác)", style: .default) { [weak self] _ in
            self?.onTogglePiP?()
        })

        // 3. In-app resizable floating mini-window
        alert.addAction(UIAlertAction(title: "🪟 Cửa sổ màn hình nhỏ (Kéo to nhỏ tuỳ ý)", style: .default) { [weak self] _ in
            self?.onToggleMiniWindow?()
        })

        // 4. Toggle Headless / Black Screen
        alert.addAction(UIAlertAction(title: "🌙 Bật / Tắt màn đen tiết kiệm pin", style: .default) { [weak self] _ in
            self?.onToggleHeadless?()
        })

        // 5. Switch Tab
        alert.addAction(UIAlertAction(title: "📑 Chuyển Tab Midlet", style: .default) { [weak self] _ in
            self?.onSelectTabPrompt?()
        })

        // 6. Assign Proxy
        alert.addAction(UIAlertAction(title: "🌐 Cấu hình Proxy Tab", style: .default) { [weak self] _ in
            self?.onAssignProxy?()
        })

        // 7. Turn off Keepalive / Treo
        alert.addAction(UIAlertAction(title: "🛑 Tắt chạy nền (Dừng treo)", style: .destructive) { [weak self] _ in
            self?.onToggleTreo?()
        })

        alert.addAction(UIAlertAction(title: "✕ Đóng", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = self.bounds
        }

        parentVC.present(alert, animated: true)
    }
}
