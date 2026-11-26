import UIKit

/// Exact 1:1 port of `J2me.iOS.Ui.MicroController`:
/// - Top 44pt dark navy bar (`#1C2534`) with scrollable multi-slot tabs (`1..100`, active `#69D21E`) + 4 buttons (`🎮`, `+`, `−`, `⋮`)
/// - Light gray PlayView (`#D0D0D0`) hosting active slot's `WKWebView` at `PlayLayout.gameRect(...)` + 15-key `NstKeyboardView`
/// - `⋮` menu: `✓ Treo tắt màn` (`BackgroundAudio` + `background-loop.wav`), `Cỡ màn hình`, `Proxy`, `Cài đặt game`, `Ẩn ứng dụng`, `Thoát`
@MainActor
final class MicroController: UIViewController {
    private static let maxSlots = 100
    private(set) static var activeInstance: MicroController?

    static var activeSlotCount: Int {
        activeInstance?.slots.count ?? 0
    }

    static func isRunning(gameId: String) -> Bool {
        activeInstance?.slots.contains(where: { $0.game.id == gameId }) ?? false
    }

    static func open(game: GameEntry, from nav: UINavigationController?) {
        guard let nav else { return }
        if let existing = activeInstance {
            if !nav.viewControllers.contains(existing) {
                nav.pushViewController(existing, animated: true)
            }
            if let match = existing.slots.first(where: { $0.game.id == game.id }) {
                existing.select(slot: match)
            } else {
                existing.addSlot(game: game)
            }
        } else {
            let vc = MicroController()
            activeInstance = vc
            nav.pushViewController(vc, animated: true)
            vc.loadViewIfNeeded()
            vc.addSlot(game: game)
        }
    }

    static func resume(from nav: UINavigationController?) {
        guard let nav, let existing = activeInstance else { return }
        if !nav.viewControllers.contains(existing) {
            nav.pushViewController(existing, animated: true)
        }
    }

    // MARK: - Slot State

    private var slots: [EmulatorSession] = []
    private var currentSlot: EmulatorSession?
    private var keyboardVisible = true
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Views (Exact J2ME NST hierarchy)

    private let topBar = UIView()
    private let tabsScroll = UIScrollView()
    private let tabStack = UIStackView()
    private let rightStack = UIStackView()

    private let playContainer = UIView()
    private let keyboardView = NstKeyboardView()

    private let loadingPill = UIView()
    private let loadingSpinner = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()

    private let errorOverlay = UIView()
    private let errorTitleLabel = UILabel()
    private let errorDetailLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    private let toastLabel = UILabel()
    private var toastHideWork: DispatchWorkItem?
    private var proxyCoordinator: ProxyMenuCoordinator?

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = NstTheme.Player.barBg

        setupTopBar()
        setupPlayArea()
        setupOverlays()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        updateSlotBackgroundStates(appInBackground: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardView.cancelAllTouches()
        currentSlot?.releaseAllKeys()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let topInset = view.safeAreaInsets.top
        let bottomInset = view.safeAreaInsets.bottom
        let barH = PlayLayout.tabBar

        topBar.frame = CGRect(x: 0, y: 0, width: b.width, height: topInset + barH)
        let rightW: CGFloat = 176 // 4 buttons x 44pt exact
        rightStack.frame = CGRect(x: b.width - rightW, y: topInset, width: rightW, height: barH)
        tabsScroll.frame = CGRect(x: 0, y: topInset, width: max(0, b.width - rightW), height: barH)
        layoutTabStack()

        let playY = topInset + barH
        let playH = max(1, b.height - playY - bottomInset)
        playContainer.frame = CGRect(x: 0, y: playY, width: b.width, height: playH)

        relayoutPlayArea()
    }

    // MARK: - Setup UI

    private func setupTopBar() {
        topBar.backgroundColor = NstTheme.Player.barBg
        view.addSubview(topBar)

        tabsScroll.showsHorizontalScrollIndicator = false
        tabsScroll.showsVerticalScrollIndicator = false
        tabsScroll.alwaysBounceHorizontal = true
        topBar.addSubview(tabsScroll)

        tabStack.axis = .horizontal
        tabStack.alignment = .center
        tabStack.spacing = 6
        tabStack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tabStack.isLayoutMarginsRelativeArrangement = true
        tabsScroll.addSubview(tabStack)

        rightStack.axis = .horizontal
        rightStack.distribution = .fillEqually
        rightStack.alignment = .fill
        topBar.addSubview(rightStack)

        rightStack.addArrangedSubview(makeBarButton(title: "🎮") { [weak self] in self?.toggleKeyboard() })
        rightStack.addArrangedSubview(makeBarButton(title: "+") { [weak self] in self?.pickGame() })
        rightStack.addArrangedSubview(makeBarButton(title: "−") { [weak self] in self?.askCloseCurrent() })
        rightStack.addArrangedSubview(makeBarButton(title: "⋮") { [weak self] in self?.showMenu() })
    }

    private func makeBarButton(title: String, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    private func setupPlayArea() {
        playContainer.backgroundColor = NstTheme.Player.playBg
        playContainer.clipsToBounds = true
        view.addSubview(playContainer)

        keyboardView.onKeyPress = { [weak self] code in
            self?.currentSlot?.rawKeyDown(code)
        }
        keyboardView.onKeyRelease = { [weak self] code in
            self?.currentSlot?.rawKeyUp(code)
        }
        keyboardView.onKeyRepeat = { [weak self] code in
            self?.currentSlot?.rawKeyRepeat(code)
        }
        keyboardView.onTabAction = { [weak self] in
            self?.cycleNextSlot()
        }
        keyboardView.onSizeAction = { [weak self] in
            self?.showSizeInput()
        }
        playContainer.addSubview(keyboardView)
    }

    private func setupOverlays() {
        // Lightweight loading pill (NEVER hides WKWebView!)
        loadingPill.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        loadingPill.layer.cornerRadius = 14
        loadingPill.isUserInteractionEnabled = false
        loadingPill.isHidden = true
        loadingPill.translatesAutoresizingMaskIntoConstraints = false

        loadingSpinner.color = .white
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.text = "Đang mở game..."
        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false

        loadingPill.addSubview(loadingSpinner)
        loadingPill.addSubview(loadingLabel)
        playContainer.addSubview(loadingPill)

        NSLayoutConstraint.activate([
            loadingPill.centerXAnchor.constraint(equalTo: playContainer.centerXAnchor),
            loadingPill.topAnchor.constraint(equalTo: playContainer.topAnchor, constant: 48),
            loadingSpinner.leadingAnchor.constraint(equalTo: loadingPill.leadingAnchor, constant: 14),
            loadingSpinner.centerYAnchor.constraint(equalTo: loadingPill.centerYAnchor),
            loadingLabel.leadingAnchor.constraint(equalTo: loadingSpinner.trailingAnchor, constant: 10),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingPill.trailingAnchor, constant: -14),
            loadingLabel.topAnchor.constraint(equalTo: loadingPill.topAnchor, constant: 10),
            loadingLabel.bottomAnchor.constraint(equalTo: loadingPill.bottomAnchor, constant: -10),
        ])

        // Error overlay
        errorOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        errorOverlay.isHidden = true
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false

        errorTitleLabel.text = "Không mở được game"
        errorTitleLabel.textColor = .white
        errorTitleLabel.font = .boldSystemFont(ofSize: 17)
        errorTitleLabel.textAlignment = .center

        errorDetailLabel.textColor = NstTheme.Lic.codeMuted
        errorDetailLabel.font = .systemFont(ofSize: 14)
        errorDetailLabel.textAlignment = .center
        errorDetailLabel.numberOfLines = 0

        retryButton.setTitle("Thử lại", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.backgroundColor = NstTheme.Lic.accent
        retryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        retryButton.layer.cornerRadius = 10
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
        retryButton.addTarget(self, action: #selector(retryCurrentSlot), for: .touchUpInside)

        let errStack = UIStackView(arrangedSubviews: [errorTitleLabel, errorDetailLabel, retryButton])
        errStack.axis = .vertical
        errStack.alignment = .center
        errStack.spacing = 12
        errStack.translatesAutoresizingMaskIntoConstraints = false
        errorOverlay.addSubview(errStack)
        playContainer.addSubview(errorOverlay)

        NSLayoutConstraint.activate([
            errorOverlay.leadingAnchor.constraint(equalTo: playContainer.leadingAnchor),
            errorOverlay.trailingAnchor.constraint(equalTo: playContainer.trailingAnchor),
            errorOverlay.topAnchor.constraint(equalTo: playContainer.topAnchor),
            errorOverlay.bottomAnchor.constraint(equalTo: playContainer.bottomAnchor),
            errStack.centerYAnchor.constraint(equalTo: errorOverlay.centerYAnchor),
            errStack.leadingAnchor.constraint(equalTo: errorOverlay.leadingAnchor, constant: 24),
            errStack.trailingAnchor.constraint(equalTo: errorOverlay.trailingAnchor, constant: -24),
        ])

        // Toast pill
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        toastLabel.textColor = .white
        toastLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.layer.cornerRadius = 12
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.isUserInteractionEnabled = false
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: PlayLayout.tabBar + 12),
            toastLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
        ])
    }

    // MARK: - Layout Computation

    private func playAreaSize() -> CGSize {
        let b = playContainer.bounds.size
        if b.width > 10 && b.height > 10 { return b }
        let screen = UIScreen.main.bounds.size
        return CGSize(width: screen.width, height: max(200, screen.height - PlayLayout.tabBar - 80))
    }

    private func virtualSize(for cfg: GameConfig) -> VirtualSize {
        let area = playAreaSize()
        return PlayLayout.resolve(
            prefs: NstLibrary.shared.displayPrefs,
            keyboard: cfg.vkEnabled && keyboardVisible,
            areaW: area.width,
            areaH: area.height
        )
    }

    private func relayoutPlayArea() {
        let bounds = playContainer.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let cfg = currentSlot?.config ?? GameConfig()
        let showKb = cfg.vkEnabled && keyboardVisible
        let vSize = currentSlot?.virtualSize ?? virtualSize(for: cfg)

        let gameRect = PlayLayout.gameRect(
            areaW: bounds.width,
            areaH: bounds.height,
            vw: vSize.width,
            vh: vSize.height,
            config: cfg,
            keyboard: showKb,
            autoFit: vSize.autoFit,
            pixelScale: UIScreen.main.scale
        )

        playContainer.backgroundColor = UIColor(hex: cfg.screenBackgroundColor)

        for slot in slots {
            slot.webView.frame = gameRect
        }

        keyboardView.frame = bounds
        keyboardView.isHidden = !showKb
        keyboardView.config = cfg
        keyboardView.updateLayout(screen: bounds, game: gameRect, tabBar: PlayLayout.tabBar)

        playContainer.bringSubviewToFront(keyboardView)
        playContainer.bringSubviewToFront(loadingPill)
        playContainer.bringSubviewToFront(errorOverlay)
    }

    private func layoutTabStack() {
        let fit = tabStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let w = max(1, fit.width)
        tabStack.frame = CGRect(x: 0, y: 0, width: w, height: PlayLayout.tabBar)
        tabsScroll.contentSize = CGSize(width: w, height: PlayLayout.tabBar)
    }

    // MARK: - Multi-Slot Management (Exact J2ME NST)

    private func freeSlotIndex() -> Int {
        let used = Set(slots.map { $0.slotIndex })
        for i in 0..<Self.maxSlots where !used.contains(i) {
            return i
        }
        return slots.count
    }

    func addSlot(game: GameEntry) {
        guard slots.count < Self.maxSlots else {
            showToast("Đã đạt tối đa \(Self.maxSlots) cửa sổ")
            return
        }

        let idx = freeSlotIndex()
        let cfg = NstLibrary.shared.loadConfig(for: game.id)
        let vSize = virtualSize(for: cfg)
        let jarURL = NstLibrary.shared.jarURL(for: game)
        let saveURL = NstLibrary.shared.saveURL(for: game, slot: idx)

        let session = EmulatorSession(
            game: game,
            slotIndex: idx,
            gameURL: jarURL,
            saveURL: saveURL,
            config: cfg,
            virtualSize: vSize,
            proxyProvider: {
                ProxyStore.shared.proxyForSlot(gameId: game.id, slot: idx)
            }
        )

        session.onStateChanged = { [weak self, weak session] in
            guard let self, let session, self.currentSlot === session else { return }
            self.refreshStatusOverlay()
        }
        session.onExitRequested = { [weak self, weak session] in
            guard let self, let session else { return }
            self.closeSlot(session, stopSession: false)
        }

        slots.append(session)
        playContainer.insertSubview(session.webView, belowSubview: keyboardView)
        select(slot: session)
        session.start()
    }

    private func select(slot: EmulatorSession) {
        keyboardView.cancelAllTouches()
        currentSlot?.releaseAllKeys()
        currentSlot = slot

        for s in slots {
            let active = (s === slot)
            // Keep alpha = 1 so WebKit never suspends active or running slots; place active on top!
            s.webView.isUserInteractionEnabled = active
            s.setBackgrounded(!active)
            if active {
                playContainer.insertSubview(s.webView, belowSubview: keyboardView)
            }
        }

        rebuildTabs()
        relayoutPlayArea()
        refreshStatusOverlay()
    }

    private func rebuildTabs() {
        for v in tabStack.arrangedSubviews {
            tabStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        for slot in slots {
            let isActive = (slot === currentSlot)
            let btn = UIButton(type: .system)
            btn.setTitle("\(slot.slotIndex + 1)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            btn.layer.cornerRadius = 7
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
            btn.heightAnchor.constraint(equalToConstant: 30).isActive = true
            btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

            if isActive {
                btn.backgroundColor = NstTheme.Player.tabActive
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor.white.withAlphaComponent(0.10)
                btn.setTitleColor(NstTheme.Player.tabText, for: .normal)
            }

            btn.addAction(UIAction { [weak self, weak slot] _ in
                guard let self, let slot else { return }
                self.select(slot: slot)
            }, for: .touchUpInside)

            tabStack.addArrangedSubview(btn)
        }

        layoutTabStack()
    }

    private func refreshStatusOverlay() {
        guard let current = currentSlot else {
            loadingPill.isHidden = true
            loadingSpinner.stopAnimating()
            errorOverlay.isHidden = true
            return
        }

        if let err = current.errorMessage {
            loadingPill.isHidden = true
            loadingSpinner.stopAnimating()
            errorDetailLabel.text = err
            errorOverlay.isHidden = false
        } else if !current.isReady {
            errorOverlay.isHidden = true
            loadingPill.isHidden = false
            loadingSpinner.startAnimating()
        } else {
            loadingPill.isHidden = true
            loadingSpinner.stopAnimating()
            errorOverlay.isHidden = true
        }
    }

    @objc private func retryCurrentSlot() {
        guard let failed = currentSlot else { return }
        let game = failed.game
        closeSlot(failed, stopSession: true, exitIfEmpty: false)
        addSlot(game: game)
    }

    private func closeSlot(_ slot: EmulatorSession, stopSession: Bool, exitIfEmpty: Bool = true) {
        guard let idx = slots.firstIndex(where: { $0 === slot }) else { return }
        slots.remove(at: idx)
        slot.webView.removeFromSuperview()
        if stopSession {
            slot.stop()
        }

        if slots.isEmpty {
            currentSlot = nil
            if exitIfEmpty {
                BackgroundAudio.shared.stop()
                endBackgroundTask()
                if MicroController.activeInstance === self {
                    MicroController.activeInstance = nil
                }
                navigationController?.popViewController(animated: true)
            }
            return
        }

        if currentSlot === slot {
            let nextIdx = min(idx, slots.count - 1)
            select(slot: slots[nextIdx])
        } else {
            rebuildTabs()
        }
    }

    func closeAllAndExit() {
        keyboardView.cancelAllTouches()
        let all = slots
        slots.removeAll()
        currentSlot = nil
        for s in all {
            s.webView.removeFromSuperview()
            s.stop()
        }
        BackgroundAudio.shared.stop()
        endBackgroundTask()
        if MicroController.activeInstance === self {
            MicroController.activeInstance = nil
        }
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Top Bar & Keyboard Actions

    private func toggleKeyboard() {
        keyboardVisible.toggle()
        if !keyboardVisible {
            keyboardView.cancelAllTouches()
            currentSlot?.releaseAllKeys()
        }
        relayoutPlayArea()
    }

    private func cycleNextSlot() {
        guard slots.count > 1, let cur = currentSlot,
              let idx = slots.firstIndex(where: { $0 === cur }) else {
            showToast("Bấm + ở góc trên để mở thêm cửa sổ game")
            return
        }
        let next = slots[(idx + 1) % slots.count]
        select(slot: next)
    }

    private func pickGame() {
        let games = NstLibrary.shared.allPlayableGames()
        guard !games.isEmpty else {
            showToast("Chưa có game nào để mở")
            return
        }

        let sheet = UIAlertController(title: "Chọn bản mở ở cửa sổ mới", message: nil, preferredStyle: .actionSheet)
        for g in games {
            sheet.addAction(UIAlertAction(title: g.name, style: .default) { [weak self] _ in
                self?.addSlot(game: g)
            })
        }
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        presentActionSheet(sheet)
    }

    private func askCloseCurrent() {
        guard let cur = currentSlot else { return }
        let alert = UIAlertController(
            title: "Đóng cửa sổ \(cur.slotIndex + 1)",
            message: "Bạn có muốn đóng cửa sổ này không?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Đóng", style: .destructive) { [weak self] _ in
            self?.closeSlot(cur, stopSession: true)
        })
        present(alert, animated: true)
    }

    private func showMenu() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let afkPrefix = BackgroundAudio.shared.isEnabled ? "✓ " : ""
        sheet.addAction(UIAlertAction(title: "\(afkPrefix)Treo tắt màn", style: .default) { [weak self] _ in
            self?.toggleBackgroundAudio()
        })

        sheet.addAction(UIAlertAction(title: "Cỡ màn hình", style: .default) { [weak self] _ in
            self?.showSizeInput()
        })

        sheet.addAction(UIAlertAction(title: "Proxy", style: .default) { [weak self] _ in
            self?.showProxyMenu()
        })

        if let cur = currentSlot {
            sheet.addAction(UIAlertAction(title: "Cài đặt", style: .default) { [weak self] _ in
                let cfgVC = ConfigController(game: cur.game, startAfter: false) { [weak self, weak cur] updated in
                    guard let self, let cur else { return }
                    cur.applyConfig(updated)
                    self.relayoutPlayArea()
                }
                self?.navigationController?.pushViewController(cfgVC, animated: true)
            })
        }

        sheet.addAction(UIAlertAction(title: "Ẩn ứng dụng", style: .default) { [weak self] _ in
            self?.hideToHome()
        })

        sheet.addAction(UIAlertAction(title: "Thoát", style: .destructive) { [weak self] _ in
            self?.confirmExitAll()
        })

        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        presentActionSheet(sheet)
    }

    private func toggleBackgroundAudio() {
        if BackgroundAudio.shared.isEnabled {
            BackgroundAudio.shared.stop()
            showToast("Treo 24/24: TẮT")
        } else {
            BackgroundAudio.shared.start()
            showToast("Treo 24/24: BẬT")
        }
    }

    private func showSizeInput() {
        let area = playAreaSize()
        let prefs = NstLibrary.shared.displayPrefs
        let autoH = PlayLayout.autoHeightFor(width: prefs.width, areaW: area.width, areaH: area.height)

        let alert = UIAlertController(
            title: "Cỡ màn hình",
            message: "Áp cho mọi game. Rộng càng lớn nhìn càng rộng, Cao tự điền cho vừa màn (sửa được). Lưu xong game thoát về trang chủ để mở lại.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Rộng"
            tf.text = "\(prefs.width)"
            tf.keyboardType = .numberPad
        }
        alert.addTextField { tf in
            tf.placeholder = "Cao (tự khớp: \(autoH))"
            tf.text = prefs.height > 0 ? "\(prefs.height)" : "\(autoH)"
            tf.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { [weak self] _ in
            guard let self else { return }
            let wText = alert.textFields?.first?.text ?? ""
            let hText = (alert.textFields?.count ?? 0) > 1 ? (alert.textFields?[1].text ?? "") : ""
            let curArea = self.playAreaSize()
            let autoFn: (Int) -> Int = { w in
                PlayLayout.autoHeightFor(width: w, areaW: curArea.width, areaH: curArea.height)
            }
            var next = NstLibrary.shared.displayPrefs
            next.setFromText(widthText: wText, heightText: hText, autoFor: autoFn)
            NstLibrary.shared.displayPrefs = next
            NstLibrary.shared.saveDisplayPrefs()

            let desc = next.describe(autoHeight: autoFn(next.width))
            let info = UIAlertController(
                title: "Cỡ màn hình",
                message: "Đã đổi thành \(desc). Game sẽ thoát về trang chủ, bấm vào game để mở lại.",
                preferredStyle: .alert
            )
            info.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.closeAllAndExit()
            })
            self.present(info, animated: true)
        })
        present(alert, animated: true)
    }

    private func showProxyMenu() {
        let coord = ProxyMenuCoordinator(
            presenter: self,
            openSlotsProvider: { [weak self] in
                guard let self else { return [] }
                return self.slots.map { slot in
                    ProxyMenuCoordinator.OpenSlotInfo(
                        slot: slot.slotIndex,
                        gameId: slot.game.id,
                        gameName: slot.game.name,
                        disconnect: { [weak slot] in
                            slot?.disconnectSockets()
                        }
                    )
                }
            },
            toastHandler: { [weak self] msg in
                self?.showToast(msg)
            }
        )
        self.proxyCoordinator = coord
        coord.showRoot()
    }

    private func hideToHome() {
        keyboardView.cancelAllTouches()
        currentSlot?.releaseAllKeys()
        navigationController?.popViewController(animated: true)
    }

    private func confirmExitAll() {
        let alert = UIAlertController(
            title: "Thoát",
            message: "Bạn muốn thoát ra ngoài?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Thoát", style: .destructive) { [weak self] _ in
            self?.closeAllAndExit()
        })
        present(alert, animated: true)
    }

    // MARK: - App Lifecycle (Low-CPU Background AFK)

    func appDidEnterBackground() {
        keyboardView.cancelAllTouches()
        currentSlot?.releaseAllKeys()
        updateSlotBackgroundStates(appInBackground: true)
        beginBackgroundTask()
    }

    func appWillEnterForeground() {
        endBackgroundTask()
        BackgroundAudio.shared.foreground()
        updateSlotBackgroundStates(appInBackground: false)
    }

    private func updateSlotBackgroundStates(appInBackground: Bool) {
        for slot in slots {
            let bg = appInBackground || (slot !== currentSlot)
            slot.setBackgrounded(bg)
        }
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "J2ME-NST-AFK") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let id = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(id)
    }

    // MARK: - Helpers

    private func presentActionSheet(_ sheet: UIAlertController) {
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = rightStack
            pop.sourceRect = rightStack.bounds
        }
        present(sheet, animated: true)
    }

    private func showToast(_ text: String) {
        toastHideWork?.cancel()
        toastLabel.text = "  \(text)  "
        UIView.animate(withDuration: 0.18) {
            self.toastLabel.alpha = 1
        }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.25) {
                self?.toastLabel.alpha = 0
            }
        }
        toastHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
