import UIKit

/// Exact 1:1 port of `J2me.Host.ProxyMenu` UI flows (`Danh sách proxy`, `Import`, `Thêm 1`, `Sửa`, `Test`, `Xóa`, `Gán proxy`).
@MainActor
final class ProxyMenuCoordinator {
    struct OpenSlotInfo {
        let slot: Int
        let gameId: String
        let gameName: String
        let disconnect: () -> Void
    }

    private weak var presenter: UIViewController?
    private let openSlotsProvider: () -> [OpenSlotInfo]
    private let toastHandler: (String) -> Void

    init(
        presenter: UIViewController,
        openSlotsProvider: @escaping () -> [OpenSlotInfo],
        toastHandler: @escaping (String) -> Void
    ) {
        self.presenter = presenter
        self.openSlotsProvider = openSlotsProvider
        self.toastHandler = toastHandler
    }

    func showRoot() {
        let sheet = UIAlertController(title: "Proxy", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Danh sách proxy", style: .default) { [weak self] _ in
            self?.showList()
        })
        sheet.addAction(UIAlertAction(title: "Gán proxy", style: .default) { [weak self] _ in
            self?.showAssign()
        })
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        presentSheet(sheet)
    }

    func showList() {
        let list = ProxyStore.shared.proxies
        let title = "Danh sách proxy (\(list.count))"
        let message = list.isEmpty ? "Chưa có proxy, bấm Import hoặc Thêm 1." : nil
        let sheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

        for p in list {
            let count = ProxyStore.shared.routeCount(for: p.id)
            let suffix = count > 0 ? "  ✓ \(count) ô/tab" : ""
            sheet.addAction(UIAlertAction(title: "\(p.displayRow)\(suffix)", style: .default) { [weak self] _ in
                self?.showProxyActions(p)
            })
        }

        sheet.addAction(UIAlertAction(title: "Import", style: .default) { [weak self] _ in
            self?.showBulkImport()
        })
        sheet.addAction(UIAlertAction(title: "Thêm 1", style: .default) { [weak self] _ in
            self?.showProxyForm(editing: nil)
        })
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        presentSheet(sheet)
    }

    private func showProxyActions(_ proxy: ProxyInfo) {
        let sheet = UIAlertController(title: proxy.displayRow, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Sửa", style: .default) { [weak self] _ in
            self?.showProxyForm(editing: proxy)
        })
        sheet.addAction(UIAlertAction(title: "Test", style: .default) { [weak self] _ in
            self?.testProxy(proxy)
        })
        sheet.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            self?.confirmDelete(proxy)
        })
        sheet.addAction(UIAlertAction(title: "Quay lại", style: .cancel) { [weak self] _ in
            self?.showList()
        })
        presentSheet(sheet)
    }

    private func confirmDelete(_ proxy: ProxyInfo) {
        let count = ProxyStore.shared.routeCount(for: proxy.id)
        if count > 0 {
            let alert = UIAlertController(
                title: "Proxy đang được gán",
                message: "\(proxy.displayRow)\n\nĐang gán cho \(count) ô/tab. Vào \"Gán proxy\" bỏ gán trước rồi mới xóa được.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter?.present(alert, animated: true)
            return
        }

        let alert = UIAlertController(title: "Xóa proxy?", message: proxy.displayRow, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            _ = ProxyStore.shared.remove(id: proxy.id)
            self?.showList()
        })
        presenter?.present(alert, animated: true)
    }

    private func showProxyForm(editing: ProxyInfo?) {
        let alert = UIAlertController(
            title: editing == nil ? "Thêm proxy" : "Sửa proxy",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "IP"
            tf.text = editing?.host ?? ""
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "Port"
            tf.text = editing.map { "\($0.port)" } ?? ""
            tf.keyboardType = .numberPad
        }
        alert.addTextField { tf in
            tf.placeholder = "User"
            tf.text = editing?.user ?? ""
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "Pass"
            tf.text = editing?.pass ?? ""
            tf.autocapitalizationType = .none
        }

        let saveHandler: (String) -> Void = { [weak self] proto in
            let fields = alert.textFields ?? []
            let host = fields.indices.contains(0) ? (fields[0].text ?? "") : ""
            let portText = fields.indices.contains(1) ? (fields[1].text ?? "") : ""
            let user = fields.indices.contains(2) ? (fields[2].text ?? "") : ""
            let pass = fields.indices.contains(3) ? (fields[3].text ?? "") : ""

            guard let port = Int(portText.trimmingCharacters(in: .whitespaces)),
                  (1...65535).contains(port),
                  !host.trimmingCharacters(in: .whitespaces).isEmpty else {
                self?.toastHandler("Host/port proxy không hợp lệ")
                return
            }

            if var old = editing {
                old.type = proto
                old.host = host.trimmingCharacters(in: .whitespaces)
                old.port = port
                old.user = user.trimmingCharacters(in: .whitespaces)
                old.pass = pass.trimmingCharacters(in: .whitespaces)
                ProxyStore.shared.update(old)
            } else {
                _ = ProxyStore.shared.add(type: proto, host: host, port: port, user: user, pass: pass)
            }
            self?.showList()
        }

        alert.addAction(UIAlertAction(title: "Lưu SOCKS5", style: .default) { _ in saveHandler("socks5") })
        alert.addAction(UIAlertAction(title: "Lưu HTTP", style: .default) { _ in saveHandler("http") })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        presenter?.present(alert, animated: true)
    }

    private func showBulkImport() {
        let vc = ProxyBulkImportController { [weak self] text, proto in
            let res = ProxyStore.shared.importLines(text, type: proto)
            self?.toastHandler("Đã thêm \(res.added) proxy (\(res.duplicates) trùng)")
            self?.showList()
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        presenter?.present(nav, animated: true)
    }

    private func testProxy(_ proxy: ProxyInfo) {
        toastHandler("Đang test \(proxy.host):\(proxy.port) ...")
        Task { @MainActor [weak self] in
            let result = await ProxyDialer.testProxy(proxy)
            self?.toastHandler("\(proxy.host):\(proxy.port) — \(result)")
        }
    }

    // MARK: - Assign Proxy Per Slot

    func showAssign() {
        let slots = openSlotsProvider()
        guard !slots.isEmpty else {
            toastHandler("Chưa có ô nào đang chạy game")
            return
        }
        if ProxyStore.shared.proxies.isEmpty {
            let alert = UIAlertController(
                title: "Chưa có proxy",
                message: "Hãy vào \"Danh sách proxy\" để import/thêm trước.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Thêm ngay", style: .default) { [weak self] _ in
                self?.showList()
            })
            alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
            presenter?.present(alert, animated: true)
            return
        }

        let sheet = UIAlertController(
            title: "Gán proxy theo ô",
            message: "Số ô là số trên dải tab.",
            preferredStyle: .actionSheet
        )
        for s in slots {
            let routeText: String
            if let px = ProxyStore.shared.proxyForSlot(gameId: s.gameId, slot: s.slot) {
                routeText = px.displayRow
            } else {
                routeText = "Trực tiếp"
            }
            let row = "Ô \(s.slot + 1) · \(s.gameName) — \(routeText)"
            sheet.addAction(UIAlertAction(title: row, style: .default) { [weak self] _ in
                self?.showSlotPicker(s)
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        presentSheet(sheet)
    }

    private func showSlotPicker(_ slotInfo: OpenSlotInfo) {
        let currentId = ProxyStore.shared.proxyIdForScreen(gameId: slotInfo.gameId, slot: slotInfo.slot)
        let sheet = UIAlertController(
            title: "Proxy mặc định — Ô \(slotInfo.slot + 1)",
            message: slotInfo.gameName,
            preferredStyle: .actionSheet
        )

        let directTitle = (currentId == 0 ? "✓ " : "") + "Mặc định - không proxy"
        sheet.addAction(UIAlertAction(title: directTitle, style: .default) { [weak self] _ in
            ProxyStore.shared.assignScreen(gameId: slotInfo.gameId, slot: slotInfo.slot, proxyId: 0)
            slotInfo.disconnect()
            self?.toastHandler("Ô này dùng mạng trực tiếp")
        })

        for p in ProxyStore.shared.proxies {
            let prefix = (currentId == p.id) ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: "\(prefix)\(p.displayRow)", style: .default) { [weak self] _ in
                ProxyStore.shared.assignScreen(gameId: slotInfo.gameId, slot: slotInfo.slot, proxyId: p.id)
                slotInfo.disconnect()
                self?.toastHandler("Đã gán proxy cho ô này")
            })
        }

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        presentSheet(sheet)
    }

    private func presentSheet(_ sheet: UIAlertController) {
        guard let presenter else { return }
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 64, width: 1, height: 1)
        }
        presenter.present(sheet, animated: true)
    }
}

/// Multi-line proxy bulk import sheet (`ip:port:user:pass`, Import SOCKS5 / Import HTTP).
@MainActor
private final class ProxyBulkImportController: UIViewController {
    private let textView = UITextView()
    private let onImport: (String, String) -> Void

    init(onImport: @escaping (String, String) -> Void) {
        self.onImport = onImport
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Import proxy"
        view.backgroundColor = NstTheme.Lic.page

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancelTapped))

        let hint = UILabel()
        hint.text = "Mỗi dòng 1 proxy:\nip:port:user:pass"
        hint.numberOfLines = 0
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = NstTheme.Lic.muted
        hint.translatesAutoresizingMaskIntoConstraints = false

        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NstTheme.Lic.card
        textView.textColor = NstTheme.Lic.text
        textView.layer.cornerRadius = 10
        textView.layer.borderWidth = 1
        textView.layer.borderColor = NstTheme.Lic.line.cgColor
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.translatesAutoresizingMaskIntoConstraints = false

        let socksBtn = makeActionButton(title: "Import SOCKS5", primary: true) { [weak self] in
            guard let self else { return }
            let txt = self.textView.text ?? ""
            self.dismiss(animated: true) { self.onImport(txt, "socks5") }
        }
        let httpBtn = makeActionButton(title: "Import HTTP", primary: false) { [weak self] in
            guard let self else { return }
            let txt = self.textView.text ?? ""
            self.dismiss(animated: true) { self.onImport(txt, "http") }
        }

        let btnRow = UIStackView(arrangedSubviews: [socksBtn, httpBtn])
        btnRow.axis = .horizontal
        btnRow.spacing = 12
        btnRow.distribution = .fillEqually
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(hint)
        view.addSubview(textView)
        view.addSubview(btnRow)

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            textView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 220),

            btnRow.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 16),
            btnRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            btnRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            btnRow.heightAnchor.constraint(equalToConstant: 46),
        ])
    }

    private func makeActionButton(title: String, primary: Bool, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.layer.cornerRadius = 10
        if primary {
            btn.backgroundColor = NstTheme.Lic.accent
            btn.setTitleColor(.white, for: .normal)
        } else {
            btn.backgroundColor = NstTheme.Lic.neutralSoft
            btn.setTitleColor(NstTheme.Lic.text, for: .normal)
        }
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
