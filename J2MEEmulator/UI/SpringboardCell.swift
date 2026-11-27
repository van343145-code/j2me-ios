//
//  SpringboardCell.swift
//  J2MEEmulator
//
//  Thiết kế thẻ game chuẩn 1:1 theo giao diện "Chơi Game Tuổi Thơ"
//

import UIKit

class SpringboardCell: UICollectionViewCell {

    static let reuseID = "SpringboardCell"
    static let iconSize: CGFloat = 52
    static let iconCornerRadius: CGFloat = 12

    var onMenuTap: (() -> Void)?

    private let cardContainer = UIView()
    let iconView = UIImageView()
    let nameLabel = UILabel()
    let detailsLabel = UILabel()

    // Status Tags
    private let tagsStack = UIStackView()
    private let resPill = UIView()
    private let resLabel = UILabel()
    private let statusPill = UIView()
    private let statusDot = UIView()
    private let statusLabel = UILabel()

    // 3-dots button
    private let menuButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.backgroundColor = .clear

        // Card Container: Dark modern rounded card (#171920)
        cardContainer.backgroundColor = UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1.0)
        cardContainer.layer.cornerRadius = 16
        cardContainer.layer.borderWidth = 1.0
        cardContainer.layer.borderColor = UIColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1.0).cgColor
        cardContainer.layer.masksToBounds = true
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardContainer)

        NSLayoutConstraint.activate([
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // App Icon
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = Self.iconCornerRadius
        iconView.layer.masksToBounds = true
        iconView.layer.borderWidth = 0.5
        iconView.layer.borderColor = UIColor(white: 1.0, alpha: 0.15).cgColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(iconView)

        // 3-dots Menu Button
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = UIColor(red: 0.60, green: 0.64, blue: 0.70, alpha: 1.0)
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(menuButton)

        // Middle Text Info Stack
        nameLabel.font = .systemFont(ofSize: 16, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        detailsLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailsLabel.textColor = UIColor(red: 0.58, green: 0.62, blue: 0.68, alpha: 1.0)
        detailsLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false

        // Resolution Tag Pill
        resPill.backgroundColor = UIColor(red: 0.15, green: 0.17, blue: 0.21, alpha: 1.0)
        resPill.layer.cornerRadius = 8
        resPill.translatesAutoresizingMaskIntoConstraints = false

        let resIcon = UIImageView(image: UIImage(systemName: "aspectratio"))
        resIcon.tintColor = UIColor(red: 0.68, green: 0.72, blue: 0.78, alpha: 1.0)
        resIcon.contentMode = .scaleAspectFit
        resIcon.translatesAutoresizingMaskIntoConstraints = false

        resLabel.font = .systemFont(ofSize: 11, weight: .medium)
        resLabel.textColor = UIColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1.0)
        resLabel.translatesAutoresizingMaskIntoConstraints = false

        resPill.addSubview(resIcon)
        resPill.addSubview(resLabel)
        NSLayoutConstraint.activate([
            resIcon.leadingAnchor.constraint(equalTo: resPill.leadingAnchor, constant: 6),
            resIcon.centerYAnchor.constraint(equalTo: resPill.centerYAnchor),
            resIcon.widthAnchor.constraint(equalToConstant: 12),
            resIcon.heightAnchor.constraint(equalToConstant: 12),

            resLabel.leadingAnchor.constraint(equalTo: resIcon.trailingAnchor, constant: 4),
            resLabel.trailingAnchor.constraint(equalTo: resPill.trailingAnchor, constant: -6),
            resLabel.centerYAnchor.constraint(equalTo: resPill.centerYAnchor),
            resPill.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Live Running Status Pill
        statusPill.layer.cornerRadius = 8
        statusPill.translatesAutoresizingMaskIntoConstraints = false

        statusDot.layer.cornerRadius = 3.5
        statusDot.layer.masksToBounds = true
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        statusPill.addSubview(statusDot)
        statusPill.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusDot.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 6),
            statusDot.centerYAnchor.constraint(equalTo: statusPill.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),

            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -6),
            statusLabel.centerYAnchor.constraint(equalTo: statusPill.centerYAnchor),
            statusPill.heightAnchor.constraint(equalToConstant: 20),
        ])

        tagsStack.axis = .horizontal
        tagsStack.spacing = 6
        tagsStack.alignment = .center
        tagsStack.addArrangedSubview(resPill)
        tagsStack.addArrangedSubview(statusPill)
        tagsStack.translatesAutoresizingMaskIntoConstraints = false

        cardContainer.addSubview(nameLabel)
        cardContainer.addSubview(detailsLabel)
        cardContainer.addSubview(tagsStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            menuButton.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -8),
            menuButton.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),

            nameLabel.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -8),

            detailsLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailsLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailsLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -8),

            tagsStack.topAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 6),
            tagsStack.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            tagsStack.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -10),
        ])
    }

    @objc private func menuTapped() {
        onMenuTap?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        nameLabel.text = nil
        detailsLabel.text = nil
        onMenuTap = nil
    }

    // Touch animation
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.cardContainer.alpha = self.isHighlighted ? 0.75 : 1.0
                self.cardContainer.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }

    func configure(name: String, details: String, icon: UIImage, resText: String, isRunning: Bool) {
        iconView.image = icon
        nameLabel.text = name
        detailsLabel.text = details
        resLabel.text = resText

        if isRunning {
            statusPill.backgroundColor = UIColor(red: 0.05, green: 0.24, blue: 0.14, alpha: 1.0)
            statusDot.backgroundColor = UIColor(red: 0.20, green: 0.83, blue: 0.45, alpha: 1.0)
            statusLabel.textColor = UIColor(red: 0.29, green: 0.87, blue: 0.52, alpha: 1.0)
            statusLabel.text = "Đang Chạy"
        } else {
            statusPill.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            statusDot.backgroundColor = UIColor(red: 0.55, green: 0.58, blue: 0.65, alpha: 1.0)
            statusLabel.textColor = UIColor(red: 0.60, green: 0.64, blue: 0.70, alpha: 1.0)
            statusLabel.text = "Đã Dừng"
        }
    }
}
