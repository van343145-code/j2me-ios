//
//  TuoiThoPopupMenuView.swift
//  J2MEEmulator
//
//  Popup Menu mở từ nút 3 chấm [⋮] góc trên bên phải màn hình game.
//  Thiết kế chuẩn 1:1 theo Ảnh 1 của bản Chơi Game Tuổi Thơ.
//

import UIKit

final class TuoiThoPopupMenuView: UIView {

    var onOpenGameSettings: (() -> Void)?
    var onOpenScreenSize: (() -> Void)?
    var onOpenProxySettings: (() -> Void)?
    var onCleanRam: (() -> Void)?
    var onOpenKeyboardSettings: (() -> Void)?
    var onArrangeKeyboard: (() -> Void)?
    var onToggleKeyboardVisibility: (() -> Void)?
    var onOpenNativeKeyboard: (() -> Void)?
    var onToggleSplitView: (() -> Void)?
    var onOledSleepMode: (() -> Void)?
    var onToggleTreo247: (() -> Void)?
    var onTogglePiP: (() -> Void)?
    var onHideApp: (() -> Void)?
    var onRestartGame: (() -> Void)?
    var onBackToList: (() -> Void)?
    var onExitGame: (() -> Void)?

    private let backdropView = UIView()
    private let cardView = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var isDismissing = false

    var isKeypadHidden: Bool = false {
        didSet {
            updateHideKeypadLabel()
        }
    }

    var isTreo247Active: Bool = DecadeBackgroundKeeper.shared.isTreoActive {
        didSet {
            updateTreo247Appearance()
        }
    }

    private var hideKeypadBtn: UIButton?
    private var treo247Btn: UIButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdropView)

        let tapBackdrop = UITapGestureRecognizer(target: self, action: #selector(handleDismissTap))
        backdropView.addGestureRecognizer(tapBackdrop)

        // Card Container
        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = 16
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.16
        cardView.layer.shadowRadius = 16
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)
        cardView.layer.borderWidth = 0.5
        cardView.layer.borderColor = UIColor(white: 0.88, alpha: 1.0).cgColor
        cardView.clipsToBounds = false
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        // Scrollable container so menu never clips on compact or landscape screens
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        scrollView.layer.cornerRadius = 16
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(scrollView)

        // Stack View for Rows
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let matchContentHeight = scrollView.heightAnchor.constraint(equalTo: contentStack.heightAnchor)
        matchContentHeight.priority = .defaultLow

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -4),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            matchContentHeight,

            cardView.widthAnchor.constraint(equalToConstant: 248),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cardView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 48),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        buildMenuItems()
    }

    private func buildMenuItems() {
        // 1. Cài Đặt Game (Slider icon tím)
        let btnGameSettings = makeMenuItem(
            iconName: "slider.horizontal.3",
            iconColor: UIColor(red: 0.49, green: 0.34, blue: 0.76, alpha: 1.0), // Purple #7E57C2
            title: "Cài Đặt Game",
            action: #selector(handleGameSettings)
        )
        contentStack.addArrangedSubview(btnGameSettings)

        // 1a. Cỡ Màn Hình chuẩn NST (Size Rộng × Cao)
        let btnScreenSize = makeMenuItem(
            iconName: "aspectratio.fill",
            iconColor: UIColor(red: 0.16, green: 0.49, blue: 0.85, alpha: 1.0),
            title: "Cỡ Màn Hình (Size)",
            action: #selector(handleScreenSize)
        )
        contentStack.addArrangedSubview(btnScreenSize)

        // 1b. Proxy SOCKS5 (Shield icon xanh dương)
        let btnProxy = makeMenuItem(
            iconName: "lock.shield.fill",
            iconColor: UIColor(red: 0.10, green: 0.46, blue: 0.82, alpha: 1.0), // Blue #1976D2
            title: "Proxy SOCKS5",
            action: #selector(handleProxySettings)
        )
        contentStack.addArrangedSubview(btnProxy)

        // 1c. Dọn Dẹp RAM (Sparkles icon xanh ngọc)
        let btnCleanRam = makeMenuItem(
            iconName: "sparkles",
            iconColor: UIColor(red: 0.00, green: 0.54, blue: 0.48, alpha: 1.0), // Teal #00897B
            title: "Dọn Dẹp RAM",
            action: #selector(handleCleanRam)
        )
        contentStack.addArrangedSubview(btnCleanRam)

        // 2. Cài Đặt Bàn Phím (Keyboard+gear icon xanh)
        let btnKbSettings = makeMenuItem(
            iconName: "keyboard.fill",
            iconColor: UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0), // Green #2E7D32
            title: "Cài Đặt Bàn Phím",
            action: #selector(handleKbSettings)
        )
        contentStack.addArrangedSubview(btnKbSettings)

        // 3. Sắp Xếp Bàn Phím (4-way move icon xanh)
        let btnArrange = makeMenuItem(
            iconName: "arrow.up.and.down.and.arrow.left.and.right",
            iconColor: UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0),
            title: "Sắp Xếp Bàn Phím",
            action: #selector(handleArrange)
        )
        contentStack.addArrangedSubview(btnArrange)

        // 4. Ẩn Bàn Phím (Keyboard icon xanh)
        let btnHideKb = makeMenuItem(
            iconName: "keyboard",
            iconColor: UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0),
            title: isKeypadHidden ? "Hiện Bàn Phím" : "Ẩn Bàn Phím",
            action: #selector(handleToggleHideKb)
        )
        self.hideKeypadBtn = btnHideKb
        contentStack.addArrangedSubview(btnHideKb)

        // 4b. Bàn Phím Gốc QWERTY (Keyboard icon xanh dương - hiện bàn phím iPhone gốc)
        let btnNativeKb = makeMenuItem(
            iconName: "keyboard.badge.ellipsis",
            iconColor: UIColor(red: 0.12, green: 0.58, blue: 0.95, alpha: 1.0),
            title: "Bàn Phím Gốc QWERTY",
            action: #selector(handleNativeKb)
        )
        contentStack.addArrangedSubview(btnNativeKb)

        // 4c. Chia Màn Hình / Split View (Rectangle split icon xanh dương)
        let btnSplit = makeMenuItem(
            iconName: "rectangle.split.2x1.fill",
            iconColor: UIColor(red: 0.12, green: 0.45, blue: 0.88, alpha: 1.0), // Blue #1976D2
            title: "⧉ Chia Màn Hình (2/4/6 Game)",
            action: #selector(handleToggleSplitView)
        )
        contentStack.addArrangedSubview(btnSplit)

        // 4d. Ngủ Ẩn / Treo Màn Đen OLED (Moon icon tím đậm)
        let btnOledSleep = makeMenuItem(
            iconName: "moon.zzz.fill",
            iconColor: UIColor(red: 0.35, green: 0.28, blue: 0.78, alpha: 1.0),
            title: "Ngủ Ẩn (Tắt Màn Đen)",
            action: #selector(handleOledSleep)
        )
        contentStack.addArrangedSubview(btnOledSleep)

        // 4e. Treo 24/24 tắt màn & ẩn đa nhiệm (hiển thị rõ ĐANG BẬT ✓ / ĐANG TẮT để tránh bấm nhầm tắt)
        let btnTreo247 = makeMenuItem(
            iconName: isTreo247Active ? "checkmark.circle.fill" : "xmark.circle",
            iconColor: isTreo247Active ? UIColor(red: 0.13, green: 0.62, blue: 0.30, alpha: 1.0) : UIColor(red: 0.75, green: 0.25, blue: 0.22, alpha: 1.0),
            title: isTreo247Active ? "Treo 24/24: ĐANG BẬT ✓" : "Treo 24/24: ĐANG TẮT",
            action: #selector(handleToggleTreo247)
        )
        self.treo247Btn = btnTreo247
        updateTreo247Appearance()
        contentStack.addArrangedSubview(btnTreo247)

        // 4f. Ẩn Ứng Dụng chạy ngầm (giống J2ME NST HideApp: tự bật & nhớ chạy ẩn 24/24 vĩnh viễn)
        let btnHideApp = makeMenuItem(
            iconName: "eye.slash.circle.fill",
            iconColor: UIColor(red: 0.08, green: 0.56, blue: 0.46, alpha: 1.0),
            title: "Ẩn Ứng Dụng (Chạy Ngầm)",
            action: #selector(handleHideApp)
        )
        contentStack.addArrangedSubview(btnHideApp)

        // 4g. Cửa Sổ Nhỏ Ngoài Màn Hình Chính (PiP kéo to nhỏ tự do)
        let btnPiP = makeMenuItem(
            iconName: "pip.enter",
            iconColor: UIColor(red: 0.10, green: 0.46, blue: 0.88, alpha: 1.0),
            title: "Cửa Sổ Nhỏ Ngoài Màn Hình",
            action: #selector(handleTogglePiP)
        )
        contentStack.addArrangedSubview(btnPiP)

        // 5. Khởi Động Lại (Refresh icon tím)
        let btnRestart = makeMenuItem(
            iconName: "arrow.clockwise",
            iconColor: UIColor(red: 0.49, green: 0.34, blue: 0.76, alpha: 1.0),
            title: "Khởi Động Lại",
            action: #selector(handleRestart)
        )
        contentStack.addArrangedSubview(btnRestart)

        // 5c. Danh Sách Game (Quay lại danh sách chọn game)
        let btnGameList = makeMenuItem(
            iconName: "square.grid.2x2",
            iconColor: UIColor(red: 0.12, green: 0.58, blue: 0.95, alpha: 1.0),
            title: "Danh Sách Chọn Game",
            action: #selector(handleBackToList)
        )
        contentStack.addArrangedSubview(btnGameList)

        // Divider
        contentStack.addArrangedSubview(makeSeparator())

        // 6. Thoát Game (Exit door icon cam)
        let btnExit = makeMenuItem(
            iconName: "rectangle.portrait.and.arrow.right",
            iconColor: UIColor(red: 0.95, green: 0.50, blue: 0.10, alpha: 1.0), // Orange #F57C00
            title: "Thoát Game",
            action: #selector(handleExit)
        )
        contentStack.addArrangedSubview(btnExit)

        // 7. Đóng (Xmark)
        let btnClose = makeMenuItem(
            iconName: "xmark",
            iconColor: UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0),
            title: "Đóng",
            action: #selector(handleDismissTap)
        )
        contentStack.addArrangedSubview(btnClose)
    }

    private func makeMenuItem(iconName: String, iconColor: UIColor, title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let iv = UIImageView(image: UIImage(systemName: iconName))
        iv.tintColor = iconColor
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false

        let lbl = UILabel()
        lbl.text = title
        lbl.font = .systemFont(ofSize: 15, weight: .regular)
        lbl.textColor = UIColor(red: 0.12, green: 0.14, blue: 0.12, alpha: 1.0)
        lbl.translatesAutoresizingMaskIntoConstraints = false

        btn.addSubview(iv)
        btn.addSubview(lbl)

        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: btn.leadingAnchor, constant: 16),
            iv.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 20),
            iv.heightAnchor.constraint(equalToConstant: 20),

            lbl.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 14),
            lbl.trailingAnchor.constraint(equalTo: btn.trailingAnchor, constant: -16),
            lbl.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
        ])

        btn.addTarget(self, action: action, for: .touchUpInside)

        // Highlight visual feedback
        btn.addTarget(self, action: #selector(btnTouchDown(_:)), for: .touchDown)
        btn.addTarget(self, action: #selector(btnTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return btn
    }

    private func makeSeparator() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor(white: 0.92, alpha: 1.0)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    private func updateHideKeypadLabel() {
        guard let btn = hideKeypadBtn else { return }
        for sub in btn.subviews {
            if let lbl = sub as? UILabel {
                lbl.text = isKeypadHidden ? "Hiện Bàn Phím" : "Ẩn Bàn Phím"
            }
        }
    }

    private func updateTreo247Appearance() {
        guard let btn = treo247Btn else { return }
        for sub in btn.subviews {
            if let lbl = sub as? UILabel {
                lbl.text = isTreo247Active ? "Treo 24/24: ĐANG BẬT ✓" : "Treo 24/24: ĐANG TẮT"
                lbl.font = .systemFont(ofSize: 15, weight: isTreo247Active ? .semibold : .regular)
                lbl.textColor = isTreo247Active
                    ? UIColor(red: 0.10, green: 0.52, blue: 0.24, alpha: 1.0)
                    : UIColor(red: 0.65, green: 0.22, blue: 0.20, alpha: 1.0)
            } else if let iv = sub as? UIImageView {
                iv.image = UIImage(systemName: isTreo247Active ? "checkmark.circle.fill" : "xmark.circle")
                iv.tintColor = isTreo247Active
                    ? UIColor(red: 0.13, green: 0.62, blue: 0.30, alpha: 1.0)
                    : UIColor(red: 0.75, green: 0.25, blue: 0.22, alpha: 1.0)
            }
        }
    }

    @objc private func btnTouchDown(_ sender: UIButton) {
        sender.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
    }

    @objc private func btnTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.15) {
            sender.backgroundColor = .clear
        }
    }

    // ============================================================
    // MARK: - Handlers
    // ============================================================

    @objc private func handleGameSettings() {
        dismissMenu { [weak self] in
            self?.onOpenGameSettings?()
        }
    }

    @objc private func handleScreenSize() {
        dismissMenu { [weak self] in
            self?.onOpenScreenSize?()
        }
    }

    @objc private func handleProxySettings() {
        dismissMenu { [weak self] in
            self?.onOpenProxySettings?()
        }
    }

    @objc private func handleCleanRam() {
        dismissMenu { [weak self] in
            self?.onCleanRam?()
        }
    }

    @objc private func handleKbSettings() {
        dismissMenu { [weak self] in
            self?.onOpenKeyboardSettings?()
        }
    }

    @objc private func handleArrange() {
        dismissMenu { [weak self] in
            self?.onArrangeKeyboard?()
        }
    }

    @objc private func handleToggleHideKb() {
        dismissMenu { [weak self] in
            self?.onToggleKeyboardVisibility?()
        }
    }

    @objc private func handleToggleSplitView() {
        dismissMenu { [weak self] in
            self?.onToggleSplitView?()
        }
    }

    @objc private func handleOledSleep() {
        dismissMenu { [weak self] in
            self?.onOledSleepMode?()
        }
    }

    @objc private func handleToggleTreo247() {
        dismissMenu { [weak self] in
            self?.onToggleTreo247?()
        }
    }

    @objc private func handleTogglePiP() {
        dismissMenu { [weak self] in
            self?.onTogglePiP?()
        }
    }

    @objc private func handleHideApp() {
        dismissMenu { [weak self] in
            self?.onHideApp?()
        }
    }

    @objc private func handleRestart() {
        dismissMenu { [weak self] in
            self?.onRestartGame?()
        }
    }

    @objc private func handleNativeKb() {
        dismissMenu { [weak self] in
            self?.onOpenNativeKeyboard?()
        }
    }

    @objc private func handleBackToList() {
        dismissMenu { [weak self] in
            self?.onBackToList?()
        }
    }

    @objc private func handleExit() {
        dismissMenu { [weak self] in
            self?.onExitGame?()
        }
    }

    // ============================================================
    // MARK: - Presentation & Dismissal
    // ============================================================

    func show(in parentView: UIView) {
        isDismissing = false
        frame = parentView.bounds
        alpha = 0
        cardView.transform = CGAffineTransform(scaleX: 0.88, y: 0.88).translatedBy(x: 10, y: -20)
        parentView.addSubview(self)

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut], animations: {
            self.alpha = 1.0
            self.cardView.transform = .identity
        })
    }

    @objc private func handleDismissTap() {
        dismissMenu(completion: nil)
    }

    func dismissMenu(completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn], animations: {
            self.alpha = 0
            self.cardView.transform = CGAffineTransform(scaleX: 0.88, y: 0.88).translatedBy(x: 10, y: -20)
        }) { _ in
            self.removeFromSuperview()
            completion?()
        }
    }
}
