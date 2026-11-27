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

// MARK: - Split-Screen Mini Game Pane View (Up to 6 Screens)

final class SplitGamePaneView: UIView {
    let slotIndex: Int
    let imageView = UIImageView()
    let headerView = UIView()
    let titleLabel = UILabel()
    let badgeLabel = UILabel()
    var onTapped: ((Int) -> Void)?

    init(index: Int) {
        self.slotIndex = index
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        layer.cornerRadius = 6
        layer.borderWidth = 1.0
        layer.borderColor = UIColor(white: 0.25, alpha: 0.8).cgColor
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        addSubview(imageView)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        addSubview(headerView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.text = "Tab \(slotIndex + 1)"
        headerView.addSubview(titleLabel)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        badgeLabel.textColor = UIColor.lightGray
        badgeLabel.text = "Chạm để chọn"
        headerView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            badgeLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            imageView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    @objc private func handleTap() {
        onTapped?(slotIndex)
    }

    func setFocused(_ isFocused: Bool) {
        layer.borderWidth = isFocused ? 2.5 : 1.0
        layer.borderColor = isFocused ? UIColor.systemBlue.cgColor : UIColor(white: 0.25, alpha: 0.8).cgColor
        badgeLabel.textColor = isFocused ? UIColor.systemGreen : UIColor.lightGray
        badgeLabel.text = isFocused ? "⚡ Đang chọn" : "Chạm chọn"
        headerView.backgroundColor = isFocused ? UIColor(red: 0.08, green: 0.25, blue: 0.55, alpha: 0.85) : UIColor.black.withAlphaComponent(0.75)
    }
}

// MARK: - GameViewController

class GameViewController: UIViewController, UITextFieldDelegate {

    var jarPath: String
    var appName: String
    var appIcon: UIImage
    var canvasWidth: Int
    var canvasHeight: Int
    let render3dScale: Int
    let fpsLimit: Int
    let layoutMode: GameLayoutMode

    static var currentActiveGameVC: GameViewController?
    // Native frame callbacks and the main UI share this cache under the same lock.
    nonisolated(unsafe) static var slotFrames: [Int: CGImage] = [:]
    nonisolated static let slotFrameLock = NSLock()
    nonisolated(unsafe) private static var frameDispatchPending = false

    static var activeTabCount: Int {
        guard let vc = activeGameViewController else { return 1 }
        return max(1, vc.tabButtons.count)
    }

    nonisolated static func updateSlotFrame(slot: Int, image: CGImage) {
        slotFrameLock.lock()
        slotFrames[slot] = image
        if frameDispatchPending {
            slotFrameLock.unlock()
            return
        }
        frameDispatchPending = true
        slotFrameLock.unlock()

        DispatchQueue.main.async {
            let vc = activeGameViewController
            slotFrameLock.lock()
            frameDispatchPending = false
            let frame = vc.flatMap { slotFrames[$0.activeSlot] }
            var multiFrames: [Int: CGImage] = [:]
            if let vc = vc, vc.isSplitViewEnabled {
                for session in vc.tabSessions.prefix(6) {
                    if let f = slotFrames[session.slotIndex] {
                        multiFrames[session.slotIndex] = f
                    }
                }
            }
            slotFrameLock.unlock()
            guard let vc = vc, !vc.isShuttingDown else { return }
            if UIApplication.shared.applicationState == .active {
                vc.isAppInBackground = false
            }
            if vc.isAppInBackground {
                if let frame = frame, DecadePiPManager.shared.isPiPActiveOrStarting {
                    DecadePiPManager.shared.updateFrame(frame)
                }
                return
            }

            if vc.isSplitViewEnabled {
                let count = min(vc.splitTargetCount, vc.tabSessions.count, vc.splitPanes.count)
                for i in 0..<count {
                    let slot = vc.tabSessions[i].slotIndex
                    if let f = multiFrames[slot] {
                        vc.splitPanes[i].imageView.layer.contents = f
                    }
                }
            } else if let frame = frame {
                vc.emulatorView.layer.contents = frame
            }

            if let frame = frame {
                if DecadePiPManager.shared.isPiPActiveOrStarting {
                    DecadePiPManager.shared.updateFrame(frame)
                }
            }
            if let icon = vc.placeholderIconView, icon.alpha > 0 {
                UIView.animate(withDuration: 0.15) { icon.alpha = 0 }
            }
        }
    }

    nonisolated static func purgeInactiveSlotFrames() {
        let activeIdx = Int(jvm_bridge_get_focused_slot())
        slotFrameLock.lock()
        let keepSlots = Set(0...6).union([activeIdx])
        let keysToDrop = slotFrames.keys.filter { k in !keepSlots.contains(k) }
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
        let jarPath: String
        let appName: String
        let saveRoot: String
        let icon: UIImage
        var width: Int
        var height: Int
        let renderScale: Int
        let fps: Int
        var screenshot: UIImage?
    }
    var tabSessions: [TabSession] = []
    var tabButtons: [UIButton] = []
    var activeTabIndex: Int = 0
    private var tabWorkerSlots: Set<Int> = []
    private var restartingSlots: Set<Int> = []
    private var cleanupStarted = false
    private var activeSlot: Int {
        tabSessions.indices.contains(activeTabIndex) ? tabSessions[activeTabIndex].slotIndex : 0
    }

    // Quick floating unhide keypad button
    private let floatingShowKeypadBtn = UIButton(type: .system)

    // Toolbar action buttons (Camera button removed per user request)
    private let backToListBtn = UIButton(type: .system)
    private let splitBtn = UIButton(type: .system)
    private let multiTabBtn = UIButton(type: .system)
    private let removeTabBtn = UIButton(type: .system)
    private let addTabBtn = UIButton(type: .system)
    private let nativeKeyboardBtn = UIButton(type: .system)
    private let keyboardBtn = UIButton(type: .system)
    private let menuBtn = UIButton(type: .system)

    // Native QWERTY Phone Keyboard Bar (like Chơi Game Tuổi Thơ)
    private let nativeChatBar = UIView()
    private let nativeTextField = UITextField()
    private var nativeChatBarBottomConstraint: NSLayoutConstraint?

    // Split-Screen Components (up to 6 screens)
    var isSplitViewEnabled: Bool = false {
        didSet {
            j2me_render_set_split_view(isSplitViewEnabled ? 1 : 0)
            j2me_input_wake_all()
        }
    }
    var splitTargetCount: Int = 6
    private let splitContainer = UIView()
    private let splitMasterStack = UIStackView()
    private var splitRowStacks: [UIStackView] = []
    private var splitPanes: [SplitGamePaneView] = []

    // Legacy controls (if in ngage mode)
    private var joystickView: JoystickView?
    private var numpadView: NumpadView?

    // Decade state
    private var isKeepAwake = DecadeBackgroundKeeper.shared.isTreoActive
    private var isOledSleeping = false {
        didSet {
            GameViewController.isOledSleepingActive = isOledSleeping
        }
    }
    static var isOledSleepingActive = false
    private var shouldSuspendOnPiPStart = false
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
        alertTimeoutWork?.cancel()
        autoShutdownTimer?.invalidate()
        statsTimer?.invalidate()
    }

    private var alertTimeoutWork: DispatchWorkItem?
    private weak var nativeAlert: UIAlertController?

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

        tabSessions = [TabSession(slotIndex: 0, jarPath: jarPath, appName: appName,
                                  saveRoot: Self.saveRoot(for: jarPath, appName: appName, slot: 0),
                                  icon: appIcon, width: canvasWidth, height: canvasHeight,
                                  renderScale: render3dScale, fps: fpsLimit, screenshot: nil)]

        switch layoutMode {
        case .decade:
            setupDecadeLayout()
        case .ngage:
            setupNGageLayout()
        }

        // Apply saved configuration: Aspect ratio & Forced Fullscreen
        let isForceFullscreen = isForceFullscreenEnabled
        let isForceFill = isForceFullscreen || !isAspectFitEnabled
        emulatorView.isAspectFit = !isForceFill

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

        // Setup isolated Picture-in-Picture host view (4:3 behind game canvas for smooth PiP animation)
        pipHostView.frame = CGRect(x: 0, y: 0, width: 160, height: 120)
        pipHostView.alpha = 0.01
        pipHostView.isUserInteractionEnabled = false
        view.insertSubview(pipHostView, at: 0)

        DecadePiPManager.shared.setup(sourceView: pipHostView)
        DecadePiPManager.shared.setGameInfo(name: appName, icon: appIcon, tabNumber: activeTabIndex + 1)
        DecadePiPManager.shared.onPiPStateChanged = { [weak self] active in
            guard let self = self else { return }
            if active {
                j2me_render_set_background(0)
                j2me_input_post_repaint()
                if self.shouldSuspendOnPiPStart {
                    self.shouldSuspendOnPiPStart = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        let suspendSel = NSSelectorFromString("suspend")
                        if UIApplication.shared.responds(to: suspendSel) {
                            UIApplication.shared.perform(suspendSel)
                        }
                    }
                }
            } else {
                self.shouldSuspendOnPiPStart = false
                if self.isAppInBackground || self.isOledSleeping {
                    j2me_render_set_background(1)
                } else {
                    j2me_render_set_background(0)
                    j2me_input_post_repaint()
                }
            }
        }
        DecadePiPManager.shared.onPiPFailed = { [weak self] error in
            self?.shouldSuspendOnPiPStart = false
            self?.showToast(message: "Không mở được cửa sổ nhỏ ngoài màn hình (\(error.localizedDescription))")
        }

        // Observe app lifecycle for background power & connection preservation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackgroundChange),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackgroundChange),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
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
        if DecadeBackgroundKeeper.shared.isTreoActive {
            DecadeBackgroundKeeper.shared.startKeepalive()
        }
        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isAppInBackground = false
        j2me_render_set_background(0)
        j2me_input_post_repaint()
        if let frame = cachedFrame(for: activeSlot) {
            emulatorView.displayImage(frame)
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
        pipHostView.frame = CGRect(x: 0, y: 0, width: 160, height: 120)
        DecadePiPManager.shared.updateLayout()
    }

    // ============================================================
    // MARK: - Decade 1:1 Authentic Portrait Layout
    // ============================================================

    private func setupDecadeLayout() {
        // Background color of main view matches dark navy of the top bar
        view.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.17, alpha: 1.0)

        // 1. Unified Top Bar (Dark Navy #161D2B matching user reference screenshot)
        topToolbar.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.17, alpha: 1.0)
        topToolbar.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.clipsToBounds = true
        view.addSubview(topToolbar)

        // [ ‹ ] Back to Game Selection List Button
        let backConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        backToListBtn.setImage(UIImage(systemName: "chevron.backward", withConfiguration: backConfig), for: .normal)
        backToListBtn.tintColor = .white
        backToListBtn.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        backToListBtn.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.addSubview(backToListBtn)

        // Tab Scroll View on the LEFT side of topToolbar
        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.showsVerticalScrollIndicator = false
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.addSubview(tabScrollView)

        tabStrip.axis = .horizontal
        tabStrip.spacing = 2
        tabStrip.alignment = .fill
        tabStrip.distribution = .fill
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.addSubview(tabStrip)

        // Action Buttons on the RIGHT side of topToolbar: [⋮] [-] [+] [⌨] [🎮]
        let actionStack = UIStackView()
        actionStack.axis = .horizontal
        actionStack.spacing = 13
        actionStack.alignment = .center
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.addSubview(actionStack)

        // [⋮] Menu Button (vertical 3 dots)
        let menuConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        menuBtn.setImage(UIImage(systemName: "ellipsis", withConfiguration: menuConfig), for: .normal)
        menuBtn.tintColor = .white
        menuBtn.transform = CGAffineTransform(rotationAngle: .pi / 2) // Rotate to vertical 3 dots!
        menuBtn.addTarget(self, action: #selector(showMenu), for: .touchUpInside)

        // [-] Remove Current Tab Button
        let minusConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        removeTabBtn.setImage(UIImage(systemName: "minus", withConfiguration: minusConfig), for: .normal)
        removeTabBtn.tintColor = .white
        removeTabBtn.addTarget(self, action: #selector(removeTabTapped), for: .touchUpInside)

        // [+] Add New Tab Button (1 tap = choose game / clone tab)
        let plusConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        addTabBtn.setImage(UIImage(systemName: "plus", withConfiguration: plusConfig), for: .normal)
        addTabBtn.tintColor = .white
        addTabBtn.addTarget(self, action: #selector(addTabTapped), for: .touchUpInside)
        let addLongPress = UILongPressGestureRecognizer(target: self, action: #selector(addTabLongPressed(_:)))
        addTabBtn.addGestureRecognizer(addLongPress)

        // [⌨] Native QWERTY Phone Keyboard Button (like Chơi Game Tuổi Thơ)
        let kbConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        nativeKeyboardBtn.setImage(UIImage(systemName: "keyboard", withConfiguration: kbConfig), for: .normal)
        nativeKeyboardBtn.tintColor = UIColor(white: 0.90, alpha: 1.0)
        nativeKeyboardBtn.addTarget(self, action: #selector(nativeKeyboardTapped), for: .touchUpInside)

        // [🎮] Game Controller Button (toggle virtual keypad/keyboard)
        let gamePadConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        keyboardBtn.setImage(UIImage(systemName: "gamecontroller.fill", withConfiguration: gamePadConfig), for: .normal)
        keyboardBtn.tintColor = UIColor(white: 0.90, alpha: 1.0)
        keyboardBtn.addTarget(self, action: #selector(toggleKeypadVisibility), for: .touchUpInside)

        actionStack.addArrangedSubview(menuBtn)
        actionStack.addArrangedSubview(removeTabBtn)
        actionStack.addArrangedSubview(addTabBtn)
        actionStack.addArrangedSubview(nativeKeyboardBtn)
        actionStack.addArrangedSubview(keyboardBtn)

        NSLayoutConstraint.activate([
            backToListBtn.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor, constant: 6),
            backToListBtn.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            backToListBtn.widthAnchor.constraint(equalToConstant: 34),
            backToListBtn.heightAnchor.constraint(equalToConstant: 38),

            tabScrollView.leadingAnchor.constraint(equalTo: backToListBtn.trailingAnchor, constant: 2),
            tabScrollView.topAnchor.constraint(equalTo: topToolbar.topAnchor),
            tabScrollView.bottomAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: actionStack.leadingAnchor, constant: -6),

            tabStrip.leadingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.trailingAnchor),
            tabStrip.topAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.topAnchor),
            tabStrip.bottomAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.bottomAnchor),
            tabStrip.heightAnchor.constraint(equalTo: tabScrollView.frameLayoutGuide.heightAnchor),

            actionStack.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor, constant: -10),
            actionStack.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
        ])

        createTabButton(index: 0)
        selectTab(at: 0)
        setupNativeChatBar()

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
        keypad.loadHiddenKeys()
        self.decadeKeypadView = keypad
        view.addSubview(keypad)

        // Floating unhide keypad button (backup when keypad is hidden)
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

        // 4. Game Canvas (fills between topToolbar and keypad directly)
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
            // Top Bar pinned right below Safe Area
            topToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topToolbar.heightAnchor.constraint(equalToConstant: 38),

            // Keypad at bottom
            keypad.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keypad.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keypad.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,

            // Floating unhide keypad button
            floatingShowKeypadBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            floatingShowKeypadBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),

            // Game Canvas fills between Top Bar and Keypad directly
            emulatorView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            emulatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emulatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emulatorView.bottomAnchor.constraint(equalTo: keypad.topAnchor),

            // Screen Views fill between Top Bar and View Bottom
            textBoxView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            textBoxView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textBoxView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textBoxView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            formView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            formView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            formView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            listView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 6. Split Screen Container (Supports 2 / 4 / 6 screens)
        splitContainer.translatesAutoresizingMaskIntoConstraints = false
        splitContainer.backgroundColor = .black
        splitContainer.isHidden = true
        view.addSubview(splitContainer)

        splitMasterStack.axis = .vertical
        splitMasterStack.spacing = 3
        splitMasterStack.distribution = .fillEqually
        splitMasterStack.translatesAutoresizingMaskIntoConstraints = false
        splitContainer.addSubview(splitMasterStack)

        NSLayoutConstraint.activate([
            splitContainer.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            splitContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitContainer.bottomAnchor.constraint(equalTo: keypad.topAnchor),

            splitMasterStack.topAnchor.constraint(equalTo: splitContainer.topAnchor, constant: 2),
            splitMasterStack.leadingAnchor.constraint(equalTo: splitContainer.leadingAnchor, constant: 2),
            splitMasterStack.trailingAnchor.constraint(equalTo: splitContainer.trailingAnchor, constant: -2),
            splitMasterStack.bottomAnchor.constraint(equalTo: splitContainer.bottomAnchor, constant: -2),
        ])

        view.bringSubviewToFront(topToolbar)
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
        tabBtn.setTitle("Tab \(index + 1)", for: .normal)
        tabBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        tabBtn.layer.cornerRadius = 0
        tabBtn.tag = index
        tabBtn.translatesAutoresizingMaskIntoConstraints = false
        tabBtn.widthAnchor.constraint(equalToConstant: 58).isActive = true
        tabBtn.heightAnchor.constraint(equalToConstant: 38).isActive = true
        tabBtn.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(tabButtonLongPressed(_:)))
        tabBtn.addGestureRecognizer(longPress)

        tabStrip.addArrangedSubview(tabBtn)
        tabButtons.append(tabBtn)
    }

    @objc private func removeTabTapped() {
        if tabSessions.count > 1 {
            let currentTabNum = activeTabIndex + 1
            closeTab(at: activeTabIndex)
            showToast(message: "Đã đóng Tab \(currentTabNum)")
        } else {
            let alert = UIAlertController(
                title: "Thoát Game",
                message: "Bạn có chắc muốn đóng game [\(appName)] và quay về màn hình chính không?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Thoát", style: .destructive) { [weak self] _ in
                self?.forceExitGame()
            })
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            present(alert, animated: true)
        }
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        let tapped = sender.tag
        if isSplitViewEnabled && activeTabIndex == tapped {
            disableSplitView()
            showToast(message: "Toàn màn hình Tab \(tapped + 1)")
        } else {
            selectTab(at: tapped)
        }
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

        if tabSessions.count > 1 {
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
        guard tabSessions.indices.contains(index), !isShuttingDown else { return }
        guard tabSessions.count > 1 else {
            forceExitGame()
            return
        }
        let slot = tabSessions[index].slotIndex
        restartingSlots.remove(slot)
        jvm_bridge_request_stop_slot(Int32(slot))
        removeTab(at: index)
        showToast(message: "Đã đóng Tab \(index + 1)")
    }

    private func removeTab(at index: Int) {
        let slot = tabSessions[index].slotIndex
        let previousSlot = activeSlot
        if slot == previousSlot {
            endTabEditing()
        }
        tabSessions.remove(at: index)
        tabButtons.remove(at: index).removeFromSuperview()
        forgetFrame(for: slot)
        for (i, button) in tabButtons.enumerated() {
            button.tag = i
            button.setTitle("Tab \(i + 1)", for: .normal)
        }
        let newActive = tabSessions.firstIndex(where: { $0.slotIndex == previousSlot })
            ?? min(index, tabSessions.count - 1)
        activeTabIndex = newActive
        selectTab(at: newActive)
        updateTabStripVisibility()
        if tabSessions.count < 2 && isSplitViewEnabled {
            disableSplitView()
        } else if isSplitViewEnabled {
            setupSplitGrid(count: min(splitTargetCount, tabSessions.count))
        }
        updateSplitFocusBorders()
        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
    }

    private func endTabEditing() {
        if !formView.isHidden { formView.syncAllTextFields() }
        view.endEditing(true)
        dismissNativeAlert()
    }

    private func cachedFrame(for slot: Int) -> CGImage? {
        Self.slotFrameLock.lock()
        defer { Self.slotFrameLock.unlock() }
        return Self.slotFrames[slot]
    }

    private func forgetFrame(for slot: Int) {
        Self.slotFrameLock.lock()
        Self.slotFrames.removeValue(forKey: slot)
        Self.slotFrameLock.unlock()
    }

    private func selectTab(at index: Int) {
        guard tabSessions.indices.contains(index), tabButtons.indices.contains(index), !isShuttingDown else { return }

        if activeTabIndex != index && tabSessions.indices.contains(activeTabIndex) {
            if !emulatorView.isHidden { tabSessions[activeTabIndex].screenshot = takeSnapshot() }
            endTabEditing()
        }

        activeTabIndex = index
        let session = tabSessions[index]
        jvm_bridge_set_focused_slot(Int32(session.slotIndex))
        j2me_input_post_repaint()

        titleLabel.text = session.appName
        appName = session.appName
        jarPath = session.jarPath
        appIcon = session.icon
        canvasWidth = session.width
        canvasHeight = session.height
        emulatorView.canvasWidth = session.width
        emulatorView.canvasHeight = session.height
        emulatorView.isAspectFit = !isForceFullscreenEnabled && isAspectFitEnabled
        DecadeFloatingBubble.shared.setGameInfo(name: session.appName, icon: session.icon, tabNumber: index + 1)
        DecadeMiniWindow.shared.setTabInfo(tabNumber: index + 1)
        DecadePiPManager.shared.setGameInfo(name: session.appName, icon: session.icon, tabNumber: index + 1)

        for (i, btn) in tabButtons.enumerated() {
            if i == index {
                btn.backgroundColor = UIColor(red: 0.12, green: 0.43, blue: 0.98, alpha: 1.0) // #1E6FFB Vibrant Blue
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = UIColor(red: 0.10, green: 0.13, blue: 0.19, alpha: 1.0) // Dark Navy #1A222E
                btn.setTitleColor(UIColor(white: 0.70, alpha: 1.0), for: .normal)
            }
        }

        // Scroll tab into view
        let targetBtn = tabButtons[index]
        tabScrollView.scrollRectToVisible(targetBtn.frame, animated: true)

        if let keypad = decadeKeypadView {
            keypad.gameId = currentGameId
            let defaults = UserDefaults.standard
            let savedLayout = defaults.object(forKey: "keypad_layout_\(currentGameId)") as? Int
                ?? defaults.object(forKey: "keypad_layout_\(legacyGameId)") as? Int ?? 0
            keypad.currentLayout = DecadeKeypadLayout(rawValue: savedLayout) ?? .tuoitho
            isKeypadHidden = defaults.bool(forKey: "keypad_hidden_\(currentGameId)")
            let hidden = isForceFullscreenEnabled || isKeypadHidden
            keypad.isHidden = hidden
            floatingShowKeypadBtn.isHidden = isForceFullscreenEnabled || !isKeypadHidden
            keypadHeightConstraint?.constant = hidden ? 0 : keypadCurrentHeight
            keypad.loadHiddenKeys()
            keypad.updateKeysVisibility()
        }

        j2me_ui_restore_focused_screen()
        if !emulatorView.isHidden {
            // Immediately isolate and show this tab's frame!
            if let frame = cachedFrame(for: session.slotIndex) {
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

        updateTabStripVisibility()
        updateSplitFocusBorders()

        showToast(message: "Chuyển sang Tab \(index + 1): \(session.appName)")
    }

    var isShuttingDown: Bool { isUserInitiatedExit }
    var runningGameCount: Int { isShuttingDown ? 0 : Set(tabSessions.map { $0.jarPath }).count }

    func hasGameTab(path: String) -> Bool {
        !isShuttingDown && tabSessions.contains { $0.jarPath == path }
    }

    func stopGameTabs(path: String) {
        for index in tabSessions.indices.reversed() where tabSessions[index].jarPath == path {
            closeTab(at: index)
        }
    }

    func showGameTab(app: AppsListViewController.AppInfo, width: Int, height: Int,
                     scale: Int, fps: Int) -> Bool {
        guard !isShuttingDown else { return false }
        if let index = tabSessions.firstIndex(where: { $0.jarPath == app.path }) {
            if jarPath != app.path { selectTab(at: index) }
            return true
        }
        return addTabs(path: app.path, name: app.name, icon: app.icon,
                       size: (width, height), scale: scale, fps: fps, count: 1)
    }

    private var availableSlots: [Int] {
        let reserved = Set(tabSessions.map { $0.slotIndex }).union(tabWorkerSlots)
        return (0..<Int(JVM_BRIDGE_MAX_SLOTS)).filter { !reserved.contains($0) }
    }

    private static func saveRoot(for path: String, appName: String, slot: Int) -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
            ?? NSTemporaryDirectory()
        let jarName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let base = slot == 0 ? jarName : appName
        let game = base.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let name = slot == 0 ? game : "\(game)-tab\(slot + 1)"
        return docs + "/Games Data/" + name
    }

    @discardableResult
    private func addTabs(path: String, name: String, icon: UIImage, size: (Int, Int),
                         scale: Int, fps: Int, count: Int) -> Bool {
        guard layoutMode == .decade, !isShuttingDown else { return false }
        let slots = availableSlots.prefix(count)
        guard !slots.isEmpty else {
            showToast(message: "Đã dùng hết \(JVM_BRIDGE_MAX_SLOTS) slot. Hãy đợi tab đang đóng hoặc đóng bớt tab.")
            return false
        }
        var newSessions: [TabSession] = []
        for slot in slots {
            let session = TabSession(slotIndex: slot, jarPath: path, appName: name,
                                     saveRoot: Self.saveRoot(for: path, appName: name, slot: slot),
                                     icon: icon, width: size.0, height: size.1,
                                     renderScale: scale, fps: fps, screenshot: nil)
            createTabButton(index: tabSessions.count)
            tabSessions.append(session)
            newSessions.append(session)
        }
        selectTab(at: tabSessions.count - 1)
        for session in newSessions { launchTab(session) }
        updateTabStripVisibility()
        updateSplitFocusBorders()
        showToast(message: "Đã yêu cầu mở \(newSessions.count) tab cho \(name)")
        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
        return true
    }

    private func duplicateActiveTab(count: Int) {
        guard tabSessions.indices.contains(activeTabIndex) else { return }
        let active = tabSessions[activeTabIndex]
        addTabs(path: active.jarPath, name: active.appName, icon: active.icon,
                size: (active.width, active.height), scale: active.renderScale, fps: active.fps, count: count)
    }

    private func addInstalledGame(_ app: AppsListViewController.AppInfo, count: Int) {
        addTabs(path: app.path, name: app.name, icon: app.icon,
                size: AppsListViewController.resolution(for: app),
                scale: AppsListViewController.is3DSupersampling(for: app) ? 3 : 1,
                fps: AppsListViewController.fpsLimit(for: app), count: count)
    }

    @objc private func addTabTapped() {
        showAddTabOptionsSheet()
    }

    @objc private func addTabLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        showAddTabOptionsSheet()
    }

    private func showAddTabOptionsSheet() {
        guard !availableSlots.isEmpty, !isShuttingDown else {
            showToast(message: "Hiện chưa còn slot trống để thêm tab.")
            return
        }

        let installedApps = AppsListViewController.loadInstalledApps()
        let activeGameName = (activeTabIndex < tabSessions.count) ? tabSessions[activeTabIndex].appName : appName

        let alert = UIAlertController(
            title: "➕ Thêm Tab Mới",
            message: "Chọn game để mở trong Tab \(tabSessions.count + 1):",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "➕ Nhân bản game này: [\(activeGameName)]", style: .default) { [weak self] _ in
            self?.duplicateActiveTab(count: 1)
            if let count = self?.tabSessions.count {
                self?.showToast(message: "Đã thêm Tab \(count)")
            }
        })

        for app in installedApps {
            if app.path != self.jarPath {
                alert.addAction(UIAlertAction(title: "🎮 [\(app.name)]", style: .default) { [weak self] _ in
                    self?.addInstalledGame(app, count: 1)
                })
            }
        }

        if availableSlots.count >= 3 {
            alert.addAction(UIAlertAction(title: "➕➕ Mở nhanh 3 Tab [\(activeGameName)]", style: .default) { [weak self] _ in
                self?.duplicateActiveTab(count: 3)
                if let count = self?.tabSessions.count {
                    self?.showToast(message: "Đã thêm 3 Tab (Tổng: \(count) Tab)")
                }
            })
        }

        if availableSlots.count >= 5 {
            alert.addAction(UIAlertAction(title: "➕➕➕ Mở nhanh 5 Tab [\(activeGameName)]", style: .default) { [weak self] _ in
                self?.duplicateActiveTab(count: 5)
                if let count = self?.tabSessions.count {
                    self?.showToast(message: "Đã thêm 5 Tab (Tổng: \(count) Tab)")
                }
            })
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = addTabBtn
            popover.sourceRect = addTabBtn.bounds
        }
        present(alert, animated: true)
    }

    @objc private func multiTabTapped() {
        let maxAvailable = availableSlots.count
        guard maxAvailable > 0, !isShuttingDown else {
            showToast(message: "Hiện chưa còn slot trống để thêm tab.")
            return
        }

        let installedApps = AppsListViewController.loadInstalledApps()

        let alert = UIAlertController(
            title: "Mở nhiều tab (++)",
            message: "Nhập số lượng tab và chọn game cần mở:",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = "\(min(5, maxAvailable))"
            tf.keyboardType = .numberPad
            tf.placeholder = "Số tab (tối đa \(maxAvailable))"
        }

        // Action for current game
        alert.addAction(UIAlertAction(title: "⧉ Mở cho: \(appName)", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            guard let count = self.requestedTabCount(in: alert) else { return }
            self.duplicateActiveTab(count: count)
        })

        // Actions for other installed games
        for app in installedApps.prefix(4) {
            if app.path != self.jarPath {
                alert.addAction(UIAlertAction(title: "🎮 " + app.name, style: .default) { [weak self, weak alert] _ in
                    guard let self = self else { return }
                    guard let count = self.requestedTabCount(in: alert) else { return }
                    self.addInstalledGame(app, count: count)
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    private func requestedTabCount(in alert: UIAlertController?) -> Int? {
        let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let count = Int(text), count > 0, count <= availableSlots.count else {
            showToast(message: "Nhập số tab hợp lệ theo số slot còn trống.")
            return nil
        }
        return count
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
    // MARK: - Multi-Tab & Split-Screen Actions
    // ============================================================

    private func updateTabStripVisibility() {
        tabStripContainer.isHidden = true
        tabStripHeightConstraint?.constant = 0
    }

    @objc private func splitTapped() {
        toggleSplitView()
    }

    private func toggleSplitView() {
        let sheet = UIAlertController(
            title: "⧉ Chia Màn Hình Đa Game",
            message: "Chọn chế độ chia màn hình hiển thị đồng thời:",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "📱 6 Màn Hình (Chuẩn cày 6 acc)", style: .default) { [weak self] _ in
            self?.enableSplitView(count: 6)
        })
        sheet.addAction(UIAlertAction(title: "📱 4 Màn Hình (2x2)", style: .default) { [weak self] _ in
            self?.enableSplitView(count: 4)
        })
        sheet.addAction(UIAlertAction(title: "📱 3 Màn Hình", style: .default) { [weak self] _ in
            self?.enableSplitView(count: 3)
        })
        sheet.addAction(UIAlertAction(title: "📱 2 Màn Hình (Trên / Dưới)", style: .default) { [weak self] _ in
            self?.enableSplitView(count: 2)
        })
        if isSplitViewEnabled {
            sheet.addAction(UIAlertAction(title: "❌ Tắt Chia Màn Hình (Toàn Màn Hình 1 Game)", style: .destructive) { [weak self] _ in
                self?.disableSplitView()
            })
        }
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = topToolbar
            pop.sourceRect = topToolbar.bounds
        }
        present(sheet, animated: true)
    }

    private func enableSplitView(count: Int = 6) {
        splitTargetCount = count
        if tabSessions.count < count {
            let needed = count - tabSessions.count
            duplicateActiveTab(count: needed)
        }
        setupSplitGrid(count: count)
        isSplitViewEnabled = true
        splitBtn.tintColor = UIColor.systemGreen
        splitContainer.isHidden = false
        emulatorView.isHidden = true
        updateSplitFocusBorders()
        showToast(message: "Đã bật: Chia màn hình (\(count) Tab)")
    }

    private func disableSplitView() {
        isSplitViewEnabled = false
        splitBtn.tintColor = UIColor(red: 0.10, green: 0.46, blue: 0.82, alpha: 1.0)
        splitContainer.isHidden = true
        emulatorView.isHidden = false
        if let frame = cachedFrame(for: activeSlot) {
            emulatorView.displayImage(frame)
        }
        showToast(message: "Đã tắt chế độ chia màn hình")
    }

    private func setupSplitGrid(count: Int) {
        for row in splitRowStacks {
            row.removeFromSuperview()
        }
        splitRowStacks.removeAll()
        splitPanes.removeAll()

        let cols = (count <= 2) ? 1 : 2
        let rows = (count + cols - 1) / cols

        var paneIdx = 0
        for _ in 0..<rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 3
            rowStack.distribution = .fillEqually
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            splitMasterStack.addArrangedSubview(rowStack)
            splitRowStacks.append(rowStack)

            for _ in 0..<cols {
                if paneIdx < count {
                    let pane = SplitGamePaneView(index: paneIdx)
                    pane.onTapped = { [weak self] idx in
                        self?.selectTab(at: idx)
                    }
                    rowStack.addArrangedSubview(pane)
                    splitPanes.append(pane)
                    paneIdx += 1
                }
            }
        }
    }

    private func updateSplitFocusBorders() {
        for (i, pane) in splitPanes.enumerated() {
            let isFocused = (i == activeTabIndex)
            pane.setFocused(isFocused)
            if i < tabSessions.count {
                pane.titleLabel.text = "Tab \(i + 1): \(tabSessions[i].appName)"
                pane.isHidden = false
            } else {
                pane.titleLabel.text = "Tab \(i + 1)"
            }
        }
    }

    // ============================================================
    // MARK: - Popup Menu 3 Chấm Chuẩn 1:1 Bản Tuổi Thơ (Ảnh 1)
    // ============================================================

    @objc private func showMenu() {
        softKeyHaptic.impactOccurred(intensity: 0.6)
        let popup = TuoiThoPopupMenuView()
        popup.isKeypadHidden = self.isKeypadHidden
        popup.isTreo247Active = DecadeBackgroundKeeper.shared.isTreoActive

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
        popup.onToggleSplitView = { [weak self] in
            self?.toggleSplitView()
        }
        popup.onOledSleepMode = { [weak self] in
            self?.enterOledSleepMode()
        }
        popup.onToggleTreo247 = { [weak self] in
            self?.toggleTreoTatMan()
        }
        popup.onTogglePiP = { [weak self] in
            self?.openFloatingPiPWindow()
        }
        popup.onHideApp = { [weak self] in
            self?.hideAppToBackground()
        }
        popup.onOpenNativeKeyboard = { [weak self] in
            self?.nativeKeyboardTapped()
        }
        popup.onRestartGame = { [weak self] in
            self?.restartGameSession()
        }
        popup.onBackToList = { [weak self] in
            self?.backButtonTapped()
        }
        popup.onExitGame = { [weak self] in
            self?.forceExitGame()
        }

        popup.show(in: view)
    }

    private func showHideKeysDialog() {
        guard let keypad = self.decadeKeypadView else { return }
        let gid = self.currentGameId
        let dialog = DecadeHideButtonsDialog(gameId: gid, currentHiddenKeys: keypad.hiddenKeys) { [weak self] newHiddenKeys in
            keypad.hiddenKeys = newHiddenKeys
            keypad.saveHiddenKeys()
            self?.showToast(message: "Đã cập nhật hiển thị nút bàn phím")
        }
        self.present(dialog, animated: true)
    }

    private func promptChangeKeyboardLayout() {
        let alert = UIAlertController(title: "Cài Đặt Bàn Phím", message: "Chọn kiểu bàn phím hoặc chỉnh sửa phím ảo:", preferredStyle: .actionSheet)
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
        alert.addAction(UIAlertAction(title: "👁️ Thêm / Xoá Nút Phím Số (1, 2, 3...)", style: .default) { [weak self] _ in
            self?.showHideKeysDialog()
        })
        alert.addAction(UIAlertAction(title: "⌨ Bật Bàn Phím Gốc QWERTY (Gõ Chữ / Chat)", style: .default) { [weak self] _ in
            self?.nativeKeyboardTapped()
        })
        alert.addAction(UIAlertAction(title: "✥ Di Chuyển Phím Bấm (Kéo Thả Tự Do)", style: .default) { [weak self] _ in
            self?.decadeKeypadView?.toggleEditMode()
            self?.showToast(message: "Kéo thả các phím để sắp xếp vị trí mong muốn")
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = menuBtn
            popover.sourceRect = menuBtn.bounds
        }
        present(alert, animated: true)
    }

    private func restartGameSession() {
        guard !isShuttingDown, tabSessions.indices.contains(activeTabIndex) else { return }
        let slot = activeSlot
        guard restartingSlots.insert(slot).inserted else { return }
        let savedW = UserDefaults.standard.object(forKey: "resW_\(currentGameId)") as? Int ?? 0
        let savedH = UserDefaults.standard.object(forKey: "resH_\(currentGameId)") as? Int ?? 0
        let size = (savedW > 0 && savedH > 0) ? (savedW, savedH) : calculateAutoCanvasSize()
        tabSessions[activeTabIndex].width = size.0
        tabSessions[activeTabIndex].height = size.1
        tabSessions[activeTabIndex].screenshot = nil
        showToast(message: "Đang khởi động lại tab \(activeTabIndex + 1)…")
        if tabWorkerSlots.contains(slot) {
            jvm_bridge_request_stop_slot(Int32(slot))
        } else {
            restartingSlots.remove(slot)
            launchTab(tabSessions[activeTabIndex])
        }
    }

    // ============================================================
    // MARK: - Live RAM / CPU Status Bar & 1-Tap RAM Cleaner
    // ============================================================

    private func startSystemStatsMonitor() {
        statsTimer?.invalidate()
        updateSystemStatsLabel()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateSystemStatsLabel()
        }
    }

    private func updateSystemStatsLabel() {
        guard !isAppInBackground && !isOledSleeping else { return }
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
        if !isOledSleeping {
            j2me_render_set_background(0)
        }
        // Request immediate frame redraw upon unlock without injecting fake touch
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isOledSleeping, let img = GameViewController.slotFrames[self.activeSlot] {
                self.emulatorView.displayImage(img)
            }
            if !self.isOledSleeping {
                j2me_input_post_repaint()
            }
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

        let isForceFullscreen = isForceFullscreenEnabled
        let isForceFill = isForceFullscreen || !isAspectFitEnabled
        emulatorView.isAspectFit = !isForceFill

        let savedLayout = (UserDefaults.standard.object(forKey: "keypad_layout_\(currentGameId)") as? Int) ??
                          (UserDefaults.standard.object(forKey: "keypad_layout_\(legacyGameId)") as? Int) ?? 0
        decadeKeypadView?.currentLayout = DecadeKeypadLayout(rawValue: savedLayout) ?? .tuoitho

        if let treo = notif.userInfo?["treo"] as? Bool {
            DecadeBackgroundKeeper.shared.setTreoActive(treo)
        }
        if let fps = notif.userInfo?["fps"] as? Int {
            j2me_render_set_fps_limit(Int32(fps))
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

    // OLED Pure Black Overlay for authentic "Ngủ Ẩn / Treo tắt màn"
    private lazy var oledBlackOverlay: UIView = {
        let v = UIView(frame: UIScreen.main.bounds)
        v.backgroundColor = .black
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.isUserInteractionEnabled = true
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(dismissOledBlackOverlay))
        doubleTap.numberOfTapsRequired = 2
        v.addGestureRecognizer(doubleTap)
        let lbl = UILabel()
        lbl.text = "🌙 Đang ngủ ẩn (Tiết kiệm pin OLED — Game vẫn chạy ngầm 24/7)\nChạm ĐÚP (2 lần) vào màn hình để bật sáng lại"
        lbl.numberOfLines = 3
        lbl.textAlignment = .center
        lbl.textColor = UIColor(white: 0.30, alpha: 1.0)
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            lbl.leadingAnchor.constraint(greaterThanOrEqualTo: v.leadingAnchor, constant: 24),
            lbl.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -24),
        ])
        return v
    }()

    @objc private func dismissOledBlackOverlay() {
        isOledSleeping = false
        if !isAppInBackground && !DecadePiPManager.shared.isPiPActive {
            j2me_render_set_background(0)
            j2me_input_post_repaint()
        }
        UIView.animate(withDuration: 0.25, animations: {
            self.oledBlackOverlay.alpha = 0
        }) { _ in
            self.oledBlackOverlay.removeFromSuperview()
            self.oledBlackOverlay.alpha = 1.0
        }
    }

    private func enterOledSleepMode() {
        isKeepAwake = true
        DecadeBackgroundKeeper.shared.setTreoActive(true)
        DecadeBackgroundKeeper.shared.startKeepalive()
        isOledSleeping = true
        if !DecadePiPManager.shared.isPiPActiveOrStarting {
            j2me_render_set_background(1)
        }
        if let win = view.window {
            oledBlackOverlay.frame = win.bounds
            if oledBlackOverlay.superview == nil {
                win.addSubview(oledBlackOverlay)
            }
        }
    }

    /// Mở cửa sổ nhỏ nổi ngoài màn hình chính (iOS PiP kéo to nhỏ tự do bằng 2 ngón, không có chế độ bong bóng)
    private func openFloatingPiPWindow() {
        isKeepAwake = true
        if !DecadeBackgroundKeeper.shared.isTreoActive {
            DecadeBackgroundKeeper.shared.setTreoActive(true)
        }
        DecadeBackgroundKeeper.shared.startKeepalive()
        if DecadePiPManager.shared.isPiPActive {
            DecadePiPManager.shared.stopPiP()
            showToast(message: "Đã đóng cửa sổ nhỏ ngoài màn hình")
            return
        }
        shouldSuspendOnPiPStart = true
        let initialFrame = cachedFrame(for: activeSlot)
        DecadePiPManager.shared.startPiP(initialFrame: initialFrame)
    }

    /// Ẩn ứng dụng xuống nền iOS (khớp 1:1 J2ME NST MicroController.HideApp:
    /// tự bật & lưu vĩnh viễn chế độ Treo 24/24 để các lần sau vuốt đa nhiệm hay khóa màn hình
    /// đều tự nhớ chạy ngầm liên tục không nghỉ).
    private func hideAppToBackground() {
        isKeepAwake = true
        let wasAlreadyPlaying = DecadeBackgroundKeeper.shared.isAudioPlaying
        // Permanently persist "Treo 24/24" so every future multitasking swipe or screen lock auto-remembers!
        DecadeBackgroundKeeper.shared.setTreoActive(true)
        DecadeBackgroundKeeper.shared.startKeepalive()
        // Tear down any inactive PiP video layer so screen-lock runs 100% pure audio-only like NST
        if !DecadePiPManager.shared.isPiPActive {
            DecadePiPManager.shared.teardownPipeline()
        }
        let delay: TimeInterval = wasAlreadyPlaying ? 0.3 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            let suspendSel = NSSelectorFromString("suspend")
            if UIApplication.shared.responds(to: suspendSel) {
                UIApplication.shared.perform(suspendSel)
            } else {
                self?.enterOledSleepMode()
            }
        }
    }

    /// Bật/tắt chế độ Treo tắt màn & chạy ẩn đa nhiệm 24/24 (khớp 1:1 ✓ Treo tắt màn của J2ME NST)
    private func toggleTreoTatMan() {
        let next = !DecadeBackgroundKeeper.shared.isTreoActive
        isKeepAwake = next
        DecadeBackgroundKeeper.shared.setTreoActive(next)
        if next {
            DecadeBackgroundKeeper.shared.startKeepalive()
            showToast(message: "Treo 24/24: BẬT (Tự nhớ khi ẩn đa nhiệm & tắt màn)")
        } else {
            dismissOledBlackOverlay()
            DecadePiPManager.shared.stopPiP()
            showToast(message: "Treo 24/24: TẮT")
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
            title: "👁️ Thêm / Xoá Nút Phím Số (1, 2, 3...)",
            image: UIImage(systemName: "eye.slash")
        ) { [weak self] _ in
            self?.showHideKeysDialog()
        }

        let textInputItem = UIAction(
            title: "Nhập văn bản (IME)",
            image: UIImage(systemName: "character.cursor.ibeam")
        ) { [weak self] _ in
            self?.promptTextInput()
        }

        let splitTabItem = UIAction(
            title: isSplitViewEnabled ? "⧉ Tắt chia màn hình" : "⧉ Chia màn hình đa game",
            image: UIImage(systemName: "rectangle.split.2x1")
        ) { [weak self] _ in
            self?.toggleSplitView()
        }

        return UIMenu(
            title: "Bàn phím ảo",
            children: [
                toggleKeypadItem,
                splitTabItem,
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

        // 1c. Chia màn hình đa game
        let splitTitle = isSplitViewEnabled ? "⧉ Tắt chia màn hình" : "⧉ Chia màn hình đa game"
        alert.addAction(UIAlertAction(title: splitTitle, style: .default) { [weak self] _ in
            self?.toggleSplitView()
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

        // 6. Thêm / Xóa nút phím số
        alert.addAction(UIAlertAction(title: "👁️ Thêm / Xoá Nút Phím Số (1, 2, 3...)", style: .default) { [weak self] _ in
            self?.showHideKeysDialog()
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

    // Giới hạn FPS (áp dụng tức thì vào lõi render chuẩn J2ME NST)
    private func promptFPSLimit() {
        let curFps = Int(j2me_render_get_fps_limit())
        let curText = curFps == 0 ? "Không giới hạn" : "\(curFps) FPS"
        let alert = UIAlertController(title: "Giới hạn FPS", message: "Hiện tại: \(curText). Chọn tốc độ khung hình:", preferredStyle: .alert)
        for fps in [60, 30, 15] {
            alert.addAction(UIAlertAction(title: "\(fps) FPS", style: .default) { [weak self] _ in
                guard let self = self else { return }
                j2me_render_set_fps_limit(Int32(fps))
                UserDefaults.standard.set(fps, forKey: "fpsLimit_\(self.currentGameId)")
                self.showToast(message: "Đã áp dụng giới hạn \(fps) FPS")
            })
        }
        alert.addAction(UIAlertAction(title: "Không giới hạn", style: .default) { [weak self] _ in
            guard let self = self else { return }
            j2me_render_set_fps_limit(0)
            UserDefaults.standard.set(0, forKey: "fpsLimit_\(self.currentGameId)")
            self.showToast(message: "Đã bật FPS không giới hạn")
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
    // MARK: - Native QWERTY Phone Keyboard Bar (like Chơi Game Tuổi Thơ)
    // ============================================================

    private func setupNativeChatBar() {
        nativeChatBar.backgroundColor = UIColor(red: 0.10, green: 0.13, blue: 0.19, alpha: 0.98)
        nativeChatBar.layer.borderColor = UIColor(white: 1.0, alpha: 0.15).cgColor
        nativeChatBar.layer.borderWidth = 0.5
        nativeChatBar.translatesAutoresizingMaskIntoConstraints = false
        nativeChatBar.isHidden = true
        view.addSubview(nativeChatBar)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        nativeChatBar.addSubview(stack)

        // 1. Paste Button
        let pasteBtn = UIButton(type: .system)
        let pasteCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        pasteBtn.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: pasteCfg), for: .normal)
        pasteBtn.tintColor = UIColor(white: 0.85, alpha: 1.0)
        pasteBtn.addTarget(self, action: #selector(pasteToNativeChat), for: .touchUpInside)
        pasteBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pasteBtn.widthAnchor.constraint(equalToConstant: 32),
            pasteBtn.heightAnchor.constraint(equalToConstant: 32)
        ])

        // 2. Text Field
        nativeTextField.backgroundColor = UIColor(white: 0.20, alpha: 0.85)
        nativeTextField.textColor = .white
        nativeTextField.font = .systemFont(ofSize: 15, weight: .regular)
        nativeTextField.layer.cornerRadius = 8
        nativeTextField.layer.masksToBounds = true
        nativeTextField.placeholder = "Nhập chữ, chat, tài khoản..."
        nativeTextField.attributedPlaceholder = NSAttributedString(
            string: "Nhập chữ, chat, tài khoản...",
            attributes: [.foregroundColor: UIColor(white: 0.60, alpha: 1.0)]
        )
        nativeTextField.autocorrectionType = .no
        nativeTextField.autocapitalizationType = .none
        nativeTextField.clearButtonMode = .whileEditing
        nativeTextField.returnKeyType = .send
        nativeTextField.delegate = self
        let pad = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 36))
        nativeTextField.leftView = pad
        nativeTextField.leftViewMode = .always
        nativeTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nativeTextField.heightAnchor.constraint(equalToConstant: 36)
        ])

        // 3. Send Button
        let sendBtn = UIButton(type: .system)
        sendBtn.setTitle("Gửi ↵", for: .normal)
        sendBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        sendBtn.setTitleColor(.white, for: .normal)
        sendBtn.backgroundColor = UIColor(red: 0.12, green: 0.50, blue: 0.95, alpha: 1.0)
        sendBtn.layer.cornerRadius = 8
        sendBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        sendBtn.addTarget(self, action: #selector(sendNativeChatText), for: .touchUpInside)

        // 4. Close Button
        let closeBtn = UIButton(type: .system)
        let closeCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: closeCfg), for: .normal)
        closeBtn.tintColor = UIColor(white: 0.70, alpha: 1.0)
        closeBtn.addTarget(self, action: #selector(dismissNativeChat), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeBtn.widthAnchor.constraint(equalToConstant: 32),
            closeBtn.heightAnchor.constraint(equalToConstant: 32)
        ])

        stack.addArrangedSubview(pasteBtn)
        stack.addArrangedSubview(nativeTextField)
        stack.addArrangedSubview(sendBtn)
        stack.addArrangedSubview(closeBtn)

        let bottomConstraint = nativeChatBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        self.nativeChatBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            nativeChatBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nativeChatBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nativeChatBar.heightAnchor.constraint(equalToConstant: 48),
            bottomConstraint,

            stack.leadingAnchor.constraint(equalTo: nativeChatBar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: nativeChatBar.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: nativeChatBar.centerYAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func pasteToNativeChat() {
        if let clip = UIPasteboard.general.string, !clip.isEmpty {
            let current = nativeTextField.text ?? ""
            nativeTextField.text = current + clip
        }
    }

    @objc private func dismissNativeChat() {
        nativeTextField.resignFirstResponder()
        nativeChatBar.isHidden = true
    }

    @objc private func sendNativeChatText() {
        let text = nativeTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            sendTextToMIDlet(text, sendEnter: true)
            nativeTextField.text = ""
            showToast(message: "Đã gửi vào game")
        } else {
            sendEnterToMIDlet()
        }
        nativeTextField.resignFirstResponder()
    }

    private func sendEnterToMIDlet() {
        DispatchQueue.global(qos: .userInitiated).async {
            j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), -5) // Canvas.FIRE
            j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), 10) // '\n'
            usleep(20000)
            j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), 10)
            j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), -5)
        }
    }

    @objc private func handleKeyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let kbFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        nativeChatBarBottomConstraint?.constant = -kbFrame.height
        nativeChatBar.isHidden = false
        view.bringSubviewToFront(nativeChatBar)
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        nativeChatBarBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration, animations: {
            self.view.layoutIfNeeded()
        }) { _ in
            self.nativeChatBar.isHidden = true
        }
    }

    @objc private func nativeKeyboardTapped() {
        softKeyHaptic.impactOccurred(intensity: 0.7)
        if nativeTextField.isFirstResponder {
            nativeTextField.resignFirstResponder()
            nativeChatBar.isHidden = true
        } else {
            nativeChatBar.isHidden = false
            view.bringSubviewToFront(nativeChatBar)
            nativeTextField.becomeFirstResponder()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendNativeChatText()
        return true
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
        dismissNativeAlert()
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
        dismissNativeAlert()
        let formTitle = String(cString: j2me_ui_get_form_title())
        titleLabel.text = formTitle.isEmpty ? "Tài khoản" : formTitle
        textBoxView.buildFromNativeData()
        textBoxView.isHidden = false
        emulatorView.isHidden = false
        decadeKeypadView?.isHidden = true
        floatingShowKeypadBtn.isHidden = true
        formView.isHidden = true
        listView.isHidden = true
        view.bringSubviewToFront(textBoxView)
    }

    func showFormView() {
        dismissNativeAlert()
        let formTitle = String(cString: j2me_ui_get_form_title())
        titleLabel.text = formTitle.isEmpty ? appName : formTitle
        formView.buildFromNativeData()
        formView.isHidden = false
        emulatorView.isHidden = false
        decadeKeypadView?.isHidden = true
        floatingShowKeypadBtn.isHidden = true
        textBoxView.isHidden = true
        listView.isHidden = true
        view.bringSubviewToFront(formView)
    }

    func showListView() {
        dismissNativeAlert()
        let formTitle = String(cString: j2me_ui_get_form_title())
        titleLabel.text = formTitle.isEmpty ? "Menu" : formTitle
        listView.buildFromNativeData()
        listView.isHidden = false
        emulatorView.isHidden = false
        decadeKeypadView?.isHidden = true
        floatingShowKeypadBtn.isHidden = true
        textBoxView.isHidden = true
        formView.isHidden = true
        view.bringSubviewToFront(listView)
    }

    private func dismissNativeAlert() {
        alertTimeoutWork?.cancel()
        alertTimeoutWork = nil
        nativeAlert?.dismiss(animated: false)
        nativeAlert = nil
    }

    func showAlert() {
        dismissNativeAlert()
        let slot = jvm_bridge_get_focused_slot()
        let revision = j2me_ui_screen_revision(slot)
        let isCurrentScreen = {
            jvm_bridge_get_focused_slot() == slot && j2me_ui_screen_revision(slot) == revision
        }
        let title = String(cString: j2me_ui_get_form_title())
        let text = String(cString: j2me_ui_get_alert_text())

        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)

        let cmdCount = j2me_ui_get_command_count()
        if cmdCount == 0 {
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                guard isCurrentScreen() else { return }
                self?.alertTimeoutWork?.cancel()
                j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
            })
        } else {
            for i in 0..<cmdCount {
                let label = String(cString: j2me_ui_get_command_label(Int32(i)))
                let cmdId = j2me_ui_get_command_id(Int32(i))
                alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                    guard isCurrentScreen() else { return }
                    self?.alertTimeoutWork?.cancel()
                    j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmdId)
                })
            }
        }

        if let presenter = view.topMostPresentedViewController {
            presenter.present(alert, animated: true)
            nativeAlert = alert
        }

        let timeout = j2me_ui_get_alert_timeout()
        if timeout > 0 {
            let work = DispatchWorkItem { [weak alert] in
                guard isCurrentScreen() else { return }
                alert?.dismiss(animated: true)
                j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
            }
            alertTimeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeout) / 1000.0, execute: work)
        }
    }

    // ============================================================
    // MARK: - Game Lifecycle
    // ============================================================

    private func startGame() {
        guard !isShuttingDown, !hasStartedGame, let session = tabSessions.first else { return }
        hasStartedGame = true
        GameViewController.currentActiveGameVC = self
        j2me_input_reset()
        j2me_render_set_split_view(isSplitViewEnabled ? 1 : 0)
        j2me_render_set_fps_limit(Int32(session.fps))
        DecadeBackgroundKeeper.shared.updateNowPlayingGame(name: session.appName)
        let treo = DecadeBackgroundKeeper.shared.isTreoActive
        isKeepAwake = treo
        UIApplication.shared.isIdleTimerDisabled = treo
        if treo {
            DecadeBackgroundKeeper.shared.startKeepalive()
        }
        launchTab(session)
        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
    }

    private func launchTab(_ session: TabSession) {
        let slot = session.slotIndex
        guard !isShuttingDown, tabWorkerSlots.insert(slot).inserted else { return }
        forgetFrame(for: slot)
        if activeSlot == slot {
            canvasWidth = session.width
            canvasHeight = session.height
            emulatorView.canvasWidth = session.width
            emulatorView.canvasHeight = session.height
            emulatorView.layer.contents = nil
            placeholderIconView?.image = session.icon
            placeholderIconView?.alpha = 1
        }

        DecadeProxyManager.shared.syncToNative(appId: session.appName, slot: slot)
        DecadeChangeIpViewController.syncToNative()
        let path = session.jarPath
        let saveRoot = session.saveRoot
        let width = Int32(session.width), height = Int32(session.height)
        let scale = Int32(session.renderScale), fps = Int32(session.fps)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.runTab(slot: slot, path: path, saveRoot: saveRoot,
                                     width: width, height: height, scale: scale, fps: fps)
            DispatchQueue.main.async { self.tabDidFinish(slot: slot, result: result) }
        }
    }

    nonisolated private func tabMayRun(slot: Int) -> Bool {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                !self.isShuttingDown && !self.restartingSlots.contains(slot)
                    && self.tabSessions.contains { $0.slotIndex == slot }
            }
        }
    }

    nonisolated private func runTab(slot index: Int, path: String, saveRoot: String,
                                    width: Int32, height: Int32, scale: Int32, fps: Int32) -> Int32 {
        guard tabMayRun(slot: index) else { return 0 }
        guard let resources = Bundle.main.resourcePath else { return -1 }
        do {
            try FileManager.default.createDirectory(atPath: saveRoot, withIntermediateDirectories: true)
        } catch {
            print("[Swift] Could not create save directory for slot \(index): \(error)")
            return -1
        }

        let slot = Int32(index)
        let initResult = jvm_bridge_init_slot(slot, resources, saveRoot, path, width, height, scale, fps)
        guard initResult == 0 else { return initResult }
        defer { jvm_bridge_destroy_slot(slot) }
        guard tabMayRun(slot: index) else { return 0 }
        return jvm_bridge_run_midlet_slot(slot, path)
    }

    private func tabDidFinish(slot: Int, result: Int32) {
        tabWorkerSlots.remove(slot)
        forgetFrame(for: slot)
        if isShuttingDown {
            finishShutdownIfReady()
            return
        }
        let restart = restartingSlots.remove(slot) != nil
        guard let index = tabSessions.firstIndex(where: { $0.slotIndex == slot }) else { return }
        if restart {
            launchTab(tabSessions[index])
            return
        }
        if tabSessions.count == 1 {
            if result != 0 { print("[Swift] MIDlet slot \(slot) failed: \(result)") }
            forceExitGame()
        } else {
            removeTab(at: index)
            if result != 0 { showToast(message: "Không chạy được tab \(index + 1) (mã \(result)).") }
        }
    }

    @objc private func backButtonTapped() {
        backTapped()
    }

    @objc private func backTapped() {
        let alert = UIAlertController(
            title: "📋 Danh Sách Chọn Game",
            message: "Bạn muốn quay lại danh sách chọn game như thế nào?",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "🟢 Về Danh Sách & Treo Ngầm (Giữ game 24/7)", style: .default) { [weak self] _ in
            self?.minimizeToLobby()
        })
        alert.addAction(UIAlertAction(title: "🔴 Thoát Game Hoàn Toàn", style: .destructive) { [weak self] _ in
            self?.forceExitGame()
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = backToListBtn
            popover.sourceRect = backToListBtn.bounds
        }
        present(alert, animated: true)
    }

    func minimizeToLobby() {
        isAppInBackground = false
        if DecadeBackgroundKeeper.shared.isTreoActive {
            DecadeBackgroundKeeper.shared.startKeepalive()
        }
        dismiss(animated: true) {
            NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
        }
    }

    func forceExitGame() {
        guard !isShuttingDown else { return }
        isUserInitiatedExit = true
        isOledSleeping = false
        restartingSlots.removeAll()
        backButton.isEnabled = false
        autoShutdownTimer?.invalidate()
        autoShutdownTimer = nil
        DecadeFloatingBubble.shared.hide()
        DecadeMiniWindow.shared.hide()
        DecadePiPManager.shared.stopPiP()
        // Only stop runtime audio keepalive — NEVER overwrite the user's saved isTreoActive preference!
        DecadeBackgroundKeeper.shared.stopKeepalive()
        UIApplication.shared.isIdleTimerDisabled = false
        for slot in tabWorkerSlots { jvm_bridge_request_stop_slot(Int32(slot)) }
        NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
        if presentingViewController != nil { dismiss(animated: true) }
        finishShutdownIfReady()
    }

    private func finishShutdownIfReady() {
        guard tabWorkerSlots.isEmpty, !cleanupStarted else { return }
        cleanupStarted = true
        DispatchQueue.global(qos: .utility).async {
            jvm_bridge_destroy_all()
            DispatchQueue.main.async {
                Self.slotFrameLock.lock()
                Self.slotFrames.removeAll()
                Self.slotFrameLock.unlock()
                if activeGameViewController === self { activeGameViewController = nil }
                setGlobalEmulatorView(nil)
                if Self.currentActiveGameVC === self { Self.currentActiveGameVC = nil }
                NotificationCenter.default.post(name: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil)
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

let slotFlushCallback: @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Int32) -> Void = { slot, cgImagePtr, width, height in
    guard let ptr = cgImagePtr else { return }
    let cgImage = Unmanaged<CGImage>.fromOpaque(ptr).takeRetainedValue()
    let slotIdx = Int(slot)
    GameViewController.updateSlotFrame(slot: slotIdx, image: cgImage)
}
