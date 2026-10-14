import UIKit

/// Building blocks of the app's settings screens: a scrolling column, section titles, cards, rows and buttons.
enum SettingsUI {
    /// Puts `stack` in `scroll`, which ends where any keyboard begins, so nothing hides under it.
    static func layout(_ scroll: UIScrollView, _ stack: UIStackView, in view: UIView) {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular,
                      color: UIColor = EasyTalkTheme.ink) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    /// A small caption above a card, like the grouped lists of iOS.
    static func sectionTitle(_ text: String) -> UIView {
        let title = label(text.uppercased(), size: 13, weight: .semibold, color: EasyTalkTheme.secondary)
        title.accessibilityTraits.insert(.header)
        let wrapper = UIStackView(arrangedSubviews: [title])
        wrapper.isLayoutMarginsRelativeArrangement = true
        wrapper.layoutMargins = UIEdgeInsets(top: 10, left: 4, bottom: 0, right: 4)
        return wrapper
    }

    static func card() -> WarmCard {
        let card = WarmCard(padding: 14)
        card.spacing = 6
        return card
    }

    /// The main action of a screen.
    static func primaryButton(_ title: String, _ target: Any, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        EasyTalkTheme.style(button, primary: true, blue: true)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        height(button, 48)
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }

    static func secondaryButton(_ title: String, _ target: Any, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        EasyTalkTheme.style(button)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        height(button, 44)
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }

    /// A text action with the shared dotted underline; `danger` for deleting.
    static func link(_ title: String, _ target: Any, _ action: Selector, danger: Bool = false) -> UIButton {
        let button = TextLinkButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        let color = danger ? UIColor.systemRed : EasyTalkTheme.link
        button.setTitleColor(color, for: .normal)
        button.setTitleColor(color, for: .highlighted)
        button.contentHorizontalAlignment = .left
        button.showsLinkUnderline = true
        height(button, 40)
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }

    /// Title with an optional explanation on the left, a switch on the right.
    static func switchRow(_ title: String, detail: String?, control: UISwitch) -> UIView {
        control.onTintColor = EasyTalkTheme.gold
        control.accessibilityLabel = title
        control.accessibilityHint = detail
        let texts = UIStackView(arrangedSubviews: [label(title, size: 17, weight: .medium)])
        texts.axis = .vertical
        texts.spacing = 2
        if let detail { texts.addArrangedSubview(label(detail, size: 14, color: EasyTalkTheme.secondary)) }
        let row = UIStackView(arrangedSubviews: [texts, control])
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        return row
    }

    /// A text field in the app's colours, with «Готово» above the keyboard.
    static func field(_ placeholder: String, _ target: Any, done: Selector) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 17)
        field.backgroundColor = EasyTalkTheme.paper
        field.textColor = EasyTalkTheme.ink
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.inputAccessoryView = doneBar(target, done)
        height(field, 44)
        return field
    }

    /// The standard bar above any keyboard with «Готово», which hides it.
    static func doneBar(_ target: Any, _ action: Selector) -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let done = UIBarButtonItem(title: "Готово", style: .done, target: target, action: action)
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        bar.sizeToFit()
        return bar
    }

    static func height(_ view: UIView, _ value: CGFloat) {
        let constraint = view.heightAnchor.constraint(equalToConstant: value)
        constraint.priority = .init(999)
        constraint.isActive = true
    }
}

/// A tappable settings row: title, optional explanation under it, current value and a chevron on the right.
final class SettingsRow: UIControl {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let valueLabel = UILabel()
    private let mark = UIImageView()

    init(title: String, detail: String? = nil, value: String? = nil) {
        super.init(frame: .zero)
        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        titleLabel.textColor = EasyTalkTheme.ink
        titleLabel.numberOfLines = 0
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = EasyTalkTheme.secondary
        detailLabel.numberOfLines = 0
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textColor = EasyTalkTheme.secondary
        valueLabel.numberOfLines = 2
        valueLabel.textAlignment = .right
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        mark.tintColor = EasyTalkTheme.secondary
        mark.contentMode = .center
        mark.setContentHuggingPriority(.required, for: .horizontal)
        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = 2
        texts.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [texts, valueLabel, mark])
        row.alignment = .center
        row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        isAccessibilityElement = true
        updateMark()
        update(title: title, detail: detail, value: value)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, detail: String? = nil, value: String? = nil) {
        titleLabel.text = title
        detailLabel.text = detail
        detailLabel.isHidden = detail == nil
        valueLabel.text = value
        valueLabel.isHidden = value == nil
        accessibilityLabel = [title, value, detail].compactMap { $0 }.joined(separator: ", ")
    }

    /// A filled check mark instead of the chevron: the chosen one of several.
    var isChosen = false {
        didSet { updateMark() }
    }
    private func updateMark() {
        mark.image = UIImage(systemName: isChosen ? "checkmark.circle.fill" : "chevron.right")
        mark.tintColor = isChosen ? EasyTalkTheme.green : EasyTalkTheme.secondary
        accessibilityTraits = isChosen ? [.button, .selected] : .button
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}
