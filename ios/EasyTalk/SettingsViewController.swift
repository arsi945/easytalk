import UIKit

/// «Настройки»: keyboard status, the AI connection, translation and keyboard options, history, about.
/// Keyboard options are the same as in the keyboard's ⚙; the keyboard reads them when it has Full Access.
final class SettingsViewController: UIViewController {
    private let preferences = KeyboardPreferences(defaults: SharedStorage.defaults())
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let keyboardStatus = SettingsUI.label("", size: 16)
    private let systemSettings = UIButton(type: .system)
    private let aiRow = SettingsRow(title: "Подключение AI")
    private let speakerGender = UISegmentedControl(items: SpeakerGender.allCases.map { $0.title })
    private let translateScope = UISegmentedControl(items: TranslateScope.allCases.map { $0.title })
    private let suggestionsSwitch = UISwitch()
    private let tipsSwitch = UISwitch()
    private let hapticsSwitch = UISwitch()
    private let rewardsSwitch = UISwitch()
    private let secondSkillSwitch = UISwitch()
    private let historySwitch = UISwitch()
    private let message = SettingsUI.label("", size: 15, color: EasyTalkTheme.secondary)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Настройки"
        view.backgroundColor = EasyTalkTheme.canvas
        SettingsUI.layout(scroll, stack, in: view)
        addKeyboardSection()
        addAISection()
        addTranslationSection()
        addKeyboardOptions()
        addHistorySection()
        addAboutSection()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    // MARK: Sections

    private func addKeyboardSection() {
        stack.addArrangedSubview(SettingsUI.sectionTitle("Клавиатура"))
        let card = SettingsUI.card()
        card.addArrangedSubview(keyboardStatus)
        systemSettings.setTitle("Открыть настройки iPhone", for: .normal)
        EasyTalkTheme.style(systemSettings, primary: true, blue: true)
        systemSettings.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        SettingsUI.height(systemSettings, 44)
        systemSettings.addTarget(self, action: #selector(openSystemSettings), for: .touchUpInside)
        card.addArrangedSubview(systemSettings)
        let guide = SettingsRow(title: "Как пользоваться клавиатурой", detail: "Перевод, словарь, курсор, «Скопировать контекст»")
        guide.addTarget(self, action: #selector(openGuide), for: .touchUpInside)
        card.addArrangedSubview(guide)
        stack.addArrangedSubview(card)
    }

    private func addAISection() {
        stack.addArrangedSubview(SettingsUI.sectionTitle("Перевод через AI"))
        let card = SettingsUI.card()
        aiRow.addTarget(self, action: #selector(openConnection), for: .touchUpInside)
        card.addArrangedSubview(aiRow)
        let note = "Нужен для кнопки «Перевести» и перевода слов в словаре. Всё остальное работает без ключа."
        card.addArrangedSubview(SettingsUI.label(note, size: 14, color: EasyTalkTheme.secondary))
        stack.addArrangedSubview(card)
    }

    private func addTranslationSection() {
        stack.addArrangedSubview(SettingsUI.sectionTitle("Перевод"))
        let card = SettingsUI.card()
        card.addArrangedSubview(SettingsUI.label("Пол для перевода", size: 17, weight: .medium))
        speakerGender.accessibilityLabel = "Пол говорящего для перевода"
        speakerGender.addTarget(self, action: #selector(changeSpeakerGender), for: .valueChanged)
        SettingsUI.height(speakerGender, 36)
        card.addArrangedSubview(speakerGender)
        let genderNote = "Для фраз от твоего лица: «я сделал» или «я сделала». Других людей и цитаты не меняет."
        card.addArrangedSubview(SettingsUI.label(genderNote, size: 14, color: EasyTalkTheme.secondary))
        card.setCustomSpacing(14, after: card.arrangedSubviews.last!)
        card.addArrangedSubview(SettingsUI.label("Что переводить", size: 17, weight: .medium))
        translateScope.accessibilityLabel = "Что переводить кнопкой «Перевести»"
        translateScope.addTarget(self, action: #selector(changeTranslateScope), for: .valueChanged)
        SettingsUI.height(translateScope, 36)
        card.addArrangedSubview(translateScope)
        let scopeNote = "Без выделения «Перевести» берёт всё сообщение, абзац или предложение у курсора. "
            + "Выделенный текст всегда переводится как есть."
        card.addArrangedSubview(SettingsUI.label(scopeNote, size: 14, color: EasyTalkTheme.secondary))
        stack.addArrangedSubview(card)
    }

    private func addKeyboardOptions() {
        stack.addArrangedSubview(SettingsUI.sectionTitle("На клавиатуре"))
        let card = SettingsUI.card()
        let rows: [(String, String?, UISwitch, Selector)] = [
            ("Подсказки слов", "Ряд над клавишами; появляется, только когда есть что подсказать",
             suggestionsSwitch, #selector(toggleSuggestions)),
            ("Советы", "Короткая подсказка о клавиатуре при её появлении",
             tipsSwitch, #selector(toggleTips)),
            ("Вибрация клавиш", nil,
             hapticsSwitch, #selector(toggleHaptics)),
            ("Поощрения", "Поздравление за английский без ошибок",
             rewardsSwitch, #selector(toggleRewards)),
            ("Второй навык", "Карточки со словами в «Разборе»",
             secondSkillSwitch, #selector(toggleSecondSkill)),
        ]
        for (title, detail, control, action) in rows {
            control.addTarget(self, action: action, for: .valueChanged)
            card.addArrangedSubview(SettingsUI.switchRow(title, detail: detail, control: control))
        }
        card.addArrangedSubview(SettingsUI.link("Показать советы снова", self, #selector(showTipsAgain)))
        card.addArrangedSubview(message)
        stack.addArrangedSubview(card)
        let note = "Эти настройки общие с ⚙ на клавиатуре. Клавиатура видит их, когда у неё включён «Полный доступ». "
            + "Ряд символов настраивается в ⚙ клавиатуры."
        stack.addArrangedSubview(SettingsUI.label(note, size: 14, color: EasyTalkTheme.secondary))
    }

    private func addHistorySection() {
        stack.addArrangedSubview(SettingsUI.sectionTitle("История"))
        let card = SettingsUI.card()
        historySwitch.addTarget(self, action: #selector(toggleHistory), for: .valueChanged)
        let detail = "Отправленные сообщения хранятся 90 дней только на этом iPhone — для «Скопировать контекст»"
        card.addArrangedSubview(SettingsUI.switchRow("История вводов", detail: detail, control: historySwitch))
        let history = SettingsRow(title: "История и контекст", detail: "Скопировать для ИИ, вставить слова из ответа")
        history.addTarget(self, action: #selector(openHistory), for: .touchUpInside)
        card.addArrangedSubview(history)
        stack.addArrangedSubview(card)
    }

    private func addAboutSection() {
        stack.addArrangedSubview(SettingsUI.sectionTitle("О приложении"))
        let card = SettingsUI.card()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        card.addArrangedSubview(SettingsUI.label("easytalk \(version), сборка \(build)", size: 16))
        let privacy = "Сообщения, словарь и ключ хранятся только на этом iPhone. "
            + "Текст уходит выбранному провайдеру AI только по кнопкам «Перевести» и «В словарь»."
        card.addArrangedSubview(SettingsUI.label(privacy, size: 14, color: EasyTalkTheme.secondary))
        stack.addArrangedSubview(card)
    }

    // MARK: State

    private func refresh() {
        if preferences.fullAccessSeen != nil {
            keyboardStatus.text = "✓ Клавиатура добавлена, «Полный доступ» включён."
            keyboardStatus.textColor = EasyTalkTheme.green
            systemSettings.isHidden = true
        } else {
            keyboardStatus.text = "Клавиатура ещё не открывалась с «Полным доступом». "
                + "Настройки iPhone → easytalk → Клавиатуры: включи easytalk и «Полный доступ». "
                + "Потом открой клавиатуру в любом поле через 🌐."
            keyboardStatus.textColor = EasyTalkTheme.ink
            systemSettings.isHidden = false
        }
        if let connection = ConnectionStore.read() {
            aiRow.update(title: "Подключение AI", value: "\(connection.provider.title) · \(connection.model)")
        } else {
            aiRow.update(title: "Подключение AI", detail: "Пошаговая настройка за пару минут", value: "Не настроен")
        }
        speakerGender.selectedSegmentIndex = SpeakerGender.allCases.firstIndex(of: preferences.speakerGender) ?? 0
        translateScope.selectedSegmentIndex = TranslateScope.allCases.firstIndex(of: preferences.translateScope) ?? 0
        suggestionsSwitch.isOn = preferences.suggestionsEnabled
        tipsSwitch.isOn = preferences.tipsEnabled
        hapticsSwitch.isOn = preferences.hapticsEnabled
        rewardsSwitch.isOn = preferences.rewardsEnabled
        secondSkillSwitch.isOn = preferences.secondSkillEnabled
        historySwitch.isOn = preferences.historyEnabled
        message.isHidden = (message.text ?? "").isEmpty
    }

    // MARK: Actions

    @objc private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    @objc private func openGuide() { navigationController?.pushViewController(GuideViewController(), animated: true) }
    @objc private func openConnection() { navigationController?.pushViewController(AIConnectionViewController(), animated: true) }
    @objc private func openHistory() { navigationController?.pushViewController(HistoryViewController(), animated: true) }

    @objc private func changeSpeakerGender() {
        let index = speakerGender.selectedSegmentIndex
        guard SpeakerGender.allCases.indices.contains(index) else { return }
        preferences.speakerGender = SpeakerGender.allCases[index]
        // Older keyboards read the gender from the saved connection.
        if var saved = ConnectionStore.read() {
            saved.speakerGender = preferences.speakerGender
            ConnectionStore.write(saved)
        }
    }
    @objc private func changeTranslateScope() {
        let index = translateScope.selectedSegmentIndex
        guard TranslateScope.allCases.indices.contains(index) else { return }
        preferences.translateScope = TranslateScope.allCases[index]
    }
    @objc private func toggleSuggestions() { preferences.suggestionsEnabled = suggestionsSwitch.isOn }
    @objc private func toggleTips() { preferences.tipsEnabled = tipsSwitch.isOn }
    @objc private func toggleHaptics() { preferences.hapticsEnabled = hapticsSwitch.isOn }
    @objc private func toggleRewards() { preferences.rewardsEnabled = rewardsSwitch.isOn }
    @objc private func toggleSecondSkill() { preferences.secondSkillEnabled = secondSkillSwitch.isOn }
    @objc private func toggleHistory() { preferences.historyEnabled = historySwitch.isOn }
    @objc private func showTipsAgain() {
        preferences.resetTips()
        message.text = "Советы начнутся заново при следующем появлении клавиатуры."
        refresh()
    }
}
