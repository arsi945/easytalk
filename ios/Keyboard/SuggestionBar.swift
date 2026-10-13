import UIKit
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

/// The row of up to three word suggestions above the letters. Like the system keyboard, the best
/// suggestion is in the middle. A tap only reports the choice; the keyboard inserts it.
final class SuggestionBar: UIStackView {
    var onPick: ((WordSuggestion) -> Void)?
    private var buttons: [UIButton] = []
    private var items: [WordSuggestion] = []
    /// Visual slot → index in `items`: the best one goes in the centre.
    private let slotOrder = [1, 0, 2]

    init() {
        super.init(frame: .zero)
        axis = .horizontal; distribution = .fillEqually; spacing = 1
        accessibilityLabel = "Подсказки слов"
        for slot in 0..<3 {
            let button = UIButton(type: .system)
            button.tag = slot
            button.titleLabel?.lineBreakMode = .byTruncatingMiddle
            button.titleLabel?.adjustsFontSizeToFitWidth = true; button.titleLabel?.minimumScaleFactor = 0.75
            button.setTitleColor(EasyTalkTheme.ink, for: .normal)
            button.backgroundColor = EasyTalkTheme.canvas
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            buttons.append(button); addArrangedSubview(button)
        }
        backgroundColor = EasyTalkTheme.muted
        show([])
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ suggestions: [WordSuggestion]) {
        items = Array(suggestions.prefix(3))
        for (slot, button) in buttons.enumerated() {
            let index = slotOrder[slot]
            let item = index < items.count ? items[index] : nil
            let quoted = item?.kind == .replacement ? "«\(item!.text)»" : item?.text
            button.setTitle(quoted, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: index == 0 ? .semibold : .regular)
            button.isEnabled = item != nil
            button.isAccessibilityElement = item != nil
            button.accessibilityLabel = item.map { "Подсказка: \($0.text)" }
        }
    }

    @objc private func tapped(_ button: UIButton) {
        let index = slotOrder[button.tag]
        guard index < items.count else { return }
        onPick?(items[index])
    }
}
