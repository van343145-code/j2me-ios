//
//  DecadeHelpViewController.swift
//  J2MEEmulator
//
//  Authentic Decade "Trợ giúp" screen with full user guide.
//

import UIKit

class DecadeHelpViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
        title = "Trợ giúp & Hướng dẫn"

        setupNavBar()
        setupUI()
    }

    private func setupNavBar() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 18, weight: .bold)]
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = .white

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Đóng", style: .plain, target: self, action: #selector(closeTapped))
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 16, bottom: 24, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        stack.addArrangedSubview(makeSectionCard(
            title: "1. Thêm game Java (.jar)",
            content: "Nhấn vào nút dấu cộng (+) màu đỏ ở góc dưới bên phải màn hình chính để chọn và nhập file game .jar từ Files (Tệp) trên iPhone."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "2. Chạy bản mod ghép nhiều tài khoản",
            content: "• Bản mod ghép (Ninja School Online, MrQuyet, AngelChip...) tự động nhận diện các phiên bản độc lập.\n• Bấm nút [+] trên thanh công cụ trong game để thêm 1 tab mới.\n• Bấm nút [++] để mở nhiều tab trong số \(JVM_BRIDGE_MAX_SLOTS) slot của ứng dụng.\n• Chạm số tab để đổi màn hình. Các tab khác vẫn chạy trong J2ME-Decade.\n• Nhấn giữ một tab để đóng riêng phiên đó."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "3. Tùy chỉnh bàn phím ảo tự do",
            content: "• Bấm nút 3 chấm [⋮] góc trên bên phải màn hình khi đang chơi game.\n• Chọn 'Chế độ chỉnh sửa cấu trúc phím': Bạn có thể kéo thả bất kỳ phím nào tới vị trí mong muốn trên màn hình.\n• Chọn 'Chế độ thay đổi kích cỡ cấu trúc phím': Dùng 2 ngón tay thu phóng (pinch) để phóng to / thu nhỏ phím.\n• Khi đã ưng ý, bấm lại [⋮] -> 'Hoàn thành chế độ chỉnh sửa' để lưu vị trí phím."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "4. Ẩn từng phím bấm",
            content: "• Bấm [⋮] -> chọn 'Ẩn nút'.\n• Tích chọn hoặc bỏ chọn những phím bạn muốn hiển thị hoặc ẩn đi (1-9, 0, *, #, L, R, C, các mũi tên, F...).\n• Bấm 'OK' màu đỏ để áp dụng."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "5. Bàn phím gõ chữ (Chat)",
            content: "• Khi cần nhập văn bản chat trong game, bấm vào biểu tượng bàn phím [⌨] ở thanh công cụ trên cùng.\n• Nhập nội dung xong bấm nút '✓ Xong' màu xanh để đóng bàn phím và gửi vào game."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "6. Quản lý Proxy & Thay IP máy chủ",
            content: "• Vào menu 3 chấm [⋮] ở màn hình chính ngoài danh sách game.\n• 'Quản lý Proxy': Kết nối mạng J2ME qua proxy HTTP / SOCKS5.\n• 'Thay IP Phiên Bản': Đổi IP server game sang máy chủ private tùy ý."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "7. Cửa sổ nhỏ ngoài màn hình chính (PiP)",
            content: "• Bấm [⋮] -> chọn 'Cửa Sổ Nhỏ Ngoài Màn Hình' để thu game thành cửa sổ nhỏ chạy trực tiếp ngoài màn hình chính và đè lên các ứng dụng khác (Facebook, Zalo, TikTok, Safari...).\n• Dùng 2 ngón tay kéo phóng to / thu nhỏ tuỳ ý hoặc kéo trượt cửa sổ tới bất kỳ vị trí nào trên màn hình.\n• Chạm vào biểu tượng mở rộng trên cửa sổ nhỏ để quay lại toàn màn hình game."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "8. Thông tin ứng dụng",
            content: "• Ứng dụng: jarNO1 iOS Native (miniJVM Multi-Tab Engine)\n• Tính năng nổi bật: Chơi và treo nhiều tab game J2ME, ẩn chạy ngầm 24/24, gộp setup bàn phím 1 chạm, cửa sổ nhỏ PiP kéo to nhỏ tự do ngoài màn hình chính."
        ))
    }

    private func makeSectionCard(title: String, content: String) -> UIView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.05
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 4

        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 8
        s.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        s.isLayoutMarginsRelativeArrangement = true
        s.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(s)

        let t = UILabel()
        t.text = title
        t.font = .systemFont(ofSize: 16, weight: .bold)
        t.textColor = UIColor(red: 0.12, green: 0.41, blue: 0.82, alpha: 1.0)
        s.addArrangedSubview(t)

        let c = UILabel()
        c.text = content
        c.font = .systemFont(ofSize: 14, weight: .regular)
        c.textColor = UIColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1.0)
        c.numberOfLines = 0
        s.addArrangedSubview(c)

        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: card.topAnchor),
            s.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            s.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            s.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        return card
    }
}
