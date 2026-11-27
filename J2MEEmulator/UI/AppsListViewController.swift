//
//  AppsListViewController.swift
//  J2MEEmulator
//
//  Giao diện danh sách game chuẩn 1:1 theo thiết kế "Chơi Game Tuổi Thơ"
//  Hỗ trợ hiển thị trạng thái đang chạy 24/7, khôi phục game ngầm, và thanh điều hướng 5 tab hiện đại.
//

import UIKit
import UniformTypeIdentifiers

class AppsListViewController: UIViewController,
                              UICollectionViewDataSource,
                              UICollectionViewDelegate,
                              UIDocumentPickerDelegate {

    private var springboardCollectionView: UICollectionView!
    private let headerView = UIView()
    private let headerSubtitleLabel = UILabel()
    private let emptyStateLabel = UILabel()
    private let bottomTabBar = UIView()
    private let runningBadgeLabel = UILabel()
    private var lastLayoutWidth: CGFloat = 0

    private struct PendingImportItem {
        let tempURL: URL
        let originalFileName: String
        let meta: JARMetadata?
        let fileSize: Int64
    }

    private var pendingImportQueue: [PendingImportItem] = []
    private var isProcessingImportQueue: Bool = false

    /// Directory where imported JARs are stored
    private static var gamesDirectory: String {
        documentsDirectory + "/games"
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Dark theme matching modern screenshot #0D0F14
        view.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)

        setupHeader()
        setupCollectionView()
        setupBottomTabBar()
        setupEmptyState()

        // Ensure games directory exists
        try? FileManager.default.createDirectory(atPath: Self.gamesDirectory,
                                                  withIntermediateDirectories: true)
        scanApps()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        refreshStatus()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus),
                                               name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
    }

    // ============================================================
    // MARK: - Header (Chơi Game Tuổi Thơ & + Thêm)
    // ============================================================

    private func setupHeader() {
        headerView.backgroundColor = .clear
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        // Green App Icon
        let iconContainer = UIView()
        iconContainer.backgroundColor = UIColor(red: 0.06, green: 0.72, blue: 0.44, alpha: 1.0)
        iconContainer.layer.cornerRadius = 12
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(iconContainer)

        let gamepadIcon = UIImageView(image: UIImage(systemName: "gamecontroller.fill"))
        gamepadIcon.tintColor = .white
        gamepadIcon.contentMode = .scaleAspectFit
        gamepadIcon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(gamepadIcon)

        NSLayoutConstraint.activate([
            gamepadIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            gamepadIcon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            gamepadIcon.widthAnchor.constraint(equalToConstant: 22),
            gamepadIcon.heightAnchor.constraint(equalToConstant: 22),
        ])

        // Title and Subtitle
        let titleLabel = UILabel()
        titleLabel.text = "Chơi Game Tuổi Thơ"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        headerSubtitleLabel.text = "Đang Chạy: 0 / 0 Game"
        headerSubtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        headerSubtitleLabel.textColor = UIColor(red: 0.60, green: 0.64, blue: 0.70, alpha: 1.0)
        headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, headerSubtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 3
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleStack)

        // "+ Thêm" Button
        let addBtn = UIButton(type: .system)
        addBtn.setTitle("+ Thêm", for: .normal)
        addBtn.setTitleColor(UIColor(red: 0.20, green: 0.83, blue: 0.45, alpha: 1.0), for: .normal)
        addBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        addBtn.backgroundColor = UIColor(red: 0.04, green: 0.24, blue: 0.16, alpha: 1.0)
        addBtn.layer.cornerRadius = 17
        addBtn.layer.borderWidth = 1.0
        addBtn.layer.borderColor = UIColor(red: 0.12, green: 0.65, blue: 0.38, alpha: 1.0).cgColor
        addBtn.addTarget(self, action: #selector(addAppTapped), for: .touchUpInside)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(addBtn)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 54),

            iconContainer.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            iconContainer.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 42),
            iconContainer.heightAnchor.constraint(equalToConstant: 42),

            titleStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),

            addBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            addBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 80),
            addBtn.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    // ============================================================
    // MARK: - Collection View (Game Cards)
    // ============================================================

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 10

        springboardCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        springboardCollectionView.dataSource = self
        springboardCollectionView.delegate = self
        springboardCollectionView.backgroundColor = .clear
        springboardCollectionView.alwaysBounceVertical = true
        springboardCollectionView.showsVerticalScrollIndicator = false
        springboardCollectionView.register(SpringboardCell.self,
                                           forCellWithReuseIdentifier: SpringboardCell.reuseID)
        springboardCollectionView.contentInsetAdjustmentBehavior = .never
        springboardCollectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(springboardCollectionView)

        NSLayoutConstraint.activate([
            springboardCollectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            springboardCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            springboardCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            springboardCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -70),
        ])
    }

    private func setupEmptyState() {
        emptyStateLabel.text = "Chưa Có Game Nào\nBấm nút [+ Thêm] để nạp file .jar"
        emptyStateLabel.textColor = UIColor(red: 0.50, green: 0.55, blue: 0.62, alpha: 1.0)
        emptyStateLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.isHidden = true
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
        ])
    }

    // ============================================================
    // MARK: - Bottom Navigation Bar (5 Tabs)
    // ============================================================

    private func setupBottomTabBar() {
        bottomTabBar.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 0.96)
        bottomTabBar.layer.borderWidth = 0.5
        bottomTabBar.layer.borderColor = UIColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1.0).cgColor
        bottomTabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomTabBar)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomTabBar.addSubview(stack)

        NSLayoutConstraint.activate([
            bottomTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomTabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),

            stack.topAnchor.constraint(equalTo: bottomTabBar.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: bottomTabBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bottomTabBar.trailingAnchor),
            stack.heightAnchor.constraint(equalToConstant: 48),
        ])

        // Tab 1: Kho Game (Active)
        stack.addArrangedSubview(makeTabButton(
            title: "Kho Game",
            iconName: "gamecontroller.fill",
            color: UIColor(red: 0.20, green: 0.83, blue: 0.45, alpha: 1.0),
            action: #selector(tabKhoGameTapped)
        ))

        // Tab 2: Treo 24/7
        stack.addArrangedSubview(makeTabButton(
            title: "Treo 24/7",
            iconName: "cloud.fill",
            color: UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0),
            action: #selector(tabTreo247Tapped)
        ))

        // Tab 3: Đang Chạy (With Red Badge)
        let runningTab = makeTabButton(
            title: "Đang Chạy",
            iconName: "play.circle.fill",
            color: UIColor(red: 0.65, green: 0.35, blue: 0.95, alpha: 1.0),
            action: #selector(tabDangChayTapped)
        )
        setupRunningBadge(on: runningTab)
        stack.addArrangedSubview(runningTab)

        // Tab 4: Tài Khoản
        stack.addArrangedSubview(makeTabButton(
            title: "Tài Khoản",
            iconName: "person.fill",
            color: UIColor(red: 0.96, green: 0.62, blue: 0.05, alpha: 1.0),
            action: #selector(tabTaiKhoanTapped)
        ))

        // Tab 5: Cài Đặt
        stack.addArrangedSubview(makeTabButton(
            title: "Cài Đặt",
            iconName: "gearshape.fill",
            color: UIColor(red: 0.45, green: 0.52, blue: 0.60, alpha: 1.0),
            action: #selector(tabCaiDatTapped)
        ))
    }

    private func makeTabButton(title: String, iconName: String, color: UIColor, action: Selector) -> UIView {
        let container = UIButton(type: .custom)
        container.addTarget(self, action: action, for: .touchUpInside)

        let iv = UIImageView(image: UIImage(systemName: iconName))
        iv.tintColor = color
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false

        let lbl = UILabel()
        lbl.text = title
        lbl.font = .systemFont(ofSize: 10, weight: .medium)
        lbl.textColor = color
        lbl.textAlignment = .center
        lbl.isUserInteractionEnabled = false
        lbl.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iv)
        container.addSubview(lbl)

        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            iv.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iv.widthAnchor.constraint(equalToConstant: 22),
            iv.heightAnchor.constraint(equalToConstant: 22),

            lbl.topAnchor.constraint(equalTo: iv.bottomAnchor, constant: 3),
            lbl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            lbl.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 2),
            lbl.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -2),
        ])

        return container
    }

    private func setupRunningBadge(on tabView: UIView) {
        runningBadgeLabel.backgroundColor = UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
        runningBadgeLabel.textColor = .white
        runningBadgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        runningBadgeLabel.textAlignment = .center
        runningBadgeLabel.layer.cornerRadius = 8
        runningBadgeLabel.layer.masksToBounds = true
        runningBadgeLabel.isHidden = true
        runningBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        tabView.addSubview(runningBadgeLabel)

        NSLayoutConstraint.activate([
            runningBadgeLabel.topAnchor.constraint(equalTo: tabView.topAnchor, constant: 2),
            runningBadgeLabel.centerXAnchor.constraint(equalTo: tabView.centerXAnchor, constant: 12),
            runningBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            runningBadgeLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func updateRunningBadge() {
        let count = runningCount
        if count > 0 {
            runningBadgeLabel.text = " \(count) "
            runningBadgeLabel.isHidden = false
        } else {
            runningBadgeLabel.isHidden = true
        }
    }

    // ============================================================
    // MARK: - Tab Actions
    // ============================================================

    @objc private func tabKhoGameTapped() {
        if !apps.isEmpty {
            springboardCollectionView.scrollToItem(at: IndexPath(item: 0, section: 0),
                                                   at: .top, animated: true)
        }
    }

    @objc private func tabTreo247Tapped() {
        let keeper = DecadeBackgroundKeeper.shared
        let isTreo = keeper.isTreoActive
        let isExclusive = keeper.isExclusiveAudioMode
        let hasGame = (GameViewController.currentActiveGameVC != nil)
        let netDesc = DecadeNetworkManager.shared.currentNetworkDescription()
        let ramMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0

        let audioState: String
        if keeper.isAudioPlaying {
            audioState = "\(keeper.audioStatus) ✓"
        } else if isTreo && !hasGame {
            audioState = "Sẵn sàng (tự chạy khi mở game)"
        } else {
            audioState = keeper.audioStatus
        }

        let alert = UIAlertController(
            title: "Treo Game 24/24 (1:1 Lõi J2ME NST)",
            message: "• Tự nhớ chạy ẩn & tắt màn: \(isTreo ? "ĐANG BẬT ✓" : "ĐANG TẮT")\n• Chế độ Audio: \(keeper.audioModeDescription)\n• Lõi giữ nền: \(audioState)\n• Lần tắt màn gần nhất: \(keeper.lastBgReport)\n• Mạng: \(netDesc) • RAM: \(Int(ramMB)) MB",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: isTreo ? "Tắt chế độ Treo 24/24" : "Bật chế độ Treo 24/24 (Tự nhớ vĩnh viễn)", style: .default) { _ in
            keeper.setTreoActive(!isTreo)
        })
        alert.addAction(UIAlertAction(
            title: isExclusive
                ? "Chuyển Audio Mix app khác (Nghe TikTok/YouTube)"
                : "Bật Audio Độc quyền (Khóa cứng chống tắt màn tối đa)",
            style: .default
        ) { _ in
            keeper.setExclusiveAudioMode(!isExclusive)
        })
        alert.addAction(UIAlertAction(title: "Dọn dẹp RAM ngay", style: .default) { _ in
            keeper.performRamCleanup(completion: nil)
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = bottomTabBar
            popover.sourceRect = bottomTabBar.bounds
        }
        present(alert, animated: true)
    }

    @objc private func tabDangChayTapped() {
        if let runningVC = GameViewController.currentActiveGameVC, !runningVC.isShuttingDown {
            runningVC.modalPresentationStyle = .fullScreen
            present(runningVC, animated: true)
        } else {
            let alert = UIAlertController(title: "Thông Báo",
                                          message: "Hiện chưa có game nào đang chạy ngầm. Hãy bấm vào một game để bắt đầu chơi!",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    @objc private func tabTaiKhoanTapped() {
        showAuthorInfo()
    }

    @objc private func tabCaiDatTapped() {
        showTopMoreMenuActionSheet()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = springboardCollectionView.bounds.width
        guard width > 0, width != lastLayoutWidth else { return }
        lastLayoutWidth = width

        guard let layout = springboardCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        layout.itemSize = CGSize(width: width - 32, height: 90)
        layout.sectionInset = UIEdgeInsets(top: 10, left: 16, bottom: 20, right: 16)
    }

    // ============================================================
    // MARK: - App Scanning & Running State
    // ============================================================

    struct AppInfo {
        let name: String
        let path: String
        let fileName: String
        let version: String?
        let vendor: String?
        let icon: UIImage
        let fileSizeString: String
        let resolutionString: String

        init(name: String, path: String, fileName: String, version: String?, vendor: String?, icon: UIImage, fileSizeString: String = "0 MB", resolutionString: String = "Tự Động") {
            self.name = name
            self.path = path
            self.fileName = fileName
            self.version = version
            self.vendor = vendor
            self.icon = icon
            self.fileSizeString = fileSizeString
            self.resolutionString = resolutionString
        }
    }
    private var apps: [AppInfo] = []

    func isGameRunning(_ app: AppInfo) -> Bool {
        GameViewController.currentActiveGameVC?.hasGameTab(path: app.path) ?? false
    }

    var runningCount: Int {
        GameViewController.currentActiveGameVC?.runningGameCount ?? 0
    }

    @objc private func refreshStatus() {
        headerSubtitleLabel.text = "Đang Chạy: \(runningCount) / \(apps.count) Game"
        updateRunningBadge()
        springboardCollectionView.reloadData()
    }

    static func loadInstalledApps() -> [AppInfo] {
        let gamesDir = gamesDirectory
        var jarPaths: [(name: String, path: String)] = []
        if let files = try? FileManager.default.contentsOfDirectory(atPath: gamesDir) {
            for file in files where file.hasSuffix(".jar") {
                jarPaths.append((name: String(file.dropLast(4)), path: gamesDir + "/" + file))
            }
        }
        var unsorted = jarPaths.map { jar -> (String, String, String, String?, String?, UIImage?, String, String) in
            let meta = JARMetadata.read(from: jar.path)
            let jarIcon = meta?.readIcon(from: jar.path)
            let fileName = URL(fileURLWithPath: jar.path).lastPathComponent
            let appName = meta?.midletName ?? jar.name
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: jar.path)[.size] as? Int64) ?? 0
            let sizeString = String(format: "%.1f MB", Double(fileSize) / (1024.0 * 1024.0))

            let gid = fileName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            let savedW = UserDefaults.standard.object(forKey: "resW_\(gid)") as? Int ?? 0
            let savedH = UserDefaults.standard.object(forKey: "resH_\(gid)") as? Int ?? 0
            let resStr = (savedW > 0 && savedH > 0) ? "\(savedW)×\(savedH)" : "Theo Form Game"

            return (appName, jar.path, fileName, meta?.version, meta?.vendor, jarIcon, sizeString, resStr)
        }
        unsorted.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        return unsorted.enumerated().map { (index, t) in
            AppInfo(name: t.0, path: t.1, fileName: t.2,
                    version: t.3, vendor: t.4,
                    icon: Self.springboardIcon(t.5, name: t.0, index: index),
                    fileSizeString: t.6, resolutionString: t.7)
        }
    }

    private func scanApps() {
        let gamesDir = Self.gamesDirectory

        DispatchQueue.global(qos: .userInitiated).async {
            var jarPaths: [(name: String, path: String)] = []

            if let files = try? FileManager.default.contentsOfDirectory(atPath: gamesDir) {
                for file in files where file.hasSuffix(".jar") {
                    jarPaths.append((name: String(file.dropLast(4)), path: gamesDir + "/" + file))
                }
            }

            var unsorted = jarPaths.map { jar -> (String, String, String, String?, String?, UIImage?, String, String) in
                let meta = JARMetadata.read(from: jar.path)
                let jarIcon = meta?.readIcon(from: jar.path)
                let fileName = URL(fileURLWithPath: jar.path).lastPathComponent
                let appName = meta?.midletName ?? jar.name
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: jar.path)[.size] as? Int64) ?? 0
                let sizeString = String(format: "%.1f MB", Double(fileSize) / (1024.0 * 1024.0))

                let gid = fileName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
                let savedW = UserDefaults.standard.object(forKey: "resW_\(gid)") as? Int ?? 0
                let savedH = UserDefaults.standard.object(forKey: "resH_\(gid)") as? Int ?? 0
                let resStr = (savedW > 0 && savedH > 0) ? "\(savedW)×\(savedH)" : "Theo Form Game"

                return (appName, jar.path, fileName, meta?.version, meta?.vendor, jarIcon, sizeString, resStr)
            }
            unsorted.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

            let scannedApps = unsorted.enumerated().map { (index, t) in
                AppInfo(name: t.0, path: t.1, fileName: t.2,
                        version: t.3, vendor: t.4,
                        icon: Self.springboardIcon(t.5, name: t.0, index: index),
                        fileSizeString: t.6, resolutionString: t.7)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apps = scannedApps
                self.headerSubtitleLabel.text = "Đang Chạy: \(self.runningCount) / \(scannedApps.count) Game"
                self.updateRunningBadge()
                self.springboardCollectionView.reloadData()
                self.emptyStateLabel.isHidden = !scannedApps.isEmpty
                print("[Swift] Found \(scannedApps.count) MIDlet JARs in \(gamesDir)")
            }
        }
    }

    // ============================================================
    // MARK: - Icon Generation
    // ============================================================

    private static let iconSize: CGFloat = SpringboardCell.iconSize

    private static let placeholderGradients: [(UIColor, UIColor)] = [
        (UIColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 1),
         UIColor(red: 0.35, green: 0.60, blue: 1.00, alpha: 1)),
        (UIColor(red: 0.00, green: 0.68, blue: 0.63, alpha: 1),
         UIColor(red: 0.20, green: 0.85, blue: 0.60, alpha: 1)),
        (UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1),
         UIColor(red: 1.00, green: 0.75, blue: 0.28, alpha: 1)),
        (UIColor(red: 0.88, green: 0.22, blue: 0.28, alpha: 1),
         UIColor(red: 1.00, green: 0.42, blue: 0.48, alpha: 1)),
    ]

    private static func springboardIcon(_ jarIcon: UIImage?, name: String, index: Int) -> UIImage {
        let size = CGSize(width: iconSize, height: iconSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            UIBezierPath(roundedRect: rect, cornerRadius: SpringboardCell.iconCornerRadius).addClip()

            if let img = jarIcon {
                UIColor(white: 0.15, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                img.draw(in: rect)
            } else {
                let pair = placeholderGradients[index % placeholderGradients.count]
                let cgCtx = ctx.cgContext
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(colorsSpace: colorSpace,
                                              colors: [pair.0.cgColor, pair.1.cgColor] as CFArray,
                                              locations: [0, 1]) {
                    cgCtx.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: iconSize, y: iconSize), options: [])
                }
                let letter = String(name.prefix(1)).uppercased()
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white.withAlphaComponent(0.95),
                    .font: UIFont.systemFont(ofSize: iconSize * 0.45, weight: .bold)
                ]
                let strSize = (letter as NSString).size(withAttributes: attrs)
                (letter as NSString).draw(
                    at: CGPoint(x: (iconSize - strSize.width) / 2,
                                y: (iconSize - strSize.height) / 2),
                    withAttributes: attrs)
            }
        }
    }

    // ============================================================
    // MARK: - UICollectionView Data Source & Delegate
    // ============================================================

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        apps.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SpringboardCell.reuseID, for: indexPath) as! SpringboardCell
        let app = apps[indexPath.item]
        let running = isGameRunning(app)
        let versionStr = app.version ?? "1.6.12"
        let details = "\(app.name) • v\(versionStr) • \(app.fileSizeString)"

        cell.configure(name: app.name,
                       details: details,
                       icon: app.icon,
                       resText: app.resolutionString,
                       isRunning: running)

        cell.onMenuTap = { [weak self] in
            guard let self = self else { return }
            self.showCardActionSheet(for: app, at: indexPath)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < apps.count else { return }
        let app = apps[indexPath.item]
        didSelectApp(app)
    }

    private func didSelectApp(_ app: AppInfo) {
        launchGame(app: app)
    }

    private func showCardActionSheet(for app: AppInfo, at indexPath: IndexPath) {
        let running = isGameRunning(app)
        let alert = UIAlertController(title: app.name, message: "Chọn tác vụ cho game:", preferredStyle: .actionSheet)

        if running {
            alert.addAction(UIAlertAction(title: "▶ Tiếp Tục Chơi (Khôi Phục Màn Hình)", style: .default) { [weak self] _ in
                self?.didSelectApp(app)
            })
            alert.addAction(UIAlertAction(title: "⏹ Thoát Game Này", style: .destructive) { [weak self] _ in
                GameViewController.currentActiveGameVC?.stopGameTabs(path: app.path)
                self?.refreshStatus()
            })
        } else {
            alert.addAction(UIAlertAction(title: "▶ Bắt Đầu Chơi", style: .default) { [weak self] _ in
                self?.launchGame(app: app)
            })
        }

        alert.addAction(UIAlertAction(title: "⚙ Thiết Lập Game", style: .default) { [weak self] _ in
            self?.openConfig(for: app)
        })

        alert.addAction(UIAlertAction(title: "🌐 Quản Lý Proxy", style: .default) { [weak self] _ in
            self?.showProxyDialog()
        })

        alert.addAction(UIAlertAction(title: "✏️ Đổi Tên", style: .default) { [weak self] _ in
            self?.promptRenameApp(app: app)
        })

        alert.addAction(UIAlertAction(title: "🔄 Cài Đặt Lại Dữ Liệu", style: .default) { [weak self] _ in
            self?.confirmClearGameData(for: app)
        })

        alert.addAction(UIAlertAction(title: "🗑️ Xóa Game", style: .destructive) { [weak self] _ in
            self?.confirmDeleteApp(at: indexPath)
        })

        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        present(alert, animated: true)
    }

    // ============================================================
    // MARK: - Game Launcher & Actions
    // ============================================================

    func launchGame(app: AppInfo, overrideW: Int? = nil, overrideH: Int? = nil, overrideFps: Int? = nil) {
        let render3dScale = Self.is3DSupersampling(for: app) ? 3 : 1
        let res = (overrideW != nil && overrideH != nil) ? (overrideW!, overrideH!) : Self.resolution(for: app)
        let fps = overrideFps ?? Self.fpsLimit(for: app)
        if let runningVC = GameViewController.currentActiveGameVC {
            guard runningVC.showGameTab(app: app, width: res.0, height: res.1, scale: render3dScale, fps: fps) else {
                let alert = UIAlertController(title: "J2ME-Decade",
                                              message: runningVC.isShuttingDown ? "Đang đóng các phiên game. Vui lòng đợi."
                                                  : "Hiện chưa còn slot trống để mở game.",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            runningVC.modalPresentationStyle = .fullScreen
            present(runningVC, animated: true)
            return
        }
        let gameVC = GameViewController(jarPath: app.path, appName: app.name, appIcon: app.icon,
                                         canvasWidth: res.0, canvasHeight: res.1,
                                         render3dScale: render3dScale, fpsLimit: fps)
        GameViewController.currentActiveGameVC = gameVC
        gameVC.modalPresentationStyle = .fullScreen
        present(gameVC, animated: true)
    }

    private func openConfig(for app: AppInfo) {
        let configVC = DecadeConfigViewController(app: app) { [weak self] w, h, fps in
            self?.launchGame(app: app, overrideW: w, overrideH: h, overrideFps: fps)
        }
        let nav = UINavigationController(rootViewController: configVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func promptRenameApp(app: AppInfo) {
        let alert = UIAlertController(title: "Đổi Tên", message: "Nhập tên mới cho ứng dụng:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = app.name
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { [weak self] _ in
            guard let self, let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !newName.isEmpty else { return }
            UserDefaults.standard.set(newName, forKey: "name_\(Self.gameId(for: app))")
            self.scanApps()
        })
        present(alert, animated: true)
    }

    // ============================================================
    // MARK: - Top More Menu & Dialogs
    // ============================================================

    @objc private func showTopMoreMenuActionSheet() {
        let alert = UIAlertController(title: "Cài Đặt & Tuỳ Chọn", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "👑 Tác giả: Vạn Trần idol J2me NSV IOS", style: .default) { [weak self] _ in self?.showAuthorInfo() })
        alert.addAction(UIAlertAction(title: "🌐 Quản lý Proxy SOCKS5", style: .default) { [weak self] _ in self?.showProxyDialog() })
        alert.addAction(UIAlertAction(title: "🔄 Thay IP Phiên Bản", style: .default) { [weak self] _ in self?.showChangeIpDialog() })
        alert.addAction(UIAlertAction(title: "⚙ Thiết lập game", style: .default) { [weak self] _ in self?.showGlobalSettings() })
        alert.addAction(UIAlertAction(title: "👤 Quản lý hồ sơ", style: .default) { [weak self] _ in self?.showProfilesDialog() })
        alert.addAction(UIAlertAction(title: "❓ Trợ giúp", style: .default) { [weak self] _ in self?.showHelpDialog() })
        alert.addAction(UIAlertAction(title: "📝 Lưu log", style: .default) { [weak self] _ in self?.saveLogs() })
        alert.addAction(UIAlertAction(title: "✕ Thoát ứng dụng", style: .destructive) { _ in exit(0) })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func showAuthorInfo() {
        let alert = UIAlertController(
            title: "Vạn Trần idol J2me NSV IOS",
            message: "Ứng dụng jarNO1 J2ME iOS Multi-Tab Engine — Native Edition.\nTác giả: Vạn Trần idol J2me NSV IOS\n• Chế độ Chơi Game Tuổi Thơ\n• Treo 24/24 Port 1:1 Lõi J2ME NST (background-loop.wav + AVAudioPlayer)\n• Tự nhớ chạy ẩn đa nhiệm & tắt khóa màn hình không nghỉ\n• Cửa sổ nhỏ PiP kéo to nhỏ tự do ngoài màn hình chính.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showProxyDialog() {
        let proxyVC = DecadeProxyViewController()
        let nav = UINavigationController(rootViewController: proxyVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func showChangeIpDialog() {
        let changeIpVC = DecadeChangeIpViewController()
        let nav = UINavigationController(rootViewController: changeIpVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func showGlobalSettings() {
        if let firstApp = apps.first {
            openConfig(for: firstApp)
        } else {
            let dummyApp = AppInfo(name: "KamenRider Decade", path: "", fileName: "", version: "1.0.0", vendor: "Havan", icon: UIImage(), fileSizeString: "0 MB", resolutionString: "Tự Động")
            openConfig(for: dummyApp)
        }
    }

    private func showProfilesDialog() {
        let profilesVC = DecadeProfilesViewController()
        let nav = UINavigationController(rootViewController: profilesVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func showHelpDialog() {
        let helpVC = DecadeHelpViewController()
        let nav = UINavigationController(rootViewController: helpVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func saveLogs() {
        let logText = "KamenRider Decade J2ME iOS System Log\nTimestamp: \(Date())\nActive Games: \(apps.map { $0.name }.joined(separator: ", "))\n"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("decade_system.log")
        try? logText.write(to: tempURL, atomically: true, encoding: .utf8)
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    // ============================================================
    // MARK: - Import JAR & Smart Overwrite Manager
    // ============================================================

    func showToast(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let toast = UILabel()
            toast.text = "  \(message)  "
            toast.font = .systemFont(ofSize: 14, weight: .semibold)
            toast.textColor = .white
            toast.backgroundColor = UIColor(white: 0.15, alpha: 0.95)
            toast.textAlignment = .center
            toast.layer.cornerRadius = 18
            toast.clipsToBounds = true
            toast.layer.shadowColor = UIColor.black.cgColor
            toast.layer.shadowOpacity = 0.25
            toast.layer.shadowRadius = 4
            toast.layer.shadowOffset = CGSize(width: 0, height: 2)
            toast.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(toast)

            NSLayoutConstraint.activate([
                toast.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                toast.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -70),
                toast.heightAnchor.constraint(equalToConstant: 38),
                toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            ])

            toast.alpha = 0
            UIView.animate(withDuration: 0.25, animations: {
                toast.alpha = 1
            }) { _ in
                UIView.animate(withDuration: 0.3, delay: 2.2, options: .curveEaseOut, animations: {
                    toast.alpha = 0
                }) { _ in
                    toast.removeFromSuperview()
                }
            }
        }
    }

    @objc private func addAppTapped() {
        var contentTypes: [UTType] = []
        if let customJar = UTType("com.sun.java-archive") {
            contentTypes.append(customJar)
        }
        if let jarType = UTType(filenameExtension: "jar") {
            contentTypes.append(jarType)
        }
        if let zipType = UTType(filenameExtension: "zip") {
            contentTypes.append(zipType)
        }
        contentTypes.append(contentsOf: [.archive, .data, .item])

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        importFiles(from: urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Picker cancelled
    }

    func importFiles(from urls: [URL]) {
        let fm = FileManager.default
        let gamesDir = Self.gamesDirectory
        try? fm.createDirectory(atPath: gamesDir, withIntermediateDirectories: true, attributes: nil)

        var newItems: [PendingImportItem] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == "jar" || ext == "zip" else { continue }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            let tempName = UUID().uuidString + "_" + url.lastPathComponent
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tempName)

            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readURL in
                do {
                    try? fm.removeItem(at: tempURL)
                    try fm.copyItem(at: readURL, to: tempURL)
                } catch {
                    if let data = try? Data(contentsOf: readURL) {
                        try? data.write(to: tempURL, options: .atomic)
                    }
                }
            }

            guard fm.fileExists(atPath: tempURL.path) else { continue }
            let fSize = (try? fm.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            guard fSize > 0 else {
                try? fm.removeItem(at: tempURL)
                continue
            }

            let meta = JARMetadata.read(from: tempURL.path)
            newItems.append(PendingImportItem(
                tempURL: tempURL,
                originalFileName: url.lastPathComponent,
                meta: meta,
                fileSize: fSize
            ))
        }

        guard !newItems.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pendingImportQueue.append(contentsOf: newItems)
            if !self.isProcessingImportQueue {
                self.processNextPendingImport()
            }
        }
    }

    private func processNextPendingImport() {
        guard !pendingImportQueue.isEmpty else {
            isProcessingImportQueue = false
            scanApps()
            return
        }

        isProcessingImportQueue = true
        let item = pendingImportQueue.removeFirst()
        let fm = FileManager.default
        let gamesDir = Self.gamesDirectory

        let newFileName = item.originalFileName
        let newName = item.meta?.midletName ?? URL(fileURLWithPath: newFileName).deletingPathExtension().lastPathComponent
        let newClassName = item.meta?.className
        let newVersion = item.meta?.version ?? "Không rõ"
        let newVendor = item.meta?.vendor ?? "Không rõ"
        let newSizeStr = String(format: "%.1f MB", Double(item.fileSize) / (1024.0 * 1024.0))

        // Check for matching game (Direct filename or same MIDlet-Name/Class)
        var matchedApp: AppInfo? = apps.first { $0.fileName.caseInsensitiveCompare(newFileName) == .orderedSame }

        if matchedApp == nil && !newName.isEmpty {
            matchedApp = apps.first { app in
                if app.name.caseInsensitiveCompare(newName) == .orderedSame {
                    return true
                }
                if let newClass = newClassName, !newClass.isEmpty {
                    if let exMeta = JARMetadata.read(from: app.path), exMeta.className == newClass {
                        return true
                    }
                }
                return false
            }
        }

        let directDestURL = URL(fileURLWithPath: gamesDir).appendingPathComponent(newFileName)
        if matchedApp == nil && fm.fileExists(atPath: directDestURL.path) {
            let directMeta = JARMetadata.read(from: directDestURL.path)
            let directSize = (try? fm.attributesOfItem(atPath: directDestURL.path)[.size] as? Int64) ?? 0
            matchedApp = AppInfo(
                name: directMeta?.midletName ?? directDestURL.deletingPathExtension().lastPathComponent,
                path: directDestURL.path,
                fileName: newFileName,
                version: directMeta?.version,
                vendor: directMeta?.vendor,
                icon: UIImage(),
                fileSizeString: String(format: "%.1f MB", Double(directSize) / (1024.0 * 1024.0)),
                resolutionString: "Theo Form Game"
            )
        }

        if let existing = matchedApp {
            // Hiển thị thông tin so sánh chi tiết và cho phép ghi đè
            let mDate = (try? fm.attributesOfItem(atPath: existing.path)[.modificationDate] as? Date) ?? Date()
            let df = DateFormatter()
            df.dateFormat = "dd/MM/yyyy HH:mm"
            let dateStr = df.string(from: mDate)

            let isRunning = isGameRunning(existing)
            let runningWarning = isRunning ? "\n⚠️ Game hiện đang mở trong tab! Hãy thoát game hoặc khởi động lại sau khi ghi đè.\n" : ""

            let msg = """
Game [\(existing.name)] đã tồn tại trên thiết bị!

📁 BẢN HIỆN TẠI (TRÊN MÁY):
• Tên: \(existing.name)
• Tệp: \(existing.fileName)
• Phiên bản: \(existing.version ?? "Không rõ")
• Dung lượng: \(existing.fileSizeString)
• Cập nhật: \(dateStr)

📦 BẢN MỚI (CHUẨN BỊ CÀI):
• Tên: \(newName)
• Tệp: \(newFileName)
• Phiên bản: \(newVersion)
• Dung lượng: \(newSizeStr)
• Nhà phát triển: \(newVendor)
\(runningWarning)
💡 Ghi đè: Dữ liệu game (RMS, tài khoản, cấu hình) sẽ được giữ nguyên an toàn!
"""

            let alert = UIAlertController(title: "⚠️ Phát Hiện Game Cùng Mã", message: msg, preferredStyle: .alert)

            alert.addAction(UIAlertAction(title: "🔄 Ghi Đè (Cập Nhật Bản Mới)", style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                do {
                    try? fm.removeItem(atPath: existing.path)
                    try fm.copyItem(at: item.tempURL, to: URL(fileURLWithPath: existing.path))
                    try? fm.removeItem(at: item.tempURL)
                    self.showToast(message: "Đã ghi đè cập nhật [\(existing.name)]!")
                } catch {
                    self.showToast(message: "Lỗi ghi đè: \(error.localizedDescription)")
                }
                self.processNextPendingImport()
            })

            alert.addAction(UIAlertAction(title: "➕ Cài Song Song (Giữ Cả 2 Bản)", style: .default) { [weak self] _ in
                guard let self = self else { return }
                let uniqueName = self.generateUniqueFileName(baseName: newFileName, inDir: gamesDir)
                let dest = URL(fileURLWithPath: gamesDir).appendingPathComponent(uniqueName)
                do {
                    try fm.copyItem(at: item.tempURL, to: dest)
                    try? fm.removeItem(at: item.tempURL)
                    self.showToast(message: "Đã cài đặt bản song song: [\(uniqueName)]!")
                } catch {
                    self.showToast(message: "Lỗi cài đặt: \(error.localizedDescription)")
                }
                self.processNextPendingImport()
            })

            alert.addAction(UIAlertAction(title: "❌ Hủy Bỏ (Không Cài)", style: .cancel) { [weak self] _ in
                try? fm.removeItem(at: item.tempURL)
                self?.showToast(message: "Đã hủy cài đặt [\(newFileName)].")
                self?.processNextPendingImport()
            })

            present(alert, animated: true)
        } else {
            // Không trùng: Cài đặt trực tiếp
            let destURL = URL(fileURLWithPath: gamesDir).appendingPathComponent(newFileName)
            do {
                try? fm.removeItem(at: destURL)
                try fm.copyItem(at: item.tempURL, to: destURL)
                try? fm.removeItem(at: item.tempURL)
                self.showToast(message: "Đã cài đặt [\(newName)]!")
            } catch {
                print("[Swift] Failed to install \(newFileName): \(error)")
            }
            processNextPendingImport()
        }
    }

    private func generateUniqueFileName(baseName: String, inDir dir: String) -> String {
        let fm = FileManager.default
        let ext = (baseName as NSString).pathExtension
        let nameWithoutExt = (baseName as NSString).deletingPathExtension

        var counter = 1
        var candidate = "\(nameWithoutExt)_\(counter).\(ext)"
        while fm.fileExists(atPath: (dir as NSString).appendingPathComponent(candidate)) {
            counter += 1
            candidate = "\(nameWithoutExt)_\(counter).\(ext)"
        }
        return candidate
    }

    // ============================================================
    // MARK: - Game Settings Resolution & Delete
    // ============================================================

    private static func gameId(for app: AppInfo) -> String {
        let jarName = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
        return jarName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    static func is3DSupersampling(for app: AppInfo) -> Bool {
        UserDefaults.standard.object(forKey: "ss3d_\(gameId(for: app))") as? Bool ?? false
    }

    static func resolution(for app: AppInfo) -> (w: Int, h: Int) {
        let gid = gameId(for: app)
        let w = UserDefaults.standard.object(forKey: "resW_\(gid)") as? Int ?? 0
        let h = UserDefaults.standard.object(forKey: "resH_\(gid)") as? Int ?? 0
        if w > 0 && h > 0 {
            return (w, h)
        }
        let scale = UserDefaults.standard.object(forKey: "res_scale_\(gid)") as? Int ?? 360
        let screen = UIScreen.main.bounds
        let sw = max(1.0, min(screen.width, screen.height))
        let sh = max(1.0, max(screen.width, screen.height))

        let isKbHidden = UserDefaults.standard.bool(forKey: "keypad_hidden_\(gid)")
        let kpH: CGFloat = isKbHidden ? 0.0 : 280.0
        let safeTop = UIApplication.shared.windows.first?.safeAreaInsets.top ?? 47.0
        let topBarH: CGFloat = 44.0 + safeTop

        let visibleH = max(120.0, sh - topBarH - kpH)
        let baseW = scale > 0 ? scale : Int(sw)
        var autoH = Int((Double(baseW) * Double(visibleH / sw)).rounded())
        if autoH % 2 != 0 { autoH += 1 }
        return (baseW, autoH)
    }

    static func fpsLimit(for app: AppInfo) -> Int {
        UserDefaults.standard.object(forKey: "fpsLimit_\(gameId(for: app))") as? Int ?? 30
    }

    private static var documentsDirectory: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
    }

    private func confirmClearGameData(for app: AppInfo) {
        let alert = UIAlertController(title: "Xóa Dữ Liệu Game",
                                       message: "Bạn có chắc muốn xóa toàn bộ dữ liệu lưu của \(app.name)?",
                                       preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { _ in
            let gid = Self.gameId(for: app)
            try? FileManager.default.removeItem(atPath: Self.documentsDirectory + "/Games Data/" + gid)
        })
        present(alert, animated: true)
    }

    private func confirmDeleteApp(at indexPath: IndexPath) {
        let app = apps[indexPath.item]
        let alert = UIAlertController(title: "Xóa Game",
                                       message: "Bạn có chắc muốn xóa \(app.name) cùng toàn bộ dữ liệu lưu?",
                                       preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let gid = Self.gameId(for: app)
            try? FileManager.default.removeItem(atPath: Self.documentsDirectory + "/Games Data/" + gid)
            try? FileManager.default.removeItem(atPath: app.path)
            self.springboardCollectionView.performBatchUpdates {
                self.apps.remove(at: indexPath.item)
                self.springboardCollectionView.deleteItems(at: [indexPath])
            }
            self.headerSubtitleLabel.text = "Đang Chạy: \(self.runningCount) / \(self.apps.count) Game"
            self.emptyStateLabel.isHidden = !self.apps.isEmpty
        })
        present(alert, animated: true)
    }
}
