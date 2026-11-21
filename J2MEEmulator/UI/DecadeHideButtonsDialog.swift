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
