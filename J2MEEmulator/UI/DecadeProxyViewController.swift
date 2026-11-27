//
//  DecadeProxyViewController.swift
//  J2MEEmulator
//
//  1:1 Replica of Decade APK "Quản lý Proxy" & "Gán proxy cho tab":
//  - Danh Sách Proxy: CRUD, SOCKS5 & HTTP, Bulk Import, Test Latency
//  - Gán Proxy Cho Tab: Gán proxy cho từng tab game bên trong theo từng tab độc lập:
//    Tab 1 - 1 (Ký hiệu: a), Tab 1 - 2 (Ký hiệu: b)... Tab 1 - 27 (Ký hiệu: aa)
//    Tab 2 - Avatar (Ký hiệu: a)
//    Tích chọn [✓] tab nào thì proxy được gán trực tiếp cho tab đó!
//

import UIKit

class DecadeProxyViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let segmentedControl = UISegmentedControl(items: ["Danh Sách Proxy", "Gán Proxy Cho Tab"])
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Current proxy selected for quick-ticking tabs (nil = direct/no proxy)
    private var selectedProxyId: Int? = nil
    private weak var headerSelectorBtn: UIButton?

    // Initial segment to show
    var initialSegmentIndex: Int = 0

    private var proxies: [ProxyItem] {
        return DecadeProxyManager.shared.proxies
    }

    // List of independent sessions currently running
    private var independentSessions: [(slot: Int, appName: String, jarPath: String?, tabs: [MidletTab])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        title = "Quản lý Proxy"
        view.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)

        setupNavBar()
        setupUI()
        loadData()

        if initialSegmentIndex > 0 {
            segmentedControl.selectedSegmentIndex = initialSegmentIndex
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
        tableView.reloadData()
    }

    private func loadData() {
        DecadeProxyManager.shared.loadProxies()

        // Default selected proxy to first available
        if selectedProxyId == nil, let first = proxies.first {
            selectedProxyId = first.id
        }

        // Build list of running independent tabs (Màn 1, Màn 2...)
        independentSessions.removeAll()

        if let gvc = activeGameViewController, !gvc.tabSessions.isEmpty {
            for session in gvc.tabSessions {
                let tabs = MidletTabs.read(from: session.jarPath, appName: session.appName)
                independentSessions.append((slot: session.slotIndex, appName: session.appName, jarPath: session.jarPath, tabs: tabs))
            }
        } else {
            // Fallback if not inside GameViewController
            let jar = activeGameViewController?.jarPath
            let name = activeGameViewController?.appName ?? "Game"
            let tabs = MidletTabs.read(from: jar, appName: name)
            independentSessions.append((slot: 0, appName: name, jarPath: jar, tabs: tabs))
        }
    }

    private func setupNavBar() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 18, weight: .bold)]
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = .white

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Đóng", style: .plain, target: self, action: #selector(closeTapped))

        let addBtn = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addProxyTapped))
        let importBtn = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.down"), style: .plain, target: self, action: #selector(bulkImportTapped))
        navigationItem.rightBarButtonItems = [addBtn, importBtn]
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func setupUI() {
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.backgroundColor = UIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1.0)
        segmentedControl.selectedSegmentTintColor = UIColor(red: 0.18, green: 0.50, blue: 0.95, alpha: 1.0)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 14, weight: .bold)
        ], for: .selected)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1.0),
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ], for: .normal)
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
        tableView.separatorColor = UIColor(red: 0.22, green: 0.26, blue: 0.35, alpha: 1.0)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProxyCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TabCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            segmentedControl.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func segmentChanged() {
        tableView.reloadData()
    }

    // MARK: - Proxy CRUD

    @objc private func addProxyTapped() {
        let alert = UIAlertController(title: "Thêm Proxy Mới", message: "Nhập thông tin máy chủ proxy:", preferredStyle: .alert)
        alert.addTextField { tf in tf.placeholder = "IP / Tên miền (Host)" }
        alert.addTextField { tf in tf.placeholder = "Cổng (Port, vd: 1080 / 8080)"; tf.keyboardType = .numberPad }
        alert.addTextField { tf in tf.placeholder = "Tài khoản (Tùy chọn)" }
        alert.addTextField { tf in tf.placeholder = "Mật khẩu (Tùy chọn)"; tf.isSecureTextEntry = true }

        let socksAction = UIAlertAction(title: "Loại: SOCKS5", style: .default) { [weak self, weak alert] _ in
            self?.handleSaveProxy(alert: alert, type: "socks5")
        }
        let httpAction = UIAlertAction(title: "Loại: HTTP", style: .default) { [weak self, weak alert] _ in
            self?.handleSaveProxy(alert: alert, type: "http")
        }

        alert.addAction(socksAction)
        alert.addAction(httpAction)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    private func handleSaveProxy(alert: UIAlertController?, type: String) {
        guard let fields = alert?.textFields,
              let host = fields[0].text?.trimmingCharacters(in: .whitespaces), !host.isEmpty,
              let portStr = fields[1].text?.trimmingCharacters(in: .whitespaces), let port = Int(portStr) else {
            return
        }
        let user = fields[2].text?.trimmingCharacters(in: .whitespaces) ?? ""
        let pass = fields[3].text ?? ""

        let newProxy = DecadeProxyManager.shared.addProxy(type: type, host: host, port: port, user: user, pass: pass)
        selectedProxyId = newProxy.id
        loadData()
        tableView.reloadData()
    }

    @objc private func bulkImportTapped() {
        let alert = UIAlertController(
            title: "Nhập Proxy Hàng Loạt",
            message: "Dán danh sách proxy theo định dạng:\nhost:port hoặc host:port:user:pass (mỗi dòng 1 proxy)",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Dán proxy tại đây..."
        }
        alert.addAction(UIAlertAction(title: "Nhập SOCKS5", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            let count = DecadeProxyManager.shared.importProxies(text: text, defaultType: "socks5")
            self?.loadData()
            self?.tableView.reloadData()
            self?.showToast("Đã nhập thành công \(count) proxy SOCKS5!")
        })
        alert.addAction(UIAlertAction(title: "Nhập HTTP", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            let count = DecadeProxyManager.shared.importProxies(text: text, defaultType: "http")
            self?.loadData()
            self?.tableView.reloadData()
            self?.showToast("Đã nhập thành công \(count) proxy HTTP!")
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let toast = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(toast, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { toast.dismiss(animated: true) }
    }

    // MARK: - TableView Header View for Tab Assignment

    private func updateTabAssignmentHeader() {
        guard let btn = headerSelectorBtn else { return }
        let curProxy = proxies.first(where: { $0.id == selectedProxyId })
        let btnTitle: String
        if let p = curProxy {
            btnTitle = "⚡ \(p.displayTitle) (\(p.type.uppercased()))  ▼"
        } else {
            btnTitle = "🚫 Không dùng proxy (Mạng trực tiếp)  ▼"
        }
        btn.setTitle(btnTitle, for: .normal)
    }

    private func makeTabAssignmentHeaderView() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 90))
        container.backgroundColor = .clear

        let card = UIView()
        card.backgroundColor = UIColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1.0)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.28, green: 0.35, blue: 0.46, alpha: 1.0).cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.2
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 4
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        // Title row
        let titleLabel = UILabel()
        titleLabel.text = "Proxy đang chọn để gán (Tích tab để gán):"
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1.0)
        stack.addArrangedSubview(titleLabel)

        // Selector Button
        let selectorBtn = UIButton(type: .system)
        selectorBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        selectorBtn.contentHorizontalAlignment = .left
        selectorBtn.backgroundColor = UIColor(red: 0.12, green: 0.22, blue: 0.38, alpha: 1.0)
        selectorBtn.layer.cornerRadius = 8
        selectorBtn.layer.borderWidth = 1
        selectorBtn.layer.borderColor = UIColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 0.7).cgColor
        selectorBtn.setTitleColor(.white, for: .normal)
        selectorBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        selectorBtn.addTarget(self, action: #selector(showProxyPickerDropdown), for: .touchUpInside)
        self.headerSelectorBtn = selectorBtn
        updateTabAssignmentHeader()
        stack.addArrangedSubview(selectorBtn)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])

        return container
    }

    @objc private func showProxyPickerDropdown() {
        let sheet = UIAlertController(
            title: "Chọn Proxy Cần Gán",
            message: "Sau khi chọn, bấm vào các tab game bên dưới để gán proxy này cho các tab đó:",
            preferredStyle: .actionSheet
        )

        for p in proxies {
            let isCurrent = (p.id == selectedProxyId)
            let mark = isCurrent ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: "\(mark)⚡ \(p.displayTitle) (\(p.type.uppercased()))", style: .default) { [weak self] _ in
                self?.selectedProxyId = p.id
                self?.updateTabAssignmentHeader()
                self?.tableView.reloadData()
            })
        }

        let isDirect = (selectedProxyId == nil)
        sheet.addAction(UIAlertAction(title: "\(isDirect ? "✓ " : "")🚫 Không dùng proxy (Trực tiếp)", style: .destructive) { [weak self] _ in
            self?.selectedProxyId = nil
            self?.updateTabAssignmentHeader()
            self?.tableView.reloadData()
        })

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: - TableView DataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        if segmentedControl.selectedSegmentIndex == 0 {
            tableView.tableHeaderView = nil
            return 1
        } else {
            tableView.tableHeaderView = makeTabAssignmentHeaderView()
            return independentSessions.count
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if segmentedControl.selectedSegmentIndex == 0 {
            return proxies.count
        } else {
            guard section < independentSessions.count else { return 0 }
            return independentSessions[section].tabs.count
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title: String?
        if segmentedControl.selectedSegmentIndex == 0 {
            title = "DANH SÁCH PROXY ĐÃ LƯU (\(proxies.count))"
        } else {
            guard section < independentSessions.count else { return nil }
            let s = independentSessions[section]
            title = "TAB ĐỘC LẬP \(s.slot + 1): \(s.appName) (\(s.tabs.count) TAB CON)"
        }
        guard let t = title else { return nil }

        let container = UIView()
        let label = UILabel()
        label.text = t
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 34
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        if segmentedControl.selectedSegmentIndex == 1 && section == independentSessions.count - 1 {
            let container = UIView()
            let label = UILabel()
            label.text = "Chạm vào tab nào để tích [✓] gán proxy đang chọn cho tab đó. Bấm lại để bỏ gán."
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = UIColor(red: 0.80, green: 0.85, blue: 0.95, alpha: 1.0)
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            ])
            return container
        }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if segmentedControl.selectedSegmentIndex == 0 {
            // Segment 0: Proxy list
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProxyCell", for: indexPath)
            cell.backgroundColor = UIColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1.0)
            let item = proxies[indexPath.row]

            var config = cell.defaultContentConfiguration()
            config.text = item.displayTitle
            config.textProperties.color = .white
            config.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
            config.secondaryText = item.displaySubtitle
            config.secondaryTextProperties.font = .systemFont(ofSize: 13, weight: .medium)
            config.secondaryTextProperties.color = UIColor(red: 0.82, green: 0.86, blue: 0.95, alpha: 1.0)
            config.image = UIImage(systemName: item.isSocks5 ? "lock.shield.fill" : "network")
            config.imageProperties.tintColor = item.isSocks5 ? UIColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 1.0) : UIColor(red: 0.30, green: 0.88, blue: 0.50, alpha: 1.0)

            cell.contentConfiguration = config
            cell.accessoryType = .detailDisclosureButton
            cell.tintColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1.0)
            return cell

        } else {
            // Segment 1: Per-game-tab proxy assignment
            let cell = tableView.dequeueReusableCell(withIdentifier: "TabCell", for: indexPath)
            cell.backgroundColor = UIColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1.0)
            let session = independentSessions[indexPath.section]
            let tab = session.tabs[indexPath.row]
            let slotIndex = session.slot

            // Format tab title: "Tab 1 - 1 (Ký hiệu: a)" or "Tab 2 - Avatar (Ký hiệu: a)"
            let displayTitle = "Tab \(slotIndex + 1) - \(tab.name)  (Ký hiệu: \(tab.prefix))"
            let assignedProxy = DecadeProxyManager.shared.proxyForTab(appId: session.appName, slot: slotIndex, tabPrefix: tab.prefix)

            // Is this tab currently assigned to the selected proxy?
            let isSelectedForCurrentProxy: Bool
            if let targetPid = selectedProxyId {
                isSelectedForCurrentProxy = (assignedProxy?.id == targetPid)
            } else {
                isSelectedForCurrentProxy = (assignedProxy == nil)
            }

            var config = cell.defaultContentConfiguration()
            config.text = displayTitle
            config.textProperties.color = .white
            config.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)

            if let p = assignedProxy {
                config.secondaryText = "⚡ Đang dùng: \(p.displayTitle) (\(p.type.uppercased()))"
                config.secondaryTextProperties.color = UIColor(red: 0.35, green: 0.90, blue: 0.55, alpha: 1.0)
            } else {
                config.secondaryText = "🚫 Mạng trực tiếp (Không dùng proxy)"
                config.secondaryTextProperties.color = UIColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
            }
            config.secondaryTextProperties.font = .systemFont(ofSize: 13, weight: .medium)

            // Visual Checkbox (Checkmark / Circle)
            if isSelectedForCurrentProxy {
                config.image = UIImage(systemName: "checkmark.circle.fill")
                config.imageProperties.tintColor = (selectedProxyId != nil)
                    ? UIColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
                    : UIColor(white: 0.80, alpha: 1.0)
            } else {
                config.image = UIImage(systemName: "circle")
                config.imageProperties.tintColor = UIColor(white: 0.60, alpha: 1.0)
            }

            cell.contentConfiguration = config
            cell.accessoryType = .none
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if segmentedControl.selectedSegmentIndex == 0 {
            // Test latency
            let item = proxies[indexPath.row]
            showTestingIndicator(for: item)
        } else {
            // Toggle proxy assignment for this game tab
            let session = independentSessions[indexPath.section]
            let tab = session.tabs[indexPath.row]
            let slotIndex = session.slot

            let currentlyAssigned = DecadeProxyManager.shared.proxyForTab(appId: session.appName, slot: slotIndex, tabPrefix: tab.prefix)

            let isAlreadyUsingSelected: Bool
            if let targetPid = selectedProxyId {
                isAlreadyUsingSelected = (currentlyAssigned?.id == targetPid)
            } else {
                isAlreadyUsingSelected = (currentlyAssigned == nil)
            }

            if isAlreadyUsingSelected {
                // Unassign (back to direct)
                DecadeProxyManager.shared.assignTab(appId: session.appName, slot: slotIndex, tabPrefix: tab.prefix, proxyId: nil)
            } else {
                // Assign selected proxy
                DecadeProxyManager.shared.assignTab(appId: session.appName, slot: slotIndex, tabPrefix: tab.prefix, proxyId: selectedProxyId)
            }

            // Disconnect active socket to apply immediately in game
            DecadeProxyManager.shared.disconnectActiveSockets(for: slotIndex)

            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    // MARK: - Testing Proxy Latency

    private func showTestingIndicator(for item: ProxyItem) {
        let alert = UIAlertController(title: "Đang kiểm tra...", message: "Đang đo độ trễ tới \(item.displayTitle)...", preferredStyle: .alert)
        present(alert, animated: true)

        DecadeProxyManager.shared.testProxy(item: item) { [weak self, weak alert] success, latencyMs, error in
            alert?.dismiss(animated: true) {
                self?.tableView.reloadData()
                let resultTitle = success ? "Kết nối thành công" : "Kết nối thất bại"
                let resultMsg = success ? "Độ trễ: \(latencyMs ?? 0) ms" : (error ?? "Không thể kết nối tới proxy")
                let resAlert = UIAlertController(title: resultTitle, message: resultMsg, preferredStyle: .alert)
                resAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(resAlert, animated: true)
            }
        }
    }

    // MARK: - Delete Proxy

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if segmentedControl.selectedSegmentIndex == 0 && editingStyle == .delete {
            let item = proxies[indexPath.row]
            DecadeProxyManager.shared.deleteProxy(id: item.id)
            if selectedProxyId == item.id {
                selectedProxyId = proxies.first?.id
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
}
