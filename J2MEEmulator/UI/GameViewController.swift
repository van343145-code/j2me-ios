//
//  GameViewController.swift
//  J2MEEmulator
//
//  Runs a single J2ME MIDlet with 1:1 authentic KamenRider Decade UI:
//  - Top Toolbar: Title ("x27" / "Tài khoản"), [++], [+], [⌨], [📷], [⋮]
//  - Tab Strip: Dark navy strip (#1C2534) with active blue tab [ 1 ] (#1E69D2)
//  - Full-screen high-resolution Canvas between tab strip and keypad
//  - Authentic KamenRider Decade Virtual Keypad (pure directional keycodes, no accidental numbers!)
//  - "Bàn phím ảo" menu: Công tắc cấu trúc phím, Ẩn/Hiện phím, Kích thước, Độ mờ
//  - In-game TextBox with "✓" (V) Done button to dismiss keyboard
//  - AngelChip Menu with red softkeys (MENU, THOÁT)
//  - Double-tap on canvas removed: Chat input ONLY opens when tapping [⌨] button
//

import UIKit

// MARK: - Layout mode

enum GameLayoutMode {
    case decade     // Portrait: Authentic Decade top bar, tab strip, canvas, and frosted keypad
    case ngage      // Landscape fallback
}

// MARK: - GameViewController

class GameViewController: UIViewController {

    var jarPath: String
    var appName: String
    var appIcon: UIImage
    var canvasWidth: Int
    var canvasHeight: Int
    let render3dScale: Int
    let fpsLimit: Int
    let layoutMode: GameLayoutMode

    static var currentActiveGameVC: GameViewController?
    static var slotFrames: [Int: CGImage] = [:]
    static let slotFrameLock = NSLock()

    static var activeTabCount: Int {
        guard let vc = activeGameViewController else { return 1 }
        return max(1, vc.tabButtons.count)
    }

    static func updateSlotFrame(slot: Int, image: CGImage) {
        slotFrameLock.lock()
        slotFrames[slot] = image
        slotFrameLock.unlock()

        DispatchQueue.main.async {
            guard let vc = activeGameViewController,
                  vc.activeTabIndex == slot else { return }
            if UIApplication.shared.applicationState == .active {
                vc.isAppInBackground = false
            }
            if vc.isAppInBackground {
                if DecadePiPManager.shared.isPiPActive {
                    DecadePiPManager.shared.updateFrame(image)
                }
                return
            }
            vc.emulatorView.layer.contents = image
            if DecadePiPManager.shared.isPiPActive {
                DecadePiPManager.shared.updateFrame(image)
            }
            DecadeMiniWindow.shared.updateFrame(image)
            if let icon = vc.placeholderIconView, icon.alpha > 0 {
                UIView.animate(withDuration: 0.15) { icon.alpha = 0 }
            }
        }
    }

    static func purgeInactiveSlotFrames() {
        let activeIdx = activeGameViewController?.activeTabIndex ?? -1
        slotFrameLock.lock()
        let keysToDrop = slotFrames.keys.filter { $0 != activeIdx }
        for k in keysToDrop {
            slotFrames.removeValue(forKey: k)
        }
        slotFrameLock.unlock()

        DispatchQueue.main.async {
            guard let vc = activeGameViewController else { return }
            for i in 0..<vc.tabSessions.count where i != vc.activeTabIndex {
                vc.tabSessions[i].screenshot = nil
            }
        }
    }

    var isAppInBackground: Bool = false

    let emulatorView = EmulatorView()
    private let pipHostView = UIView()
    private let glowContainer = UIView()
    private let glowContentView = UIView()

    // Screen views
    private lazy var textBoxView = J2METextBoxView()
    private lazy var formView = FormView()
    private lazy var listView = J2MEListView()

    private let backButton = UIButton(type: .system)
    private let lskButton = UIButton(type: .system)
    private let rskButton = UIButton(type: .system)
    private let softKeyHaptic = UIImpactFeedbackGenerator(style: .light)
    private(set) var placeholderIconView: UIImageView?

    // Decade UI components
    private var decadeKeypadView: DecadeKeypadView?
    private var keypadHeightConstraint: NSLayoutConstraint?
    private let topToolbar = UIView()
    private let backArrowBtn = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let tabStripContainer = UIView()
    private var tabStripHeightConstraint: NSLayoutConstraint?
    private let tabScrollView = UIScrollView()
    private let tabStrip = UIStackView()
    struct TabSession {
        let slotIndex: Int
        var jarPath: String
        var appName: String
        var gameId: String
        var saveRoot: String
        var icon: UIImage?
        var screenshot: UIImage?
        var activeUI: Int = 0 // 0 = Canvas, 1 = Form, 2 = List, 3 = TextBox
    }
    var tabSessions: [TabSession] = []
    var tabButtons: [UIButton] = []
    var activeTabIndex: Int = 0

    // Quick floating unhide keypad button
    private let floatingShowKeypadBtn = UIButton(type: .system)

    // Toolbar action buttons (Camera button removed per user request)
    private let multiTabBtn = UIButton(type: .system)
    private let addTabBtn = UIButton(type: .system)
    private let keyboardBtn = UIButton(type: .system)
    private let menuBtn = UIButton(type: .system)

    // Legacy controls (if in ngage mode)
    private var joystickView: JoystickView?
    private var numpadView: NumpadView?

    // Decade state
    private var isKeepAwake = false
    private var isAutoCleanRam = true
    private var isKeypadHidden = false
    private var keypadCurrentHeight: CGFloat = 280
    private var autoShutdownTimer: Timer?
    private var statsTimer: Timer?
    private var isUserInitiatedExit = false

    init(jarPath: String, appName: String, appIcon: UIImage,
         canvasWidth: Int = 240, canvasHeight: Int = 320,
         render3dScale: Int = 3, fpsLimit: Int = 0,
         layoutMode: GameLayoutMode = .decade) {
        self.jarPath = jarPath
        self.appName = appName
        self.appIcon = appIcon
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.render3dScale = render3dScale
        self.fpsLimit = fpsLimit
        self.layoutMode = layoutMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        setGlobalEmulatorView(nil)
        alertTimeoutWork?.cancel()
        autoShutdownTimer?.invalidate()
        statsTimer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = false
        GameViewController.slotFrameLock.lock()
        GameViewController.slotFrames.removeAll()
        GameViewController.slotFrameLock.unlock()
    }

    private var alertTimeoutWork: DispatchWorkItem?

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    private var currentGameId: String {
        let jarName = URL(fileURLWithPath: jarPath).deletingPathExtension().lastPathComponent
        return jarName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    private var legacyGameId: String {
        appName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    private var isForceFullscreenEnabled: Bool {
        UserDefaults.standard.bool(forKey: "fullscreen_\(currentGameId)") ||
        UserDefaults.standard.bool(forKey: "fullscreen_\(legacyGameId)")
    }

    private var isAspectFitEnabled: Bool {
        if let fill = UserDefaults.standard.object(forKey: "decade_fill_screen_\(currentGameId)") as? Bool {
            return !fill
        }
        if let fill = UserDefaults.standard.object(forKey: "decade_fill_screen_\(legacyGameId)") as? Bool {
            return !fill
        }
        let savedW = UserDefaults.standard.object(forKey: "resW_\(currentGameId)") as? Int ?? 0
        let savedH = UserDefaults.standard.object(forKey: "resH_\(currentGameId)") as? Int ?? 0
        if savedW == 0 || savedH == 0 {
            return false // "Tự Động": Kín màn hình mặc định
        }
        if let val = UserDefaults.standard.object(forKey: "aspect_\(currentGameId)") as? Bool {
            return val
        }
        if let val = UserDefaults.standard.object(forKey: "aspect_\(legacyGameId)") as? Bool {
            return val
        }
        return true
    }

    func calculateAutoCanvasSize() -> (w: Int, h: Int) {
        let gid = currentGameId
        let scale = UserDefaults.standard.object(forKey: "res_scale_\(gid)") as? Int ?? 360

        let viewW = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let viewH = view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height

        let safeTop = view.safeAreaInsets.top > 0 ? view.safeAreaInsets.top : (UIApplication.shared.windows.first?.safeAreaInsets.top ?? 47.0)
        let topBarH: CGFloat = 44.0
        let kpH: CGFloat = isKeypadHidden ? 0.0 : keypadCurrentHeight
        let visibleH = max(100.0, viewH - safeTop - topBarH - kpH)

        let baseW = scale > 0 ? scale : Int(viewW)
        var autoH = Int((Double(baseW) * Double(visibleH / viewW)).rounded())
        if autoH % 2 != 0 { autoH += 1 }
        return (baseW, autoH)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let savedKbHidden = UserDefaults.standard.bool(forKey: "keypad_hidden_\(currentGameId)")
        if savedKbHidden {
            isKeypadHidden = true
        }

        let savedW = UserDefaults.standard.object(forKey: "resW_\(currentGameId)") as? Int ?? 0
        let savedH = UserDefaults.standard.object(forKey: "resH_\(currentGameId)") as? Int ?? 0
        if savedW == 0 || savedH == 0 {
            let auto = calculateAutoCanvasSize()
            canvasWidth = auto.w
            canvasHeight = auto.h
        }

        emulatorView.canvasWidth = canvasWidth
        emulatorView.canvasHeight = canvasHeight

        switch layoutMode {
        case .decade:
            setupDecadeLayout()
        case .ngage:
            setupNGageLayout()
        }

        // Apply saved configuration: Aspect ratio & Forced Fullscreen
        let isAuto = (savedW == 0 || savedH == 0)
        let isForceFullscreen = isForceFullscreenEnabled
        emulatorView.isAspectFit = isAuto ? false : (isForceFullscreen ? false : isAspectFitEnabled)

        if isForceFullscreen || isKeypadHidden {
            decadeKeypadView?.isHidden = true
            floatingShowKeypadBtn.isHidden = isForceFullscreen
            keypadHeightConstraint?.constant = 0
        }

        // Placeholder icon — visible until first game frame
        let iconIV = UIImageView(image: appIcon)
        iconIV.contentMode = .center
        iconIV.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconIV)
        NSLayoutConstraint.activate([
            iconIV.centerXAnchor.constraint(equalTo: emulatorView.centerXAnchor),
            iconIV.centerYAnchor.constraint(equalTo: emulatorView.centerYAnchor),
        ])
        placeholderIconView = iconIV

        // Fade out placeholder on first rendered frame
        emulatorView.onFirstFrame = { [weak self] in
            guard let icon = self?.placeholderIconView else { return }
            UIView.animate(withDuration: 0.2) {
                icon.alpha = 0
            }
        }

        // NOTE: Double-tap on canvas is deliberately REMOVED so gameplay is never interrupted.
        // The [⌨] button in the top toolbar opens text input when desired.

        // Register native callbacks (use slotFlushCallback exclusively to avoid double CGImage flush!)
        setGlobalEmulatorView(emulatorView)
        j2me_render_set_flush_callback(nil)
        j2me_render_set_slot_flush_callback(slotFlushCallback)
        j2me_ui_set_callback(gameUICallback)
        activeGameViewController = self

        // Setup isolated Picture-in-Picture host view (prevents double screen overlapping bug)
        pipHostView.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        pipHostView.alpha = 0.01
        pipHostView.isUserInteractionEnabled = false
        view.insertSubview(pipHostView, at: 0)

        DecadePiPManager.shared.setup(sourceView: pipHostView)
        DecadePiPManager.shared.setGameInfo(name: appName, icon: appIcon, tabNumber: activeTabIndex + 1)

        // Observe app lifecycle for background power & connection preservation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackgroundChange),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppForegroundChange),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppForegroundChange),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        // Observe live configuration change (instant apply without game restart)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChanged(_:)),
            name: NSNotification.Name("DecadeConfigChanged"),
            object: nil
        )
        // Observe smart network transitions (Wi-Fi <-> 5G failover)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkSwitched(_:)),
            name: NSNotification.Name("DecadeNetworkSwitched"),
            object: nil
        )
        _ = DecadeNetworkManager.shared // Activate smart network monitor

        GameViewController.currentActiveGameVC = self
        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isAppInBackground = false
        j2me_render_set_background(0)
        j2me_input_post_key(0, 0)
        if let img = GameViewController.slotFrames[self.activeTabIndex] {
            self.emulatorView.displayImage(img)
        }
    }

    private var hasStartedGame = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasStartedGame {
            startGame()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pipHostView.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        DecadePiPManager.shared.updateLayout()
    }

    // ============================================================
    // MARK: - Decade 1:1 Authentic Portrait Layout
    // ============================================================

    private func setupDecadeLayout() {
        // 1. Top Toolbar (White background #FFFFFF matching Screenshot 1 & 2)
        topToolbar.backgroundColor = .white
        topToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topToolbar)

        // Back button on left (←)
        backArrowBtn.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        backArrowBtn.tintColor = UIColor(red: 0.12, green: 0.14, blue: 0.12, alpha: 1.0)
        backArrowBtn.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backArrowBtn.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.addSubview(backArrowBtn)

        // Title on left ("Thợ Đục Error" / appName) + Subtitle
        titleLabel.text = appName
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.10, green: 0.12, blue: 0.10, alpha: 1.0)

        subtitleLabel.text = "RAM: -- MB • CPU: --%"
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = UIColor(red: 0.18, green: 0.52, blue: 0.28, alpha: 1.0)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 1
        titleStack.isUserInteractionEnabled = true
        let cleanTap = UITapGestureRecognizer(target: self, action: #selector(triggerManualRamCleanup))
        titleStack.addGestureRecognizer(cleanTap)
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.addSubview(titleStack)
        startSystemStatsMonitor()

        // Toolbar action buttons on right: [+] [⌨] [⋮]
        let actionStack = UIStackView()
        actionStack.axis = .horizontal
        actionStack.spacing = 16
        actionStack.alignment = .center
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.addSubview(actionStack)

        // [+] Button in bold green (#2E7D32)
        addTabBtn.setImage(UIImage(systemName: "plus"), for: .normal)
        addTabBtn.tintColor = UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1.0)
        addTabBtn.addTarget(self, action: #selector(addTabTapped), for: .touchUpInside)

        // [⌨] Keyboard Button in dark grey (#374151)
        keyboardBtn.setImage(UIImage(systemName: "keyboard"), for: .normal)
        keyboardBtn.tintColor = UIColor(red: 0.20, green: 0.25, blue: 0.20, alpha: 1.0)
        keyboardBtn.addTarget(self, action: #selector(keyboardButtonTapped), for: .touchUpInside)

        // [⋮] Menu Button in dark grey (#374151)
        menuBtn.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuBtn.tintColor = UIColor(red: 0.20, green: 0.25, blue: 0.20, alpha: 1.0)
        menuBtn.transform = CGAffineTransform(rotationAngle: .pi / 2) // Rotate to vertical 3 dots!
        menuBtn.addTarget(self, action: #selector(showMenu), for: .touchUpInside)

        actionStack.addArrangedSubview(addTabBtn)
        actionStack.addArrangedSubview(keyboardBtn)
        actionStack.addArrangedSubview(menuBtn)

        // Bottom border for topToolbar
        let toolbarBorder = UIView()
        toolbarBorder.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
        toolbarBorder.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.addSubview(toolbarBorder)

        // 2. Tab Strip Bar (Hidden by default unless multi-tab)
        tabStripContainer.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
        tabStripContainer.isHidden = true
        tabStripContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabStripContainer)

        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabStripContainer.addSubview(tabScrollView)

        tabStrip.axis = .horizontal
        tabStrip.spacing = 6
        tabStrip.alignment = .center
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.addSubview(tabStrip)

        let tabHeightConstraint = tabStripContainer.heightAnchor.constraint(equalToConstant: 0)
        self.tabStripHeightConstraint = tabHeightConstraint

        NSLayoutConstraint.activate([
            backArrowBtn.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor, constant: 12),
            backArrowBtn.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            backArrowBtn.widthAnchor.constraint(equalToConstant: 32),
            backArrowBtn.heightAnchor.constraint(equalToConstant: 32),

            titleStack.leadingAnchor.constraint(equalTo: backArrowBtn.trailingAnchor, constant: 10),
            titleStack.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStack.leadingAnchor, constant: -8),

            actionStack.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor, constant: -14),
            actionStack.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),

            toolbarBorder.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor),
            toolbarBorder.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor),
            toolbarBorder.bottomAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            toolbarBorder.heightAnchor.constraint(equalToConstant: 0.5),

            tabScrollView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabScrollView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor, constant: 8),
            tabScrollView.trailingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor, constant: -8),
            tabScrollView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),

            tabStrip.topAnchor.constraint(equalTo: tabScrollView.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: tabScrollView.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: tabScrollView.trailingAnchor),
            tabStrip.bottomAnchor.constraint(equalTo: tabScrollView.bottomAnchor),
            tabStrip.heightAnchor.constraint(equalTo: tabScrollView.heightAnchor),
        ])

        // Initialize Tab 1 session
        let initialGid = appName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
        let initialSaveRoot = docs + "/Games Data/" + initialGid
        try? FileManager.default.createDirectory(atPath: initialSaveRoot, withIntermediateDirectories: true)
        tabSessions = [
            TabSession(slotIndex: 0, jarPath: jarPath, appName: appName, gameId: initialGid, saveRoot: initialSaveRoot, icon: appIcon, screenshot: nil)
        ]
        createTabButton(index: 0)
        selectTab(at: 0)

        // 3. Virtual Keypad at bottom
        let keypad = DecadeKeypadView()
        let gid = currentGameId
        let legGid = legacyGameId
        keypad.gameId = gid
        let savedLayout = (UserDefaults.standard.object(forKey: "keypad_layout_\(gid)") as? Int)
            ?? (UserDefaults.standard.object(forKey: "keypad_layout_\(legGid)") as? Int)
            ?? 0
        keypad.currentLayout = DecadeKeypadLayout(rawValue: savedLayout) ?? .tuoitho
        let savedAlpha = (UserDefaults.standard.object(forKey: "keypad_alpha_\(gid)") as? Float)
            ?? (UserDefaults.standard.object(forKey: "keypad_alpha_\(legGid)") as? Float)
            ?? 255.0
        keypad.keypadAlphaValue = (keypad.currentLayout == .tuoitho) ? 1.0 : max(0.35, CGFloat(savedAlpha / 255.0))

        keypad.translatesAutoresizingMaskIntoConstraints = false
        self.decadeKeypadView = keypad
        view.addSubview(keypad)

        // Floating unhide keypad button (visible when keypad is hidden)
        floatingShowKeypadBtn.setTitle("⌨ Bật phím", for: .normal)
        floatingShowKeypadBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        floatingShowKeypadBtn.setTitleColor(.white, for: .normal)
        floatingShowKeypadBtn.backgroundColor = UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 0.90)
        floatingShowKeypadBtn.layer.cornerRadius = 16
        floatingShowKeypadBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        floatingShowKeypadBtn.addTarget(self, action: #selector(toggleKeypadVisibility), for: .touchUpInside)
        floatingShowKeypadBtn.isHidden = true
        floatingShowKeypadBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingShowKeypadBtn)

        // 4. Game Canvas (fills between tab strip and keypad)
        emulatorView.translatesAutoresizingMaskIntoConstraints = false
        emulatorView.backgroundColor = .black
        view.addSubview(emulatorView)

        // 5. Native Screen Views (TextBox, Form, List)
        for v: UIView in [textBoxView, formView, listView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
            v.isHidden = true
        }

        let heightConstraint = keypad.heightAnchor.constraint(equalToConstant: keypadCurrentHeight)
        self.keypadHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            // Top Toolbar pinned below Safe Area
            topToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topToolbar.heightAnchor.constraint(equalToConstant: 44),

            // Tab Strip right under Top Toolbar
            tabStripContainer.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            tabStripContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabStripContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabHeightConstraint,

            // Keypad at bottom
            keypad.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keypad.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keypad.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,

            // Floating unhide keypad button
            floatingShowKeypadBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            floatingShowKeypadBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),

            // Game Canvas fills between Tab Strip and Keypad
            emulatorView.topAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),
            emulatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emulatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emulatorView.bottomAnchor.constraint(equalTo: keypad.topAnchor),

            // Screen Views fill between Tab Strip and View Bottom
            textBoxView.topAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),
            textBoxView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textBoxView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textBoxView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            formView.topAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),
            formView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            formView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            listView.topAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.bringSubviewToFront(topToolbar)
        view.bringSubviewToFront(tabStripContainer)
        view.bringSubviewToFront(keypad)
        view.bringSubviewToFront(floatingShowKeypadBtn)
    }

    private func styleToolbarButton(_ btn: UIButton, title: String, action: Selector) {
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        btn.setTitleColor(.white, for: .normal)
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        btn.addTarget(self, action: action, for: .touchUpInside)
    }

    // ============================================================
    // MARK: - Toolbar Actions
    // ============================================================

    // ============================================================
    // MARK: - Tab Management (+ and ++)
    // ============================================================

    private func createTabButton(index: Int) {
        let tabBtn = UIButton(type: .custom)
        tabBtn.setTitle("\(index + 1)", for: .normal)
        tabBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        tabBtn.layer.cornerRadius = 4
        tabBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        tabBtn.tag = index
        tabBtn.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(tabButtonLongPressed(_:)))
        tabBtn.addGestureRecognizer(longPress)

        tabStrip.addArrangedSubview(tabBtn)
        tabButtons.append(tabBtn)
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        selectTab(at: sender.tag)
    }

    @objc private func tabButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let btn = gesture.view as? UIButton else { return }
        let slot = btn.tag
        let appName = (slot < tabSessions.count) ? tabSessions[slot].appName : "Game"

        let sheet = UIAlertController(
            title: "Tùy chọn Tab \(slot + 1): \(appName)",
            message: nil,
            preferredStyle: .actionSheet
        )

        sheet.addAction(UIAlertAction(title: "🌐 Gắn Proxy cho Tab \(slot + 1)", style: .default) { [weak self] _ in
            self?.showProxyPickerForSlot(slot)
        })

        if slot > 0 {
            sheet.addAction(UIAlertAction(title: "❌ Đóng Tab \(slot + 1)", style: .destructive) { [weak self] _ in
                self?.closeTab(at: slot)
            })
        }

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = btn
            popover.sourceRect = btn.bounds
        }
        present(sheet, animated: true)
    }

    private func showProxyPickerForSlot(_ slot: Int) {
        openProxyManager(segment: 1)
    }

    private func closeTab(at index: Int) {
        guard index > 0 && index < tabButtons.count else { return }
        jvm_bridge_request_stop_slot(Int32(index))
        jvm_bridge_destroy_slot(Int32(index))

        let btn = tabButtons[index]
        btn.removeFromSuperview()
        tabButtons.remove(at: index)
        if index < tabSessions.count {
            tabSessions.remove(at: index)
        }

        GameViewController.slotFrameLock.lock()
        GameViewController.slotFrames.removeValue(forKey: index)
        GameViewController.slotFrameLock.unlock()

        for (i, b) in tabButtons.enumerated() {
            b.tag = i
            b.setTitle("\(i + 1)", for: .normal)
        }

        let newActive = min(activeTabIndex, tabButtons.count - 1)
        selectTab(at: newActive)
        showToast(message: "Đã đóng Tab \(index + 1)")
    }

    private func selectTab(at index: Int) {
        guard index >= 0 && index < tabButtons.count else { return }

        // Capture screenshot and UI state of current tab before switching
        if activeTabIndex != index && activeTabIndex < tabSessions.count {
            tabSessions[activeTabIndex].screenshot = takeSnapshot()
            if !formView.isHidden {
                tabSessions[activeTabIndex].activeUI = 1
            } else if !listView.isHidden {
                tabSessions[activeTabIndex].activeUI = 2
            } else if !textBoxView.isHidden {
                tabSessions[activeTabIndex].activeUI = 3
            } else {
                tabSessions[activeTabIndex].activeUI = 0
            }
        }

        activeTabIndex = index
        let session = (index < tabSessions.count) ? tabSessions[index] : tabSessions.first!

        // Switch focused slot in JVM bridge (switches display rendering & input routing)
        jvm_bridge_set_focused_slot(Int32(index))

        // Dynamically update save root for data isolation (-tabN)
        session.saveRoot.withCString { cstr in
            jvm_bridge_set_save_root(cstr)
        }

        // Update top bar title & current session info
        titleLabel.text = session.appName
        appName = session.appName
        jarPath = session.jarPath
        DecadeFloatingBubble.shared.setGameInfo(name: session.appName, icon: appIcon, tabNumber: index + 1)
        DecadeMiniWindow.shared.setTabInfo(tabNumber: index + 1)
        if let icon = session.icon {
            appIcon = icon
        }
        DecadePiPManager.shared.setGameInfo(name: session.appName, icon: appIcon, tabNumber: index + 1)

        for (i, btn) in tabButtons.enumerated() {
            if i == index {
                btn.backgroundColor = UIColor(red: 0.12, green: 0.41, blue: 0.82, alpha: 1.0)
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = UIColor(red: 0.16, green: 0.20, blue: 0.27, alpha: 1.0)
                btn.setTitleColor(UIColor(white: 0.85, alpha: 1.0), for: .normal)
            }
        }

        // Scroll tab into view
        let targetBtn = tabButtons[index]
        tabScrollView.scrollRectToVisible(targetBtn.frame, animated: true)

        decadeKeypadView?.isHidden = isKeypadHidden
        floatingShowKeypadBtn.isHidden = isForceFullscreenEnabled || !isKeypadHidden

        // Restore active UI state for this tab
        if session.activeUI == 1 {
            showFormView()
        } else if session.activeUI == 2 {
            showListView()
        } else if session.activeUI == 3 {
            showTextBoxView()
        } else {
            showCanvasView()
            // Immediately isolate and show this tab's frame!
            GameViewController.slotFrameLock.lock()
            let cachedFrame = GameViewController.slotFrames[index]
            GameViewController.slotFrameLock.unlock()

            if let frame = cachedFrame {
                emulatorView.displayImage(frame)
                placeholderIconView?.alpha = 0
            } else if let shot = session.screenshot?.cgImage {
                emulatorView.displayImage(shot)
                placeholderIconView?.alpha = 0
            } else {
                // New slot has not produced any frame yet: clear canvas and show icon
                emulatorView.layer.contents = nil
                placeholderIconView?.image = session.icon
                placeholderIconView?.alpha = 1.0
            }
        }

        showToast(message: "Chuyển sang Tab \(index + 1): \(session.appName)")
    }

    private func addNewTab(jarPath: String, appName: String, icon: UIImage) {
        let newSlot = tabButtons.count
        guard newSlot < 32 else {
            showToast(message: "Đã đạt tối đa 32 tab")
            return
        }

        let gid = appName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path

        // Data isolation logic:
        // If this game was already opened in any previous tab, or slot > 0, isolate into -tab(N)
        let sameGameCount = tabSessions.filter { $0.gameId == gid }.count
        let saveRoot: String
        if sameGameCount == 0 && newSlot == 0 {
            saveRoot = docs + "/Games Data/" + gid
        } else {
            saveRoot = docs + "/Games Data/" + gid + "-tab\(newSlot + 1)"
        }
        try? FileManager.default.createDirectory(atPath: saveRoot, withIntermediateDirectories: true)

        let session = TabSession(
            slotIndex: newSlot,
            jarPath: jarPath,
            appName: appName,
            gameId: gid,
            saveRoot: saveRoot,
            icon: icon,
            screenshot: nil,
            activeUI: 0
        )
        tabSessions.append(session)
        createTabButton(index: newSlot)

        if newSlot == 0 {
            selectTab(at: 0)
        } else {
            // Real Multi-Tab Execution: Launch independent MiniJVM instance for newSlot!
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                guard let resRoot = Bundle.main.resourcePath else { return }
                DecadeProxyManager.shared.syncToNative(appId: appName, slot: newSlot)
                DecadeChangeIpViewController.syncToNative()
                let initResult = jvm_bridge_init_slot(
                    Int32(newSlot),
                    resRoot,
                    saveRoot,
                    jarPath,
                    Int32(self.canvasWidth),
                    Int32(self.canvasHeight),
                    Int32(self.render3dScale),
                    Int32(self.fpsLimit)
                )
                guard initResult == 0 else {
                    print("[Swift] ERROR: Slot \(newSlot) JVM init failed with code \(initResult)")
                    return
                }
                print("[Swift] Slot \(newSlot) MiniJVM running midlet: \(jarPath)")
                let runResult = jvm_bridge_run_midlet_slot(Int32(newSlot), jarPath)
                print("[Swift] Slot \(newSlot) MiniJVM completed with code \(runResult)")
                jvm_bridge_destroy_slot(Int32(newSlot))
            }

            selectTab(at: newSlot)
        }

        let folderName = URL(fileURLWithPath: saveRoot).lastPathComponent
        showToast(message: "Đã thêm Tab \(newSlot + 1): \(appName)\n(Thư mục data: \(folderName))")
    }

    @objc private func addTabTapped() {
        let maxAvailable = 100 - tabButtons.count
        if maxAvailable <= 0 {
            showToast(message: "Đã đạt tối đa 100 tab")
            return
        }

        let installedApps = AppsListViewController.loadInstalledApps()

        let alert = UIAlertController(
            title: "Thêm Tab Mới",
            message: "Chọn game để chạy trên Tab \(tabButtons.count + 1):",
            preferredStyle: .actionSheet
        )

        // 1. Current game option (Cloning / duplicate)
        alert.addAction(UIAlertAction(title: "⧉ Nhân bản game hiện tại (\(appName))", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.addNewTab(jarPath: self.jarPath, appName: self.appName, icon: self.appIcon)
        })

        // 2. Installed games options from lobby / library
        for app in installedApps {
            if app.path != self.jarPath {
                alert.addAction(UIAlertAction(title: "🎮 " + app.name, style: .default) { [weak self] _ in
                    guard let self = self else { return }
                    self.addNewTab(jarPath: app.path, appName: app.name, icon: app.icon)
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = addTabBtn
            popover.sourceRect = addTabBtn.bounds
        }
        present(alert, animated: true)
    }

    @objc private func multiTabTapped() {
        let maxAvailable = 100 - tabButtons.count
        if maxAvailable <= 0 {
            showToast(message: "Đã đạt tối đa 100 tab")
            return
        }

        let installedApps = AppsListViewController.loadInstalledApps()

        let alert = UIAlertController(
            title: "Mở nhiều tab (++)",
            message: "Nhập số lượng tab và chọn game cần mở:",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = "5"
            tf.keyboardType = .numberPad
            tf.placeholder = "Số tab (tối đa \(maxAvailable))"
        }

        // Action for current game
        alert.addAction(UIAlertAction(title: "⧉ Mở cho: \(appName)", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let count = Int(alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
            let safeCount = max(1, min(count, maxAvailable))
            for _ in 0..<safeCount {
                self.addNewTab(jarPath: self.jarPath, appName: self.appName, icon: self.appIcon)
            }
        })

        // Actions for other installed games
        for app in installedApps.prefix(4) {
            if app.path != self.jarPath {
                alert.addAction(UIAlertAction(title: "🎮 " + app.name, style: .default) { [weak self, weak alert] _ in
                    guard let self = self else { return }
                    let count = Int(alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
                    let safeCount = max(1, min(count, maxAvailable))
                    for _ in 0..<safeCount {
                        self.addNewTab(jarPath: app.path, appName: app.name, icon: app.icon)
                    }
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    func captureScreenshot() -> UIImage? {
        return takeSnapshot()
    }

    private func takeSnapshot() -> UIImage? {
        let size = emulatorView.bounds.size
        guard size.width > 0 && size.height > 0, emulatorView.window != nil else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            emulatorView.drawHierarchy(in: emulatorView.bounds, afterScreenUpdates: false)
        }
    }

    // ============================================================
    // MARK: - Popup Menu 3 Chấm Chuẩn 1:1 Bản Tuổi Thơ (Ảnh 1)
    // ============================================================

    @objc private func showMenu() {
        softKeyHaptic.impactOccurred(intensity: 0.6)
        let popup = TuoiThoPopupMenuView()
        popup.isKeypadHidden = self.isKeypadHidden

        popup.onOpenGameSettings = { [weak self] in
            self?.openInGameSettings()
        }
        popup.onOpenProxySettings = { [weak self] in
            self?.openProxyManager(segment: 0)
        }
        popup.onCleanRam = { [weak self] in
            self?.triggerManualRamCleanup()
        }
        popup.onOpenKeyboardSettings = { [weak self] in
            self?.promptChangeKeyboardLayout()
        }
        popup.onArrangeKeyboard = { [weak self] in
            self?.decadeKeypadView?.toggleEditMode()
            self?.showToast(message: "Kéo thả để sắp xếp các phím ảo")
        }
        popup.onToggleKeyboardVisibility = { [weak self] in
            self?.toggleKeypadVisibility()
        }
        popup.onRestartGame = { [weak self] in
            self?.restartGameSession()
        }
        popup.onExitGame = { [weak self] in
            self?.forceExitGame()
        }

        popup.show(in: view)
    }

    private func promptChangeKeyboardLayout() {
        let alert = UIAlertController(title: "Cài Đặt Bàn Phím", message: "Chọn kiểu bàn phím ảo hiển thị:", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "⭐️ Bản Tuổi Thơ (Chuẩn Mới)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.decadeKeypadView?.currentLayout = .tuoitho
            UserDefaults.standard.set(0, forKey: "keypad_layout_\(self.currentGameId)")
            self.showToast(message: "Đã chọn Bàn phím Tuổi Thơ")
        })
        alert.addAction(UIAlertAction(title: "🎯 Chỉ Mũi Tên Điều Hướng", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.decadeKeypadView?.currentLayout = .arrows
            UserDefaults.standard.set(1, forKey: "keypad_layout_\(self.currentGameId)")
            self.showToast(message: "Đã chọn Bàn phím Mũi Tên")
        })
        alert.addAction(UIAlertAction(title: "🔢 Bàn Phím Số (Numpad)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.decadeKeypadView?.currentLayout = .numpad
            UserDefaults.standard.set(2, forKey: "keypad_layout_\(self.currentGameId)")
            self.showToast(message: "Đã chọn Bàn phím Số")
        })
        alert.addAction(UIAlertAction(title: "🔄 Kết Hợp Đầy Đủ", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.decadeKeypadView?.currentLayout = .combined
            UserDefaults.standard.set(3, forKey: "keypad_layout_\(self.currentGameId)")
            self.showToast(message: "Đã chọn Bàn phím Kết Hợp")
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = menuBtn
            popover.sourceRect = menuBtn.bounds
        }
        present(alert, animated: true)
    }

    private func restartGameSession() {
        showToast(message: "Đang khởi động lại game...")
        let savedW = UserDefaults.standard.object(forKey: "resW_\(currentGameId)") as? Int ?? 0
        let savedH = UserDefaults.standard.object(forKey: "resH_\(currentGameId)") as? Int ?? 0
        let targetSize = (savedW > 0 && savedH > 0) ? (savedW, savedH) : calculateAutoCanvasSize()
        self.canvasWidth = targetSize.0
        self.canvasHeight = targetSize.1
        self.emulatorView.canvasWidth = targetSize.0
        self.emulatorView.canvasHeight = targetSize.1
        let isAuto = (savedW == 0 || savedH == 0)
        self.emulatorView.isAspectFit = isAuto ? false : (self.isForceFullscreenEnabled ? false : self.isAspectFitEnabled)

        let slot = Int32(self.activeTabIndex)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            jvm_bridge_request_stop_slot(slot)
            Thread.sleep(forTimeInterval: 0.35)
            jvm_bridge_destroy_slot(slot)
            Thread.sleep(forTimeInterval: 0.15)
            DispatchQueue.main.async {
                self.startGame()
            }
        }
    }

    // ============================================================
    // MARK: - Live RAM / CPU Status Bar & 1-Tap RAM Cleaner
    // ============================================================

    private func startSystemStatsMonitor() {
        statsTimer?.invalidate()
        updateSystemStatsLabel()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateSystemStatsLabel()
        }
    }

    private func updateSystemStatsLabel() {
        guard !isAppInBackground else { return }
        let usedRamMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
        let totalRamGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
        let cpuPct = min(999.0, max(0.0, jvm_bridge_get_cpu_usage_percent()))

        subtitleLabel.text = String(format: "RAM: %.0f MB / %.0f GB • CPU: %.0f%%", usedRamMB, totalRamGB, cpuPct)
        if usedRamMB > 220.0 || cpuPct > 80.0 {
            subtitleLabel.textColor = UIColor(red: 0.85, green: 0.35, blue: 0.10, alpha: 1.0) // Warning orange
        } else {
            subtitleLabel.textColor = UIColor(red: 0.18, green: 0.52, blue: 0.28, alpha: 1.0) // Healthy green
        }
    }

    @objc private func triggerManualRamCleanup() {
        softKeyHaptic.impactOccurred(intensity: 0.7)
        showToast(message: "Đang dọn dẹp RAM...")
        DecadeBackgroundKeeper.shared.performRamCleanup { [weak self] beforeMB, afterMB in
            guard let self = self else { return }
            self.updateSystemStatsLabel()
            let saved = max(0.0, beforeMB - afterMB)
            if saved >= 0.5 {
                self.showToast(message: String(format: "Đã dọn RAM: %.0f MB → %.0f MB (giảm %.1f MB)", beforeMB, afterMB, saved))
            } else {
                self.showToast(message: String(format: "RAM đang tối ưu: %.0f MB", afterMB))
            }
        }
    }

    private func openInGameSettings() {
        let fileName = URL(fileURLWithPath: jarPath).lastPathComponent
        let appInfo = AppsListViewController.AppInfo(
            name: appName,
            path: jarPath,
            fileName: fileName,
            version: "1.0",
            vendor: nil,
            icon: appIcon,
            fileSizeString: "0 MB",
            resolutionString: "Tự Động"
        )
        let configVC = DecadeConfigViewController(app: appInfo, onStart: nil)
        let nav = UINavigationController(rootViewController: configVC)
        nav.modalPresentationStyle = UIModalPresentationStyle.formSheet
        present(nav, animated: true)
    }

    @objc private func handleAppBackgroundChange() {
        isAppInBackground = true
    }

    @objc private func handleAppForegroundChange() {
        isAppInBackground = false
        j2me_render_set_background(0)
        // Request immediate frame redraw upon unlock
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let img = GameViewController.slotFrames[self.activeTabIndex] {
                self.emulatorView.displayImage(img)
            }
            j2me_input_post_key(0, 0)
        }
    }

    @objc private func handleNetworkSwitched(_ notif: Notification) {
        if let msg = notif.userInfo?["message"] as? String {
            showToast(message: msg)
        }
    }

    @objc private func handleConfigChanged(_ notif: Notification) {
        let savedW = UserDefaults.standard.object(forKey: "resW_\(currentGameId)") as? Int ?? 0
        let savedH = UserDefaults.standard.object(forKey: "resH_\(currentGameId)") as? Int ?? 0
        let targetSize = (savedW > 0 && savedH > 0) ? (savedW, savedH) : calculateAutoCanvasSize()

        let isAuto = (savedW == 0 || savedH == 0)
        let isForceFullscreen = isForceFullscreenEnabled
        emulatorView.isAspectFit = isAuto ? false : (isForceFullscreen ? false : isAspectFitEnabled)

        let savedLayout = (UserDefaults.standard.object(forKey: "keypad_layout_\(currentGameId)") as? Int) ??
                          (UserDefaults.standard.object(forKey: "keypad_layout_\(legacyGameId)") as? Int) ?? 0
        decadeKeypadView?.currentLayout = DecadeKeypadLayout(rawValue: savedLayout) ?? .tuoitho

        if let treo = notif.userInfo?["treo"] as? Bool {
            DecadeBackgroundKeeper.shared.setTreoActive(treo)
        }

        let savedAlpha = (UserDefaults.standard.object(forKey: "keypad_alpha_\(currentGameId)") as? Float) ??
                         (UserDefaults.standard.object(forKey: "keypad_alpha_\(legacyGameId)") as? Float) ?? 255.0
        if let kp = decadeKeypadView {
            kp.keypadAlphaValue = (kp.currentLayout == .tuoitho) ? 1.0 : max(0.35, CGFloat(savedAlpha / 255.0))
        }

        let savedKbHidden = UserDefaults.standard.bool(forKey: "keypad_hidden_\(currentGameId)")
        if isForceFullscreen || savedKbHidden {
            isKeypadHidden = true
            decadeKeypadView?.isHidden = true
            floatingShowKeypadBtn.isHidden = isForceFullscreen
            keypadHeightConstraint?.constant = 0
        } else {
            isKeypadHidden = false
            updateKeypadVisibility()
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()

        if targetSize.0 != self.canvasWidth || targetSize.1 != self.canvasHeight {
            self.canvasWidth = targetSize.0
            self.canvasHeight = targetSize.1
            self.emulatorView.canvasWidth = targetSize.0
            self.emulatorView.canvasHeight = targetSize.1
            self.restartGameSession()
            return
        }

        showToast(message: "✅ Đã lưu và cập nhật thiết lập ngay lập tức!")
    }

    private func isCurrentOrientationLandscape() -> Bool {
        if let windowScene = view.window?.windowScene {
            return windowScene.interfaceOrientation.isLandscape
        }
        return view.bounds.width > view.bounds.height
    }

    private func toggleScreenOrientation() {
        let targetLandscape = !isCurrentOrientationLandscape()
        forceOrientation(toLandscape: targetLandscape)
    }

    private func forceOrientation(toLandscape: Bool) {
        if #available(iOS 16.0, *) {
            guard let windowScene = view.window?.windowScene else { return }
            let targetMask: UIInterfaceOrientationMask = toLandscape ? .landscapeRight : .portrait
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: targetMask)
            windowScene.requestGeometryUpdate(geometryPreferences) { [weak self] error in
                print("[GameViewController] Geometry update error: \(error)")
                self?.adjustLayoutForOrientation(isLandscape: toLandscape)
            }
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            let orientationValue = toLandscape ? UIInterfaceOrientation.landscapeRight.rawValue : UIInterfaceOrientation.portrait.rawValue
            UIDevice.current.setValue(orientationValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
            adjustLayoutForOrientation(isLandscape: toLandscape)
        }
    }

    private func adjustLayoutForOrientation(isLandscape: Bool) {
        let isForceFullscreen = isForceFullscreenEnabled
        if isForceFullscreen || isKeypadHidden {
            keypadHeightConstraint?.constant = 0
            decadeKeypadView?.isHidden = true
            floatingShowKeypadBtn.isHidden = isForceFullscreen
        } else {
            let targetHeight: CGFloat = isLandscape ? 150 : 245
            keypadCurrentHeight = targetHeight
            keypadHeightConstraint?.constant = targetHeight
            decadeKeypadView?.isHidden = false
            floatingShowKeypadBtn.isHidden = true
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let isLandscape = size.width > size.height
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.adjustLayoutForOrientation(isLandscape: isLandscape)
        }, completion: nil)
    }

    // OLED Pure Black Overlay for authentic "Treo tắt màn"
    private lazy var oledBlackOverlay: UIView = {
        let v = UIView(frame: UIScreen.main.bounds)
        v.backgroundColor = .black
        v.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissOledBlackOverlay))
        v.addGestureRecognizer(tap)
        let lbl = UILabel()
        lbl.text = "🌙 Đang treo tắt màn (Tiết kiệm pin)\nChạm vào màn hình để bật lại sáng"
        lbl.numberOfLines = 2
        lbl.textAlignment = .center
        lbl.textColor = UIColor(white: 0.35, alpha: 1.0)
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }()

    @objc private func dismissOledBlackOverlay() {
        UIView.animate(withDuration: 0.25, animations: {
            self.oledBlackOverlay.alpha = 0
        }) { _ in
            self.oledBlackOverlay.removeFromSuperview()
            self.oledBlackOverlay.alpha = 1.0
        }
    }

    private func setupFloatingBubble() {
        let currentTabName = (activeTabIndex < tabSessions.count) ? tabSessions[activeTabIndex].appName : appName
        DecadeFloatingBubble.shared.setGameInfo(name: currentTabName, icon: appIcon, tabNumber: activeTabIndex + 1)
        DecadeFloatingBubble.shared.onRestoreGame = { [weak self] in
            self?.dismissOledBlackOverlay()
        }
        DecadeFloatingBubble.shared.onToggleHeadless = { [weak self] in
            guard let self = self else { return }
            if self.oledBlackOverlay.superview != nil {
                self.dismissOledBlackOverlay()
            } else {
                self.view.window?.addSubview(self.oledBlackOverlay)
                self.view.window?.bringSubviewToFront(DecadeFloatingBubble.shared)
            }
        }
        DecadeFloatingBubble.shared.onSelectTabPrompt = { [weak self] in
            self?.promptSwitchTab()
        }
        DecadeFloatingBubble.shared.onAssignProxy = { [weak self] in
            self?.promptAssignProxyForCurrentTab()
        }
        DecadeFloatingBubble.shared.onToggleTreo = { [weak self] in
            self?.toggleTreoTatMan()
        }
        DecadeFloatingBubble.shared.onTogglePiP = {
            DecadePiPManager.shared.togglePiP()
        }
        DecadeFloatingBubble.shared.onToggleMiniWindow = { [weak self] in
            guard let self = self else { return }
            DecadeFloatingBubble.shared.hide()
            DecadeMiniWindow.shared.setTabInfo(tabNumber: self.activeTabIndex + 1)
            DecadeMiniWindow.shared.show(in: self.view.window)
        }
        DecadeMiniWindow.shared.onMinimizeToBubble = { [weak self] in
            guard let self = self else { return }
            DecadeMiniWindow.shared.hide()
            DecadeFloatingBubble.shared.setGameInfo(name: self.appName, icon: self.appIcon, tabNumber: self.activeTabIndex + 1)
            DecadeFloatingBubble.shared.show(in: self.view.window)
        }
        DecadeMiniWindow.shared.onTogglePiP = {
            DecadePiPManager.shared.togglePiP()
        }
        DecadeMiniWindow.shared.onSwitchTab = { [weak self] in
            guard let self = self, self.tabButtons.count > 1 else { return }
            let nextTab = (self.activeTabIndex + 1) % self.tabButtons.count
            self.selectTab(at: nextTab)
        }
        DecadeMiniWindow.shared.onShowMenu = {
            DecadeFloatingBubble.shared.showActionSheetMenu()
        }
    }

    private func promptSwitchTab() {
        let alert = UIAlertController(title: "Chọn Tab Midlet", message: "Đang mở \(tabButtons.count) tab:", preferredStyle: .actionSheet)
        for i in 0..<tabButtons.count {
            let isCurrent = (i == activeTabIndex)
            let tabTitle = (isCurrent ? "⦿ Tab \(i + 1) (Hiện tại)" : "○ Tab \(i + 1)")
            alert.addAction(UIAlertAction(title: tabTitle, style: .default) { [weak self] _ in
                self?.selectTab(at: i)
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = DecadeFloatingBubble.shared
            popover.sourceRect = DecadeFloatingBubble.shared.bounds
        }
        present(alert, animated: true)
    }

    private func toggleTreoTatMan() {
        isKeepAwake.toggle()
        DecadeBackgroundKeeper.shared.setTreoActive(isKeepAwake)
        if isKeepAwake {
            view.window?.addSubview(oledBlackOverlay)
            setupFloatingBubble()
            DecadeFloatingBubble.shared.show(in: view.window)
            view.window?.bringSubviewToFront(DecadeFloatingBubble.shared)
            DecadePiPManager.shared.startPiP()
            showToast(message: "Đã bật treo & Cửa sổ nổi ngoài màn hình")
        } else {
            dismissOledBlackOverlay()
            DecadeFloatingBubble.shared.hide()
            DecadeMiniWindow.shared.hide()
            DecadePiPManager.shared.stopPiP()
            showToast(message: "Đã tắt treo tắt màn")
        }
    }

    private func promptAssignProxyForCurrentTab() {
        let alert = UIAlertController(
            title: "Gán proxy — Tab \(activeTabIndex + 1)",
            message: "Chọn proxy áp dụng riêng cho tab này:",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "⦿ Mặc định (Không dùng proxy)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: "decade_tab_proxy_\(self.appName)_\(self.activeTabIndex)")
            self.showToast(message: "Tab \(self.activeTabIndex + 1): Sử dụng mạng mặc định")
        })

        // Check configured global proxy
        let host = UserDefaults.standard.string(forKey: "decade_proxy_host") ?? ""
        let port = UserDefaults.standard.string(forKey: "decade_proxy_port") ?? ""
        let proto = UserDefaults.standard.string(forKey: "decade_proxy_type") ?? "HTTP"

        if !host.isEmpty && !port.isEmpty {
            let proxyTitle = "\(proto) \(host):\(port)"
            alert.addAction(UIAlertAction(title: "⦾ Proxy chính: \(proxyTitle)", style: .default) { [weak self] _ in
                guard let self = self else { return }
                UserDefaults.standard.set(proxyTitle, forKey: "decade_tab_proxy_\(self.appName)_\(self.activeTabIndex)")
                self.showToast(message: "Đã gán \(proxyTitle) cho Tab \(self.activeTabIndex + 1)")
            })
        }

        // Additional preset proxies
        let presets = [
            "HTTP 103.152.112.5:8080",
            "SOCKS5 45.77.24.12:1080",
            "HTTP 14.225.205.10:3128"
        ]
        for p in presets {
            alert.addAction(UIAlertAction(title: "⦾ \(p)", style: .default) { [weak self] _ in
                guard let self = self else { return }
                UserDefaults.standard.set(p, forKey: "decade_tab_proxy_\(self.appName)_\(self.activeTabIndex)")
                self.showToast(message: "Đã gán \(p) cho Tab \(self.activeTabIndex + 1)")
            })
        }

        alert.addAction(UIAlertAction(title: "⚙ Quản lý & Thêm proxy mới...", style: .default) { [weak self] _ in
            self?.openProxyManager()
        })

        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = menuBtn
            popover.sourceRect = menuBtn.bounds
        }

        present(alert, animated: true)
    }

    private func openProxyManager(segment: Int = 0) {
        let proxyVC = DecadeProxyViewController()
        proxyVC.initialSegmentIndex = segment
        let nav = UINavigationController(rootViewController: proxyVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func openChangeIpDialog() {
        let changeIpVC = DecadeChangeIpViewController()
        let nav = UINavigationController(rootViewController: changeIpVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    // ============================================================
    // MARK: - Menu Bàn phím ảo cốt lõi của Decade
    // ============================================================

    @objc private func keyboardButtonTapped() {
        showVirtualKeyboardMenu()
    }

    @objc private func keyboardLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            promptTextInput()
        }
    }

    private func buildVirtualKeyboardMenu() -> UIMenu {
        let toggleKeypadItem = UIAction(
            title: isKeypadHidden ? "Bàn phím ảo (Đang tắt)" : "Bàn phím ảo (Đang bật)",
            image: UIImage(systemName: isKeypadHidden ? "keyboard" : "keyboard.fill"),
            state: isKeypadHidden ? .off : .on
        ) { [weak self] _ in
            self?.toggleKeypadVisibility()
        }

        let editLayoutItem = UIAction(
            title: "Chế độ chỉnh sửa cấu trúc phím",
            image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        ) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            if self.isKeypadHidden {
                self.isKeypadHidden = false
                self.updateKeypadVisibility()
            }
            keypad.isEditLayoutMode = true
            keypad.isResizeLayoutMode = false
            self.showToast(message: "Chế độ chỉnh sửa: Kéo thả các phím tự do")
        }

        let scaleLayoutItem = UIAction(
            title: "Chế độ thay đổi kích cỡ cấu trúc phím",
            image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        ) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            if self.isKeypadHidden {
                self.isKeypadHidden = false
                self.updateKeypadVisibility()
            }
            keypad.isResizeLayoutMode = true
            keypad.isEditLayoutMode = false
            self.showToast(message: "Chế độ thay đổi kích cỡ: Dùng 2 ngón tay thu phóng phím")
        }

        let finishEditItem = UIAction(
            title: "Hoàn thành chế độ chỉnh sửa",
            image: UIImage(systemName: "checkmark.circle.fill")
        ) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            keypad.finishEditingLayout()
            self.showToast(message: "Đã hoàn tất chế độ chỉnh sửa")
        }

        let switchLayoutItem = UIAction(
            title: "Công tắc cấu trúc phím",
            image: UIImage(systemName: "square.grid.3x3")
        ) { [weak self] _ in
            self?.showLayoutSwitchDialog()
        }

        let hideButtonsItem = UIAction(
            title: "Ẩn nút",
            image: UIImage(systemName: "eye.slash")
        ) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            let gid = self.appName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            let dialog = DecadeHideButtonsDialog(gameId: gid, currentHiddenKeys: keypad.hiddenKeys) { [weak self] newHiddenKeys in
                keypad.hiddenKeys = newHiddenKeys
                self?.showToast(message: "Đã cập nhật hiển thị nút")
            }
            self.present(dialog, animated: true)
        }

        let textInputItem = UIAction(
            title: "Nhập văn bản (IME)",
            image: UIImage(systemName: "character.cursor.ibeam")
        ) { [weak self] _ in
            self?.promptTextInput()
        }

        return UIMenu(
            title: "Bàn phím ảo",
            children: [
                toggleKeypadItem,
                editLayoutItem,
                scaleLayoutItem,
                finishEditItem,
                switchLayoutItem,
                hideButtonsItem,
                textInputItem
            ]
        )
    }

    private func showVirtualKeyboardMenu() {
        let alert = UIAlertController(title: "Bàn phím ảo", message: nil, preferredStyle: .actionSheet)

        // 1. Bàn phím ảo
        let hideTitle = isKeypadHidden ? "Bàn phím ảo (Đang tắt)" : "Bàn phím ảo (Đang bật)"
        alert.addAction(UIAlertAction(title: hideTitle, style: .default) { [weak self] _ in
            self?.toggleKeypadVisibility()
        })

        // 2. Chế độ chỉnh sửa cấu trúc phím
        alert.addAction(UIAlertAction(title: "Chế độ chỉnh sửa cấu trúc phím", style: .default) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            if self.isKeypadHidden {
                self.isKeypadHidden = false
                self.updateKeypadVisibility()
            }
            keypad.isEditLayoutMode = true
            keypad.isResizeLayoutMode = false
            self.showToast(message: "Chế độ chỉnh sửa: Kéo thả các phím tự do")
        })

        // 3. Chế độ thay đổi kích cỡ cấu trúc phím
        alert.addAction(UIAlertAction(title: "Chế độ thay đổi kích cỡ cấu trúc phím", style: .default) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            if self.isKeypadHidden {
                self.isKeypadHidden = false
                self.updateKeypadVisibility()
            }
            keypad.isResizeLayoutMode = true
            keypad.isEditLayoutMode = false
            self.showToast(message: "Chế độ thay đổi kích cỡ: Dùng 2 ngón tay thu phóng phím")
        })

        // 4. Hoàn thành chế độ chỉnh sửa
        alert.addAction(UIAlertAction(title: "Hoàn thành chế độ chỉnh sửa", style: .default) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            keypad.finishEditingLayout()
            self.showToast(message: "Đã hoàn tất chế độ chỉnh sửa")
        })

        // 5. Công tắc cấu trúc phím
        alert.addAction(UIAlertAction(title: "Công tắc cấu trúc phím", style: .default) { [weak self] _ in
            self?.showLayoutSwitchDialog()
        })

        // 6. Ẩn nút
        alert.addAction(UIAlertAction(title: "Ẩn nút", style: .default) { [weak self] _ in
            guard let self = self, let keypad = self.decadeKeypadView else { return }
            let gid = self.appName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            let dialog = DecadeHideButtonsDialog(gameId: gid, currentHiddenKeys: keypad.hiddenKeys) { [weak self] newHiddenKeys in
                keypad.hiddenKeys = newHiddenKeys
                self?.showToast(message: "Đã cập nhật hiển thị nút")
            }
            self.present(dialog, animated: true)
        })

        // 7. Nhập văn bản (IME)
        alert.addAction(UIAlertAction(title: "Nhập văn bản (IME)", style: .default) { [weak self] _ in
            self?.promptTextInput()
        })

        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = keyboardBtn
            popover.sourceRect = keyboardBtn.bounds
        }

        present(alert, animated: true)
    }

    @objc private func toggleKeypadVisibility() {
        isKeypadHidden.toggle()
        updateKeypadVisibility()
        showToast(message: isKeypadHidden ? "Đã ẩn bàn phím ảo" : "Đã hiện bàn phím ảo")
    }

    private func updateKeypadVisibility() {
        UserDefaults.standard.set(isKeypadHidden, forKey: "keypad_hidden_\(currentGameId)")
        decadeKeypadView?.isHidden = isKeypadHidden
        floatingShowKeypadBtn.isHidden = isForceFullscreenEnabled || !isKeypadHidden
        keypadHeightConstraint?.constant = isKeypadHidden ? 0 : keypadCurrentHeight
        if #available(iOS 14.0, *) {
            keyboardBtn.menu = buildVirtualKeyboardMenu()
        }
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    private func setKeypadHeight(_ height: CGFloat) {
        keypadCurrentHeight = height
        if !isKeypadHidden {
            keypadHeightConstraint?.constant = height
            UIView.animate(withDuration: 0.2) {
                self.view.layoutIfNeeded()
            }
        }
    }

    // Công tắc cấu trúc phím
    private func showLayoutSwitchDialog() {
        let alert = UIAlertController(title: "Công tắc cấu trúc phím", message: "Chọn kiểu bàn phím mong muốn:", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "1. Decade Mũi tên (Mặc định - Điều hướng 8 chiều)", style: .default) { [weak self] _ in
            self?.decadeKeypadView?.currentLayout = .arrows
            self?.showToast(message: "Đã chuyển sang: Bố cục Mũi tên Decade")
        })

        alert.addAction(UIAlertAction(title: "2. Bàn phím số (Numpad 0-9, *, #)", style: .default) { [weak self] _ in
            self?.decadeKeypadView?.currentLayout = .numpad
            self?.showToast(message: "Đã chuyển sang: Bàn phím số (0-9)")
        })

        alert.addAction(UIAlertAction(title: "3. Kết hợp (Mũi tên & Phím số)", style: .default) { [weak self] _ in
            self?.decadeKeypadView?.currentLayout = .combined
            self?.showToast(message: "Đã chuyển sang: Kết hợp Mũi tên & Số")
        })

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    // Tuỳ chỉnh kích thước bàn phím
    private func showKeypadSizeDialog() {
        let alert = UIAlertController(title: "Tuỳ chỉnh kích thước bàn phím", message: "Chọn chiều cao phù hợp với tay:", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Nhỏ gọn (210pt)", style: .default) { [weak self] _ in
            self?.setKeypadHeight(210)
            self?.showToast(message: "Kích thước: Nhỏ gọn")
        })
        alert.addAction(UIAlertAction(title: "Vừa phải (245pt - Mặc định)", style: .default) { [weak self] _ in
            self?.setKeypadHeight(245)
            self?.showToast(message: "Kích thước: Vừa phải")
        })
        alert.addAction(UIAlertAction(title: "Lớn (290pt)", style: .default) { [weak self] _ in
            self?.setKeypadHeight(290)
            self?.showToast(message: "Kích thước: Lớn")
        })
        alert.addAction(UIAlertAction(title: "Rất lớn (330pt)", style: .default) { [weak self] _ in
            self?.setKeypadHeight(330)
            self?.showToast(message: "Kích thước: Rất lớn")
        })

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    // Độ mờ / trong suốt
    private func showKeypadOpacityDialog() {
        let alert = UIAlertController(title: "Độ mờ bàn phím ảo", message: "Chọn mức độ trong suốt của phím:", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Trong suốt cao (40%)", style: .default) { [weak self] _ in
            self?.decadeKeypadView?.keypadAlphaValue = 0.40
            self?.showToast(message: "Đã chỉnh độ mờ: 40%")
        })
        alert.addAction(UIAlertAction(title: "Vừa phải (70% - Mặc định)", style: .default) { [weak self] _ in
            self?.decadeKeypadView?.keypadAlphaValue = 0.70
            self?.showToast(message: "Đã chỉnh độ mờ: 70%")
        })
        alert.addAction(UIAlertAction(title: "Đậm nét (100%)", style: .default) { [weak self] _ in
            self?.decadeKeypadView?.keypadAlphaValue = 1.00
            self?.showToast(message: "Đã chỉnh độ mờ: 100%")
        })

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    // Ẩn / Hiện từng phím
    private func showIndividualKeysToggleDialog() {
        guard let keypad = decadeKeypadView else { return }
        let alert = UIAlertController(title: "Ẩn / Hiện từng phím", message: "Bật hoặc tắt các nhóm phím theo nhu cầu:", preferredStyle: .alert)

        let diagTitle = (keypad.showDiagonalKeys ? "✓ " : "   ") + "Phím chéo (↖, ↗, ↙, ↘)"
        alert.addAction(UIAlertAction(title: diagTitle, style: .default) { [weak self] _ in
            keypad.showDiagonalKeys.toggle()
            self?.showToast(message: keypad.showDiagonalKeys ? "Đã hiện phím chéo" : "Đã ẩn phím chéo")
        })

        let softTitle = (keypad.showSoftKeys ? "✓ " : "   ") + "Phím chức năng (L, R)"
        alert.addAction(UIAlertAction(title: softTitle, style: .default) { [weak self] _ in
            keypad.showSoftKeys.toggle()
            self?.showToast(message: keypad.showSoftKeys ? "Đã hiện phím L, R" : "Đã ẩn phím L, R")
        })

        let fireTitle = (keypad.showFireKey ? "✓ " : "   ") + "Phím giữa F (Chọn / Đánh)"
        alert.addAction(UIAlertAction(title: fireTitle, style: .default) { [weak self] _ in
            keypad.showFireKey.toggle()
            self?.showToast(message: keypad.showFireKey ? "Đã hiện phím F" : "Đã ẩn phím F")
        })

        alert.addAction(UIAlertAction(title: "Xong", style: .cancel))
        present(alert, animated: true)
    }

    // Hẹn giờ tự tắt
    private func promptShutdownTimer() {
        let alert = UIAlertController(title: "⏰ Hẹn giờ tự tắt game", message: "Chọn thời gian sau đó tự động đóng game:", preferredStyle: .alert)
        for mins in [15, 30, 60, 120] {
            alert.addAction(UIAlertAction(title: "\(mins) phút", style: .default) { [weak self] _ in
                self?.autoShutdownTimer?.invalidate()
                self?.autoShutdownTimer = Timer.scheduledTimer(withTimeInterval: Double(mins * 60), repeats: false) { [weak self] _ in
                    self?.backTapped()
                }
                self?.showToast(message: "Đã đặt hẹn giờ tự tắt sau \(mins) phút")
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy hẹn giờ", style: .destructive) { [weak self] _ in
            self?.autoShutdownTimer?.invalidate()
            self?.autoShutdownTimer = nil
            self?.showToast(message: "Đã hủy hẹn giờ")
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = menuBtn
            popover.sourceRect = menuBtn.bounds
        }
        present(alert, animated: true)
    }

    // Giới hạn FPS
    private func promptFPSLimit() {
        let alert = UIAlertController(title: "Giới hạn FPS", message: "Chọn tốc độ khung hình mong muốn:", preferredStyle: .alert)
        for fps in [60, 30, 15] {
            alert.addAction(UIAlertAction(title: "\(fps) FPS", style: .default) { [weak self] _ in
                self?.showToast(message: "Đã chuyển giới hạn sang \(fps) FPS")
            })
        }
        alert.addAction(UIAlertAction(title: "Không giới hạn", style: .default) { [weak self] _ in
            self?.showToast(message: "Đã bật FPS không giới hạn")
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = menuBtn
            popover.sourceRect = menuBtn.bounds
        }
        present(alert, animated: true)
    }

    // Thay IP Phiên Bản
    private func promptChangeServerIP() {
        openChangeIpDialog()
    }

    // ============================================================
    // MARK: - Toast helper
    // ============================================================

    private func showToast(message: String) {
        let toast = UILabel()
        toast.text = message
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textColor = .black
        toast.backgroundColor = UIColor(white: 0.95, alpha: 0.95)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 18
        toast.clipsToBounds = true
        toast.layer.shadowColor = UIColor.black.cgColor
        toast.layer.shadowOpacity = 0.2
        toast.layer.shadowRadius = 4
        toast.layer.shadowOffset = CGSize(width: 0, height: 2)
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            toast.heightAnchor.constraint(equalToConstant: 38),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        toast.alpha = 0
        UIView.animate(withDuration: 0.25, animations: {
            toast.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: .curveEaseOut, animations: {
                toast.alpha = 0
            }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    // ============================================================
    // MARK: - Quick Text Input Dialog (⌨) on Canvas
    // ============================================================

    @objc func promptTextInput() {
        softKeyHaptic.impactOccurred(intensity: 0.7)
        let alert = UIAlertController(
            title: "⌨ Nhập văn bản vào Game",
            message: "Gõ tài khoản, mật khẩu hoặc tin nhắn chat:",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Gõ nội dung tại đây..."
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
            tf.clearButtonMode = .whileEditing
            tf.returnKeyType = .done

            if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !clip.isEmpty, clip.count <= 64 {
                tf.text = clip
            }
        }
        alert.addAction(UIAlertAction(title: "Gửi & Enter (↵)", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            self?.sendTextToMIDlet(text, sendEnter: true)
        })
        alert.addAction(UIAlertAction(title: "Chỉ gửi", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            self?.sendTextToMIDlet(text, sendEnter: false)
        })
        alert.addAction(UIAlertAction(title: "⌫ Xóa hết", style: .destructive) { [weak self] _ in
            self?.sendClearToMIDlet()
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    private func sendTextToMIDlet(_ text: String, sendEnter: Bool = false) {
        text.withCString { cstr in
            j2me_ui_set_textbox_text(cstr)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            for char in text {
                if let scalar = char.unicodeScalars.first {
                    let code = Int32(scalar.value)
                    j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), code)
                    usleep(15000)
                    j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), code)
                    usleep(15000)
                }
            }
            if sendEnter {
                usleep(50000)
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), -5) // Canvas.FIRE
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), 10) // '\n'
                usleep(20000)
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), 10)
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), -5)
            }
        }
    }

    private func sendClearToMIDlet() {
        "".withCString { cstr in
            j2me_ui_set_textbox_text(cstr)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<30 {
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), 8)
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), -8)
                usleep(10000)
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), 8)
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), -8)
                usleep(10000)
            }
        }
    }

    // ============================================================
    // MARK: - View switching (Canvas, TextBox, List, Form)
    // ============================================================

    func showCanvasView() {
        let currentTabName = (activeTabIndex < tabSessions.count) ? tabSessions[activeTabIndex].appName : appName
        titleLabel.text = currentTabName
        emulatorView.isHidden = false
        decadeKeypadView?.isHidden = isKeypadHidden
        floatingShowKeypadBtn.isHidden = isForceFullscreenEnabled || !isKeypadHidden
        textBoxView.isHidden = true
        formView.isHidden = true
        listView.isHidden = true
    }

    func showTextBoxView() {
        let formTitle = String(cString: j2me_ui_get_form_title())
        titleLabel.text = formTitle.isEmpty ? "Tài khoản" : formTitle
        textBoxView.buildFromNativeData()
        textBoxView.isHidden = false
        emulatorView.isHidden = true
        decadeKeypadView?.isHidden = true
        floatingShowKeypadBtn.isHidden = true
        formView.isHidden = true
        listView.isHidden = true
        view.bringSubviewToFront(textBoxView)
    }

    func showFormView() {
        let formTitle = String(cString: j2me_ui_get_form_title())
        titleLabel.text = formTitle.isEmpty ? appName : formTitle
        formView.buildFromNativeData()
        formView.isHidden = false
        emulatorView.isHidden = true
        decadeKeypadView?.isHidden = true
        floatingShowKeypadBtn.isHidden = true
        textBoxView.isHidden = true
        listView.isHidden = true
        view.bringSubviewToFront(formView)
    }

    func showListView() {
        let formTitle = String(cString: j2me_ui_get_form_title())
        titleLabel.text = formTitle.isEmpty ? "Menu" : formTitle
        listView.buildFromNativeData()
        listView.isHidden = false
        emulatorView.isHidden = true
        decadeKeypadView?.isHidden = true
        floatingShowKeypadBtn.isHidden = true
        textBoxView.isHidden = true
        formView.isHidden = true
        view.bringSubviewToFront(listView)
    }

    func showAlert() {
        let title = String(cString: j2me_ui_get_form_title())
        let text = String(cString: j2me_ui_get_alert_text())

        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)

        alertTimeoutWork?.cancel()
        alertTimeoutWork = nil

        let cmdCount = j2me_ui_get_command_count()
        if cmdCount == 0 {
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.alertTimeoutWork?.cancel()
                j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
            })
        } else {
            for i in 0..<cmdCount {
                let label = String(cString: j2me_ui_get_command_label(Int32(i)))
                let cmdId = j2me_ui_get_command_id(Int32(i))
                alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                    self?.alertTimeoutWork?.cancel()
                    j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmdId)
                })
            }
        }

        present(alert, animated: true)

        let timeout = j2me_ui_get_alert_timeout()
        if timeout > 0 {
            let work = DispatchWorkItem { [weak alert] in
                alert?.dismiss(animated: true) {
                    j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
                }
            }
            alertTimeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeout) / 1000.0, execute: work)
        }
    }

    // ============================================================
    // MARK: - Game Lifecycle
    // ============================================================

    private func startGame() {
        guard !hasStartedGame else {
            isAppInBackground = false
            j2me_render_set_background(0)
            j2me_input_post_key(0, 0)
            return
        }
        hasStartedGame = true
        isUserInitiatedExit = false
        GameViewController.currentActiveGameVC = self
        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)

        // Tự động kích hoạt chạy nền liên tục chuẩn NowPlaying/MediaPlayback và giữ kết nối không bị ngắt
        DecadeBackgroundKeeper.shared.updateNowPlayingGame(name: appName)
        DecadeBackgroundKeeper.shared.setTreoActive(true)
        UIApplication.shared.isIdleTimerDisabled = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.runMIDlet()
            DispatchQueue.main.async {
                if self.isUserInitiatedExit {
                    if self.presentingViewController != nil {
                        self.dismiss(animated: true) {
                            NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
                        }
                    } else {
                        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
                    }
                } else {
                    // Check if MIDlet actually quit cleanly (user chose "Thoát" in game)
                    if jvm_bridge_is_slot_running(0) == 0 {
                        print("[Swift] MIDlet finished cleanly by user in-game exit.")
                        self.forceExitGame()
                    } else {
                        print("[Swift] MIDlet finished unexpectedly while hanging (user did not tap Back)!")
                        self.handleUnexpectedGameExit()
                    }
                }
            }
        }
    }

    private func handleUnexpectedGameExit() {
        guard !isUserInitiatedExit else { return }
        hasStartedGame = false
        DecadeBackgroundKeeper.shared.updateNowPlayingGame(name: "\(appName) (Tự kết nối lại...)")

        showToast(message: "🔄 Game đã ngắt kết nối. Đang tự động kết nối lại sau 2 giây...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.isUserInitiatedExit else { return }
            print("[Swift] Auto-reconnecting / restarting game after unexpected exit...")
            self.startGame()
        }
    }

    private func runMIDlet() {
        guard let resRoot = Bundle.main.resourcePath else { return }
        let docs = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()

        let jarFileName = URL(fileURLWithPath: jarPath).deletingPathExtension().lastPathComponent
        let gameId = jarFileName.replacingOccurrences(of: "[^a-zA-Z0-9._-]",
                                                       with: "_", options: .regularExpression)
        let saveRoot = docs + "/Games Data/" + gameId
        try? FileManager.default.createDirectory(atPath: saveRoot, withIntermediateDirectories: true)

        DecadeProxyManager.shared.syncToNative(appId: appName, slot: 0)
        DecadeChangeIpViewController.syncToNative()

        let initResult = jvm_bridge_init(resRoot, saveRoot, jarPath,
                                         Int32(canvasWidth),
                                         Int32(canvasHeight),
                                         Int32(render3dScale),
                                         Int32(fpsLimit))
        guard initResult == 0 else {
            print("[Swift] ERROR: JVM init failed with code \(initResult)")
            return
        }

        let runResult = jvm_bridge_run_midlet(jarPath)
        print("[Swift] MIDlet run result: \(runResult)")
        jvm_bridge_destroy_slot(0)
    }

    @objc private func backTapped() {
        let alert = UIAlertController(
            title: "Trạng Thái Game",
            message: "Bạn muốn tiếp tục treo game chạy nền 24/7 hay thoát game hoàn toàn?",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Ẩn & Treo ngầm (Giữ game chạy 24/7)", style: .default) { [weak self] _ in
            self?.minimizeToLobby()
        })
        alert.addAction(UIAlertAction(title: "Thoát game hoàn toàn", style: .destructive) { [weak self] _ in
            self?.forceExitGame()
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = backArrowBtn
            popover.sourceRect = backArrowBtn.bounds
        }
        present(alert, animated: true)
    }

    func minimizeToLobby() {
        isAppInBackground = false
        dismiss(animated: true) {
            NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
        }
    }

    func forceExitGame() {
        isUserInitiatedExit = true
        hasStartedGame = false
        GameViewController.currentActiveGameVC = nil
        backButton.isEnabled = false
        autoShutdownTimer?.invalidate()
        autoShutdownTimer = nil
        DecadeFloatingBubble.shared.hide()
        DecadeMiniWindow.shared.hide()
        DecadePiPManager.shared.stopPiP()
        DecadeBackgroundKeeper.shared.setTreoActive(false)
        DecadeBackgroundKeeper.shared.stopKeepalive()
        UIApplication.shared.isIdleTimerDisabled = false

        // 1. Signal stop to ALL slots
        jvm_bridge_request_stop_all()

        // 2. Wake up event loop
        j2me_input_post_key(0, 0)

        // 3. Dismiss UI back to apps list immediately on main thread so it NEVER hangs/freezes!
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
            if self.presentingViewController != nil {
                self.dismiss(animated: true) {
                    DispatchQueue.global(qos: .background).async {
                        jvm_bridge_destroy_all()
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
                        }
                    }
                }
            } else {
                DispatchQueue.global(qos: .background).async {
                    jvm_bridge_destroy_all()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
                    }
                }
            }
        }
    }

    // ============================================================
    // MARK: - N-Gage Landscape Layout (Fallback)
    // ============================================================

    private func setupNGageLayout() {
        let joystick = JoystickView()
        let numpad = NumpadView()
        self.joystickView = joystick
        self.numpadView = numpad

        for v: UIView in [joystick, emulatorView, numpad, lskButton, rskButton, textBoxView, formView, listView, backButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        textBoxView.isHidden = true
        formView.isHidden = true
        listView.isHidden = true

        for (btn, title) in [(lskButton, "L"), (rskButton, "R")] {
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = UIColor(white: 0.12, alpha: 1)
            btn.layer.cornerRadius = 10
            btn.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
            btn.layer.borderWidth = 1
            btn.addTarget(self, action: #selector(softKeyDown(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(softKeyUp(_:)),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        lskButton.tag = -6
        rskButton.tag = -7

        backButton.setTitle("  ✕  ", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        backButton.backgroundColor = UIColor(white: 0.15, alpha: 0.85)
        backButton.setTitleColor(.white, for: .normal)
        backButton.layer.cornerRadius = 10
        backButton.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        backButton.layer.borderWidth = 1
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let canvasRatio: CGFloat = CGFloat(emulatorView.canvasWidth) / CGFloat(emulatorView.canvasHeight)
        let pad: CGFloat = 8

        let leftArea = UILayoutGuide()
        let rightArea = UILayoutGuide()
        view.addLayoutGuide(leftArea)
        view.addLayoutGuide(rightArea)

        NSLayoutConstraint.activate([
            leftArea.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            leftArea.trailingAnchor.constraint(equalTo: emulatorView.leadingAnchor),

            rightArea.leadingAnchor.constraint(equalTo: emulatorView.trailingAnchor),
            rightArea.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            emulatorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emulatorView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: pad),
            emulatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),
            emulatorView.widthAnchor.constraint(equalTo: emulatorView.heightAnchor, multiplier: canvasRatio),

            joystick.centerXAnchor.constraint(equalTo: leftArea.centerXAnchor),
            joystick.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            joystick.widthAnchor.constraint(equalToConstant: 160),
            joystick.heightAnchor.constraint(equalToConstant: 160),

            numpad.trailingAnchor.constraint(equalTo: rightArea.trailingAnchor, constant: -12),
            numpad.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            numpad.widthAnchor.constraint(equalToConstant: 140),
            numpad.heightAnchor.constraint(equalToConstant: 180),

            lskButton.trailingAnchor.constraint(equalTo: emulatorView.leadingAnchor, constant: -6),
            lskButton.bottomAnchor.constraint(equalTo: emulatorView.bottomAnchor),
            lskButton.widthAnchor.constraint(equalToConstant: 68),
            lskButton.heightAnchor.constraint(equalToConstant: 40),

            rskButton.leadingAnchor.constraint(equalTo: emulatorView.trailingAnchor, constant: 6),
            rskButton.bottomAnchor.constraint(equalTo: emulatorView.bottomAnchor),
            rskButton.widthAnchor.constraint(equalToConstant: 68),
            rskButton.heightAnchor.constraint(equalToConstant: 40),

            textBoxView.topAnchor.constraint(equalTo: view.topAnchor),
            textBoxView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textBoxView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textBoxView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            formView.topAnchor.constraint(equalTo: view.topAnchor),
            formView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            formView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            listView.topAnchor.constraint(equalTo: view.topAnchor),
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
        ])
    }

    @objc private func softKeyDown(_ sender: UIButton) {
        softKeyHaptic.impactOccurred(intensity: 0.6)
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), Int32(sender.tag))
        sender.backgroundColor = UIColor(white: 0.30, alpha: 1)
    }

    @objc private func softKeyUp(_ sender: UIButton) {
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), Int32(sender.tag))
        sender.backgroundColor = UIColor(white: 0.12, alpha: 1)
    }
}

// ============================================================
// MARK: - Global active GameViewController reference
// ============================================================

private(set) weak var activeGameViewController: GameViewController?

let gameUICallback: @convention(c) (Int32, UnsafePointer<CChar>?) -> Void = { action, data in
    DispatchQueue.main.async {
        guard let vc = activeGameViewController else { return }
        switch action {
        case Int32(J2ME_UI_ACTION_SHOW_CANVAS):  vc.showCanvasView()
        case Int32(J2ME_UI_ACTION_SHOW_FORM):    vc.showFormView()
        case Int32(J2ME_UI_ACTION_SHOW_LIST):    vc.showListView()
        case Int32(J2ME_UI_ACTION_SHOW_ALERT):   vc.showAlert()
        case Int32(J2ME_UI_ACTION_SHOW_TEXTBOX): vc.showTextBoxView()
        default: break
        }
    }
}

let slotFlushCallback: @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Int32) -> Void = { slot, cgImagePtr, width, height in
    guard let ptr = cgImagePtr else { return }
    let cgImage = Unmanaged<CGImage>.fromOpaque(ptr).takeRetainedValue()
    let slotIdx = Int(slot)
    GameViewController.updateSlotFrame(slot: slotIdx, image: cgImage)
}
