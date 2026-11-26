import UIKit
import UniformTypeIdentifiers

/// Exact 1:1 port of `J2me.iOS.Ui.VariantController` (lists ready-to-play bundled mods and lets users launch or configure).
@MainActor
final class VariantController: UITableViewController, UIDocumentPickerDelegate {
    private let product: CatalogProduct

    init(product: CatalogProduct) {
        self.product = product
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = product.name
        view.backgroundColor = NstTheme.Apk.background
        tableView.backgroundColor = NstTheme.Apk.background
        tableView.separatorColor = NstTheme.Apk.divider
        tableView.rowHeight = 64
        tableView.tableFooterView = UIView()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        product.variants.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = (tableView.dequeueReusableCell(withIdentifier: "variant") as? NstGameCell)
            ?? NstGameCell(reuseIdentifier: "variant")
        let variant = product.variants[indexPath.row]
        let icon = NstLibrary.shared.productIcon(product.iconKey)

        if let entry = NstLibrary.shared.bundledEntries[variant.variantId] {
            let running = MicroController.isRunning(gameId: entry.id) ? " · Đang chạy" : " · Sẵn sàng"
            cell.bind(title: variant.label, subtitle: "\(entry.subtitle)\(running)", icon: icon)
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.bind(title: variant.label, subtitle: "Chọn file .jar hoặc .zip trong máy", icon: icon)
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let variant = product.variants[indexPath.row]
        if let entry = NstLibrary.shared.bundledEntries[variant.variantId] {
            MicroController.open(game: entry, from: navigationController)
        } else {
            pickJarFile()
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        let pt = gr.location(in: tableView)
        guard let ip = tableView.indexPathForRow(at: pt) else { return }
        let variant = product.variants[ip.row]
        guard let entry = NstLibrary.shared.bundledEntries[variant.variantId] else { return }

        let sheet = UIAlertController(title: entry.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Cài đặt", style: .default) { [weak self] _ in
            let cfgVC = ConfigController(game: entry, startAfter: true)
            self?.navigationController?.pushViewController(cfgVC, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Xóa dữ liệu chơi", style: .destructive) { [weak self] _ in
            if MicroController.isRunning(gameId: entry.id) {
                let alert = UIAlertController(title: "Thông báo", message: "Game đang chạy, hãy đóng game trước.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
                return
            }
            NstLibrary.shared.clearSaveData(for: entry)
        })
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let pop = sheet.popoverPresentationController, let cell = tableView.cellForRow(at: ip) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    private func pickJarFile() {
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
        let outcome = NstLibrary.shared.importURLs(urls)
        if let first = outcome.installed.first {
            MicroController.open(game: first, from: navigationController)
        } else if !outcome.rejected.isEmpty {
            let msg = outcome.rejected.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            let alert = UIAlertController(title: "Không thêm được game", message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
