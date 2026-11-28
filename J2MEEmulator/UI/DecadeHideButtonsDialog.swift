//
//  DecadeHideButtonsDialog.swift
//  J2MEEmulator
//
//  Hộp thoại Thêm / Xoá (Ẩn / Hiện) từng phím bấm 1, 2, 3... trên bàn phím ảo.
//

import UIKit

class DecadeHideButtonsDialog: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let gameId: String
    private let onApply: (Set<String>) -> Void

    // All customizable virtual keypad keys with display labels
    struct KeyOption {
        let id: String
        let displayName: String
    }

    private let keyOptions: [KeyOption] = [
        KeyOption(id: "1", displayName: "Phím số 1"),
        KeyOption(id: "2", displayName: "Phím số 2 (Lên / Nhảy)"),
        KeyOption(id: "3", displayName: "Phím số 3"),
        KeyOption(id: "4", displayName: "Phím số 4 (Trái)"),
        KeyOption(id: "5", displayName: "Phím số 5 (Đánh / Giữa)"),
        KeyOption(id: "6", displayName: "Phím số 6 (Phải)"),
        KeyOption(id: "7", displayName: "Phím số 7 (Bơm HP)"),
        KeyOption(id: "8", displayName: "Phím số 8 (Xuống)"),
        KeyOption(id: "9", displayName: "Phím số 9"),
        KeyOption(id: "0", displayName: "Phím số 0"),
        KeyOption(id: "*", displayName: "Phím sao (*)"),
        KeyOption(id: "#", displayName: "Phím thăng (#)"),
        KeyOption(id: "Del", displayName: "Phím xóa (Del)"),
        KeyOption(id: "/", displayName: "Phím gạch chéo (/)"),
        KeyOption(id: "L", displayName: "Phím mềm trái (L)"),
        KeyOption(id: "R", displayName: "Phím mềm phải (R)"),
        KeyOption(id: "OK", displayName: "Phím giữa (OK / FIRE)"),
        KeyOption(id: "↑", displayName: "Mũi tên Lên (↑)"),
        KeyOption(id: "↓", displayName: "Mũi tên Xuống (↓)"),
        KeyOption(id: "←", displayName: "Mũi tên Trái (←)"),
        KeyOption(id: "→", displayName: "Mũi tên Phải (→)"),
        KeyOption(id: "↖", displayName: "Phím chéo Lên-Trái (↖)"),
        KeyOption(id: "↗", displayName: "Phím chéo Lên-Phải (↗)"),
        KeyOption(id: "↙", displayName: "Phím chéo Xuống-Trái (↙)"),
        KeyOption(id: "↘", displayName: "Phím chéo Xuống-Phải (↘)")
    ]

    // Set of keys that are currently HIDDEN (ẩn/xóa khỏi bàn phím)
    private var hiddenKeys: Set<String>

    private let dialogView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(gameId: String, currentHiddenKeys: Set<String>, onApply: @escaping (Set<String>) -> Void) {
        self.gameId = gameId
        self.hiddenKeys = currentHiddenKeys
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(white: 0, alpha: 0.55)

        dialogView.backgroundColor = .white
        dialogView.layer.cornerRadius = 14
        dialogView.clipsToBounds = true
        dialogView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dialogView)

        let titleLabel = UILabel()
        titleLabel.text = "👁️ Thêm / Xóa Phím Ảo"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(titleLabel)

        let subLabel = UILabel()
        subLabel.text = "Tích chọn phím muốn HIỆN trên bàn phím:"
        subLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subLabel.textColor = .secondaryLabel
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(subLabel)

        // Action bar: [Hiện Tất Cả] [Ẩn Tất Cả]
        let btnShowAll = UIButton(type: .system)
        btnShowAll.setTitle("Hiện tất cả", for: .normal)
        btnShowAll.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btnShowAll.addTarget(self, action: #selector(showAllTapped), for: .touchUpInside)

        let btnHideAll = UIButton(type: .system)
        btnHideAll.setTitle("Xóa bớt", for: .normal)
        btnHideAll.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btnHideAll.setTitleColor(.systemRed, for: .normal)
        btnHideAll.addTarget(self, action: #selector(hideAllNumpadTapped), for: .touchUpInside)

        let quickStack = UIStackView(arrangedSubviews: [btnShowAll, btnHideAll])
        quickStack.axis = .horizontal
        quickStack.spacing = 16
        quickStack.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(quickStack)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .white
        tableView.separatorStyle = .singleLine
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(tableView)

        let btnCancel = UIButton(type: .system)
        btnCancel.setTitle("Hủy", for: .normal)
        btnCancel.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        btnCancel.setTitleColor(.secondaryLabel, for: .normal)
        btnCancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        btnCancel.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(btnCancel)

        let btnSave = UIButton(type: .system)
        btnSave.setTitle("Áp Dụng", for: .normal)
        btnSave.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        btnSave.setTitleColor(.white, for: .normal)
        btnSave.backgroundColor = UIColor(red: 0.12, green: 0.43, blue: 0.98, alpha: 1.0)
        btnSave.layer.cornerRadius = 8
        btnSave.contentEdgeInsets = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        btnSave.addTarget(self, action: #selector(okTapped), for: .touchUpInside)
        btnSave.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(btnSave)

        let screenH = UIScreen.main.bounds.height

        NSLayoutConstraint.activate([
            dialogView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dialogView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dialogView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.88),
            dialogView.heightAnchor.constraint(equalToConstant: min(560, screenH * 0.75)),

            titleLabel.topAnchor.constraint(equalTo: dialogView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor, constant: -18),

            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subLabel.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor, constant: 18),

            quickStack.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor, constant: -18),
            quickStack.centerYAnchor.constraint(equalTo: subLabel.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: btnSave.topAnchor, constant: -12),

            btnCancel.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor, constant: 20),
            btnCancel.bottomAnchor.constraint(equalTo: dialogView.bottomAnchor, constant: -14),
            btnCancel.heightAnchor.constraint(equalToConstant: 38),

            btnSave.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor, constant: -18),
            btnSave.bottomAnchor.constraint(equalTo: dialogView.bottomAnchor, constant: -14),
            btnSave.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    @objc private func showAllTapped() {
        hiddenKeys.removeAll()
        tableView.reloadData()
    }

    @objc private func hideAllNumpadTapped() {
        // Hide all 0-9 numpad keys (keeping arrows & OK)
        for k in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "#", "Del", "/"] {
            hiddenKeys.insert(k)
        }
        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func okTapped() {
        let key = "decade_hidden_keys_\(gameId)"
        UserDefaults.standard.set(Array(hiddenKeys), forKey: key)
        onApply(hiddenKeys)
        dismiss(animated: true)
    }

    // ============================================================
    // MARK: - TableView DataSource & Delegate
    // ============================================================

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return keyOptions.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 42
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "KeyCell")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "KeyCell")

        cell.backgroundColor = .white
        cell.selectionStyle = .none

        let opt = keyOptions[indexPath.row]
        let isHidden = hiddenKeys.contains(opt.id)

        // Checked = VISIBLE (HIỆN), Unchecked = HIDDEN (ẨN/XÓA)
        let isVisible = !isHidden
        let iconName = isVisible ? "checkmark.circle.fill" : "circle"
        let iconColor = isVisible ? UIColor(red: 0.12, green: 0.65, blue: 0.35, alpha: 1.0) : UIColor.systemGray3
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        cell.imageView?.image = UIImage(systemName: iconName, withConfiguration: config)
        cell.imageView?.tintColor = iconColor

        cell.textLabel?.text = "  " + opt.displayName
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: isVisible ? .medium : .regular)
        cell.textLabel?.textColor = isVisible ? .black : .secondaryLabel

        cell.detailTextLabel?.text = isVisible ? "Hiện" : "Đã xóa (Ẩn)"
        cell.detailTextLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        cell.detailTextLabel?.textColor = isVisible ? UIColor(red: 0.12, green: 0.65, blue: 0.35, alpha: 1.0) : .systemRed

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let opt = keyOptions[indexPath.row]
        if hiddenKeys.contains(opt.id) {
            hiddenKeys.remove(opt.id) // Unhide (Hiện lại / Thêm)
        } else {
            hiddenKeys.insert(opt.id) // Hide (Ẩn đi / Xóa)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}

// ============================================================
// MARK: - Unified All-in-One Keyboard Setup Controller
// ============================================================

enum DecadeKeyboardQuickAction {
    case arrangeKeys
    case resizeKeys
    case finishEditing
    case resetPositions
    case openNativeTextKeyboard
    case openTextInputDialog
}

final class DecadeKeyboardSetupViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let gameId: String
    private let legacyGameId: String?
    private let inGame: Bool
    private let isCurrentlyEditing: Bool
    private let isCurrentlyResizing: Bool
    private let onChanged: (() -> Void)?
    private let onAction: ((DecadeKeyboardQuickAction) -> Void)?

    private struct KeyOption {
        let id: String
        let title: String
    }

    private let keyOptions: [KeyOption] = [
        KeyOption(id: "1", title: "Phím số 1"),
        KeyOption(id: "2", title: "Phím số 2 (Lên / Nhảy)"),
        KeyOption(id: "3", title: "Phím số 3"),
        KeyOption(id: "4", title: "Phím số 4 (Trái)"),
        KeyOption(id: "5", title: "Phím số 5 (Đánh / Giữa)"),
        KeyOption(id: "6", title: "Phím số 6 (Phải)"),
        KeyOption(id: "7", title: "Phím số 7 (Bơm HP)"),
        KeyOption(id: "8", title: "Phím số 8 (Xuống)"),
        KeyOption(id: "9", title: "Phím số 9"),
        KeyOption(id: "0", title: "Phím số 0"),
        KeyOption(id: "*", title: "Phím sao (*)"),
        KeyOption(id: "#", title: "Phím thăng (#)"),
        KeyOption(id: "Del", title: "Phím xóa (Del)"),
        KeyOption(id: "/", title: "Phím gạch chéo (/)"),
        KeyOption(id: "L", title: "Phím mềm trái (L)"),
        KeyOption(id: "R", title: "Phím mềm phải (R)"),
        KeyOption(id: "OK", title: "Phím giữa (OK / FIRE)"),
        KeyOption(id: "↑", title: "Mũi tên Lên (↑)"),
        KeyOption(id: "↓", title: "Mũi tên Xuống (↓)"),
        KeyOption(id: "←", title: "Mũi tên Trái (←)"),
        KeyOption(id: "→", title: "Mũi tên Phải (→)"),
        KeyOption(id: "↖", title: "Phím chéo Lên-Trái (↖)"),
        KeyOption(id: "↗", title: "Phím chéo Lên-Phải (↗)"),
        KeyOption(id: "↙", title: "Phím chéo Xuống-Trái (↙)"),
        KeyOption(id: "↘", title: "Phím chéo Xuống-Phải (↘)")
    ]

    private let heightPresets: [(label: String, value: CGFloat)] = [
        ("Nhỏ", 210),
        ("Vừa", 245),
        ("Chuẩn", 280),
        ("Lớn", 320)
    ]

    private let alphaPresets: [(label: String, value: Float)] = [
        ("Mờ 40%", 102),
        ("Vừa 70%", 179),
        ("Rõ 100%", 255)
    ]

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let visibleSwitch = UISwitch()
    private let layoutSegment = UISegmentedControl(items: ["Tuổi Thơ", "Mũi Tên", "Số", "Kết Hợp"])
    private let heightSegment = UISegmentedControl(items: ["Nhỏ", "Vừa", "Chuẩn", "Lớn"])
    private let alphaSegment = UISegmentedControl(items: ["Mờ 40%", "Vừa 70%", "Rõ 100%"])

    private var isKeypadVisible: Bool = true
    private var selectedLayout: Int = 0
    private var selectedHeightIdx: Int = 2
    private var selectedAlphaIdx: Int = 2
    private var hiddenKeys: Set<String> = []

    init(gameId: String,
         legacyGameId: String? = nil,
         inGame: Bool,
         isCurrentlyEditing: Bool = false,
         isCurrentlyResizing: Bool = false,
         onChanged: (() -> Void)? = nil,
         onAction: ((DecadeKeyboardQuickAction) -> Void)? = nil) {
        self.gameId = gameId
        self.legacyGameId = legacyGameId
        self.inGame = inGame
        self.isCurrentlyEditing = isCurrentlyEditing
        self.isCurrentlyResizing = isCurrentlyResizing
        self.onChanged = onChanged
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        title = "Setup Bàn Phím"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Xong",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )

        loadState()
        configureControls()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadState() {
        let d = UserDefaults.standard
        let hidden = d.bool(forKey: "keypad_hidden_\(gameId)")
        isKeypadVisible = !hidden

        selectedLayout = (d.object(forKey: "keypad_layout_\(gameId)") as? Int)
            ?? (legacyGameId.flatMap { d.object(forKey: "keypad_layout_\($0)") as? Int })
            ?? 0
        if selectedLayout < 0 || selectedLayout > 3 { selectedLayout = 0 }

        let savedH = CGFloat((d.object(forKey: "keypad_height_\(gameId)") as? Double)
            ?? (legacyGameId.flatMap { d.object(forKey: "keypad_height_\($0)") as? Double })
            ?? 280.0)
        selectedHeightIdx = heightPresets.enumerated().min(by: {
            abs($0.element.value - savedH) < abs($1.element.value - savedH)
        })?.offset ?? 2

        let savedAlpha = (d.object(forKey: "keypad_alpha_\(gameId)") as? Float)
            ?? (legacyGameId.flatMap { d.object(forKey: "keypad_alpha_\($0)") as? Float })
            ?? 255.0
        selectedAlphaIdx = alphaPresets.enumerated().min(by: {
            abs($0.element.value - savedAlpha) < abs($1.element.value - savedAlpha)
        })?.offset ?? 2

        if let savedKeys = d.stringArray(forKey: "decade_hidden_keys_\(gameId)") {
            hiddenKeys = Set(savedKeys)
        } else {
            hiddenKeys = []
        }
    }

    private func saveAll() {
        let d = UserDefaults.standard
        d.set(!isKeypadVisible, forKey: "keypad_hidden_\(gameId)")
        d.set(selectedLayout, forKey: "keypad_layout_\(gameId)")
        d.set(Double(heightPresets[selectedHeightIdx].value), forKey: "keypad_height_\(gameId)")
        d.set(alphaPresets[selectedAlphaIdx].value, forKey: "keypad_alpha_\(gameId)")
        d.set(Array(hiddenKeys), forKey: "decade_hidden_keys_\(gameId)")

        if let leg = legacyGameId, !leg.isEmpty {
            d.set(!isKeypadVisible, forKey: "keypad_hidden_\(leg)")
            d.set(selectedLayout, forKey: "keypad_layout_\(leg)")
            d.set(Double(heightPresets[selectedHeightIdx].value), forKey: "keypad_height_\(leg)")
            d.set(alphaPresets[selectedAlphaIdx].value, forKey: "keypad_alpha_\(leg)")
        }
        onChanged?()
    }

    private func configureControls() {
        visibleSwitch.isOn = isKeypadVisible
        visibleSwitch.onTintColor = UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0)
        visibleSwitch.addTarget(self, action: #selector(visibilityChanged), for: .valueChanged)

        layoutSegment.selectedSegmentIndex = selectedLayout
        layoutSegment.addTarget(self, action: #selector(layoutChanged), for: .valueChanged)

        heightSegment.selectedSegmentIndex = selectedHeightIdx
        heightSegment.addTarget(self, action: #selector(heightChanged), for: .valueChanged)

        alphaSegment.selectedSegmentIndex = selectedAlphaIdx
        alphaSegment.addTarget(self, action: #selector(alphaChanged), for: .valueChanged)
    }

    @objc private func visibilityChanged() {
        isKeypadVisible = visibleSwitch.isOn
        saveAll()
    }

    @objc private func layoutChanged() {
        selectedLayout = layoutSegment.selectedSegmentIndex
        saveAll()
    }

    @objc private func heightChanged() {
        selectedHeightIdx = heightSegment.selectedSegmentIndex
        saveAll()
    }

    @objc private func alphaChanged() {
        selectedAlphaIdx = alphaSegment.selectedSegmentIndex
        saveAll()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func showAllKeysTapped() {
        hiddenKeys.removeAll()
        saveAll()
        tableView.reloadSections(IndexSet(integer: keysSectionIndex), with: .none)
    }

    @objc private func hideNumpadKeysTapped() {
        for k in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "#", "Del", "/"] {
            hiddenKeys.insert(k)
        }
        saveAll()
        tableView.reloadSections(IndexSet(integer: keysSectionIndex), with: .none)
    }

    private var keysSectionIndex: Int { inGame ? 3 : 2 }

    // MARK: - UITableViewDataSource / Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return inGame ? 4 : 3
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Hiển Thị & Kiểu Bàn Phím"
        case 1: return "Kích Cỡ & Độ Mờ"
        case 2: return inGame ? "Sắp Xếp & Gõ Chữ" : "Ẩn / Hiện Từng Phím Bấm"
        default: return "Ẩn / Hiện Từng Phím Bấm"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 2 }
        if section == 1 { return 2 }
        if inGame && section == 2 {
            var count = 5 // Kéo thả, Thu phóng, Mặc định, QWERTY, Nhập nhanh IME
            if isCurrentlyEditing || isCurrentlyResizing { count += 1 }
            return count
        }
        return keyOptions.count + 1 // +1 quick toggle bar row
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 && indexPath.row == 1 { return 58 }
        if indexPath.section == 1 { return 58 }
        return 46
    }

    private func embedControlRow(_ cell: UITableViewCell, title: String, control: UIView) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        control.removeFromSuperview()
        cell.selectionStyle = .none
        cell.accessoryType = .none

        let lbl = UILabel()
        lbl.text = title
        lbl.font = .systemFont(ofSize: 13, weight: .semibold)
        lbl.textColor = .secondaryLabel
        lbl.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(lbl)
        cell.contentView.addSubview(control)

        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
            lbl.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),

            control.topAnchor.constraint(equalTo: lbl.bottomAnchor, constant: 4),
            control.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            control.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            control.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .default

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.selectionStyle = .none
                cell.imageView?.image = UIImage(systemName: "keyboard")
                cell.imageView?.tintColor = UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0)
                cell.textLabel?.text = "Hiện bàn phím ảo"
                cell.textLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
                cell.accessoryView = visibleSwitch
                return cell
            } else {
                embedControlRow(cell, title: "Kiểu bố cục bàn phím", control: layoutSegment)
                return cell
            }
        }

        if indexPath.section == 1 {
            if indexPath.row == 0 {
                embedControlRow(cell, title: "Chiều cao bàn phím", control: heightSegment)
            } else {
                embedControlRow(cell, title: "Độ trong suốt phím", control: alphaSegment)
            }
            return cell
        }

        if inGame && indexPath.section == 2 {
            var actions: [(icon: String, color: UIColor, title: String, action: DecadeKeyboardQuickAction)] = []
            if isCurrentlyEditing || isCurrentlyResizing {
                actions.append(("checkmark.circle.fill", .systemGreen, "Xong chế độ sửa vị trí / cỡ phím", .finishEditing))
            }
            actions.append(("arrow.up.and.down.and.arrow.left.and.right", UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0), "Kéo thả di chuyển từng phím", .arrangeKeys))
            actions.append(("arrow.up.left.and.arrow.down.right", UIColor(red: 0.12, green: 0.46, blue: 0.88, alpha: 1.0), "Thu phóng cỡ từng phím (2 ngón)", .resizeKeys))
            actions.append(("arrow.counterclockwise", .systemOrange, "Khôi phục vị trí phím mặc định", .resetPositions))
            actions.append(("keyboard.badge.ellipsis", UIColor(red: 0.12, green: 0.58, blue: 0.95, alpha: 1.0), "Bật bàn phím gõ chữ QWERTY (Chat)", .openNativeTextKeyboard))
            actions.append(("character.cursor.ibeam", UIColor(red: 0.45, green: 0.32, blue: 0.78, alpha: 1.0), "Nhập văn bản nhanh (Dán / Gửi)", .openTextInputDialog))

            let item = actions[indexPath.row]
            cell.imageView?.image = UIImage(systemName: item.icon)
            cell.imageView?.tintColor = item.color
            cell.textLabel?.text = item.title
            cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            cell.accessoryType = .disclosureIndicator
            return cell
        }

        // Key visibility section
        if indexPath.row == 0 {
            cell.selectionStyle = .none
            let btnShowAll = UIButton(type: .system)
            btnShowAll.setTitle("✓ Hiện tất cả phím", for: .normal)
            btnShowAll.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            btnShowAll.addTarget(self, action: #selector(showAllKeysTapped), for: .touchUpInside)

            let btnHideNums = UIButton(type: .system)
            btnHideNums.setTitle("Ẩn bớt phím số", for: .normal)
            btnHideNums.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            btnHideNums.setTitleColor(.systemRed, for: .normal)
            btnHideNums.addTarget(self, action: #selector(hideNumpadKeysTapped), for: .touchUpInside)

            let stack = UIStackView(arrangedSubviews: [btnShowAll, btnHideNums])
            stack.axis = .horizontal
            stack.distribution = .fillEqually
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -8)
            ])
            return cell
        }

        let opt = keyOptions[indexPath.row - 1]
        let isVisible = !hiddenKeys.contains(opt.id)
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        cell.imageView?.image = UIImage(systemName: isVisible ? "checkmark.circle.fill" : "circle", withConfiguration: config)
        cell.imageView?.tintColor = isVisible ? UIColor(red: 0.12, green: 0.65, blue: 0.35, alpha: 1.0) : .systemGray3
        cell.textLabel?.text = opt.title
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: isVisible ? .medium : .regular)
        cell.textLabel?.textColor = isVisible ? .label : .secondaryLabel
        cell.detailTextLabel?.text = isVisible ? "Hiện" : "Ẩn"
        cell.detailTextLabel?.textColor = isVisible ? UIColor(red: 0.12, green: 0.65, blue: 0.35, alpha: 1.0) : .systemRed
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if inGame && indexPath.section == 2 {
            var actions: [DecadeKeyboardQuickAction] = []
            if isCurrentlyEditing || isCurrentlyResizing {
                actions.append(.finishEditing)
            }
            actions.append(contentsOf: [.arrangeKeys, .resizeKeys, .resetPositions, .openNativeTextKeyboard, .openTextInputDialog])
            let chosen = actions[indexPath.row]
            dismiss(animated: true) { [onAction] in
                onAction?(chosen)
            }
            return
        }

        if indexPath.section == keysSectionIndex && indexPath.row > 0 {
            let opt = keyOptions[indexPath.row - 1]
            if hiddenKeys.contains(opt.id) {
                hiddenKeys.remove(opt.id)
            } else {
                hiddenKeys.insert(opt.id)
            }
            saveAll()
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
}
