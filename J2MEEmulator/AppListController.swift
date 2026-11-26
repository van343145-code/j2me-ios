import UIKit
import UniformTypeIdentifiers

// MARK: - Exact 1:1 `GameCell` from `J2me.iOS.Ui.AppListController.GameCell`

@MainActor
final class NstGameCell: UITableViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var hasSubtitle = false

    init(reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupViews() {
        backgroundColor = NstTheme.Apk.background
        let selBg = UIView()
        selBg.backgroundColor = NstTheme.Lic.neutralSoft
        selectedBackgroundView = selBg

        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 11
        iconView.layer.borderWidth = 0.5
        iconView.layer.borderColor = UIColor.black.withAlphaComponent(0.08).cgColor
        iconView.backgroundColor = NstTheme.Lic.neutralSoft
        iconView.tintColor = NstTheme.Lic.accent

        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.textColor = NstTheme.Apk.text
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
    }

    func bind(title: String, subtitle: String?, icon: UIImage?, systemIconName: String? = nil) {
        titleLabel.text = title
        let sub = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasSubtitle = !sub.isEmpty
        subtitleLabel.text = sub
        subtitleLabel.isHidden = !hasSubtitle

        if let icon {
            iconView.contentMode = .scaleAspectFill
            iconView.image = icon
        } else {
            let sym = systemIconName ?? "gamecontroller.fill"
            let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            iconView.contentMode = .center
            iconView.image = UIImage(systemName: sym, withConfiguration: cfg)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        iconView.frame = CGRect(x: 16, y: (b.height - 46) * 0.5, width: 46, height: 46)

        let textW = max(0, b.width - 76 - 12)
        if hasSubtitle {
            titleLabel.frame = CGRect(x: 76, y: 11, width: textW, height: 24)
            subtitleLabel.frame = CGRect(x: 76, y: 36, width: textW, height: 16)
        } else {
            titleLabel.frame = CGRect(x: 76, y: 0, width: textW, height: b.height)
            subtitleLabel.frame = .zero
        }
    }
}

// MARK: - Exact 1:1 `AppListController` from `J2me.iOS.Ui.AppListController`

@MainActor
final class AppListController: UITableViewController, UIDocumentPickerDelegate {
    private enum Row {
        case product(CatalogProduct)
        case game(GameEntry)
        case addGame
    }

    private lazy var tabBarView = HomeTabBar { [weak self] tab in
        self?.selectTab(tab)
    }

    private var currentTab: HomeTab = NstLibrary.shared.currentTab
    private var rows: [Row] = []

    init() {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "J2ME NST"
        view.backgroundColor = NstTheme.Apk.background
        tableView.backgroundColor = NstTheme.Apk.background
        tableView.separatorColor = NstTheme.Apk.divider
        tableView.rowHeight = 64
        tableView.tableFooterView = UIView()
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        let addBtn = UIBarButtonItem(
            image: UIImage(systemName: "plus.square"),
            style: .plain,
            target: self,
            action: #selector(pickFile)
        )
        addBtn.accessibilityLabel = "Thêm game"
        addBtn.tintColor = NstTheme.Lic.accent
        navigationItem.rightBarButtonItem = addBtn

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        tableView.addGestureRecognizer(longPress)

        NstLibrary.shared.scanDocumentsDirectory()
        reloadData(animatedTab: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        NstLibrary.shared.reloadExternal()
        updateRunningIndicator()
        reloadData(animatedTab: false)
    }

    func showOwnTab() {
        selectTab(.own)
    }

    func handleExternalImport(_ urls: [URL]) {
        let outcome = NstLibrary.shared.importURLs(urls)
        if !outcome.installed.isEmpty {
            currentTab = .own
            NstLibrary.shared.saveHomeTab(.own)
            reloadData(animatedTab: true)

            var msg = "Đã cài \(outcome.installed.count) game:\n"
                + outcome.installed.map { "• \($0.name)" }.joined(separator: "\n")
            if !outcome.rejected.isEmpty {
                msg += "\n\nBỏ qua:\n" + outcome.rejected.map { "• \($0.0): \($0.1)" }.joined(separator: "\n")
            }
            let alert = UIAlertController(title: "Cài đặt thành công!", message: msg, preferredStyle: .alert)
            if outcome.installed.count == 1, let single = outcome.installed.first {
                alert.addAction(UIAlertAction(title: "Bắt đầu", style: .default) { [weak self] _ in
                    MicroController.open(game: single, from: self?.navigationController)
                })
            }
            alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
            present(alert, animated: true)
        } else if !outcome.rejected.isEmpty {
            let msg = outcome.rejected.map { "• \($0.0): \($0.1)" }.joined(separator: "\n")
            let alert = UIAlertController(title: "Không thêm được game", message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func selectTab(_ tab: HomeTab) {
        currentTab = tab
        NstLibrary.shared.saveHomeTab(tab)
        reloadData(animatedTab: true)
    }

    private func reloadData(animatedTab: Bool) {
        let lib = NstLibrary.shared
        switch currentTab {
        case .mod:
            rows = lib.products.map { .product($0) }
        case .own:
            var items: [Row] = lib.externalGames.map { .game($0) }
            items.append(.addGame)
            rows = items
        }
        tabBarView.bind(tab: currentTab, ownCount: lib.externalGames.count, animated: animatedTab)
        tableView.reloadData()
    }

    private func updateRunningIndicator() {
        let count = MicroController.activeSlotCount
        if count > 0 {
            let btn = UIButton(type: .system)
            btn.setTitle("▶ Đang chạy (\(count))", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            btn.setTitleColor(.black, for: .normal)
            btn.backgroundColor = NstTheme.Player.tabActive
            btn.layer.cornerRadius = 13
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            btn.addTarget(self, action: #selector(resumeRunningTapped), for: .touchUpInside)
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: btn)
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    @objc private func resumeRunningTapped() {
        MicroController.resume(from: navigationController)
    }

    @objc private func pickFile() {
        var types: [UTType] = [.zip, .archive, .data]
        if let jarType = UTType(filenameExtension: "jar") {
            types.insert(jarType, at: 0)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        handleExternalImport(urls)
    }

    // MARK: - Table DataSource & Delegate

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        HomeTabBar.barHeight
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        tabBarView
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = (tableView.dequeueReusableCell(withIdentifier: "game") as? NstGameCell)
            ?? NstGameCell(reuseIdentifier: "game")

        switch rows[indexPath.row] {
        case .product(let product):
            let img = NstLibrary.shared.productIcon(product.iconKey)
            cell.bind(title: product.name, subtitle: product.subtitle, icon: img)
            cell.accessoryType = .disclosureIndicator

        case .game(let entry):
            let img = NstLibrary.shared.icon(for: entry)
            let runningTag = MicroController.isRunning(gameId: entry.id) ? " · Đang chạy" : ""
            cell.bind(
                title: entry.name,
                subtitle: "\(entry.subtitle)\(runningTag)",
                icon: img,
                systemIconName: "gamecontroller.fill"
            )
            cell.accessoryType = .disclosureIndicator

        case .addGame:
            cell.bind(
                title: "Thêm game",
                subtitle: "Chọn file .jar hoặc .zip trong máy",
                icon: nil,
                systemIconName: "plus.square.dashed"
            )
            cell.accessoryType = .none
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .product(let product):
            let vc = VariantController(product: product)
            navigationController?.pushViewController(vc, animated: true)

        case .game(let entry):
            MicroController.open(game: entry, from: navigationController)

        case .addGame:
            pickFile()
        }
    }

    // MARK: - Long Press Context Menu (Exact J2ME NST options)

    @objc private func onLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let pt = gesture.location(in: tableView)
        guard let ip = tableView.indexPathForRow(at: pt) else { return }
        guard case .game(let entry) = rows[ip.row] else { return }

        let sheet = UIAlertController(title: entry.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Cài đặt", style: .default) { [weak self] _ in
            let cfgVC = ConfigController(game: entry, startAfter: true)
            self?.navigationController?.pushViewController(cfgVC, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Đổi tên", style: .default) { [weak self] _ in
            self?.promptRename(entry)
        })
        sheet.addAction(UIAlertAction(title: "Xóa dữ liệu chơi", style: .destructive) { [weak self] _ in
            self?.confirmAction(
                entry: entry,
                title: "Xóa dữ liệu",
                message: "Xóa toàn bộ dữ liệu chơi (save, RMS) của game này?",
                okTitle: "Xóa"
            ) {
                NstLibrary.shared.clearSaveData(for: entry)
            }
        })
        sheet.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            self?.confirmAction(
                entry: entry,
                title: "Xóa",
                message: "Bạn thực sự muốn xóa ứng dụng này?",
                okTitle: "Xóa"
            ) { [weak self] in
                NstLibrary.shared.deleteExternal(entry: entry)
                self?.reloadData(animatedTab: false)
            }
        })
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))

        if let pop = sheet.popoverPresentationController, let cell = tableView.cellForRow(at: ip) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    private func promptRename(_ entry: GameEntry) {
        let alert = UIAlertController(title: "Đổi tên", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = entry.name
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text else { return }
            NstLibrary.shared.rename(entry: entry, newName: name)
            self?.reloadData(animatedTab: false)
        })
        present(alert, animated: true)
    }

    private func confirmAction(
        entry: GameEntry,
        title: String,
        message: String,
        okTitle: String,
        action: @escaping () -> Void
    ) {
        if MicroController.isRunning(gameId: entry.id) {
            let alert = UIAlertController(
                title: "Thông báo",
                message: "Game đang chạy, hãy đóng game trước.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: okTitle, style: .destructive) { _ in action() })
        present(alert, animated: true)
    }
}
