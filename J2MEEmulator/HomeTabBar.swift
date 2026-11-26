import UIKit

/// Exact 1:1 port of `J2me.iOS.Ui.HomeTabBar` (BarHeight = 56pt, track #E6DFD8, white pill thumb, #B84A19 count badge).
@MainActor
final class HomeTabBar: UIView {
    static let barHeight: CGFloat = 56.0

    private let track = UIView()
    private let thumb = UIView()
    private let modButton = UIButton(type: .system)
    private let ownButton = UIButton(type: .system)
    private let badge = UILabel()
    private var badgeWidthConstraint: NSLayoutConstraint?

    private var selectedTab: HomeTab = .mod
    private let onPick: (HomeTab) -> Void

    init(onPick: @escaping (HomeTab) -> Void) {
        self.onPick = onPick
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.barHeight))
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupViews() {
        backgroundColor = NstTheme.Apk.background

        track.backgroundColor = NstTheme.HomeTab.track
        track.layer.cornerRadius = 16
        addSubview(track)

        thumb.backgroundColor = .white
        thumb.layer.cornerRadius = 12
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOpacity = 0.18
        thumb.layer.shadowRadius = 2.0
        thumb.layer.shadowOffset = CGSize(width: 0, height: 1)
        track.addSubview(thumb)

        configureTabButton(modButton, title: HomeTab.mod.title, tag: 0)
        configureTabButton(ownButton, title: HomeTab.own.title, tag: 1)
        track.addSubview(modButton)
        track.addSubview(ownButton)

        badge.backgroundColor = NstTheme.HomeTab.accent
        badge.textColor = .white
        badge.font = .boldSystemFont(ofSize: 11)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        ownButton.addSubview(badge)

        let widthC = badge.widthAnchor.constraint(equalToConstant: 18)
        badgeWidthConstraint = widthC
        NSLayoutConstraint.activate([
            badge.centerYAnchor.constraint(equalTo: ownButton.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 18),
            widthC,
        ])
        if let titleLabel = ownButton.titleLabel {
            badge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6).isActive = true
        } else {
            badge.trailingAnchor.constraint(equalTo: ownButton.trailingAnchor, constant: -10).isActive = true
        }
    }

    private func configureTabButton(_ button: UIButton, title: String, tag: Int) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14.5, weight: .semibold)
        button.tag = tag
        button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
    }

    @objc private func handleTap(_ sender: UIButton) {
        let next: HomeTab = sender.tag == 0 ? .mod : .own
        guard next != selectedTab else { return }
        onPick(next)
    }

    func bind(tab: HomeTab, ownCount: Int, animated: Bool) {
        selectedTab = tab

        if ownCount > 0 {
            let text = ownCount > 99 ? "99+" : "\(ownCount)"
            badge.text = text
            badge.isHidden = false
            badgeWidthConstraint?.constant = text.count > 1 ? 26 : 18
        } else {
            badge.isHidden = true
        }

        modButton.setTitleColor(tab == .mod ? .black : NstTheme.HomeTab.inactiveText, for: .normal)
        ownButton.setTitleColor(tab == .own ? .black : NstTheme.HomeTab.inactiveText, for: .normal)

        if animated {
            UIView.animate(withDuration: 0.22) {
                self.layoutThumb()
            }
        } else {
            layoutThumb()
        }
    }

    private func layoutThumb() {
        let halfW = max(0, (track.bounds.width - 8) * 0.5)
        let h = max(0, track.bounds.height - 8)
        let x: CGFloat = (selectedTab == .own) ? (4 + halfW) : 4
        thumb.frame = CGRect(x: x, y: 4, width: halfW, height: h)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let trackW = max(0, bounds.width - 24)
        track.frame = CGRect(x: 12, y: 8, width: trackW, height: 40)

        let halfW = max(0, (track.bounds.width - 8) * 0.5)
        modButton.frame = CGRect(x: 4, y: 0, width: halfW, height: 40)
        ownButton.frame = CGRect(x: 4 + halfW, y: 0, width: halfW, height: 40)
        layoutThumb()
    }
}
