//
//  FormView.swift
//  J2MEEmulator
//
//  Displays J2ME Forms/Lists/TextBoxes using authentic KamenRider Decade native widgets.
//  Matches Android KamenRider Decade 1:1.
//

import UIKit

extension UIView {
    var topMostPresentedViewController: UIViewController? {
        var top: UIViewController? = activeGameViewController ?? self.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// ============================================================
// MARK: - J2METextBoxView (Authentic Decade Full-screen In-Game Text Input)
// ============================================================

class J2METextBoxView: UIView, UITextViewDelegate {

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let bottomButtonBar = UIStackView()
    private var commandButtons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        overrideUserInterfaceStyle = .light
        backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 0.90) // Translucent dark overlay

        // Dark gaming editing canvas
        textView.font = .systemFont(ofSize: 18)
        textView.textColor = .white
        textView.backgroundColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 0.95)
        textView.layer.cornerRadius = 12
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor(red: 0.22, green: 0.28, blue: 0.38, alpha: 1.0).cgColor
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.delegate = self
        textView.returnKeyType = .done
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        // Placeholder
        placeholderLabel.text = "Chạm vào đây để nhập nội dung..."
        placeholderLabel.font = .systemFont(ofSize: 18)
        placeholderLabel.textColor = UIColor(white: 0.55, alpha: 1.0)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        // Setup Keyboard Accessory Toolbar with the requested "nút V" (✓ Done)
        setupKeyboardToolbar()

        // Tap on background dismisses keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)

        // Bottom Soft Button Bar
        bottomButtonBar.axis = .horizontal
        bottomButtonBar.spacing = 8
        bottomButtonBar.distribution = .fillEqually
        bottomButtonBar.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 0.95)
        bottomButtonBar.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        bottomButtonBar.isLayoutMarginsRelativeArrangement = true
        bottomButtonBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomButtonBar)

        // Top border for bottom bar
        let separator = UIView()
        separator.backgroundColor = UIColor(red: 0.20, green: 0.25, blue: 0.34, alpha: 1.0)
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -4),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 14),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomButtonBar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            bottomButtonBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomButtonBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomButtonBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            bottomButtonBar.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    /// Setup the keyboard accessory toolbar with the "V" (✓) close button
    private func setupKeyboardToolbar() {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        toolbar.barTintColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0)

        // Clear / Xóa text button on left
        let clearBtn = UIBarButtonItem(title: "Xóa", style: .plain, target: self, action: #selector(clearText))
        clearBtn.tintColor = UIColor(red: 0.70, green: 0.75, blue: 0.82, alpha: 1.0)

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        // The requested "nút V" / Done checkmark button:
        // Displays "✓" (V) or "Xong" in prominent emerald green
        let doneBtn = UIBarButtonItem(title: "✓ Xong", style: .done, target: self, action: #selector(dismissKeyboard))
        doneBtn.tintColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0)
        doneBtn.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 18, weight: .bold)
        ], for: .normal)

        toolbar.items = [clearBtn, flexSpace, doneBtn]
        textView.inputAccessoryView = toolbar
    }

    @objc private func clearText() {
        textView.text = ""
        placeholderLabel.isHidden = false
        syncTextToNative()
    }

    /// User requested: "nút V ấn vào thì nó đóng bàn phím sau khi nhập xong"
    @objc func dismissKeyboard() {
        textView.resignFirstResponder()
        syncTextToNative()
    }

    @objc private func backgroundTapped() {
        textView.resignFirstResponder()
        syncTextToNative()
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        syncTextToNative()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // If user presses return/enter on the single line, close keyboard
        if text == "\n" {
            dismissKeyboard()
            return false
        }
        return true
    }

    private func syncTextToNative() {
        let text = textView.text ?? ""
        text.withCString { cstr in
            j2me_ui_set_textbox_text(cstr)
        }
    }

    func buildFromNativeData() {
        // Load initial text
        let initial = String(cString: j2me_ui_get_textbox_text())
        textView.text = initial
        placeholderLabel.isHidden = !initial.isEmpty
        let constraints = j2me_ui_get_form_item_param2(0)
        textView.isEditable = (constraints & 0x20000) == 0
        textView.isSecureTextEntry = (constraints & 0x10000) != 0

        // Build command buttons (CANCEL, OK, MENU)
        bottomButtonBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        commandButtons.removeAll()

        let cmdCount = j2me_ui_get_command_count()
        for i in 0..<cmdCount {
            let cmdLabel = String(cString: j2me_ui_get_command_label(Int32(i)))
            let cmdId = j2me_ui_get_command_id(Int32(i))

            let btn = UIButton(type: .system)
            btn.setTitle(cmdLabel.uppercased(), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            btn.tag = Int(cmdId)

            let isOk = cmdLabel.lowercased().contains("ok") || cmdLabel.lowercased().contains("chọn") || cmdLabel.lowercased().contains("select") || cmdLabel.lowercased().contains("xong")
            let isCancel = cmdLabel.lowercased().contains("cancel") || cmdLabel.lowercased().contains("hủy") || cmdLabel.lowercased().contains("thoát") || cmdLabel.lowercased().contains("quay lại")

            if isOk {
                btn.backgroundColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0) // Emerald Green
                btn.setTitleColor(.white, for: .normal)
            } else if isCancel {
                btn.backgroundColor = UIColor(red: 0.22, green: 0.27, blue: 0.35, alpha: 1.0) // Slate Gray
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = UIColor(red: 0.18, green: 0.24, blue: 0.32, alpha: 1.0) // Dark Slate
                btn.setTitleColor(.white, for: .normal)
            }

            btn.layer.cornerRadius = 8
            btn.addTarget(self, action: #selector(commandTapped(_:)), for: .touchUpInside)

            bottomButtonBar.addArrangedSubview(btn)
            commandButtons.append(btn)
        }

        // Auto focus textview if requested
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, !self.isHidden, self.window != nil, self.textView.isEditable else { return }
            self.textView.becomeFirstResponder()
        }
    }

    @objc private func commandTapped(_ sender: UIButton) {
        dismissKeyboard()
        syncTextToNative()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let cmdId = Int32(sender.tag)
        j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmdId)
    }
}

// ============================================================
// MARK: - FormView (Multi-item forms)
// ============================================================

class FormView: UIView, UITextFieldDelegate {

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var commandButtons: [UIButton] = []
    private let commandBar = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        overrideUserInterfaceStyle = .light
        backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 0.90) // Translucent dark overlay

        // Dismiss keyboard when tapping on background
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        commandBar.axis = .horizontal
        commandBar.spacing = 10
        commandBar.distribution = .fillEqually
        commandBar.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 0.95)
        commandBar.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        commandBar.isLayoutMarginsRelativeArrangement = true
        commandBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(commandBar)

        let separator = UIView()
        separator.backgroundColor = UIColor(red: 0.20, green: 0.25, blue: 0.34, alpha: 1.0)
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: commandBar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            commandBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            commandBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            commandBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            commandBar.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private var commands: [(label: String, id: Int32, type: Int32)] = []
    private var textFields: [Int: UITextField] = [:]
    private var choiceRows: [Int: (stack: UIStackView, isMultiple: Bool, label: UILabel)] = [:]

    func buildFromNativeData() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        commandBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        commandButtons.removeAll()
        commands.removeAll()
        textFields.removeAll()
        choiceRows.removeAll()

        let count = Int(j2me_ui_get_form_item_count())
        for i in 0..<count {
            let itemType = j2me_ui_get_form_item_type(Int32(i))
            let label = String(cString: j2me_ui_get_form_item_label(Int32(i)))
            let text = String(cString: j2me_ui_get_form_item_text(Int32(i)))

            switch itemType {
            case 0:
                addStringItem(label: label, text: text)
            case 1:
                addTextField(label: label, text: text, index: i)
            case 2:
                addChoiceGroup(label: label, text: text, index: i)
            default:
                addStringItem(label: label, text: text)
            }
        }

        let cmdCount = j2me_ui_get_command_count()
        for i in 0..<cmdCount {
            let cmdLabel = String(cString: j2me_ui_get_command_label(Int32(i)))
            let cmdId = j2me_ui_get_command_id(Int32(i))
            let cmdType = j2me_ui_get_command_type(Int32(i))
            commands.append((label: cmdLabel, id: cmdId, type: cmdType))
        }

        if commands.isEmpty {
            // Default Cancel/Back
            let rightBtn = makeRedButton(title: "QUAY LẠI", tag: 0)
            commandBar.addArrangedSubview(UIView()) // spacer
            commandBar.addArrangedSubview(rightBtn)
        } else if commands.count <= 3 {
            for (index, cmd) in commands.enumerated() {
                if index > 0 && commands.count == 2 { commandBar.addArrangedSubview(UIView()) }
                commandBar.addArrangedSubview(makeRedButton(title: cmd.label.uppercased(), tag: Int(cmd.id)))
            }
        } else {
            // > 2 commands: Left is MENU, Right is Back/Exit command
            let menuBtn = makeRedButton(title: "MENU", tag: -1)
            menuBtn.addTarget(self, action: #selector(showFormMenu(_:)), for: .touchUpInside)
            commandBar.addArrangedSubview(menuBtn)
            commandBar.addArrangedSubview(UIView()) // spacer

            let exitCmd = commands.first {
                let l = $0.label.lowercased()
                return $0.type == 7 || $0.type == 2 || l.contains("thoát") || l.contains("quay lại") || l.contains("back") || l.contains("hủy")
            } ?? commands.last!
            let rightBtn = makeRedButton(title: exitCmd.label.uppercased(), tag: Int(exitCmd.id))
            commandBar.addArrangedSubview(rightBtn)
        }
    }

    private func makeRedButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        btn.layer.cornerRadius = 8
        let lower = title.lowercased()
        if lower.contains("ok") || lower.contains("chọn") || lower.contains("xong") || lower.contains("tiếp") || lower.contains("lưu") {
            btn.backgroundColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0) // Emerald Green #10B981
            btn.setTitleColor(.white, for: .normal)
        } else if lower.contains("hủy") || lower.contains("thoát") || lower.contains("quay lại") || lower.contains("back") {
            btn.backgroundColor = UIColor(red: 0.22, green: 0.27, blue: 0.35, alpha: 1.0) // Slate Gray #374151
            btn.setTitleColor(.white, for: .normal)
        } else if lower.contains("menu") {
            btn.backgroundColor = UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0) // Indigo #4F46E5
            btn.setTitleColor(.white, for: .normal)
        } else {
            btn.backgroundColor = UIColor(red: 0.18, green: 0.24, blue: 0.32, alpha: 1.0)
            btn.setTitleColor(.white, for: .normal)
        }
        btn.tag = tag
        if tag >= 0 {
            btn.addTarget(self, action: #selector(commandTapped(_:)), for: .touchUpInside)
        }
        return btn
    }

    @objc private func showFormMenu(_ sender: UIButton) {
        syncAllTextFields()
        guard let parentVC = self.topMostPresentedViewController else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for cmd in commands {
            alert.addAction(UIAlertAction(title: cmd.label, style: .default) { [weak self] _ in
                self?.endEditing(true)
                self?.syncAllTextFields()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmd.id)
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        parentVC.present(alert, animated: true)
    }

    private func addStringItem(label: String, text: String) {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 0.95)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.22, green: 0.28, blue: 0.38, alpha: 1.0).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6
        container.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        container.isLayoutMarginsRelativeArrangement = true
        container.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(container)

        if !label.isEmpty {
            let labelView = UILabel()
            labelView.text = label
            labelView.font = .boldSystemFont(ofSize: 14)
            labelView.textColor = UIColor(red: 0.38, green: 0.76, blue: 1.0, alpha: 1.0)
            container.addArrangedSubview(labelView)
        }

        if !text.isEmpty {
            let textView = UILabel()
            textView.text = text
            textView.font = .systemFont(ofSize: 15)
            textView.textColor = UIColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1.0)
            textView.numberOfLines = 0
            container.addArrangedSubview(textView)
        }

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: card.topAnchor),
            container.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        stackView.addArrangedSubview(card)
    }

    private func addTextField(label: String, text: String, index: Int) {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 0.95)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.22, green: 0.28, blue: 0.38, alpha: 1.0).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6
        container.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 12, right: 14)
        container.isLayoutMarginsRelativeArrangement = true
        container.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(container)

        if !label.isEmpty {
            let labelView = UILabel()
            labelView.text = label
            labelView.font = .boldSystemFont(ofSize: 14)
            labelView.textColor = UIColor(red: 0.38, green: 0.76, blue: 1.0, alpha: 1.0)
            container.addArrangedSubview(labelView)
        }

        let tf = UITextField()
        tf.tag = index
        tf.text = text
        tf.placeholder = "Nhập chữ"
        let constraints = j2me_ui_get_form_item_param2(Int32(index))
        tf.isEnabled = (constraints & 0x20000) == 0
        tf.isSecureTextEntry = (constraints & 0x10000) != 0
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        switch constraints & 0xFFFF {
        case 1: tf.keyboardType = .emailAddress
        case 2: tf.keyboardType = .numbersAndPunctuation
        case 3: tf.keyboardType = .phonePad
        case 4: tf.keyboardType = .URL
        case 5: tf.keyboardType = .decimalPad
        default: break
        }
        tf.borderStyle = .none
        tf.font = .systemFont(ofSize: 16)
        tf.textColor = .white
        tf.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
        tf.layer.cornerRadius = 8
        tf.layer.borderWidth = 1
        tf.layer.borderColor = UIColor(red: 0.24, green: 0.30, blue: 0.40, alpha: 1.0).cgColor
        tf.returnKeyType = .done
        tf.delegate = self
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 42))
        tf.leftView = paddingView
        tf.leftViewMode = .always

        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        toolbar.barTintColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0)
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneBtn = UIBarButtonItem(title: "✓ Xong", style: .done, target: self, action: #selector(dismissKeyboard))
        doneBtn.tintColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0)
        doneBtn.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 18, weight: .bold)], for: .normal)
        toolbar.items = [flex, doneBtn]
        tf.inputAccessoryView = toolbar

        tf.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
        textFields[index] = tf
        container.addArrangedSubview(tf)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: card.topAnchor),
            container.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        stackView.addArrangedSubview(card)
    }

    private func addChoiceGroup(label: String, text: String, index: Int) {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 0.95)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.22, green: 0.28, blue: 0.38, alpha: 1.0).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10
        container.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        container.isLayoutMarginsRelativeArrangement = true
        container.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(container)

        if !label.isEmpty {
            let labelView = UILabel()
            labelView.text = label
            labelView.font = .boldSystemFont(ofSize: 15)
            labelView.textColor = UIColor(red: 0.38, green: 0.76, blue: 1.0, alpha: 1.0)
            labelView.numberOfLines = 0
            container.addArrangedSubview(labelView)
        }

        // Parse format: "selectedIndex\nopt1\topt2\nsel0,sel1"
        let parts = text.components(separatedBy: "\n")
        let selectedIdx = Int(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        let options = parts.count > 1 && !parts[1].isEmpty ? parts[1].components(separatedBy: "\t") : []
        var flags: [Bool] = []
        if parts.count > 2 {
            flags = parts[2].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "1" }
        }

        let choiceType = j2me_ui_get_form_item_param2(Int32(index)) // 1=EXCLUSIVE, 2=MULTIPLE, 4=POPUP
        let isMultiple = (choiceType == 2)

        for (optIdx, optTitle) in options.enumerated() {
            let isSelected = isMultiple ? (optIdx < flags.count ? flags[optIdx] : false) : (optIdx == selectedIdx)

            let rowBtn = UIButton(type: .custom)
            rowBtn.tag = index * 1000 + optIdx
            rowBtn.translatesAutoresizingMaskIntoConstraints = false
            rowBtn.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
            rowBtn.contentHorizontalAlignment = .leading

            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 12
            rowStack.alignment = .center
            rowStack.isUserInteractionEnabled = false
            rowStack.translatesAutoresizingMaskIntoConstraints = false

            // Indicator (Radio circle or Checkbox)
            let indicator = makeIndicatorView(isMultiple: isMultiple, isSelected: isSelected)
            rowStack.addArrangedSubview(indicator)

            // Text label
            let optLabel = UILabel()
            optLabel.text = optTitle
            optLabel.font = .systemFont(ofSize: 16, weight: isSelected ? .medium : .regular)
            optLabel.textColor = isSelected ? .white : UIColor(red: 0.75, green: 0.80, blue: 0.88, alpha: 1.0)
            optLabel.numberOfLines = 0
            rowStack.addArrangedSubview(optLabel)

            rowBtn.addSubview(rowStack)
            NSLayoutConstraint.activate([
                rowStack.topAnchor.constraint(equalTo: rowBtn.topAnchor, constant: 4),
                rowStack.bottomAnchor.constraint(equalTo: rowBtn.bottomAnchor, constant: -4),
                rowStack.leadingAnchor.constraint(equalTo: rowBtn.leadingAnchor, constant: 4),
                rowStack.trailingAnchor.constraint(equalTo: rowBtn.trailingAnchor, constant: -4),
            ])

            rowBtn.addTarget(self, action: #selector(choiceRowTapped(_:)), for: .touchUpInside)
            choiceRows[rowBtn.tag] = (stack: rowStack, isMultiple: isMultiple, label: optLabel)
            container.addArrangedSubview(rowBtn)
        }

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: card.topAnchor),
            container.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        stackView.addArrangedSubview(card)
    }

    private func makeIndicatorView(isMultiple: Bool, isSelected: Bool) -> UIView {
        let size: CGFloat = 22
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: size).isActive = true
        v.heightAnchor.constraint(equalToConstant: size).isActive = true

        if isMultiple {
            // Checkbox: rounded rectangle
            v.layer.cornerRadius = 6
            if isSelected {
                v.backgroundColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0)
                v.layer.borderWidth = 0
                let check = UILabel()
                check.text = "✓"
                check.textColor = .white
                check.font = .systemFont(ofSize: 15, weight: .bold)
                check.textAlignment = .center
                check.translatesAutoresizingMaskIntoConstraints = false
                v.addSubview(check)
                NSLayoutConstraint.activate([
                    check.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                    check.centerYAnchor.constraint(equalTo: v.centerYAnchor)
                ])
            } else {
                v.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
                v.layer.borderWidth = 1.8
                v.layer.borderColor = UIColor(red: 0.30, green: 0.38, blue: 0.50, alpha: 1.0).cgColor
            }
        } else {
            // Radio button: circular ring with inner dot
            v.layer.cornerRadius = size / 2
            v.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
            if isSelected {
                v.layer.borderWidth = 2.2
                v.layer.borderColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0).cgColor
                let dot = UIView()
                dot.backgroundColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0)
                dot.layer.cornerRadius = 5
                dot.translatesAutoresizingMaskIntoConstraints = false
                v.addSubview(dot)
                NSLayoutConstraint.activate([
                    dot.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                    dot.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                    dot.widthAnchor.constraint(equalToConstant: 10),
                    dot.heightAnchor.constraint(equalToConstant: 10),
                ])
            } else {
                v.layer.borderWidth = 1.8
                v.layer.borderColor = UIColor(red: 0.30, green: 0.38, blue: 0.50, alpha: 1.0).cgColor
            }
        }
        return v
    }

    func syncAllTextFields() {
        for (index, tf) in textFields {
            let text = tf.text ?? ""
            text.withCString { cstr in
                j2me_ui_set_form_item_text(Int32(index), cstr)
            }
        }
    }

    private func updateRowIndicator(tag: Int, isSelected: Bool) {
        guard let entry = choiceRows[tag] else { return }
        if let oldIndicator = entry.stack.arrangedSubviews.first {
            oldIndicator.removeFromSuperview()
        }
        let newIndicator = makeIndicatorView(isMultiple: entry.isMultiple, isSelected: isSelected)
        entry.stack.insertArrangedSubview(newIndicator, at: 0)
        entry.label.font = .systemFont(ofSize: 16, weight: isSelected ? .medium : .regular)
        entry.label.textColor = isSelected ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0) : UIColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1.0)
    }

    @objc private func choiceRowTapped(_ sender: UIButton) {
        let feedback = UISelectionFeedbackGenerator()
        feedback.selectionChanged()

        // 1. Immediately commit all active textfields before touching choices
        syncAllTextFields()

        let itemIndex = sender.tag / 1000
        let optIndex = sender.tag % 1000
        let raw = String(cString: j2me_ui_get_form_item_text(Int32(itemIndex)))
        var parts = raw.components(separatedBy: "\n")
        while parts.count < 3 { parts.append("") }

        let choiceType = j2me_ui_get_form_item_param2(Int32(itemIndex))
        let options = parts.count > 1 ? parts[1].components(separatedBy: "\t") : []
        var flags = parts.count > 2 ? parts[2].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "1" } : []
        while flags.count < options.count { flags.append(false) }

        if choiceType == 2 {
            // MULTIPLE: toggle flag
            if optIndex < flags.count {
                flags[optIndex].toggle()
            }
            parts[2] = flags.map { $0 ? "1" : "0" }.joined(separator: ",")
            let updated = parts.joined(separator: "\n")
            updated.withCString { cstr in
                j2me_ui_set_form_item_text(Int32(itemIndex), cstr)
            }
            let isSel = (optIndex < flags.count) ? flags[optIndex] : false
            updateRowIndicator(tag: sender.tag, isSelected: isSel)
        } else {
            // EXCLUSIVE / POPUP: single select
            parts[0] = "\(optIndex)"
            for i in 0..<flags.count {
                flags[i] = (i == optIndex)
            }
            parts[2] = flags.map { $0 ? "1" : "0" }.joined(separator: ",")
            let updated = parts.joined(separator: "\n")
            updated.withCString { cstr in
                j2me_ui_set_form_item_text(Int32(itemIndex), cstr)
            }
            for i in 0..<options.count {
                let rowTag = itemIndex * 1000 + i
                updateRowIndicator(tag: rowTag, isSelected: (i == optIndex))
            }
        }
        j2me_input_post_key(Int32(J2ME_UI_FORM_CHANGED), Int32(itemIndex))
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        let text = textField.text ?? ""
        text.withCString { cstr in
            j2me_ui_set_form_item_text(Int32(textField.tag), cstr)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        text.withCString { cstr in
            j2me_ui_set_form_item_text(Int32(textField.tag), cstr)
        }
        textField.resignFirstResponder()
        return true
    }

    @objc func dismissKeyboard() {
        endEditing(true)
        syncAllTextFields()
    }

    @objc private func commandTapped(_ sender: UIButton) {
        endEditing(true)
        syncAllTextFields()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let cmdId = Int32(sender.tag)
        j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmdId)
    }

    @objc private func textFieldChanged(_ sender: UITextField) {
        let text = sender.text ?? ""
        text.withCString { cstr in
            j2me_ui_set_form_item_text(Int32(sender.tag), cstr)
        }
    }
}

// ============================================================
// MARK: - J2MEListView (AngelChip Menu matching Screenshot 2 & 3)
// ============================================================

class J2MEListView: UIView, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [(title: String, isRunning: Bool)] = []
    private var selectedRow: Int = 0
    private let bottomButtonBar = UIStackView()

    private var commands: [(label: String, id: Int32, type: Int32)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        overrideUserInterfaceStyle = .light
        backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 0.90) // Translucent dark overlay

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 0.95)
        tableView.separatorColor = UIColor(red: 0.20, green: 0.25, blue: 0.34, alpha: 1.0)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        // Long press on list item opens context menu
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleTableLongPress(_:)))
        tableView.addGestureRecognizer(longPress)
        addSubview(tableView)

        // Bottom Softkeys
        bottomButtonBar.axis = .horizontal
        bottomButtonBar.distribution = .equalSpacing
        bottomButtonBar.alignment = .center
        bottomButtonBar.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 0.95)
        bottomButtonBar.layoutMargins = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        bottomButtonBar.isLayoutMarginsRelativeArrangement = true
        bottomButtonBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomButtonBar)

        let separator = UIView()
        separator.backgroundColor = UIColor(red: 0.20, green: 0.25, blue: 0.34, alpha: 1.0)
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomButtonBar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            bottomButtonBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomButtonBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomButtonBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            bottomButtonBar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    func buildFromNativeData() {
        items.removeAll()
        commands.removeAll()
        let count = j2me_ui_get_list_item_count()
        for i in 0..<count {
            let title = String(cString: j2me_ui_get_list_item(Int32(i)))
            let isRunning = j2me_ui_is_list_item_running(Int32(i)) != 0
            items.append((title: title, isRunning: isRunning))
        }
        selectedRow = 0
        tableView.reloadData()

        let cmdCount = j2me_ui_get_command_count()
        for i in 0..<cmdCount {
            let cmdLabel = String(cString: j2me_ui_get_command_label(Int32(i)))
            let cmdId = j2me_ui_get_command_id(Int32(i))
            let cmdType = j2me_ui_get_command_type(Int32(i))
            commands.append((label: cmdLabel, id: cmdId, type: cmdType))
        }

        // Rebuild bottom red buttons (MENU / THOÁT)
        bottomButtonBar.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if commands.isEmpty {
            let leftBtn = makeRedButton(title: "MENU", tag: -1)
            let rightBtn = makeRedButton(title: "THOÁT", tag: 1)
            bottomButtonBar.addArrangedSubview(leftBtn)
            bottomButtonBar.addArrangedSubview(rightBtn)
        } else if commands.count <= 2 {
            let leftBtn = makeRedButton(title: commands[0].label.uppercased(), tag: Int(commands[0].id))
            bottomButtonBar.addArrangedSubview(leftBtn)
            if commands.count == 2 {
                let rightBtn = makeRedButton(title: commands[1].label.uppercased(), tag: Int(commands[1].id))
                bottomButtonBar.addArrangedSubview(rightBtn)
            }
        } else {
            // > 2 commands: Left button is "MENU" which opens popup menu (Screenshot 2), Right is "THOÁT"
            let menuBtn = makeRedButton(title: "MENU", tag: -1)
            menuBtn.addTarget(self, action: #selector(menuButtonTapped(_:)), for: .touchUpInside)
            bottomButtonBar.addArrangedSubview(menuBtn)

            let exitCmd = commands.first {
                let l = $0.label.lowercased()
                return $0.type == 7 || $0.type == 2 || l.contains("thoát") || l.contains("back") || l.contains("quay lại")
            } ?? commands.last!
            let exitBtn = makeRedButton(title: exitCmd.label.uppercased(), tag: Int(exitCmd.id))
            bottomButtonBar.addArrangedSubview(exitBtn)
        }
    }

    private func makeRedButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        btn.layer.cornerRadius = 8
        let lower = title.lowercased()
        if lower.contains("ok") || lower.contains("chọn") || lower.contains("chạy") {
            btn.backgroundColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0) // Emerald Green #10B981
            btn.setTitleColor(.white, for: .normal)
        } else if lower.contains("thoát") || lower.contains("hủy") || lower.contains("back") || lower.contains("quay lại") {
            btn.backgroundColor = UIColor(red: 0.22, green: 0.27, blue: 0.35, alpha: 1.0) // Slate Gray #374151
            btn.setTitleColor(.white, for: .normal)
        } else if lower.contains("menu") {
            btn.backgroundColor = UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0) // Indigo #4F46E5
            btn.setTitleColor(.white, for: .normal)
        } else {
            btn.backgroundColor = UIColor(red: 0.18, green: 0.24, blue: 0.32, alpha: 1.0)
            btn.setTitleColor(.white, for: .normal)
        }
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        btn.tag = tag
        if tag >= 0 {
            btn.addTarget(self, action: #selector(commandTapped(_:)), for: .touchUpInside)
        }
        return btn
    }

    @objc private func menuButtonTapped(_ sender: UIButton) {
        showListPopupMenu(sourceView: sender)
    }

    @objc private func handleTableLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        if let indexPath = tableView.indexPathForRow(at: point) {
            selectedRow = indexPath.row
            tableView.reloadData()
            j2me_input_post_key(Int32(J2ME_UI_LIST_SET_INDEX), Int32(indexPath.row)) // select without triggering selectCommand
            let cell = tableView.cellForRow(at: indexPath)
            showListPopupMenu(sourceView: cell ?? tableView)
        }
    }

    private func showListPopupMenu(sourceView: UIView) {
        guard let parentVC = self.topMostPresentedViewController else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // Show commands matching Screenshot 2: "Chạy ứng dụng", "Dừng ứng dụng", "Cài đặt cơ bản", etc.
        let displayCmds = commands.filter {
            let l = $0.label.lowercased()
            return !l.contains("thoát")
        }

        let cmdList = displayCmds.isEmpty ? commands : displayCmds
        for cmd in cmdList {
            alert.addAction(UIAlertAction(title: cmd.label, style: .default) { [weak self] _ in
                guard let self = self else { return }
                // Set selected index first, then fire the chosen command
                j2me_input_post_key(Int32(J2ME_UI_LIST_SET_INDEX), Int32(self.selectedRow))
                j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmd.id)
            })
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        parentVC.present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DecadeListCell") ??
                   UITableViewCell(style: .default, reuseIdentifier: "DecadeListCell")

        let isSelected = indexPath.row == selectedRow
        cell.backgroundColor = isSelected ? UIColor(red: 0.18, green: 0.24, blue: 0.34, alpha: 1.0) : UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0)

        var config = cell.defaultContentConfiguration()
        let item = items[indexPath.row]
        if item.isRunning {
            config.image = UIImage(systemName: "play.fill")
            config.imageProperties.tintColor = UIColor(red: 0.06, green: 0.72, blue: 0.45, alpha: 1.0)
        } else {
            config.image = nil
        }
        config.text = item.title
        config.textProperties.font = .systemFont(ofSize: 16, weight: .medium)
        config.textProperties.color = .white

        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedRow = indexPath.row
        tableView.reloadData()
        // Set selected index and trigger select action to run the game slot
        j2me_input_post_key(Int32(J2ME_UI_LIST_SET_INDEX), Int32(indexPath.row))
        j2me_input_post_key(Int32(J2ME_UI_LIST_SELECT), Int32(indexPath.row))
    }

    @objc private func commandTapped(_ sender: UIButton) {
        j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), Int32(sender.tag))
    }
}
