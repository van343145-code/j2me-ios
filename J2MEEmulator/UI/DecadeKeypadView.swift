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
    case dpadDiag
    case dpadOk
}

class DecadeKeypadView: UIView, UIGestureRecognizerDelegate {

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var buttonRepeatTimers: [ObjectIdentifier: Timer] = [:]
    private var activeTouches: [UITouch: DecadeKeyButton] = [:]
    private var editPanGestures: [UIPanGestureRecognizer] = []
    private var editPinchGestures: [UIPinchGestureRecognizer] = []
    private let finishEditBannerBtn = UIButton(type: .system)

    var onTextInputTapped: (() -> Void)?
    var onMenuTapped: (() -> Void)?

    let containerView = UIView()
    private var buttons: [DecadeKeyButton] = []

    // Customization state
    var gameId: String = "default" {
        didSet {
            loadSavedCustomLayout()
            loadDiagonalPreference()
            rebuildKeypad()
        }
    }

    var currentLayout: DecadeKeypadLayout = .tuoitho {
        didSet {
            loadSavedCustomLayout()
            rebuildKeypad()
        }
    }

    var showDiagonalKeys: Bool = true {
        didSet {
            if oldValue != showDiagonalKeys {
                rebuildKeypad()
            }
        }
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
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true

        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = false
        containerView.isMultipleTouchEnabled = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        finishEditBannerBtn.setTitle("✓ Xong sửa phím", for: .normal)
        finishEditBannerBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        finishEditBannerBtn.setTitleColor(.white, for: .normal)
        finishEditBannerBtn.backgroundColor = UIColor(red: 0.14, green: 0.62, blue: 0.30, alpha: 0.96)
        finishEditBannerBtn.layer.cornerRadius = 14
        finishEditBannerBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        finishEditBannerBtn.addTarget(self, action: #selector(finishEditBannerTapped), for: .touchUpInside)
        finishEditBannerBtn.translatesAutoresizingMaskIntoConstraints = false
        finishEditBannerBtn.isHidden = true
        addSubview(finishEditBannerBtn)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),

            finishEditBannerBtn.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            finishEditBannerBtn.centerXAnchor.constraint(equalTo: centerXAnchor),
            finishEditBannerBtn.heightAnchor.constraint(equalToConstant: 30)
        ])

        haptic.prepare()
        loadSavedCustomLayout()
        loadDiagonalPreference()
        rebuildKeypad()
    }

    @objc private func finishEditBannerTapped() {
        finishEditingLayout()
    }

    deinit {
        stopAllRepeatTimers()
    }

    private func loadDiagonalPreference() {
        let key = "keypad_diagonal_\(gameId)"
        if UserDefaults.standard.object(forKey: key) == nil {
            showDiagonalKeys = true
        } else {
            showDiagonalKeys = UserDefaults.standard.bool(forKey: key)
        }
    }

    private func stopAllRepeatTimers() {
        for (_, t) in buttonRepeatTimers {
            t.invalidate()
        }
        buttonRepeatTimers.removeAll()
    }

    private func releaseAllActiveTouches() {
        let held = Set(activeTouches.values.map { ObjectIdentifier($0) })
        for btn in buttons where held.contains(ObjectIdentifier(btn)) {
            releaseButton(btn)
        }
        activeTouches.removeAll()
        stopAllRepeatTimers()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyButtonPositions()
    }

    // ============================================================
    // MARK: - Rebuild Keypad
    // ============================================================

    func rebuildKeypad() {
        releaseAllActiveTouches()
        editPanGestures.removeAll()
        editPinchGestures.removeAll()
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

        func appendDpadKeys() {
            if showDiagonalKeys {
                items.append(KeyItem(title: "arrow.up.left", subtitle: nil, c1: -1, c2: -3, style: .dpadDiag, pane: 2, col: 0, row: 0, spanCols: 1, spanRows: 1))
                items.append(KeyItem(title: "arrow.up.right", subtitle: nil, c1: -1, c2: -4, style: .dpadDiag, pane: 2, col: 2, row: 0, spanCols: 1, spanRows: 1))
                items.append(KeyItem(title: "arrow.down.left", subtitle: nil, c1: -2, c2: -3, style: .dpadDiag, pane: 2, col: 0, row: 2, spanCols: 1, spanRows: 1))
                items.append(KeyItem(title: "arrow.down.right", subtitle: nil, c1: -2, c2: -4, style: .dpadDiag, pane: 2, col: 2, row: 2, spanCols: 1, spanRows: 1))
            }
            items.append(KeyItem(title: "chevron.up", subtitle: nil, c1: -1, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.left", subtitle: nil, c1: -3, c2: 0, style: .dpadMint, pane: 2, col: 0, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "OK", subtitle: nil, c1: -5, c2: 0, style: .dpadOk, pane: 2, col: 1, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.right", subtitle: nil, c1: -4, c2: 0, style: .dpadMint, pane: 2, col: 2, row: 1, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "chevron.down", subtitle: nil, c1: -2, c2: 0, style: .dpadMint, pane: 2, col: 1, row: 2, spanCols: 1, spanRows: 1))
        }

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

            // Right Pane: 8-Way D-Pad Navigation Cluster
            appendDpadKeys()

        case .arrows:
            // Chỉ Mũi Tên (8 hướng căn giữa rộng rãi)
            items.append(KeyItem(title: "L", subtitle: nil, c1: -6, c2: 0, style: .softkey, pane: 0, col: 0, row: 0, spanCols: 1, spanRows: 1))
            items.append(KeyItem(title: "R", subtitle: nil, c1: -7, c2: 0, style: .softkey, pane: 0, col: 1, row: 0, spanCols: 1, spanRows: 1))
            appendDpadKeys()

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
            // Combined (Numpad + 8-Way D-Pad)
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
            appendDpadKeys()
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

            let isEditing = isEditLayoutMode || isResizeLayoutMode
            btn.isUserInteractionEnabled = isEditing

            // Edit gestures — only active while editing/resizing; normal gameplay uses direct touchesBegan/Moved/Ended!
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.isEnabled = isEditLayoutMode
            btn.addGestureRecognizer(pan)
            editPanGestures.append(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            pinch.isEnabled = isResizeLayoutMode
            btn.addGestureRecognizer(pinch)
            editPinchGestures.append(pinch)

            btn.alpha = keypadAlphaValue
            containerView.addSubview(btn)
            buttons.append(btn)
        }

        containerView.isUserInteractionEnabled = isEditLayoutMode || isResizeLayoutMode
        finishEditBannerBtn.isHidden = !(isEditLayoutMode || isResizeLayoutMode)
        bringSubviewToFront(finishEditBannerBtn)
        updateKeysVisibility()
        if containerView.bounds.width > 0 && containerView.bounds.height > 0 {
            applyButtonPositions()
        }
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

        let hasLeftPane = buttons.contains { $0.pane == 1 }
        let hasRightPane = buttons.contains { $0.pane == 2 }
        let leftW: CGFloat = hasRightPane ? (containerW - gap) * 0.58 : containerW
        let rightW: CGFloat
        let rightX: CGFloat
        if !hasLeftPane && hasRightPane {
            // Dedicated 8-way Arrows mode: center spacious 3x3 D-pad
            rightW = min(containerW * 0.78, availH * 1.15)
            rightX = (containerW - rightW) * 0.5
        } else {
            rightW = containerW - leftW - gap
            rightX = leftW + gap
        }

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
    // MARK: - Direct Multi-Touch Key Handling (Standard J2ME MIDP 2.0 Spec)
    // ============================================================

    private func hitButton(at pointInSelf: CGPoint, tolerance: CGFloat = 3.0) -> DecadeKeyButton? {
        let pt = convert(pointInSelf, to: containerView)
        // Exact hit first
        for btn in buttons.reversed() {
            guard !btn.isHidden, btn.alpha >= 0.05 else { continue }
            if btn.frame.contains(pt) {
                return btn
            }
        }
        // Small gap tolerance so edge taps between keys still register cleanly
        if tolerance > 0 {
            for btn in buttons.reversed() {
                guard !btn.isHidden, btn.alpha >= 0.05 else { continue }
                if btn.frame.insetBy(dx: -tolerance, dy: -tolerance).contains(pt) {
                    return btn
                }
            }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditLayoutMode && !isResizeLayoutMode else {
            super.touchesBegan(touches, with: event)
            return
        }
        for touch in touches {
            guard let btn = hitButton(at: touch.location(in: self)) else { continue }
            let alreadyHeld = activeTouches.values.contains { $0 === btn }
            activeTouches[touch] = btn
            if !alreadyHeld {
                pressButton(btn)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditLayoutMode && !isResizeLayoutMode else {
            super.touchesMoved(touches, with: event)
            return
        }
        for touch in touches {
            let loc = touch.location(in: self)
            let oldBtn = activeTouches[touch]
            let newBtn = hitButton(at: loc, tolerance: 2.0)

            if oldBtn === newBtn { continue }

            // Smooth 8-way D-Pad thumb sliding across pane 2 keys (↑ ↓ ← → ↖ ↗ ↙ ↘ OK)
            if let old = oldBtn, let next = newBtn, old.pane == 2 && next.pane == 2 {
                activeTouches[touch] = next
                let oldStillHeld = activeTouches.values.contains { $0 === old }
                if !oldStillHeld {
                    releaseButton(old)
                }
                let nextAlreadyHeld = activeTouches.contains { $0.key !== touch && $0.value === next }
                if !nextAlreadyHeld {
                    pressButton(next)
                }
                continue
            }

            // If finger slid far outside the button (> 18pt), release it cleanly
            if let old = oldBtn {
                let pt = convert(loc, to: containerView)
                if !old.frame.insetBy(dx: -18, dy: -18).contains(pt) {
                    activeTouches.removeValue(forKey: touch)
                    let oldStillHeld = activeTouches.values.contains { $0 === old }
                    if !oldStillHeld {
                        releaseButton(old)
                    }
                    if let next = newBtn {
                        let nextAlreadyHeld = activeTouches.values.contains { $0 === next }
                        activeTouches[touch] = next
                        if !nextAlreadyHeld {
                            pressButton(next)
                        }
                    }
                }
            } else if let next = newBtn {
                let nextAlreadyHeld = activeTouches.values.contains { $0 === next }
                activeTouches[touch] = next
                if !nextAlreadyHeld {
                    pressButton(next)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditLayoutMode && !isResizeLayoutMode else {
            super.touchesEnded(touches, with: event)
            return
        }
        for touch in touches {
            if let btn = activeTouches.removeValue(forKey: touch) {
                let stillHeld = activeTouches.values.contains { $0 === btn }
                if !stillHeld {
                    releaseButton(btn)
                }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func pressButton(_ sender: DecadeKeyButton) {
        haptic.impactOccurred(intensity: 0.6)

        UIView.animate(withDuration: 0.06, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            sender.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            sender.alpha = max(0.45, self.keypadAlphaValue * 0.78)
        }

        // Send KEY_PRESSED ONCE (never duplicate KEY_PRESSED on hold!)
        postKey(type: Int32(J2ME_INPUT_KEY_PRESSED), c1: sender.c1, c2: sender.c2)

        // Independent per-button repeat timer so multi-touch (moving + hitting skills) works cleanly!
        let bid = ObjectIdentifier(sender)
        buttonRepeatTimers[bid]?.invalidate()
        let c1 = sender.c1
        let c2 = sender.c2
        let initialTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self, weak sender] _ in
            guard let self = self, sender != nil else { return }
            self.postKey(type: Int32(J2ME_INPUT_KEY_REPEATED), c1: c1, c2: c2)
            let rep = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self, weak sender] t in
                guard let self = self, sender != nil else { t.invalidate(); return }
                self.postKey(type: Int32(J2ME_INPUT_KEY_REPEATED), c1: c1, c2: c2)
            }
            self.buttonRepeatTimers[bid] = rep
        }
        buttonRepeatTimers[bid] = initialTimer
    }

    private func releaseButton(_ sender: DecadeKeyButton) {
        let bid = ObjectIdentifier(sender)
        buttonRepeatTimers[bid]?.invalidate()
        buttonRepeatTimers.removeValue(forKey: bid)

        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            sender.transform = .identity
            sender.alpha = self.keypadAlphaValue
        }

        // Always release the exact key codes belonging to this button
        postKey(type: Int32(J2ME_INPUT_KEY_RELEASED), c1: sender.c1, c2: sender.c2)
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
        let isEditing = isEditLayoutMode || isResizeLayoutMode
        if isEditing {
            releaseAllActiveTouches()
        }
        containerView.isUserInteractionEnabled = isEditing
        finishEditBannerBtn.isHidden = !isEditing
        if isEditing {
            bringSubviewToFront(finishEditBannerBtn)
        }
        for pan in editPanGestures {
            pan.isEnabled = isEditLayoutMode
        }
        for pinch in editPinchGestures {
            pinch.isEnabled = isResizeLayoutMode
        }
        for btn in buttons {
            btn.isUserInteractionEnabled = isEditing
            if isEditing {
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
                || (title == "arrow.up.left" && hiddenKeys.contains("↖"))
                || (title == "arrow.up.right" && hiddenKeys.contains("↗"))
                || (title == "arrow.down.left" && hiddenKeys.contains("↙"))
                || (title == "arrow.down.right" && hiddenKeys.contains("↘"))
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

        case .dpadMint, .dpadDiag:
            backgroundColor = (style == .dpadDiag)
                ? UIColor(red: 0.92, green: 0.97, blue: 0.93, alpha: 1.0)
                : UIColor(red: 0.88, green: 0.96, blue: 0.88, alpha: 1.0) // Mint #E8F5E9
            layer.cornerRadius = 11

            let sfName = keyTitle
            let iv = UIImageView(image: UIImage(systemName: sfName))
            iv.tintColor = UIColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1.0) // Green #2E7D32
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iv)

            let iconDim: CGFloat = (style == .dpadDiag) ? 16 : 20
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: iconDim),
                iv.heightAnchor.constraint(equalToConstant: iconDim)
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
