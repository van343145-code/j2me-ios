//
//  DecadeQuickKeysView.swift
//  J2MEEmulator
//
//  Quản lý Phím Nhanh (Thêm, Chỉnh, Xoá, Kéo thả sắp xếp phím nhanh)
//  Hỗ trợ game thủ J2ME (Ninja School, Hiệp Sĩ, Ngọc Rồng, Avatar...)
//

import UIKit

struct DecadeQuickKey: Codable {
    var id: String
    var label: String
    var keyCode: Int32
    var colorStyle: String // "mint", "blue", "purple", "orange", "red", "white"
    var normX: CGFloat
    var normY: CGFloat
    var width: CGFloat
    var height: CGFloat
}

class DecadeQuickKeysOverlayView: UIView {

    var gameId: String = "default" {
        didSet {
            loadKeys()
            rebuildButtons()
        }
    }

    var isEditMode: Bool = false {
        didSet {
            updateEditModeAppearance()
        }
    }

    private var keys: [DecadeQuickKey] = []
    private var buttonViews: [UIButton] = []
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private var repeatTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        clipsToBounds = false
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Only consume touches that hit one of the quick key buttons
        for btn in buttonViews {
            if !btn.isHidden && btn.alpha > 0.05 && btn.frame.contains(point) {
                return true
            }
        }
        return false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyButtonFrames()
    }

    // ============================================================
    // MARK: - Persistence & Defaults
    // ============================================================

    private func defaultQuickKeys() -> [DecadeQuickKey] {
        return [
            DecadeQuickKey(id: UUID().uuidString, label: "1", keyCode: 49, colorStyle: "mint", normX: 0.04, normY: 0.72, width: 44, height: 38),
            DecadeQuickKey(id: UUID().uuidString, label: "2", keyCode: 50, colorStyle: "mint", normX: 0.18, normY: 0.72, width: 44, height: 38),
            DecadeQuickKey(id: UUID().uuidString, label: "3", keyCode: 51, colorStyle: "mint", normX: 0.32, normY: 0.72, width: 44, height: 38),
            DecadeQuickKey(id: UUID().uuidString, label: "7", keyCode: 55, colorStyle: "purple", normX: 0.68, normY: 0.72, width: 44, height: 38),
            DecadeQuickKey(id: UUID().uuidString, label: "F", keyCode: -5, colorStyle: "blue", normX: 0.82, normY: 0.72, width: 48, height: 38),
        ]
    }

    func loadKeys() {
        let key = "decade_quick_keys_\(gameId)"
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([DecadeQuickKey].self, from: data) {
            keys = saved
        } else {
            keys = defaultQuickKeys()
            saveKeys()
        }
    }

    func saveKeys() {
        let key = "decade_quick_keys_\(gameId)"
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func resetToDefaults() {
        keys = defaultQuickKeys()
        saveKeys()
        rebuildButtons()
    }

    // ============================================================
    // MARK: - UI Construction
    // ============================================================

    func rebuildButtons() {
        buttonViews.forEach { $0.removeFromSuperview() }
        buttonViews.removeAll()

        for (index, qk) in keys.enumerated() {
            let btn = UIButton(type: .custom)
            btn.tag = index
            btn.setTitle(qk.label, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            btn.layer.cornerRadius = 8
            btn.clipsToBounds = true
            btn.layer.shadowColor = UIColor.black.cgColor
            btn.layer.shadowOpacity = 0.20
            btn.layer.shadowOffset = CGSize(width: 0, height: 2)
            btn.layer.shadowRadius = 3

            applyStyle(btn: btn, style: qk.colorStyle)

            // Touch events
            btn.addTarget(self, action: #selector(btnDown(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(btnUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

            // Drag pan gesture in edit mode
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            btn.addGestureRecognizer(pan)

            addSubview(btn)
            buttonViews.append(btn)
        }

        updateEditModeAppearance()
        setNeedsLayout()
    }

    private func applyStyle(btn: UIButton, style: String) {
        switch style {
        case "mint":
            btn.backgroundColor = UIColor(red: 0.18, green: 0.65, blue: 0.38, alpha: 0.90) // #2E7D32
            btn.setTitleColor(.white, for: .normal)
        case "blue":
            btn.backgroundColor = UIColor(red: 0.12, green: 0.45, blue: 0.88, alpha: 0.90) // #1976D2
            btn.setTitleColor(.white, for: .normal)
        case "purple":
            btn.backgroundColor = UIColor(red: 0.55, green: 0.35, blue: 0.80, alpha: 0.90) // #7E57C2
            btn.setTitleColor(.white, for: .normal)
        case "orange":
            btn.backgroundColor = UIColor(red: 0.95, green: 0.50, blue: 0.12, alpha: 0.90) // #F57C00
            btn.setTitleColor(.white, for: .normal)
        case "red":
            btn.backgroundColor = UIColor(red: 0.88, green: 0.22, blue: 0.22, alpha: 0.90) // #D32F2F
            btn.setTitleColor(.white, for: .normal)
        case "white":
            btn.backgroundColor = UIColor(white: 0.96, alpha: 0.92)
            btn.setTitleColor(UIColor(white: 0.15, alpha: 1.0), for: .normal)
            btn.layer.borderWidth = 1
            btn.layer.borderColor = UIColor(white: 0.80, alpha: 1.0).cgColor
        default:
            btn.backgroundColor = UIColor(white: 0.20, alpha: 0.85)
            btn.setTitleColor(.white, for: .normal)
        }
    }

    private func applyButtonFrames() {
        let parentW = bounds.width
        let parentH = bounds.height
        guard parentW > 0, parentH > 0 else { return }

        for (index, btn) in buttonViews.enumerated() {
            guard index < keys.count else { continue }
            let qk = keys[index]
            let w = qk.width
            let h = qk.height
            let x = qk.normX * parentW
            let y = qk.normY * parentH
            btn.frame = CGRect(x: x, y: y, width: w, height: h)
        }
    }

    // ============================================================
    // MARK: - Key Dispatch
    // ============================================================

    @objc private func btnDown(_ sender: UIButton) {
        guard !isEditMode else { return }
        let index = sender.tag
        guard index < keys.count else { return }
        let code = keys[index].keyCode

        haptic.impactOccurred(intensity: 0.7)
        UIView.animate(withDuration: 0.08) {
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            sender.alpha = 0.80
        }

        j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), code)

        // Key repeat
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { _ in
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_REPEATED), code)
            }
        }
    }

    @objc private func btnUp(_ sender: UIButton) {
        guard !isEditMode else { return }
        let index = sender.tag
        repeatTimer?.invalidate()
        repeatTimer = nil

        UIView.animate(withDuration: 0.10) {
            sender.transform = .identity
            sender.alpha = 1.0
        }

        guard index < keys.count else { return }
        let code = keys[index].keyCode
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), code)
    }

    // ============================================================
    // MARK: - Drag & Drop Arrangement
    // ============================================================

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEditMode, let btn = gesture.view as? UIButton else { return }
        let translation = gesture.translation(in: self)
        var newCenter = CGPoint(x: btn.center.x + translation.x, y: btn.center.y + translation.y)

        let halfW = btn.bounds.width / 2
        let halfH = btn.bounds.height / 2
        newCenter.x = max(halfW, min(bounds.width - halfW, newCenter.x))
        newCenter.y = max(halfH, min(bounds.height - halfH, newCenter.y))

        btn.center = newCenter
        gesture.setTranslation(.zero, in: self)

        if gesture.state == .ended {
            let index = btn.tag
            if index < keys.count && bounds.width > 0 && bounds.height > 0 {
                keys[index].normX = btn.frame.origin.x / bounds.width
                keys[index].normY = btn.frame.origin.y / bounds.height
                saveKeys()
            }
        }
    }

    private func updateEditModeAppearance() {
        for btn in buttonViews {
            if isEditMode {
                btn.layer.borderWidth = 2.0
                btn.layer.borderColor = UIColor.systemYellow.cgColor
            } else {
                let index = btn.tag
                if index < keys.count && keys[index].colorStyle == "white" {
                    btn.layer.borderWidth = 1.0
                    btn.layer.borderColor = UIColor(white: 0.80, alpha: 1.0).cgColor
                } else {
                    btn.layer.borderWidth = 0.0
                }
            }
        }
    }

    // ============================================================
    // MARK: - CRUD Helpers
    // ============================================================

    func addQuickKey(label: String, keyCode: Int32, colorStyle: String) {
        let count = keys.count
        let col = count % 5
        let row = count / 5
        let defaultX = 0.05 + CGFloat(col) * 0.18
        let defaultY = 0.65 + CGFloat(row) * 0.08

        let newKey = DecadeQuickKey(
            id: UUID().uuidString,
            label: label,
            keyCode: keyCode,
            colorStyle: colorStyle,
            normX: min(0.85, defaultX),
            normY: min(0.90, defaultY),
            width: 48,
            height: 38
        )
        keys.append(newKey)
        saveKeys()
        rebuildButtons()
    }

    func updateQuickKey(index: Int, label: String, keyCode: Int32, colorStyle: String) {
        guard index < keys.count else { return }
        keys[index].label = label
        keys[index].keyCode = keyCode
        keys[index].colorStyle = colorStyle
        saveKeys()
        rebuildButtons()
    }

    func removeQuickKey(at index: Int) {
        guard index < keys.count else { return }
        keys.remove(at: index)
        saveKeys()
        rebuildButtons()
    }

    func removeAllKeys() {
        keys.removeAll()
        saveKeys()
        rebuildButtons()
    }

    var currentKeys: [DecadeQuickKey] { keys }
}

// ============================================================
// MARK: - Quick Key Manager Dialog
// ============================================================

class DecadeQuickKeysManager {

    static let availableKeyOptions: [(name: String, code: Int32)] = [
        ("Phím 1", 49),
        ("Phím 2 (Nhảy / Lên)", 50),
        ("Phím 3", 51),
        ("Phím 4 (Trái)", 52),
        ("Phím 5 (Đánh / Giữa)", 53),
        ("Phím 6 (Phải)", 54),
        ("Phím 7 (Bơm HP)", 55),
        ("Phím 8 (Xuống)", 56),
        ("Phím 9", 57),
        ("Phím 0", 48),
        ("Phím * (Sao)", 42),
        ("Phím # (Thăng)", 35),
        ("Mũi tên Lên (UP)", -1),
        ("Mũi tên Xuống (DOWN)", -2),
        ("Mũi tên Trái (LEFT)", -3),
        ("Mũi tên Phải (RIGHT)", -4),
        ("Phím Giữa / OK (FIRE)", -5),
        ("Phím Mềm Trái (L)", -6),
        ("Phím Mềm Phải (R)", -7),
        ("Phím Xóa (Clear)", -8),
    ]

    static let availableColorStyles: [(name: String, key: String)] = [
        ("Xanh lá mint (Mặc định)", "mint"),
        ("Xanh dương", "blue"),
        ("Tím lavender", "purple"),
        ("Cam rực rỡ", "orange"),
        ("Đỏ tươi", "red"),
        ("Thẻ trắng thanh lịch", "white"),
    ]

    static func safePresent(_ alert: UIAlertController, in presenter: UIViewController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(alert, animated: true)
    }

    static func showMainManager(in presenter: UIViewController,
                                overlayView: DecadeQuickKeysOverlayView,
                                onToast: ((String) -> Void)?) {

        let alert = UIAlertController(
            title: "⚡ Quản Lý Phím Nhanh",
            message: "Tùy biến các nút phím nhanh trên màn hình:",
            preferredStyle: .actionSheet
        )

        // 1. Thêm phím nhanh mới
        alert.addAction(UIAlertAction(title: "➕ Thêm phím nhanh mới", style: .default) { _ in
            promptAddQuickKey(in: presenter, overlayView: overlayView, onToast: onToast)
        })

        // 2. Chỉnh sửa phím nhanh
        if !overlayView.currentKeys.isEmpty {
            alert.addAction(UIAlertAction(title: "✏️ Chỉnh sửa phím (Đổi tên / Gán phím)", style: .default) { _ in
                promptSelectKeyToEdit(in: presenter, overlayView: overlayView, onToast: onToast)
            })

            // 3. Xóa phím nhanh
            alert.addAction(UIAlertAction(title: "🗑️ Xóa phím nhanh", style: .destructive) { _ in
                promptSelectKeyToDelete(in: presenter, overlayView: overlayView, onToast: onToast)
            })
        }

        // 4. Bật / Tắt chế độ kéo thả sắp xếp
        let arrangeTitle = overlayView.isEditMode ? "✓ Hoàn tất sắp xếp phím" : "✋ Sắp xếp vị trí phím (Kéo thả)"
        alert.addAction(UIAlertAction(title: arrangeTitle, style: .default) { _ in
            overlayView.isEditMode.toggle()
            let msg = overlayView.isEditMode ? "Chế độ kéo thả: Chạm và kéo các phím nhanh đến vị trí mong muốn" : "Đã lưu vị trí các phím nhanh"
            onToast?(msg)
        })

        // 5. Ẩn / Hiện cụm phím nhanh
        let isHidden = overlayView.isHidden
        alert.addAction(UIAlertAction(title: isHidden ? "👁️ Hiện cụm phím nhanh" : "👁️‍🗨️ Ẩn cụm phím nhanh", style: .default) { _ in
            overlayView.isHidden.toggle()
            UserDefaults.standard.set(overlayView.isHidden, forKey: "quick_keys_hidden_\(overlayView.gameId)")
            onToast?(overlayView.isHidden ? "Đã ẩn cụm phím nhanh" : "Đã hiện cụm phím nhanh")
        })

        // 6. Khôi phục mặc định
        alert.addAction(UIAlertAction(title: "🔄 Khôi phục phím nhanh mặc định", style: .default) { _ in
            overlayView.resetToDefaults()
            onToast?("Đã khôi phục 5 phím nhanh mặc định (1, 2, 3, 7, F)")
        })

        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        safePresent(alert, in: presenter)
    }

    // ============================================================
    // MARK: - Prompt Add Key
    // ============================================================

    private static func promptAddQuickKey(in presenter: UIViewController,
                                          overlayView: DecadeQuickKeysOverlayView,
                                          onToast: ((String) -> Void)?) {

        let alert = UIAlertController(title: "➕ Thêm Phím Nhanh Mới", message: "Nhập tên hiển thị trên phím:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Ví dụ: Skill 1, Bơm HP, Nhặt..."
            tf.autocorrectionType = .no
        }

        alert.addAction(UIAlertAction(title: "Tiếp tục chọn phím", style: .default) { [weak alert] _ in
            let label = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let finalLabel = label.isEmpty ? "Key" : label
            promptSelectKeyCode(in: presenter, label: finalLabel, overlayView: overlayView, onToast: onToast)
        })

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        safePresent(alert, in: presenter)
    }

    private static func promptSelectKeyCode(in presenter: UIViewController,
                                            label: String,
                                            overlayView: DecadeQuickKeysOverlayView,
                                            onToast: ((String) -> Void)?) {

        let sheet = UIAlertController(title: "Gán Phím J2ME Cho [\(label)]", message: "Chọn phím cần kích hoạt khi bấm:", preferredStyle: .actionSheet)

        for opt in availableKeyOptions {
            sheet.addAction(UIAlertAction(title: opt.name, style: .default) { _ in
                promptSelectColor(in: presenter, label: label, keyCode: opt.code, overlayView: overlayView, onToast: onToast)
            })
        }

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        safePresent(sheet, in: presenter)
    }

    private static func promptSelectColor(in presenter: UIViewController,
                                          label: String,
                                          keyCode: Int32,
                                          overlayView: DecadeQuickKeysOverlayView,
                                          onToast: ((String) -> Void)?) {

        let sheet = UIAlertController(title: "Chọn Màu Sắc Cho [\(label)]", message: nil, preferredStyle: .actionSheet)

        for col in availableColorStyles {
            sheet.addAction(UIAlertAction(title: col.name, style: .default) { _ in
                overlayView.addQuickKey(label: label, keyCode: keyCode, colorStyle: col.key)
                onToast?("Đã thêm phím nhanh: [\(label)]")
            })
        }

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        safePresent(sheet, in: presenter)
    }

    // ============================================================
    // MARK: - Prompt Edit Key
    // ============================================================

    private static func promptSelectKeyToEdit(in presenter: UIViewController,
                                              overlayView: DecadeQuickKeysOverlayView,
                                              onToast: ((String) -> Void)?) {

        let sheet = UIAlertController(title: "✏️ Chọn Phím Cần Chỉnh Sửa", message: nil, preferredStyle: .actionSheet)

        for (index, qk) in overlayView.currentKeys.enumerated() {
            let keyName = availableKeyOptions.first(where: { $0.code == qk.keyCode })?.name ?? "Mã \(qk.keyCode)"
            sheet.addAction(UIAlertAction(title: "[\(qk.label)] - \(keyName)", style: .default) { _ in
                promptEditKeyDetails(in: presenter, index: index, key: qk, overlayView: overlayView, onToast: onToast)
            })
        }

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        safePresent(sheet, in: presenter)
    }

    private static func promptEditKeyDetails(in presenter: UIViewController,
                                             index: Int,
                                             key: DecadeQuickKey,
                                             overlayView: DecadeQuickKeysOverlayView,
                                             onToast: ((String) -> Void)?) {

        let alert = UIAlertController(title: "Chỉnh Sửa Phím [\(key.label)]", message: "Đổi tên hiển thị:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = key.label
            tf.placeholder = "Tên hiển thị"
        }

        alert.addAction(UIAlertAction(title: "Đổi Phím / Màu", style: .default) { [weak alert] _ in
            let newLabel = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? key.label
            let finalLabel = newLabel.isEmpty ? key.label : newLabel

            let codeSheet = UIAlertController(title: "Chọn Phím J2ME Cho [\(finalLabel)]", message: nil, preferredStyle: .actionSheet)
            for opt in availableKeyOptions {
                codeSheet.addAction(UIAlertAction(title: opt.name, style: .default) { _ in
                    let colorSheet = UIAlertController(title: "Chọn Màu Cho [\(finalLabel)]", message: nil, preferredStyle: .actionSheet)
                    for col in availableColorStyles {
                        colorSheet.addAction(UIAlertAction(title: col.name, style: .default) { _ in
                            overlayView.updateQuickKey(index: index, label: finalLabel, keyCode: opt.code, colorStyle: col.key)
                            onToast?("Đã cập nhật phím: [\(finalLabel)]")
                        })
                    }
                    colorSheet.addAction(UIAlertAction(title: "Giữ màu cũ", style: .default) { _ in
                        overlayView.updateQuickKey(index: index, label: finalLabel, keyCode: opt.code, colorStyle: key.colorStyle)
                        onToast?("Đã cập nhật phím: [\(finalLabel)]")
                    })
                    colorSheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
                    safePresent(colorSheet, in: presenter)
                })
            }
            codeSheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            safePresent(codeSheet, in: presenter)
        })

        alert.addAction(UIAlertAction(title: "Chỉ đổi tên", style: .default) { [weak alert] _ in
            let newLabel = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? key.label
            let finalLabel = newLabel.isEmpty ? key.label : newLabel
            overlayView.updateQuickKey(index: index, label: finalLabel, keyCode: key.keyCode, colorStyle: key.colorStyle)
            onToast?("Đã đổi tên phím thành [\(finalLabel)]")
        })

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        safePresent(alert, in: presenter)
    }

    // ============================================================
    // MARK: - Prompt Delete Key
    // ============================================================

    private static func promptSelectKeyToDelete(in presenter: UIViewController,
                                                overlayView: DecadeQuickKeysOverlayView,
                                                onToast: ((String) -> Void)?) {

        let sheet = UIAlertController(title: "🗑️ Chọn Phím Cần Xóa", message: nil, preferredStyle: .actionSheet)

        for (index, qk) in overlayView.currentKeys.enumerated() {
            sheet.addAction(UIAlertAction(title: "Xóa [\(qk.label)]", style: .destructive) { _ in
                overlayView.removeQuickKey(at: index)
                onToast?("Đã xóa phím [\(qk.label)]")
            })
        }

        sheet.addAction(UIAlertAction(title: "Xóa TẤT CẢ phím nhanh", style: .destructive) { _ in
            overlayView.removeAllKeys()
            onToast?("Đã xóa toàn bộ phím nhanh")
        })

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        safePresent(sheet, in: presenter)
    }
}
