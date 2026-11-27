//
//  DecadeProfilesViewController.swift
//  J2MEEmulator
//
//  Authentic Decade "Hồ sơ" configuration profiles screen.
//

import UIKit

class DecadeProfilesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    struct Profile {
        let name: String
        let desc: String
        let fps: Int
        let layout: Int // 0=Arrows, 1=Combined, 2=Numpad
        let alpha: Float
    }

    private let profiles: [Profile] = [
        Profile(name: "Mặc định (Default)", desc: "Bố cục tiêu chuẩn cân bằng cho mọi game", fps: 60, layout: 0, alpha: 180),
        Profile(name: "Ninja School Online (Tối ưu)", desc: "Phím mũi tên 8 hướng + nút * # góc, phản hồi siêu nhanh 60 FPS", fps: 60, layout: 0, alpha: 220),
        Profile(name: "Bản mod ghép (Tiết kiệm RAM)", desc: "Tối ưu bộ nhớ, 30 FPS ổn định khi mở nhiều tab", fps: 30, layout: 0, alpha: 160),
        Profile(name: "Bàn phím số điện thoại (Numpad)", desc: "Phù hợp game đánh theo lượt, nhập liệu nhiều", fps: 60, layout: 2, alpha: 200),
    ]

    private var activeIndex: Int = 0
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
        title = "Hồ sơ cấu hình"

        setupNavBar()
        setupUI()
        activeIndex = UserDefaults.standard.integer(forKey: "decade_active_profile_index")
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
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        profiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ProfileCell")
        cell.backgroundColor = UIColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1.0)

        let p = profiles[indexPath.row]
        cell.textLabel?.text = p.name
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        cell.textLabel?.textColor = .white

        cell.detailTextLabel?.text = p.desc
        cell.detailTextLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        cell.detailTextLabel?.textColor = UIColor(red: 0.82, green: 0.86, blue: 0.95, alpha: 1.0)
        cell.detailTextLabel?.numberOfLines = 2

        let isSelected = indexPath.row == activeIndex
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.tintColor = UIColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 1.0)

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        activeIndex = indexPath.row
        UserDefaults.standard.set(activeIndex, forKey: "decade_active_profile_index")

        let selected = profiles[activeIndex]
        UserDefaults.standard.set(selected.fps, forKey: "default_fps_limit")
        UserDefaults.standard.set(selected.layout, forKey: "default_keypad_layout")
        UserDefaults.standard.set(selected.alpha, forKey: "default_keypad_alpha")

        tableView.reloadData()

        let alert = UIAlertController(title: "Đã kích hoạt", message: "Đã áp dụng hồ sơ: \(selected.name)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
