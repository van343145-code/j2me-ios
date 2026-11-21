//
//  DecadeKeypadView.swift
//  J2MEEmulator
//
//  Bàn phím ảo phong cách "Chơi Game Tuổi Thơ" cho J2ME iOS:
//  - Hàng trên: Phím mềm L & R (màu tím nhạt lavender, chữ tím đậm).
//  - Bên trái: Bàn phím số 3x4 thẻ trắng trang nhã (1-9, *, 0, #) kèm chữ phụ (ABC, DEF...) + nút Del (tím) và / (trắng).
//  - Bên phải: Cụm phím điều hướng D-Pad (mũi tên xanh lá ^, <, >, v trên thẻ mint) và ở giữa là nút OK màu xanh lá cây nổi bật đặc trưng với chữ trắng!
//  - Hỗ trợ đa chạm (Multi-touch) mượt mà, phản hồi rung xúc giác (Haptic Feedback) chân thực.
//

import UIKit

enum DecadeKeypadLayout: Int {
    case tuoitho = 0   // Bản Tuổi Thơ (Chuẩn Mới theo Ảnh 1 & 2)
    case arrows = 1    // Chỉ Mũi Tên Điều Hướng
    case numpad = 2    // Bàn Phím Số (Phone Numpad)
    case combined = 3  // Kết Hợp Đầy Đủ
}

enum DecadeKeyStyle {
    case softkey
    case whiteCard
    case del
    case slash
    case dpadMint
    case dpadOk
}

class DecadeKeypadView: UIView, UIGestureRecognizerDelegate {

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var repeatTimer: Timer?
    private var activeCode1: Int32 = 0
    private var activeCode2: Int32 = 0

    var onTextInputTapped: (() -> Void)?
    var onMenuTapped: (() -> Void)?

    let containerView = UIView()
    private var buttons: [DecadeKeyButton] = []

    // Customization state
    var gameId: String = "default" {
        didSet {
            loadSavedCustomLayout()
            rebuildKeypad()
        }
    }

    var currentLayout: DecadeKeypadLayout = .tuoitho {
        didSet {
            loadSavedCustomLayout()
            rebuildKeypad()
        }
    }

    var showDiagonalKeys: Bool = false {
        didSet { rebuildKeypad() }
    }
    var showSoftKeys: Bool = true {
        didSet { rebuildKeypad() }
    }
    var showFireKey: Bool = true {
        didSet { rebuildKeypad() }
    }
    var keypadAlphaValue: CGFloat = 1.0 {
        didSet {
            for btn in buttons {
                btn.alpha = keypadAlphaValue
            }
        }
    }

    // Hidden keys set from dialog
    var hiddenKeys: Set<String> = [] {
        didSet {
            updateKeysVisibility()
        }
    }

    func loadHiddenKeys() {
        let key = "decade_hidden_keys_\(gameId)"
        if let saved = UserDefaults.standard.stringArray(forKey: key) {
            hiddenKeys = Set(saved)
        } else {
            hiddenKeys = []
        }
    }

    func saveHiddenKeys() {
        let key = "decade_hidden_keys_\(gameId)"
        UserDefaults.standard.set(Array(hiddenKeys), forKey: key)
        updateKeysVisibility()
    }

    // Edit & Resize mode state
    var isEditLayoutMode: Bool = false {
        didSet {
            updateEditModeAppearance()
        }
    }

    var isResizeLayoutMode: Bool = false {
        didSet {
            updateEditModeAppearance()
        }
    }

    // Saved custom frames normalized (x/w, y/h, w/w, h/h)
    private var customFrames: [String: [CGFloat]] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeypad()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeypad()
    }

    private func setupKeypad() {
        backgroundColor = UIColor(red: 0.957, green: 0.957, blue: 0.973, alpha: 1.0) // Soft light lavender-grey #F4F4F8
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true
        isMultipleTouchEnabled = true

        containerView.backgroundColor = .clear
        containerView.isMultipleTouchEnabled = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])

        loadSavedCustomLayout()
        rebuildKeypad()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyButtonPositions()
    }

    // ============================================================
    // MARK: - Rebuild Keypad
    // ============================================================

    func rebuildKeypad() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        struct KeyItem {
            let title: String
            let subtitle: String?
            let c1: Int32
            let c2: Int32
            let style: DecadeKeyStyle
            let pane: Int // 0=Softkey, 1=Left Pane, 2=Right Pane
            let col: Int
            let row: Int
            let spanCols: Int
            let spanRows: Int
        }

        var items: [KeyItem] = []

        switch currentLayout {
        case .tuoitho:
            // ⭐️ BẢN TUỔI THƠ (Ảnh 1 & 2)
            // Top Softkeys
            items.append(KeyItem(title: "L", subtitle: nil, c1: -6, c2: 0, style: .softkey, pane: 0, col: 0, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "R", subtitle: nil, c1: -7, c2: 0, style: .softkey, pane: 0, col: 1, row: 0, spanCols: 1, spanRows: 1))

            // Left Pane: Numpad 3x4 + Row 4 (Del & /)
            let numpadData: [(String, String?, Int32, Int, Int)] = [
                ("1", nil, 49, 0, 0), ("2", "ABC", 50, 1, 0), ("3", "DEF", 51, 2, 0),
                ("4", "GHI", 52, 0, 1), ("5", "JKL", 53, 1, 1), ("6", "MNO", 54, 2, 1),
                ("7", "PQRS", 55, 0, 2), ("8", "TUV", 56, 1, 2), ("9", "WXYZ", 57, 2, 2),
                ("*", nil, 42, 0, 3), ("0", nil, 48, 1, 3), ("#", nil, 35, 2, 3),
            ]
            for (title, sub, code, c, r) in numpadData {
                items.append(KeyItem(title: title, subtitle: sub, c1: code, c2: 0, style: .whiteCard, pane: 1, col: c, row: r, spanCols: 1, spanRows: 1))
            }
            // Del and / in Left Pane Row 4
            items.append(KeyItem(title: "Del", subtitle: nil, c1: 8, c2: 0, style: .del, pane: 1, col: 0, row: 4, spanCols: 2, spanRows: 1))
            items.append(KeyItem(title: "/", subtitle: nil, c1: 47, c2: 0, style: .slash, pane: 1, col: 2, row: 4, spanCols: 1, spanRows: 1))

            // Right Pane: D-Pad Navigation Cluster
            items.append(KeyItem(title: "chevron.up", subtitle: nil, c1: -1, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.left", subtitle: nil, c1: -3, c2: 0, style: .dpadMint, pane: 2, col: 0, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "OK", subtitle: nil, c1: -5, c2: 0, style: .dpadOk, pane: 2, col: 1, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.right", subtitle: nil, c1: -4, c2: 0, style: .dpadMint, pane: 2, col: 2, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.down", subtitle: nil, c1: -2, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 2, spanCols: 1, spanRows: 1))

        case .arrows:
            // Chỉ Mũi Tên
            items.append(KeyItem(title: "L", subtitle: nil, c1: -6, c2: 0, style: .softkey, pane: 0, col: 0, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "R", subtitle: nil, c1: -7, c2: 0, style: .softkey, pane: 0, col: 1, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.up", subtitle: nil, c1: -1, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.left", subtitle: nil, c1: -3, c2: 0, style: .dpadMint, pane: 2, col: 0, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "OK", subtitle: nil, c1: -5, c2: 0, style: .dpadOk, pane: 2, col: 1, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.right", subtitle: nil, c1: -4, c2: 0, style: .dpadMint, pane: 2, col: 2, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.down", subtitle: nil, c1: -2, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 2, spanCols: 1, spanRows: 1))

        case .numpad:
            // Phone Numpad
            items.append(KeyItem(title: "L", subtitle: nil, c1: -6, c2: 0, style: .softkey, pane: 0, col: 0, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "R", subtitle: nil, c1: -7, c2: 0, style: .softkey, pane: 0, col: 1, row: 0, spanCols: 1, spanRows: 1))
            let numpadOnly: [(String, String?, Int32, Int, Int)] = [
                ("1", nil, 49, 0, 0), ("2", "ABC", 50, 1, 0), ("3", "DEF", 51, 2, 0),
                ("4", "GHI", 52, 0, 1), ("5", "JKL", 53, 1, 1), ("6", "MNO", 54, 2, 1),
                ("7", "PQRS", 55, 0, 2), ("8", "TUV", 56, 1, 2), ("9", "WXYZ", 57, 2, 2),
                ("*", nil, 42, 0, 3), ("0", nil, 48, 1, 3), ("#", nil, 35, 2, 3),
            ]
            for (title, sub, code, c, r) in numpadOnly {
                items.append(KeyItem(title: title, subtitle: sub, c1: code, c2: 0, style: .whiteCard, pane: 1, col: c, row: r, spanCols: 1, spanRows: 1))
            }

        case .combined:
            // Combined
            items.append(KeyItem(title: "L", subtitle: nil, c1: -6, c2: 0, style: .softkey, pane: 0, col: 0, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "R", subtitle: nil, c1: -7, c2: 0, style: .softkey, pane: 0, col: 1, row: 0, spanCols: 1, spanRows: 1))
            let allNums: [(String, String?, Int32, Int, Int)] = [
                ("1", nil, 49, 0, 0), ("2", "ABC", 50, 1, 0), ("3", "DEF", 51, 2, 0),
                ("4", "GHI", 52, 0, 1), ("5", "JKL", 53, 1, 1), ("6", "MNO", 54, 2, 1),
                ("7", "PQRS", 55, 0, 2), ("8", "TUV", 56, 1, 2), ("9", "WXYZ", 57, 2, 2),
                ("*", nil, 42, 0, 3), ("0", nil, 48, 1, 3), ("#", nil, 35, 2, 3),
            ]
            for (title, sub, code, c, r) in allNums {
                items.append(KeyItem(title: title, subtitle: sub, c1: code, c2: 0, style: .whiteCard, pane: 1, col: c, row: r, spanCols: 1, spanRows: 1))
            }
            items.append(KeyItem(title: "chevron.up", subtitle: nil, c1: -1, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.left", subtitle: nil, c1: -3, c2: 0, style: .dpadMint, pane: 2, col: 0, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "OK", subtitle: nil, c1: -5, c2: 0, style: .dpadOk, pane: 2, col: 1, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.right", subtitle: nil, c1: -4, c2: 0, style: .dpadMint, pane: 2, col: 2, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.down", subtitle: nil, c1: -2, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 2, spanCols: 1, spanRows: 1))
        }

        for item in items {
            let btn = DecadeKeyButton(
                title: item.title,
                subtitle: item.subtitle,
                c1: item.c1,
                c2: item.c2,
                pane: item.pane,
                col: item.col,
                row: item.row,
                spanCols: item.spanCols,
                spanRows: item.spanRows,
                style: item.style
            )

            // Touch events
            btn.addTarget(self, action: #selector(buttonDown(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(buttonUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

            // Edit gesture
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            btn.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            btn.addGestureRecognizer(pinch)

            containerView.addSubview(btn)
            buttons.append(btn)
        }

        updateKeysVisibility()
        setNeedsLayout()
    }

    // ============================================================
    // MARK: - Layout Calculation
    // ============================================================

    func applyButtonPositions() {
        let containerW = containerView.bounds.width
        let containerH = containerView.bounds.height
        guard containerW > 0, containerH > 0 else { return }

        let topMargin: CGFloat = 2
        let softkeyH: CGFloat = 36
        let softkeyW: CGFloat = min(90, (containerW - 24) * 0.28)
        let gap: CGFloat = 6

        let startY = topMargin + softkeyH + 6
        let availH = containerH - startY - 4

        let hasRightPane = buttons.contains { $0.pane == 2 }
        let leftW: CGFloat = hasRightPane ? (containerW - gap) * 0.58 : containerW
        let rightW: CGFloat = containerW - leftW - gap
        let rightX: CGFloat = leftW + gap

        // Grid measurements
        let leftRows: CGFloat = 5
        let leftCols: CGFloat = 3
        let leftBtnH = floor((availH - (leftRows - 1) * gap) / leftRows)
        let leftBtnW = floor((leftW - (leftCols - 1) * gap) / leftCols)

        let rightRows: CGFloat = 3
        let rightCols: CGFloat = 3
        let rightBtnH = floor((availH - (rightRows - 1) * gap) / rightRows)
        let rightBtnW = floor((rightW - (rightCols - 1) * gap) / rightCols)

        for btn in buttons {
            // Check custom position first
            if let custom = customFrames[btn.keyTitle], custom.count == 4 {
                btn.frame = CGRect(
                    x: custom[0] * containerW,
                    y: custom[1] * containerH,
                    width: custom[2] * containerW,
                    height: custom[3] * containerH
                )
                continue
            }

            var f: CGRect = .zero
            if btn.pane == 0 {
                // Softkeys
                if btn.col == 0 {
                    f = CGRect(x: 4, y: topMargin, width: softkeyW, height: softkeyH)
                } else {
                    f = CGRect(x: containerW - 4 - softkeyW, y: topMargin, width: softkeyW, height: softkeyH)
                }
            } else if btn.pane == 1 {
                // Left Pane
                let y = startY + CGFloat(btn.row) * (leftBtnH + gap)
                if btn.row == 4 {
                    // Row 4: Del (col 0, span 2) & Slash (col 2, span 1)
                    if btn.col == 0 {
                        let w = leftBtnW * 2 + gap
                        f = CGRect(x: 0, y: y, width: w, height: leftBtnH)
                    } else {
                        let x = (leftBtnW * 2 + gap) + gap
                        f = CGRect(x: x, y: y, width: leftBtnW, height: leftBtnH)
                    }
                } else {
                    let x = CGFloat(btn.col) * (leftBtnW + gap)
                    f = CGRect(x: x, y: y, width: leftBtnW, height: leftBtnH)
                }
            } else if btn.pane == 2 {
                // Right Pane
                let x = rightX + CGFloat(btn.col) * (rightBtnW + gap)
                let y = startY + CGFloat(btn.row) * (rightBtnH + gap)
                f = CGRect(x: x, y: y, width: rightBtnW, height: rightBtnH)
            }

            btn.frame = f
        }
    }

    // ============================================================
    // MARK: - Key Press Handling (Standard J2ME MIDP 2.0 Spec)
    // ============================================================

    @objc private func buttonDown(_ sender: DecadeKeyButton) {
        guard !isEditLayoutMode && !isResizeLayoutMode else { return }
        haptic.impactOccurred(intensity: 0.6)
        activeCode1 = sender.c1
        activeCode2 = sender.c2

        UIView.animate(withDuration: 0.08) {
            sender.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            sender.alpha = 0.82
        }

        // Send KEY_PRESSED ONCE (never duplicate KEY_PRESSED on hold!)
        postKey(type: Int32(J2ME_INPUT_KEY_PRESSED), c1: sender.c1, c2: sender.c2)

        // Standard J2ME hardware repeat: wait 0.35s initial delay, then emit KEY_REPEATED every 0.10s
        repeatTimer?.invalidate()
        let c1 = sender.c1
        let c2 = sender.c2
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.postKey(type: Int32(J2ME_INPUT_KEY_REPEATED), c1: c1, c2: c2)
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
                self?.postKey(type: Int32(J2ME_INPUT_KEY_REPEATED), c1: c1, c2: c2)
            }
        }
    }

    @objc private func buttonUp(_ sender: DecadeKeyButton) {
        guard !isEditLayoutMode && !isResizeLayoutMode else { return }
        repeatTimer?.invalidate()
        repeatTimer = nil

        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
            sender.alpha = self.keypadAlphaValue
        }

        // Always release the exact key codes belonging to this button
        postKey(type: Int32(J2ME_INPUT_KEY_RELEASED), c1: sender.c1, c2: sender.c2)
        if activeCode1 == sender.c1 { activeCode1 = 0 }
        if activeCode2 == sender.c2 { activeCode2 = 0 }
    }

    private func postKey(type: Int32, c1: Int32, c2: Int32) {
        if c1 != 0 {
            j2me_input_post_key(type, c1)
        }
        if c2 != 0 {
            j2me_input_post_key(type, c2)
        }
    }

    // ============================================================
    // MARK: - Edit & Arrange Layout Gestures
    // ============================================================

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEditLayoutMode, let btn = gesture.view as? DecadeKeyButton else { return }
        let translation = gesture.translation(in: containerView)
        var newCenter = CGPoint(x: btn.center.x + translation.x, y: btn.center.y + translation.y)

        let halfW = btn.bounds.width / 2
        let halfH = btn.bounds.height / 2
        newCenter.x = max(halfW, min(containerView.bounds.width - halfW, newCenter.x))
        newCenter.y = max(halfH, min(containerView.bounds.height - halfH, newCenter.y))

        btn.center = newCenter
        gesture.setTranslation(.zero, in: containerView)

        if gesture.state == .ended {
            saveButtonPosition(btn)
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isResizeLayoutMode, let btn = gesture.view as? DecadeKeyButton else { return }
        let scale = gesture.scale
        let newWidth = max(36, min(140, btn.bounds.width * scale))
        let newHeight = max(36, min(140, btn.bounds.height * scale))
        btn.bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
        gesture.scale = 1.0

        if gesture.state == .ended {
            saveButtonPosition(btn)
        }
    }

    private func saveButtonPosition(_ btn: DecadeKeyButton) {
        let containerW = containerView.bounds.width
        let containerH = containerView.bounds.height
        guard containerW > 0, containerH > 0 else { return }

        let normX = btn.frame.origin.x / containerW
        let normY = btn.frame.origin.y / containerH
        let normW = btn.frame.width / containerW
        let normH = btn.frame.height / containerH

        customFrames[btn.keyTitle] = [normX, normY, normW, normH]
        UserDefaults.standard.set(customFrames, forKey: "custom_frames_\(gameId)")
    }

    private func loadSavedCustomLayout() {
        if let saved = UserDefaults.standard.dictionary(forKey: "custom_frames_\(gameId)") as? [String: [CGFloat]] {
            customFrames = saved
        } else {
            customFrames = [:]
        }
    }

    func resetCustomLayout() {
        customFrames.removeAll()
        UserDefaults.standard.removeObject(forKey: "custom_frames_\(gameId)")
        applyButtonPositions()
    }

    func toggleEditMode() {
        isEditLayoutMode.toggle()
    }

    func finishEditingLayout() {
        isEditLayoutMode = false
        isResizeLayoutMode = false
        UserDefaults.standard.set(customFrames, forKey: "custom_frames_\(gameId)")
        UserDefaults.standard.synchronize()
    }

    private func updateEditModeAppearance() {
        for btn in buttons {
            if isEditLayoutMode || isResizeLayoutMode {
                btn.layer.borderWidth = 2.0
                btn.layer.borderColor = UIColor.systemGreen.cgColor
            } else {
                btn.setupBorder()
            }
        }
    }

    func updateKeysVisibility() {
        for btn in buttons {
            let title = btn.keyTitle
            let isHidden = hiddenKeys.contains(title)
                || (title == "chevron.up" && (hiddenKeys.contains("↑") || hiddenKeys.contains("Lên")))
                || (title == "chevron.down" && (hiddenKeys.contains("↓") || hiddenKeys.contains("Xuống")))
                || (title == "chevron.left" && (hiddenKeys.contains("←") || hiddenKeys.contains("Trái")))
                || (title == "chevron.right" && (hiddenKeys.contains("→") || hiddenKeys.contains("Phải")))
            btn.isHidden = isHidden
        }
    }
}

// ============================================================
// MARK: - DecadeKeyButton Component
// ============================================================

class DecadeKeyButton: UIButton {
    let keyTitle: String
    let subtitle: String?
    let c1: Int32
    let c2: Int32
    let pane: Int
    let col: Int
    let row: Int
    let spanCols: Int
    let spanRows: Int
    let style: DecadeKeyStyle

    private let titleLbl = UILabel()
    private let subtitleLbl = UILabel()

    init(title: String, subtitle: String?, c1: Int32, c2: Int32,
         pane: Int, col: Int, row: Int, spanCols: Int, spanRows: Int,
         style: DecadeKeyStyle) {
        self.keyTitle = title
        self.subtitle = subtitle
        self.c1 = c1
        self.c2 = c2
        self.pane = pane
        self.col = col
        self.row = row
        self.spanCols = spanCols
        self.spanRows = spanRows
        self.style = style
        super.init(frame: .zero)
        setupVisuals()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupVisuals() {
        layer.masksToBounds = false
        isExclusiveTouch = false

        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        subtitleLbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLbl)
        addSubview(subtitleLbl)

        switch style {
        case .softkey:
            backgroundColor = UIColor(red: 0.93, green: 0.90, blue: 0.98, alpha: 1.0) // Soft lavender #EDE7F6
            layer.cornerRadius = 10
            titleLbl.text = keyTitle
            titleLbl.font = .systemFont(ofSize: 18, weight: .bold)
            titleLbl.textColor = UIColor(red: 0.49, green: 0.34, blue: 0.76, alpha: 1.0) // Purple #7E57C2
            setupBorder()

        case .whiteCard:
            backgroundColor = .white
            layer.cornerRadius = 10
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.05
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 2

            titleLbl.text = keyTitle
            titleLbl.font = .systemFont(ofSize: 20, weight: .bold)
            titleLbl.textColor = UIColor(red: 0.10, green: 0.14, blue: 0.10, alpha: 1.0)

            if let sub = subtitle {
                subtitleLbl.text = sub
                subtitleLbl.font = .systemFont(ofSize: 9, weight: .bold)
                subtitleLbl.textColor = UIColor(red: 0.45, green: 0.50, blue: 0.45, alpha: 1.0)
            }
            setupBorder()

        case .del:
            backgroundColor = UIColor(red: 0.93, green: 0.90, blue: 0.98, alpha: 1.0)
            layer.cornerRadius = 10
            titleLbl.text = "Del"
            titleLbl.font = .systemFont(ofSize: 16, weight: .bold)
            titleLbl.textColor = UIColor(red: 0.49, green: 0.34, blue: 0.76, alpha: 1.0)
            setupBorder()

        case .slash:
            backgroundColor = .white
            layer.cornerRadius = 10
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.05
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 2
            titleLbl.text = "/"
            titleLbl.font = .systemFont(ofSize: 19, weight: .bold)
            titleLbl.textColor = UIColor(red: 0.10, green: 0.14, blue: 0.10, alpha: 1.0)
            setupBorder()

        case .dpadMint:
            backgroundColor = UIColor(red: 0.88, green: 0.96, blue: 0.88, alpha: 1.0) // Mint #E8F5E9
            layer.cornerRadius = 11

            let sfName: String
            switch keyTitle {
            case "chevron.up": sfName = "chevron.up"
            case "chevron.down": sfName = "chevron.down"
            case "chevron.left": sfName = "chevron.left"
            case "chevron.right": sfName = "chevron.right"
            default: sfName = keyTitle
            }

            let iv = UIImageView(image: UIImage(systemName: sfName))
            iv.tintColor = UIColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1.0) // Green #2E7D32
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iv)

            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 20),
                iv.heightAnchor.constraint(equalToConstant: 20)
            ])
            setupBorder()

        case .dpadOk:
            backgroundColor = UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0) // Solid Vibrant Green #2E7D32
            layer.cornerRadius = 12
            layer.shadowColor = UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0).cgColor
            layer.shadowOpacity = 0.25
            layer.shadowOffset = CGSize(width: 0, height: 2)
            layer.shadowRadius = 4

            titleLbl.text = "OK"
            titleLbl.font = .systemFont(ofSize: 18, weight: .heavy)
            titleLbl.textColor = .white
        }

        // Layout labels
        if subtitle != nil {
            NSLayoutConstraint.activate([
                titleLbl.centerXAnchor.constraint(equalTo: centerXAnchor),
                titleLbl.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -5),
                subtitleLbl.centerXAnchor.constraint(equalTo: centerXAnchor),
                subtitleLbl.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 1)
            ])
        } else {
            NSLayoutConstraint.activate([
                titleLbl.centerXAnchor.constraint(equalTo: centerXAnchor),
                titleLbl.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    func setupBorder() {
        if style == .dpadOk {
            layer.borderWidth = 0
        } else {
            layer.borderWidth = 1.0
            layer.borderColor = UIColor(white: 0.90, alpha: 0.85).cgColor
        }
    }
}
