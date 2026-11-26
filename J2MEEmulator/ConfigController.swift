import UIKit

/// Exact 1:1 port of `J2me.iOS.Ui.ConfigController` (`Màn hình` & `Nhập liệu`, `Bắt đầu` / `Lưu`, `Đặt lại thiết lập`).
@MainActor
final class ConfigController: UITableViewController {
    private enum RowKind {
        case number(title: String, get: () -> Int, set: (Int) -> Void, min: Int, max: Int)
        case toggle(title: String, get: () -> Bool, set: (Bool) -> Void)
    }

    private let game: GameEntry
    private let startAfter: Bool
    private let onSaved: ((GameConfig) -> Void)?
    private var cfg: GameConfig
    private var sections: [(header: String, rows: [RowKind])] = []

    init(game: GameEntry, startAfter: Bool, onSaved: ((GameConfig) -> Void)? = nil) {
        self.game = game
        self.startAfter = startAfter
        self.onSaved = onSaved
        self.cfg = NstLibrary.shared.loadConfig(for: game.id)
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = game.name
        view.backgroundColor = NstTheme.Lic.page
        tableView.backgroundColor = NstTheme.Lic.page

        let saveTitle = startAfter ? "Bắt đầu" : "Lưu"
        let saveBtn = UIBarButtonItem(title: saveTitle, style: .done, target: self, action: #selector(saveTapped))
        saveBtn.tintColor = NstTheme.Lic.accent

        let moreBtn = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )
        moreBtn.tintColor = NstTheme.Lic.accent
        navigationItem.rightBarButtonItems = [saveBtn, moreBtn]

        buildSections()
    }

    private func buildSections() {
        sections = [
            (
                header: "Màn hình",
                rows: [
                    .number(
                        title: "Giới hạn FPS (0 = không giới hạn)",
                        get: { [weak self] in self?.cfg.fpsLimit ?? 30 },
                        set: { [weak self] v in self?.cfg.fpsLimit = v },
                        min: 0,
                        max: 120
                    ),
                    .toggle(
                        title: "Ép toàn màn",
                        get: { [weak self] in self?.cfg.forceFullscreen ?? false },
                        set: { [weak self] v in self?.cfg.forceFullscreen = v }
                    ),
                    .toggle(
                        title: "Lọc mịn",
                        get: { [weak self] in self?.cfg.screenFilter ?? false },
                        set: { [weak self] v in self?.cfg.screenFilter = v }
                    ),
                ]
            ),
            (
                header: "Nhập liệu",
                rows: [
                    .toggle(
                        title: "Cảm ứng",
                        get: { [weak self] in self?.cfg.touchInput ?? true },
                        set: { [weak self] v in self?.cfg.touchInput = v }
                    ),
                    .toggle(
                        title: "Bàn phím ảo",
                        get: { [weak self] in self?.cfg.vkEnabled ?? true },
                        set: { [weak self] v in self?.cfg.vkEnabled = v }
                    ),
                    .number(
                        title: "Độ mờ (0 – 255)",
                        get: { [weak self] in self?.cfg.vkAlpha ?? 64 },
                        set: { [weak self] v in self?.cfg.vkAlpha = v },
                        min: 0,
                        max: 255
                    ),
                    .toggle(
                        title: "Rung khi bấm",
                        get: { [weak self] in self?.cfg.vkFeedback ?? false },
                        set: { [weak self] v in self?.cfg.vkFeedback = v }
                    ),
                    .toggle(
                        title: "Ép đặc phím",
                        get: { [weak self] in self?.cfg.vkForceOpacity ?? false },
                        set: { [weak self] v in self?.cfg.vkForceOpacity = v }
                    ),
                ]
            ),
        ]
        tableView.reloadData()
    }

    @objc private func saveTapped() {
        NstLibrary.shared.saveConfig(cfg, for: game.id)
        onSaved?(cfg)
        if startAfter {
            MicroController.open(game: game, from: navigationController)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func moreTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Đặt lại thiết lập", style: .default) { [weak self] _ in
            guard let self else { return }
            self.cfg = GameConfig()
            self.tableView.reloadData()
        })
        sheet.addAction(UIAlertAction(title: "Xóa dữ liệu chơi", style: .destructive) { [weak self] _ in
            self?.confirmClearData()
        })
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(sheet, animated: true)
    }

    private func confirmClearData() {
        if MicroController.isRunning(gameId: game.id) {
            let alert = UIAlertController(
                title: "Thông báo",
                message: "Game đang chạy, hãy đóng game trước khi xoá dữ liệu.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let alert = UIAlertController(
            title: "Xóa dữ liệu",
            message: "Xoá toàn bộ dữ liệu chơi (save, RMS) của game này?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            guard let self else { return }
            NstLibrary.shared.clearSaveData(for: self.game)
        })
        present(alert, animated: true)
    }

    // MARK: - Table DataSource & Delegate

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = NstTheme.Lic.card
        cell.textLabel?.textColor = NstTheme.Lic.text

        switch row {
        case .number(let title, let get, _, _, _):
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = "\(get())"
            cell.detailTextLabel?.textColor = NstTheme.Lic.muted
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default

        case .toggle(let title, let get, let set):
            cell.textLabel?.text = title
            let sw = UISwitch()
            sw.isOn = get()
            sw.onTintColor = NstTheme.Lic.accent
            sw.addAction(UIAction { _ in set(sw.isOn) }, for: .valueChanged)
            cell.accessoryView = sw
            cell.selectionStyle = .none
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        guard case .number(let title, let get, let set, let minV, let maxV) = row else { return }

        let alert = UIAlertController(title: title, message: "\(minV) – \(maxV)", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.text = "\(get())"
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text, let v = Int(text) else { return }
            set(min(max(v, minV), maxV))
            self?.tableView.reloadRows(at: [indexPath], with: .none)
        })
        present(alert, animated: true)
    }
}
