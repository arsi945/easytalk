import UIKit

/// «История и контекст»: messages collected by the keyboard, «Скопировать контекст» for any AI chat,
/// and «Вставить слова» from the AI answer into the dictionary.
final class HistoryViewController: UIViewController {
    private let history = InputHistoryStore(defaults: SharedStorage.defaults())
    private let preferences = KeyboardPreferences(defaults: SharedStorage.defaults())
    private let periods = HistoryPeriod.allCases
    private lazy var periodControl = UISegmentedControl(items: periods.map(\.title))
    private let summary = UILabel()
    private let message = UILabel()
    private let list = UIStackView()
    private let copyButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "История и контекст"; view.backgroundColor = EasyTalkTheme.canvas
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        stack.addArrangedSubview(label("Клавиатура сохраняет отправленные сообщения на этом iPhone (90 дней). Скопируй их вместе с готовым заданием и вставь в чат любого ИИ — он разберёт твои типичные ошибки.", size: 16))
        periodControl.selectedSegmentIndex = periods.firstIndex(of: preferences.contextPeriod) ?? 0
        periodControl.accessibilityLabel = "Период"
        periodControl.addTarget(self, action: #selector(render), for: .valueChanged)
        periodControl.heightAnchor.constraint(equalToConstant: 36).isActive = true
        stack.addArrangedSubview(periodControl)
        summary.font = .systemFont(ofSize: 17, weight: .medium); summary.textColor = EasyTalkTheme.ink; summary.numberOfLines = 0
        stack.addArrangedSubview(summary)

        copyButton.setTitle("Скопировать контекст", for: .normal)
        EasyTalkTheme.style(copyButton, primary: true, blue: true)
        copyButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        copyButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        copyButton.addTarget(self, action: #selector(copyContext), for: .touchUpInside)
        stack.addArrangedSubview(copyButton)

        let paste = UIButton(type: .system); paste.setTitle("Вставить слова из ответа ИИ", for: .normal)
        EasyTalkTheme.style(paste)
        paste.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        paste.heightAnchor.constraint(equalToConstant: 44).isActive = true
        paste.addTarget(self, action: #selector(importWords), for: .touchUpInside)
        stack.addArrangedSubview(paste)
        stack.addArrangedSubview(label("В конце ответа ИИ выводит список слов. Скопируй ответ целиком и нажми «Вставить слова» — они попадут в словарь и карточки.", size: 14, color: EasyTalkTheme.secondary))

        message.font = .systemFont(ofSize: 16); message.textColor = EasyTalkTheme.ink; message.numberOfLines = 0
        stack.addArrangedSubview(message)

        stack.addArrangedSubview(label("Сообщения за период", size: 19, weight: .semibold))
        list.axis = .vertical; list.spacing = 10
        stack.addArrangedSubview(list)

        let clear = UIButton(type: .system); clear.setTitle("Очистить историю", for: .normal)
        clear.setTitleColor(.systemRed, for: .normal); clear.titleLabel?.font = .systemFont(ofSize: 16)
        clear.heightAnchor.constraint(equalToConstant: 44).isActive = true
        clear.addTarget(self, action: #selector(confirmClear), for: .touchUpInside)
        stack.addArrangedSubview(clear)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        history.reload(); render()
    }

    private var period: HistoryPeriod { periods.indices.contains(periodControl.selectedSegmentIndex) ? periods[periodControl.selectedSegmentIndex] : .today }

    @objc private func render() {
        preferences.contextPeriod = period
        let entries = history.entries(in: period)
        summary.text = entries.isEmpty ? "За этот период сообщений нет." : "Будет скопировано: \(entries.count) — \(period.phrase)."
        // Words saved without a translation are worth copying even without messages.
        let untranslated = LearningStore(defaults: SharedStorage.defaults()).untranslatedTerms.count
        if untranslated > 0 { summary.text! += " Слов без перевода: \(min(untranslated, ContextExport.maxUntranslated))." }
        let canCopy = !entries.isEmpty || untranslated > 0
        copyButton.isEnabled = canCopy
        copyButton.alpha = canCopy ? 1 : 0.5
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "d MMM, HH:mm"
        // Newest first on screen; the copied text keeps the order of writing.
        for entry in entries.reversed().prefix(100) {
            let card = WarmCard(padding: 12)
            card.addArrangedSubview(label(formatter.string(from: entry.date), size: 13, color: EasyTalkTheme.secondary))
            card.addArrangedSubview(label(entry.text, size: 16))
            if let corrected = entry.corrected { card.addArrangedSubview(label("→ " + corrected, size: 14, color: EasyTalkTheme.secondary)) }
            list.addArrangedSubview(card)
        }
        if entries.count > 100 { list.addArrangedSubview(label("…и ещё \(entries.count - 100) более старых.", size: 14, color: EasyTalkTheme.secondary)) }
        if entries.isEmpty { list.addArrangedSubview(label("Пиши в мессенджерах клавиатурой easytalk — отправленные сообщения появятся здесь. Нужен «Полный доступ».", size: 15, color: EasyTalkTheme.secondary)) }
    }

    @objc private func copyContext() {
        let entries = history.entries(in: period)
        let untranslated = LearningStore(defaults: SharedStorage.defaults()).untranslatedTerms
        guard !entries.isEmpty || !untranslated.isEmpty else { return }
        let text = ContextExport.text(entries: entries, period: period, untranslated: untranslated)
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        var copied = "Скопировано сообщений: \(entries.count)"
        if !untranslated.isEmpty { copied += ", слов без перевода: \(min(untranslated.count, ContextExport.maxUntranslated))" }
        message.text = copied + ". Открой чат любого ИИ и вставь."
        UIAccessibility.post(notification: .announcement, argument: message.text)
    }

    @objc private func importWords() {
        let words = WordImport.parse(UIPasteboard.general.string ?? "")
        guard !words.isEmpty else {
            message.text = "В буфере нет списка слов. Скопируй ответ ИИ целиком — список начинается строкой \(WordImport.startMarker)."; return
        }
        let store = LearningStore(defaults: SharedStorage.defaults())
        let fresh = words.filter { store.accepts($0) }
        guard !fresh.isEmpty else { message.text = "Все \(words.count) слов уже есть в словаре."; return }
        let preview = fresh.prefix(8).map { "\($0.term) — \($0.meaning)" }.joined(separator: "\n") + (fresh.count > 8 ? "\n…и ещё \(fresh.count - 8)" : "")
        let alert = UIAlertController(title: "Добавить в словарь: \(fresh.count)", message: preview, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak self] _ in
            let added = store.importWords(fresh)
            let skipped = words.count - added
            self?.message.text = "Добавлено в словарь: \(added)." + (skipped > 0 ? " Уже были: \(skipped)." : "")
        })
        present(alert, animated: true)
    }

    @objc private func confirmClear() {
        let alert = UIAlertController(title: "Очистить историю?", message: "Все собранные сообщения будут удалены с этого iPhone. Словарь не изменится.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Очистить", style: .destructive) { [weak self] _ in
            self?.history.clear(); self?.message.text = "История очищена."; self?.render()
        })
        present(alert, animated: true)
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = EasyTalkTheme.ink) -> UILabel {
        let label = UILabel(); label.text = text; label.numberOfLines = 0
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
        return label
    }
}
