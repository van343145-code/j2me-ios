//
//  DecadeConfigViewController.swift
//  J2MEEmulator
//
//  Giao diện "Cài Đặt Game" chuẩn phong cách hiện đại theo đúng thiết kế bản Chơi Game Tuổi Thơ.
//  Bao gồm các mục Màn Hình (Cỡ màn hình, Độ phân giải, Khung hình/giây) và
//  Khi Chơi (Cài đặt bàn phím, Treo khi ra ngoài, Âm thanh game).
//

import UIKit
import ObjectiveC

class DecadeConfigViewController: UIViewController {

    private let app: AppsListViewController.AppInfo
    private let onStartGame: ((Int, Int, Int) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // State for Màn Hình
    private var selectedScreenSizeIndex: Int = 0
    private var customScreenWidth: Int = 0
    private var customScreenHeight: Int = 0
    private let screenSizes: [(label: String, w: Int, h: Int)] = [
        ("Theo Form Game", 0, 0),
        ("240 × 320", 240, 320),
        ("320 × 240", 320, 240),
        ("360 × 640", 360, 640),
        ("480 × 800", 480, 800),
        ("Tự Chọn", -1, -1)
    ]
    private var screenSizeButtons: [PillButton] = []

    // State for Độ Phân Giải
    private var selectedResIndex: Int = 3 // 360 default
    private let resOptions: [(label: String, val: Int)] = [
        ("Theo\nMáy", 0),
        ("240", 240),
        ("320", 320),
        ("360", 360),
        ("480", 480)
    ]
    private var resButtons: [PillButton] = []

    // State for Khung Hình / Giây
    private var selectedFpsIndex: Int = 3 // 30 FPS default (matches J2ME NST)
    private let fpsOptions: [Int] = [10, 15, 20, 30, 60]
    private var fpsButtons: [PillButton] = []

    // State for Khi Chơi
    private let keyboardStatusLabel = UILabel()
    private let proxyStatusLabel = UILabel()
    private let fillScreenSwitch = UISwitch()
    private let treoSwitch = UISwitch()
    private let exclusiveAudioSwitch = UISwitch()
    private let autoCleanRamSwitch = UISwitch()
    private let soundSwitch = UISwitch()

    init(app: AppsListViewController.AppInfo, onStart: ((Int, Int, Int) -> Void)? = nil) {
        self.app = app
        self.onStartGame = onStart
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(red: 0.957, green: 0.973, blue: 0.957, alpha: 1.0) // Soft mint #F4F8F4

        setupNavBar()
        setupUI()
        loadSavedValues()
    }

    private var gid: String {
        let jarName = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
        return jarName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    // ============================================================
    // MARK: - Navigation Bar
    // ============================================================

    private func setupNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.957, green: 0.973, blue: 0.957, alpha: 1.0)
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(red: 0.08, green: 0.12, blue: 0.08, alpha: 1.0),
            .font: UIFont.systemFont(ofSize: 18, weight: .bold)
        ]

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = UIColor(red: 0.10, green: 0.14, blue: 0.10, alpha: 1.0)

        title = "Cài Đặt Game"

        // Back button on left
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.left"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    @objc private func backTapped() {
        saveValues()
        if let onStart = onStartGame {
            let res = AppsListViewController.resolution(for: app)
            let fps = fpsOptions[selectedFpsIndex]
            dismiss(animated: true) {
                onStart(res.w, res.h, fps)
            }
        } else if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    // ============================================================
    // MARK: - Setup UI
    // ============================================================

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 32, right: 16)
        contentStack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        // 1. SECTION: MÀN HÌNH
        buildScreenSection()

        // 2. SECTION: KHI CHƠI
        buildGameplaySection()
    }

    // ============================================================
    // MARK: - Section 1: Màn Hình
    // ============================================================

    private func buildScreenSection() {
        // Section Header
        let header = makeSectionHeader(
            icon: "display",
            iconBg: UIColor(red: 0.88, green: 0.95, blue: 0.88, alpha: 1.0),
            iconTint: UIColor(red: 0.18, green: 0.50, blue: 0.20, alpha: 1.0),
            title: "Màn Hình"
        )
        contentStack.addArrangedSubview(header)

        // Card Container
        let card = makeCardView()
        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.spacing = 16
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.layoutMargins = UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16)
        cardStack.isLayoutMarginsRelativeArrangement = true
        card.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        // Row 1: Cỡ Màn Hình
        let sizeRowHeader = makeRowHeader(
            icon: "iphone",
            iconBg: UIColor(red: 0.88, green: 0.95, blue: 0.88, alpha: 1.0),
            iconTint: UIColor(red: 0.18, green: 0.50, blue: 0.20, alpha: 1.0),
            title: "Cỡ Màn Hình",
            subtitle: "Chuẩn Form Game Gốc, Không Méo Hình"
        )
        cardStack.addArrangedSubview(sizeRowHeader)

        // Grid of 6 buttons (3 rows x 2 cols)
        let sizeGrid = UIStackView()
        sizeGrid.axis = .vertical
        sizeGrid.spacing = 8
        screenSizeButtons.removeAll()

        for r in 0..<3 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually

            for c in 0..<2 {
                let idx = r * 2 + c
                let item = screenSizes[idx]
                let btn = PillButton(title: item.label)
                btn.tag = idx
                btn.addTarget(self, action: #selector(screenSizeTapped(_:)), for: .touchUpInside)
                rowStack.addArrangedSubview(btn)
                screenSizeButtons.append(btn)
            }
            sizeGrid.addArrangedSubview(rowStack)
        }
        cardStack.addArrangedSubview(sizeGrid)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Row 1b: Co Giãn Kín Màn Hình
        let fillRow = makeToggleRow(
            icon: "aspectratio",
            iconBg: UIColor(red: 0.88, green: 0.95, blue: 0.88, alpha: 1.0),
            iconTint: UIColor(red: 0.18, green: 0.50, blue: 0.20, alpha: 1.0),
            title: "Co Giãn Kín Màn Hình",
            subtitle: "Tắt: Giữ form gốc game · Bật: Ép kín màn",
            toggle: fillScreenSwitch,
            action: #selector(fillScreenSwitchChanged(_:))
        )
        cardStack.addArrangedSubview(fillRow)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Row 2: Độ Phân Giải
        let resRowHeader = makeRowHeader(
            icon: "sparkles.tv",
            iconBg: UIColor(red: 0.94, green: 0.90, blue: 0.98, alpha: 1.0),
            iconTint: UIColor(red: 0.49, green: 0.34, blue: 0.76, alpha: 1.0),
            title: "Độ Phân Giải",
            subtitle: "Nhỏ: Chữ To · Lớn: Thấy Rộng"
        )
        cardStack.addArrangedSubview(resRowHeader)

        let resRowStack = UIStackView()
        resRowStack.axis = .horizontal
        resRowStack.spacing = 8
        resRowStack.distribution = .fillEqually
        resButtons.removeAll()

        for (idx, opt) in resOptions.enumerated() {
            let btn = PillButton(title: opt.label)
            btn.tag = idx
            btn.addTarget(self, action: #selector(resTapped(_:)), for: .touchUpInside)
            resRowStack.addArrangedSubview(btn)
            resButtons.append(btn)
        }
        cardStack.addArrangedSubview(resRowStack)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Row 3: Khung Hình / Giây
        let fpsRowHeader = makeRowHeader(
            icon: "gauge.with.needle",
            iconBg: UIColor(red: 0.94, green: 0.90, blue: 0.98, alpha: 1.0),
            iconTint: UIColor(red: 0.49, green: 0.34, blue: 0.76, alpha: 1.0),
            title: "Khung Hình / Giây",
            subtitle: "Ít Hơn Thì Đỡ Pin Khi Treo"
        )
        cardStack.addArrangedSubview(fpsRowHeader)

        let fpsRowStack = UIStackView()
        fpsRowStack.axis = .horizontal
        fpsRowStack.spacing = 8
        fpsRowStack.distribution = .fillEqually
        fpsButtons.removeAll()

        for (idx, val) in fpsOptions.enumerated() {
            let btn = PillButton(title: "\(val)")
            btn.tag = idx
            btn.addTarget(self, action: #selector(fpsTapped(_:)), for: .touchUpInside)
            fpsRowStack.addArrangedSubview(btn)
            fpsButtons.append(btn)
        }
        cardStack.addArrangedSubview(fpsRowStack)

        contentStack.addArrangedSubview(card)
    }

    // ============================================================
    // MARK: - Section 2: Khi Chơi
    // ============================================================

    private func buildGameplaySection() {
        // Section Header
        let header = makeSectionHeader(
            icon: "gamecontroller",
            iconBg: UIColor(red: 0.94, green: 0.90, blue: 0.98, alpha: 1.0),
            iconTint: UIColor(red: 0.49, green: 0.34, blue: 0.76, alpha: 1.0),
            title: "Khi Chơi"
        )
        contentStack.addArrangedSubview(header)

        // Card Container
        let card = makeCardView()
        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.spacing = 14
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        cardStack.isLayoutMarginsRelativeArrangement = true
        card.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        // Item 1: Cài Đặt Bàn Phím
        let kbRow = UIView()
        let kbIcon = makeChipIcon("keyboard", bg: UIColor(red: 0.88, green: 0.95, blue: 0.88, alpha: 1.0), tint: UIColor(red: 0.18, green: 0.50, blue: 0.20, alpha: 1.0))
        let kbTitle = UILabel()
        kbTitle.text = "Cài Đặt Bàn Phím"
        kbTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        kbTitle.textColor = UIColor(red: 0.10, green: 0.14, blue: 0.10, alpha: 1.0)

        keyboardStatusLabel.text = "Đang Hiện"
        keyboardStatusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        keyboardStatusLabel.textColor = UIColor(red: 0.45, green: 0.50, blue: 0.45, alpha: 1.0)

        let textStack = UIStackView(arrangedSubviews: [kbTitle, keyboardStatusLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor(white: 0.75, alpha: 1.0)
        chevron.contentMode = .scaleAspectFit

        kbIcon.translatesAutoresizingMaskIntoConstraints = false
        textStack.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false

        kbRow.addSubview(kbIcon)
        kbRow.addSubview(textStack)
        kbRow.addSubview(chevron)

        NSLayoutConstraint.activate([
            kbIcon.leadingAnchor.constraint(equalTo: kbRow.leadingAnchor),
            kbIcon.centerYAnchor.constraint(equalTo: kbRow.centerYAnchor),
            kbIcon.widthAnchor.constraint(equalToConstant: 36),
            kbIcon.heightAnchor.constraint(equalToConstant: 36),

            textStack.leadingAnchor.constraint(equalTo: kbIcon.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: kbRow.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: kbRow.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: kbRow.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14),
            kbRow.heightAnchor.constraint(equalToConstant: 44)
        ])

        let kbTap = UITapGestureRecognizer(target: self, action: #selector(keyboardSettingsTapped))
        kbRow.addGestureRecognizer(kbTap)
        kbRow.isUserInteractionEnabled = true
        cardStack.addArrangedSubview(kbRow)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Item 2: Treo Khi Ra Ngoài (Khóa Máy Game Vẫn Chạy 24/24)
        let treoRow = makeToggleRow(
            icon: "moon.fill",
            iconBg: UIColor(red: 0.88, green: 0.95, blue: 0.88, alpha: 1.0),
            iconTint: UIColor(red: 0.18, green: 0.50, blue: 0.20, alpha: 1.0),
            title: "Treo Khi Ra Ngoài (24/24)",
            subtitle: "Tự Nhớ Chạy Ẩn Đa Nhiệm & Khóa Màn Hình",
            toggle: treoSwitch,
            action: #selector(treoSwitchChanged(_:))
        )
        cardStack.addArrangedSubview(treoRow)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Item 2a: Khóa Cứng Audio Độc Quyền (Chống tắt màn mạnh nhất trên iOS 26)
        let exclusiveRow = makeToggleRow(
            icon: "waveform.circle.fill",
            iconBg: UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1.0),
            iconTint: UIColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1.0),
            title: "Khóa Cứng Audio Độc Quyền",
            subtitle: "Tắt: Mix TikTok/YouTube · Bật: Chống Tắt Màn Tối Đa",
            toggle: exclusiveAudioSwitch,
            action: #selector(exclusiveAudioSwitchChanged(_:))
        )
        cardStack.addArrangedSubview(exclusiveRow)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Item 2b: Tự Động Dọn RAM (Giải phóng bộ nhớ định kỳ khi treo lâu)
        let ramRow = makeToggleRow(
            icon: "sparkles",
            iconBg: UIColor(red: 0.88, green: 0.96, blue: 0.95, alpha: 1.0),
            iconTint: UIColor(red: 0.00, green: 0.54, blue: 0.48, alpha: 1.0),
            title: "Tự Động Dọn RAM",
            subtitle: "Giải Phóng Bộ Nhớ Khi Treo Lâu",
            toggle: autoCleanRamSwitch,
            action: #selector(autoCleanRamSwitchChanged(_:))
        )
        cardStack.addArrangedSubview(ramRow)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Item 3: Âm Thanh Game (Nhạc Nền Và Tiếng Hiệu Ứng)
        let soundRow = makeToggleRow(
            icon: "speaker.wave.2.fill",
            iconBg: UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1.0),
            iconTint: UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1.0),
            title: "Âm Thanh Game",
            subtitle: "Nhạc Nền Và Tiếng Hiệu Ứng",
            toggle: soundSwitch,
            action: #selector(soundSwitchChanged(_:))
        )
        cardStack.addArrangedSubview(soundRow)

        // Divider
        cardStack.addArrangedSubview(makeDivider())

        // Item 4: Proxy SOCKS5 (Quản lý & gán proxy cho tab game)
        let proxyRow = UIView()
        proxyRow.translatesAutoresizingMaskIntoConstraints = false

        let proxyIcon = makeChipIcon("lock.shield.fill",
                                     bg: UIColor(red: 0.89, green: 0.95, blue: 0.99, alpha: 1.0),
                                     tint: UIColor(red: 0.10, green: 0.46, blue: 0.82, alpha: 1.0))

        let proxyTitle = UILabel()
        proxyTitle.text = "Proxy SOCKS5"
        proxyTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        proxyTitle.textColor = UIColor(red: 0.12, green: 0.14, blue: 0.12, alpha: 1.0)

        proxyStatusLabel.text = "Chưa cấu hình (Nhấn để thêm)"
        proxyStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        proxyStatusLabel.textColor = UIColor(red: 0.45, green: 0.50, blue: 0.45, alpha: 1.0)

        let proxyTextStack = UIStackView(arrangedSubviews: [proxyTitle, proxyStatusLabel])
        proxyTextStack.axis = .vertical
        proxyTextStack.spacing = 2
        proxyTextStack.translatesAutoresizingMaskIntoConstraints = false

        let proxyChevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        proxyChevron.tintColor = UIColor(white: 0.65, alpha: 1.0)
        proxyChevron.contentMode = .scaleAspectFit
        proxyChevron.translatesAutoresizingMaskIntoConstraints = false

        proxyRow.addSubview(proxyIcon)
        proxyRow.addSubview(proxyTextStack)
        proxyRow.addSubview(proxyChevron)

        NSLayoutConstraint.activate([
            proxyIcon.leadingAnchor.constraint(equalTo: proxyRow.leadingAnchor),
            proxyIcon.centerYAnchor.constraint(equalTo: proxyRow.centerYAnchor),
            proxyIcon.widthAnchor.constraint(equalToConstant: 36),
            proxyIcon.heightAnchor.constraint(equalToConstant: 36),

            proxyTextStack.leadingAnchor.constraint(equalTo: proxyIcon.trailingAnchor, constant: 12),
            proxyTextStack.trailingAnchor.constraint(lessThanOrEqualTo: proxyChevron.leadingAnchor, constant: -8),
            proxyTextStack.centerYAnchor.constraint(equalTo: proxyRow.centerYAnchor),

            proxyChevron.trailingAnchor.constraint(equalTo: proxyRow.trailingAnchor),
            proxyChevron.centerYAnchor.constraint(equalTo: proxyRow.centerYAnchor),
            proxyChevron.widthAnchor.constraint(equalToConstant: 14),
            proxyChevron.heightAnchor.constraint(equalToConstant: 14),
            proxyRow.heightAnchor.constraint(equalToConstant: 44)
        ])

        let proxyTap = UITapGestureRecognizer(target: self, action: #selector(proxySettingsTapped))
        proxyRow.addGestureRecognizer(proxyTap)
        proxyRow.isUserInteractionEnabled = true
        cardStack.addArrangedSubview(proxyRow)

        contentStack.addArrangedSubview(card)
    }

    // ============================================================
    // MARK: - Component Helpers
    // ============================================================

    private func makeCardView() -> UIView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.04
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func makeSectionHeader(icon: String, iconBg: UIColor, iconTint: UIColor, title: String) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 10
        container.alignment = .center

        let chip = makeChipIcon(icon, bg: iconBg, tint: iconTint)
        let lbl = UILabel()
        lbl.text = title
        lbl.font = .systemFont(ofSize: 16, weight: .bold)
        lbl.textColor = UIColor(red: 0.10, green: 0.14, blue: 0.10, alpha: 1.0)

        container.addArrangedSubview(chip)
        container.addArrangedSubview(lbl)
        return container
    }

    private func makeChipIcon(_ name: String, bg: UIColor, tint: UIColor) -> UIView {
        let v = UIView()
        v.backgroundColor = bg
        v.layer.cornerRadius = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 28).isActive = true
        v.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let iv = UIImageView(image: UIImage(systemName: name))
        iv.tintColor = tint
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(iv)

        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16)
        ])
        return v
    }

    private func makeRowHeader(icon: String, iconBg: UIColor, iconTint: UIColor, title: String, subtitle: String) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 12
        container.alignment = .center

        let chip = makeChipIcon(icon, bg: iconBg, tint: iconTint)
        chip.layer.cornerRadius = 10
        chip.widthAnchor.constraint(equalToConstant: 36).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 2

        let tLbl = UILabel()
        tLbl.text = title
        tLbl.font = .systemFont(ofSize: 15, weight: .semibold)
        tLbl.textColor = UIColor(red: 0.10, green: 0.14, blue: 0.10, alpha: 1.0)

        let sLbl = UILabel()
        sLbl.text = subtitle
        sLbl.font = .systemFont(ofSize: 13, weight: .regular)
        sLbl.textColor = UIColor(red: 0.45, green: 0.50, blue: 0.45, alpha: 1.0)

        textStack.addArrangedSubview(tLbl)
        textStack.addArrangedSubview(sLbl)

        container.addArrangedSubview(chip)
        container.addArrangedSubview(textStack)
        return container
    }

    private func makeToggleRow(icon: String, iconBg: UIColor, iconTint: UIColor, title: String, subtitle: String, toggle: UISwitch, action: Selector) -> UIView {
        let row = UIView()
        let header = makeRowHeader(icon: icon, iconBg: iconBg, iconTint: iconTint, title: title, subtitle: subtitle)
        header.translatesAutoresizingMaskIntoConstraints = false

        toggle.onTintColor = UIColor(red: 0.18, green: 0.65, blue: 0.28, alpha: 1.0)
        toggle.addTarget(self, action: action, for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(header)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            header.topAnchor.constraint(equalTo: row.topAnchor),
            header.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            header.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 44)
        ])
        return row
    }

    private func makeDivider() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor(red: 0.92, green: 0.94, blue: 0.92, alpha: 1.0)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    // ============================================================
    // MARK: - Actions & State Updates
    // ============================================================

    @objc private func screenSizeTapped(_ sender: UIButton) {
        if sender.tag == 5 {
            let initW = customScreenWidth > 0 ? customScreenWidth : 360
            let initH = customScreenHeight > 0 ? customScreenHeight : DecadeScreenSizeEditor.autoHeight(for: initW, keypadHidden: UserDefaults.standard.bool(forKey: "keypad_hidden_\(gid)"))
            DecadeScreenSizeEditor.presentNstCustomSizeAlert(
                on: self,
                initialW: initW,
                initialH: initH,
                keypadHidden: UserDefaults.standard.bool(forKey: "keypad_hidden_\(gid)"),
                showApplyAllOption: true
            ) { [weak self] w, h, applyAll in
                guard let self = self else { return }
                if w == 0 || h == 0 {
                    self.selectedScreenSizeIndex = 0
                    self.customScreenWidth = 0
                    self.customScreenHeight = 0
                    if self.screenSizeButtons.indices.contains(5) {
                        self.screenSizeButtons[5].setTitle("Tự Chọn", for: .normal)
                    }
                } else {
                    self.selectedScreenSizeIndex = 5
                    self.customScreenWidth = w
                    self.customScreenHeight = h
                    if self.screenSizeButtons.indices.contains(5) {
                        self.screenSizeButtons[5].setTitle("Tự Chọn\n\(w)×\(h)", for: .normal)
                    }
                }
                for (idx, btn) in self.screenSizeButtons.enumerated() {
                    btn.isSelectedState = (idx == self.selectedScreenSizeIndex)
                }
                if applyAll {
                    DecadeScreenSizeEditor.applySize(w: w, h: h, gameId: self.gid, applyToAll: true)
                }
                self.saveValues()
            }
            return
        }
        selectedScreenSizeIndex = sender.tag
        for (idx, btn) in screenSizeButtons.enumerated() {
            btn.isSelectedState = (idx == selectedScreenSizeIndex)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        saveValues()
    }

    @objc private func fillScreenSwitchChanged(_ sender: UISwitch) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        saveValues()
    }

    @objc private func resTapped(_ sender: UIButton) {
        selectedResIndex = sender.tag
        for (idx, btn) in resButtons.enumerated() {
            btn.isSelectedState = (idx == selectedResIndex)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        saveValues()
    }

    @objc private func fpsTapped(_ sender: UIButton) {
        selectedFpsIndex = sender.tag
        for (idx, btn) in fpsButtons.enumerated() {
            btn.isSelectedState = (idx == selectedFpsIndex)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        saveValues()
    }

    @objc private func treoSwitchChanged(_ sender: UISwitch) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DecadeBackgroundKeeper.shared.setTreoActive(sender.isOn)
        saveValues()
    }

    @objc private func exclusiveAudioSwitchChanged(_ sender: UISwitch) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DecadeBackgroundKeeper.shared.setExclusiveAudioMode(sender.isOn)
        saveValues()
    }

    @objc private func autoCleanRamSwitchChanged(_ sender: UISwitch) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DecadeBackgroundKeeper.shared.setAutoCleanRamActive(sender.isOn)
        if sender.isOn {
            DecadeBackgroundKeeper.shared.performRamCleanup(completion: nil)
        }
        saveValues()
    }

    @objc private func soundSwitchChanged(_ sender: UISwitch) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UserDefaults.standard.set(sender.isOn, forKey: "decade_game_sound")
        saveValues()
    }

    @objc private func keyboardSettingsTapped() {
        let setupVC = DecadeKeyboardSetupViewController(
            gameId: gid,
            inGame: false,
            onChanged: { [weak self] in
                self?.refreshKeyboardStatusLabel()
                self?.saveValues()
            }
        )
        let nav = UINavigationController(rootViewController: setupVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func refreshKeyboardStatusLabel() {
        let d = UserDefaults.standard
        let isKbHidden = d.bool(forKey: "keypad_hidden_\(gid)")
        if isKbHidden {
            keyboardStatusLabel.text = "Đang Ẩn"
            return
        }
        let layoutNames = ["Tuổi Thơ", "Mũi Tên", "Số (Numpad)", "Kết Hợp"]
        let idx = d.object(forKey: "keypad_layout_\(gid)") as? Int ?? 0
        let layoutLabel = (idx >= 0 && idx < layoutNames.count) ? layoutNames[idx] : "Tuổi Thơ"
        keyboardStatusLabel.text = "Đang Hiện · \(layoutLabel)"
    }

    @objc private func proxySettingsTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let proxyVC = DecadeProxyViewController()
        proxyVC.initialSegmentIndex = 0
        let nav = UINavigationController(rootViewController: proxyVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshProxyStatusLabel()
        refreshKeyboardStatusLabel()
    }

    private func refreshProxyStatusLabel() {
        DecadeProxyManager.shared.loadProxies()
        let count = DecadeProxyManager.shared.proxies.count
        if let assigned = DecadeProxyManager.shared.proxyForScreen(appId: app.name, slot: 0) {
            proxyStatusLabel.text = "\(assigned.isSocks5 ? "SOCKS5" : "HTTP"): \(assigned.host):\(assigned.port)"
        } else if count > 0 {
            proxyStatusLabel.text = "Đã lưu \(count) proxy (Nhấn để gán)"
        } else {
            proxyStatusLabel.text = "Chưa cấu hình (Nhấn để thêm)"
        }
    }

    // ============================================================
    // MARK: - Load & Save Values
    // ============================================================

    private func loadSavedValues() {
        let defaults = UserDefaults.standard

        // Cỡ Màn Hình
        let savedW = defaults.object(forKey: "resW_\(gid)") as? Int ?? (defaults.object(forKey: "jarno1_global_resW") as? Int ?? 0)
        let savedH = defaults.object(forKey: "resH_\(gid)") as? Int ?? (defaults.object(forKey: "jarno1_global_resH") as? Int ?? 0)
        var foundSizeIdx = 0
        if savedW > 0 && savedH > 0 {
            var matchedPreset = false
            for (i, s) in screenSizes.enumerated() where s.w > 0 && s.h > 0 {
                if s.w == savedW && s.h == savedH {
                    foundSizeIdx = i
                    matchedPreset = true
                    break
                }
            }
            if !matchedPreset {
                foundSizeIdx = 5
                customScreenWidth = savedW
                customScreenHeight = savedH
                if screenSizeButtons.indices.contains(5) {
                    screenSizeButtons[5].setTitle("Tự Chọn\n\(savedW)×\(savedH)", for: .normal)
                }
            }
        }
        selectedScreenSizeIndex = foundSizeIdx
        for (i, btn) in screenSizeButtons.enumerated() {
            btn.isSelectedState = (i == selectedScreenSizeIndex)
        }

        // Độ Phân Giải
        let savedRes = defaults.object(forKey: "res_scale_\(gid)") as? Int ?? 360
        var foundResIdx = 3
        for (i, r) in resOptions.enumerated() {
            if r.val == savedRes {
                foundResIdx = i
                break
            }
        }
        selectedResIndex = foundResIdx
        for (i, btn) in resButtons.enumerated() {
            btn.isSelectedState = (i == selectedResIndex)
        }

        // FPS (default 30 matching J2ME NST)
        let savedFps = defaults.object(forKey: "fpsLimit_\(gid)") as? Int ?? 30
        selectedFpsIndex = fpsOptions.firstIndex(of: savedFps) ?? 3
        for (i, btn) in fpsButtons.enumerated() {
            btn.isSelectedState = (i == selectedFpsIndex)
        }

        // Treo khi ra ngoài: Mặc định luôn là TRUE
        treoSwitch.isOn = DecadeBackgroundKeeper.shared.isTreoActive

        // Khóa cứng Audio độc quyền: Mặc định FALSE (Mix app khác chuẩn NST)
        exclusiveAudioSwitch.isOn = DecadeBackgroundKeeper.shared.isExclusiveAudioMode

        // Co Giãn Kín Màn Hình: Mặc định tắt (FALSE) để giữ chuẩn form game gốc không méo hình
        let savedFill = defaults.object(forKey: "decade_fill_screen_\(gid)") as? Bool
            ?? !(defaults.object(forKey: "aspect_\(gid)") as? Bool ?? true)
        fillScreenSwitch.isOn = savedFill

        // Tự động dọn RAM: Mặc định luôn là TRUE
        autoCleanRamSwitch.isOn = DecadeBackgroundKeeper.shared.isAutoCleanRamActive

        // Âm thanh game: Mặc định TRUE
        soundSwitch.isOn = defaults.object(forKey: "decade_game_sound") as? Bool ?? true

        // Keyboard status
        refreshKeyboardStatusLabel()
    }

    private func saveValues() {
        let defaults = UserDefaults.standard

        let sSize = screenSizes[selectedScreenSizeIndex]
        let effW = (selectedScreenSizeIndex == 5) ? max(0, customScreenWidth) : max(0, sSize.w)
        let effH = (selectedScreenSizeIndex == 5) ? max(0, customScreenHeight) : max(0, sSize.h)
        defaults.set(effW, forKey: "resW_\(gid)")
        defaults.set(effH, forKey: "resH_\(gid)")

        let sRes = resOptions[selectedResIndex].val
        defaults.set(sRes, forKey: "res_scale_\(gid)")

        let sFps = fpsOptions[selectedFpsIndex]
        defaults.set(sFps, forKey: "fpsLimit_\(gid)")
        j2me_render_set_fps_limit(Int32(sFps))

        DecadeBackgroundKeeper.shared.setTreoActive(treoSwitch.isOn)
        DecadeBackgroundKeeper.shared.setExclusiveAudioMode(exclusiveAudioSwitch.isOn)
        defaults.set(soundSwitch.isOn, forKey: "decade_game_sound")
        defaults.set(fillScreenSwitch.isOn, forKey: "decade_fill_screen_\(gid)")
        defaults.set(!fillScreenSwitch.isOn, forKey: "aspect_\(gid)")
        defaults.synchronize()

        NotificationCenter.default.post(
            name: NSNotification.Name("DecadeConfigChanged"),
            object: nil,
            userInfo: [
                "gid": gid,
                "width": effW,
                "height": effH,
                "scale": sRes,
                "fps": sFps,
                "treo": treoSwitch.isOn,
                "exclusiveAudio": exclusiveAudioSwitch.isOn,
                "cleanRam": autoCleanRamSwitch.isOn,
                "fillScreen": fillScreenSwitch.isOn,
                "sound": soundSwitch.isOn
            ]
        )
    }
}

// ============================================================
// MARK: - NST-style Screen Size Editor (Rộng × Cao tự điền tỷ lệ)
// ============================================================

final class DecadeScreenSizeEditor {

    private final class AutoSyncDelegate: NSObject {
        weak var widthField: UITextField?
        weak var heightField: UITextField?
        let keypadHidden: Bool
        private var heightEditedManually = false
        private var isUpdatingProgrammatically = false

        init(widthField: UITextField, heightField: UITextField, keypadHidden: Bool) {
            self.widthField = widthField
            self.heightField = heightField
            self.keypadHidden = keypadHidden
            super.init()
            widthField.addTarget(self, action: #selector(widthChanged), for: .editingChanged)
            heightField.addTarget(self, action: #selector(heightChanged), for: .editingChanged)
        }

        @objc private func widthChanged() {
            guard !isUpdatingProgrammatically, !heightEditedManually else { return }
            let raw = (widthField?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let w = Int(raw) else { return }
            isUpdatingProgrammatically = true
            if w <= 0 {
                heightField?.text = "0"
            } else {
                let clampedW = min(1200, max(120, w))
                heightField?.text = "\(DecadeScreenSizeEditor.autoHeight(for: clampedW, keypadHidden: keypadHidden))"
            }
            isUpdatingProgrammatically = false
        }

        @objc private func heightChanged() {
            if !isUpdatingProgrammatically {
                heightEditedManually = true
            }
        }
    }

    private static var assocKey: UInt8 = 0

    static func autoHeight(for width: Int, keypadHidden: Bool) -> Int {
        let w = max(120, min(1200, width))
        let screen = UIScreen.main.bounds
        let sw = max(1.0, min(screen.width, screen.height))
        let sh = max(1.0, max(screen.width, screen.height))
        let safeTop = UIApplication.shared.windows.first?.safeAreaInsets.top ?? 47.0
        let topBarH: CGFloat = 38.0 + safeTop
        let kpH: CGFloat = keypadHidden ? 0.0 : 280.0
        let visibleH = max(120.0, sh - topBarH - kpH)
        var autoH = Int((Double(w) * Double(visibleH / sw)).rounded())
        if autoH % 2 != 0 { autoH += 1 }
        return max(120, min(2000, autoH))
    }

    static func effectiveSize(forGameId gid: String, autoProvider: () -> (w: Int, h: Int)) -> (w: Int, h: Int) {
        let d = UserDefaults.standard
        let w = d.object(forKey: "resW_\(gid)") as? Int ?? (d.object(forKey: "jarno1_global_resW") as? Int ?? 0)
        let h = d.object(forKey: "resH_\(gid)") as? Int ?? (d.object(forKey: "jarno1_global_resH") as? Int ?? 0)
        if w > 0 && h > 0 {
            return (w, h)
        }
        return autoProvider()
    }

    static func applySize(w: Int, h: Int, gameId: String?, applyToAll: Bool) {
        let d = UserDefaults.standard
        let cleanW = w > 0 ? max(120, min(1200, w)) : 0
        let cleanH = h > 0 ? max(120, min(2000, h)) : 0
        let finalW = (cleanW > 0 && cleanH > 0) ? cleanW : 0
        let finalH = (cleanW > 0 && cleanH > 0) ? cleanH : 0

        if let gid = gameId, !gid.isEmpty {
            d.set(finalW, forKey: "resW_\(gid)")
            d.set(finalH, forKey: "resH_\(gid)")
        }
        if applyToAll {
            d.set(finalW, forKey: "jarno1_global_resW")
            d.set(finalH, forKey: "jarno1_global_resH")
            let gamesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path + "/games"
            if let files = try? FileManager.default.contentsOfDirectory(atPath: gamesDir) {
                for file in files where file.hasSuffix(".jar") {
                    let stem = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
                    let g = stem.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
                    let gFull = file.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
                    d.set(finalW, forKey: "resW_\(g)")
                    d.set(finalH, forKey: "resH_\(g)")
                    d.set(finalW, forKey: "resW_\(gFull)")
                    d.set(finalH, forKey: "resH_\(gFull)")
                }
            }
        }
        d.synchronize()
    }

    static func presentNstCustomSizeAlert(
        on vc: UIViewController,
        initialW: Int,
        initialH: Int,
        keypadHidden: Bool,
        showApplyAllOption: Bool,
        onApply: @escaping (_ w: Int, _ h: Int, _ applyAll: Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: "Cỡ Màn Hình (Chuẩn NST)",
            message: "Rộng càng lớn nhìn càng rộng, Cao tự điền cho vừa màn (sửa được).\nNhập 0 để dùng tự động vừa màn.",
            preferredStyle: .alert
        )

        alert.addTextField { tf in
            tf.placeholder = "Rộng (ví dụ: 240, 360, 480)"
            tf.keyboardType = .numberPad
            tf.text = initialW > 0 ? "\(initialW)" : "360"
            tf.clearButtonMode = .whileEditing
        }
        alert.addTextField { tf in
            tf.placeholder = "Cao (tự điền theo Rộng, sửa được)"
            tf.keyboardType = .numberPad
            tf.text = initialH > 0 ? "\(initialH)" : "\(autoHeight(for: initialW > 0 ? initialW : 360, keypadHidden: keypadHidden))"
            tf.clearButtonMode = .whileEditing
        }

        if let wField = alert.textFields?.first, let hField = alert.textFields?.last {
            let sync = AutoSyncDelegate(widthField: wField, heightField: hField, keypadHidden: keypadHidden)
            objc_setAssociatedObject(alert, &assocKey, sync, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        let parseAndApply: (Bool) -> Void = { applyAll in
            let wRaw = Int((alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let hRaw = Int((alert.textFields?.last?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if wRaw <= 0 {
                onApply(0, 0, applyAll)
                return
            }
            let clampedW = max(120, min(1200, wRaw))
            let clampedH = hRaw > 0 ? max(120, min(2000, hRaw)) : autoHeight(for: clampedW, keypadHidden: keypadHidden)
            onApply(clampedW, clampedH, applyAll)
        }

        if showApplyAllOption {
            alert.addAction(UIAlertAction(title: "Áp cho game này", style: .default) { _ in
                parseAndApply(false)
            })
            alert.addAction(UIAlertAction(title: "Áp cho mọi game (NST)", style: .default) { _ in
                parseAndApply(true)
            })
        } else {
            alert.addAction(UIAlertAction(title: "Lưu cho mọi game", style: .default) { _ in
                parseAndApply(true)
            })
        }
        alert.addAction(UIAlertAction(title: "Mặc định vừa màn (0×0)", style: .default) { _ in
            onApply(0, 0, false)
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))

        vc.present(alert, animated: true)
    }
}

// ============================================================
// MARK: - PillButton Component
// ============================================================

final class PillButton: UIButton {

    var isSelectedState: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.numberOfLines = 2
        titleLabel?.textAlignment = .center
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.75
        layer.cornerRadius = 10
        layer.masksToBounds = true
        contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        if isSelectedState {
            backgroundColor = UIColor(red: 0.91, green: 0.96, blue: 0.91, alpha: 1.0) // Soft green tint
            layer.borderWidth = 1.5
            layer.borderColor = UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0).cgColor
            setTitleColor(UIColor(red: 0.15, green: 0.52, blue: 0.24, alpha: 1.0), for: .normal)
            titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        } else {
            backgroundColor = .white
            layer.borderWidth = 1.0
            layer.borderColor = UIColor(red: 0.88, green: 0.90, blue: 0.88, alpha: 1.0).cgColor
            setTitleColor(UIColor(red: 0.20, green: 0.25, blue: 0.20, alpha: 1.0), for: .normal)
            titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        }
    }
}
