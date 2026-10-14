import UIKit
import Security

final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
    private var russian = false, numbers = false, symbols = false, shifted = false, busy = false
    /// Shift turned on by the capitalization rule (not by the user); caps lock by a double tap on Shift.
    private var autoShift = false, capsLock = false
    private var lastShiftTap = Date.distantPast, lastSpaceAt = Date.distantPast
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    /// Suggestions only, never automatic replacement: the user's mistakes stay for the AI review.
    private let suggestionBar = SuggestionBar()
    private let spellChecker = UITextChecker()
    private var textReplacements: [String: String] = [:]
    private var knownWords: [String: KnownWord] = [:]
    static let suggestionHeight: CGFloat = 40
    private var showingSettings = false, showingStudy = false, showingVocabulary = false, showingGame = false
    /// «Контекст»: copy the history of a period for any AI chat, paste words back from its answer.
    private var showingContext = false
    private var showingPanel: Bool { showingStudy || showingSettings || showingContext }
    private let contextPanel = UIStackView(), contextPeriods = UIStackView(), contextSummary = UILabel(), contextMessage = UILabel()
    private var generation = 0, lessonIndex = 0
    private var request: AnalysisOperation?
    private var progressTimer: Timer?
    private let diagnostic = UILabel()
    private var letterKeys: [(KeyboardKey, String)] = []
    private var shiftKey: KeyboardKey?
    private weak var spaceKey: KeyboardKey?
    private var pending: InputSnapshot?
    private var applying = false
    private var connection: ConnectionSettings?
    /// Shared with the app through the App Group; without Full Access iOS gives the keyboard only its own container.
    private lazy var storage: UserDefaults = {
        let shared = SharedStorage.defaults(shared: self.hasFullAccess)
        SharedStorage.migrateLegacyDefaults(to: shared, process: "keyboard")
        return shared
    }()
    private lazy var store = LearningStore(defaults: storage)
    private lazy var preferences = KeyboardPreferences(defaults: storage)
    private lazy var practice = StudyProgressStore(defaults: storage)
    private lazy var rewards = RewardProgress(defaults: storage)
    private lazy var history = InputHistoryStore(defaults: storage)
    private var sentDetector = SentTextDetector()
    private var game: StudySession?
    private var gameFinishedRecorded = false
    private var flippingCard = false
    private var swipingCard: Bool { cardPager.moving }
    private let cardPager = StudyPagingView()
    private let speech = SpeechPlayer()
    private var studyRequest: StudyActionOperation?
    private var studyGeneration = 0
    private var studyBusy = false
    private var translatedSnapshot: InputSnapshot?
    private var studyHostSnapshot: InputSnapshot?
    private var lastTranslationDocument: UUID?
    private var sessionExpanded = false
    private var revisingMeaning = false
    private var showingOriginal = false
    private var expandedCardID: String?
    private var expandedVariantLessons = Set<UUID>()
    private var expandedTranslations = Set<UUID>()
    private var dictionaryFilter = VocabularyFilter.all
    private var archivingCard = false, analysisFailed = false
    private var learnedFeedback: String?
    private var feedbackTimer: Timer?
    private var rewardTimer: Timer?
    private let rewardBanner = WarmCard(padding: 8)
    private let rewardTitle = UILabel()
    private let celebration = CelebrationOverlay()
    private let rewardsEnabled = UISwitch(), secondSkillEnabled = UISwitch(), historySwitch = UISwitch(), hapticsSwitch = UISwitch(), suggestionsSwitch = UISwitch()
    private var cursorPreferredX: Double?
    private var cursorDragging = false
    private var lastKeyWidth = 0
    private var letterRows: [UIStackView] = []
    private var punctuationKeys: [KeyboardKey] = []
    private weak var deleteKey: KeyboardKey?
    private var note = ""
    private let root = UIStackView()
    private let panelTitle = UILabel()
    private let speakerGender = UISegmentedControl(items: SpeakerGender.allCases.map { $0.title })
    private let translate = UIButton(type: .system), study = UIButton(type: .system)
    private let globeSwitch = UIButton(type: .system)
    private let status = UILabel()
    private let settings = UIStackView(), lessonContent = UIStackView()
    private let keys = KeyboardKeyArea()
    private let settingsScroll = UIScrollView()
    private let symbolsEnabled = UISwitch()
    private let symbolChoices = UIStackView()
    private let symbolsPreview = UILabel(), settingsFeedback = UILabel()
    private let studyTabs = UISegmentedControl(items: ["Разбор", "Игра", "Словарь"])
    private let dictionaryFilters = UIStackView()
    private let translationControl = UIStackView()
    private var dictionaryTabIndex: Int { preferences.secondSkillEnabled ? 2 : 1 }
    private let lessonScroll = UIScrollView()
    private var height: NSLayoutConstraint?
    private var lessonHeight: NSLayoutConstraint?
    // The simulator drives the real UI with a test host document.
    var previewSnapshot: (() -> InputSnapshot)?
    var previewType: ((String) -> Void)?
    var previewDelete: (() -> Void)?
    var previewMove: ((Int) -> Void)?
    var previewReplace: ((InputSnapshot, String) -> Bool)?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Let iOS provide its native dictation key. It inserts into the host
        // field and does not launch our app or pass audio through the extension.
        hasDictationKey = false
        connection = ConnectionStore.read()
        russian = preferences.russianLayout
        KeyboardKey.feedback = { [weak self] in self?.keyFeedback() }
        if !preferences.hasSpeakerGender, let connection { preferences.speakerGender = connection.speakerGender }
        view.backgroundColor = EasyTalkTheme.canvas
        root.axis = .vertical; root.spacing = 6; root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8)
        ])
        height = view.heightAnchor.constraint(equalToConstant: 267)
        height?.priority = .init(999); height?.isActive = true
        configure(translate, "Перевести", height: 36, action: #selector(translateInput))
        translate.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        translate.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        translate.setContentHuggingPriority(.required, for: .horizontal)
        configure(study, "Последний урок", height: 36, action: #selector(toggleStudy))
        study.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular); study.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        study.setContentHuggingPriority(.required, for: .horizontal)
        study.accessibilityLabel = "Открыть последний разбор"
        translationControl.addArrangedSubview(translate); translationControl.addArrangedSubview(study)
        translationControl.spacing = 10
        translate.accessibilityIdentifier = "translate-input"; study.accessibilityIdentifier = "last-lesson"
        translationControl.setContentHuggingPriority(.required, for: .horizontal)
        let gear = button("", height: 36, action: #selector(toggleSettings))
        gear.setImage(UIImage(systemName: "gearshape"), for: .normal)
        gear.accessibilityLabel = "Настройки"; fixedWidth(gear, 38)
        panelTitle.font = .systemFont(ofSize: 20, weight: .semibold); panelTitle.textColor = EasyTalkTheme.ink
        let spacer = UIView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.accessibilityIdentifier = "toolbar-spacer"
        let context = button("", height: 36, action: #selector(toggleContext))
        context.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        context.accessibilityLabel = "Скопировать контекст для ИИ"; fixedWidth(context, 38)
        let hide = button("", height: 36, action: #selector(hideKeyboard))
        hide.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hide.accessibilityLabel = "Свернуть клавиатуру"; fixedWidth(hide, 38)
        let toolbar = UIStackView(arrangedSubviews: [hide, spacer, translationControl, studyTabs, panelTitle, context, gear]); toolbar.spacing = 6; toolbar.alignment = .center
        toolbar.accessibilityIdentifier = "input-toolbar"; root.addArrangedSubview(toolbar)
        settings.axis = .vertical; settings.spacing = 12
        settings.translatesAutoresizingMaskIntoConstraints = false
        settingsScroll.backgroundColor = EasyTalkTheme.paper; settingsScroll.layer.cornerRadius = 18
        settingsScroll.addSubview(settings)
        NSLayoutConstraint.activate([
            settings.topAnchor.constraint(equalTo: settingsScroll.contentLayoutGuide.topAnchor, constant: 12),
            settings.bottomAnchor.constraint(equalTo: settingsScroll.contentLayoutGuide.bottomAnchor, constant: -12),
            settings.leadingAnchor.constraint(equalTo: settingsScroll.contentLayoutGuide.leadingAnchor, constant: 12),
            settings.trailingAnchor.constraint(equalTo: settingsScroll.contentLayoutGuide.trailingAnchor, constant: -12),
            settings.widthAnchor.constraint(equalTo: settingsScroll.frameLayoutGuide.widthAnchor, constant: -24)
        ])
        fixedHeight(settingsScroll, 340)
        settings.addArrangedSubview(label("Пол для перевода", size: 19, weight: .medium))
        speakerGender.addTarget(self, action: #selector(changeSpeakerGender), for: .valueChanged)
        speakerGender.accessibilityLabel = "Пол говорящего для перевода"
        fixedHeight(speakerGender, 36); settings.addArrangedSubview(speakerGender)
        settings.addArrangedSubview(label("Для фраз от твоего лица: «я сделал» или «я сделала». Других людей и цитаты эта настройка не меняет.", size: 16))
        rewardsEnabled.addTarget(self, action: #selector(toggleRewards), for: .valueChanged)
        secondSkillEnabled.addTarget(self, action: #selector(toggleSecondSkill), for: .valueChanged)
        historySwitch.addTarget(self, action: #selector(toggleHistory), for: .valueChanged)
        hapticsSwitch.addTarget(self, action: #selector(toggleHaptics), for: .valueChanged)
        suggestionsSwitch.addTarget(self, action: #selector(toggleSuggestions), for: .valueChanged)
        for (title, control) in [("Поощрения", rewardsEnabled), ("Второй навык", secondSkillEnabled), ("История вводов", historySwitch), ("Вибрация клавиш", hapticsSwitch), ("Подсказки слов", suggestionsSwitch)] {
            control.onTintColor = EasyTalkTheme.gold; control.accessibilityLabel = title
            let row = UIStackView(arrangedSubviews: [label(title, size: 19, weight: .medium), control])
            row.alignment = .center; row.spacing = 12; fixedHeight(row, 44); settings.addArrangedSubview(row)
        }
        settings.addArrangedSubview(label("Поощрения — поздравления и короткий салют за английский без ошибок. «Второй навык» — до 4 карточек за раз; открывается только по твоему желанию.", size: 16))
        settings.addArrangedSubview(label("История вводов — отправленные сообщения сохраняются только на этом iPhone, 90 дней, для «Скопировать контекст». Сообщение считается отправленным, когда поле очистилось не клавишей удаления.", size: 16))
        settings.addArrangedSubview(button("Очистить историю вводов", height: 36, action: #selector(clearInputHistory)))
        symbolsEnabled.onTintColor = EasyTalkTheme.gold
        symbolsEnabled.addTarget(self, action: #selector(toggleSymbolRow), for: .valueChanged)
        symbolsEnabled.accessibilityLabel = "Ряд символов на основной клавиатуре"
        let symbolToggle = UIStackView(arrangedSubviews: [label("Ряд символов", size: 19, weight: .medium), symbolsEnabled])
        symbolToggle.alignment = .center; symbolToggle.spacing = 12; fixedHeight(symbolToggle, 44)
        settings.addArrangedSubview(symbolToggle)
        symbolsPreview.font = .systemFont(ofSize: 20, weight: .medium); symbolsPreview.numberOfLines = 0
        settings.addArrangedSubview(symbolsPreview)
        settings.addArrangedSubview(label("Выбери до 12 знаков. Золотые включены; повторное нажатие убирает знак. Новые знаки добавляются справа.", size: 16))
        symbolChoices.axis = .vertical; symbolChoices.spacing = 6; settings.addArrangedSubview(symbolChoices)
        settingsFeedback.font = .systemFont(ofSize: 16); settingsFeedback.numberOfLines = 0; settingsFeedback.textColor = .systemOrange
        settingsFeedback.isHidden = true; settings.addArrangedSubview(settingsFeedback)
        settings.addArrangedSubview(button("Вернуть стандартные знаки", height: 40, action: #selector(resetSymbols)))
        settings.addArrangedSubview(label("Что переводится", size: 20, weight: .semibold))
        settings.addArrangedSubview(label("Выделенный текст или доступный абзац перед курсором. Последний набор отдельно не отслеживается. Вся заметка или файл автоматически не отправляется.", size: 17))
        settings.addArrangedSubview(label("Курсор", size: 20, weight: .semibold))
        settings.addArrangedSubview(label("Удерживай пробел и двигай палец влево, вправо, вверх или вниз.", size: 17))
        settings.addArrangedSubview(label("Подключение AI", size: 20, weight: .semibold))
        settings.addArrangedSubview(label("Ключ AI вводится в приложении easytalk → «Настройки». Клавиатура видит его сразу, если включён «Полный доступ».", size: 16))
        settings.addArrangedSubview(button("Отключить AI", height: 40, action: #selector(disconnectAI)))
        settings.addArrangedSubview(button("Завершить занятие и сбросить разборы", height: 36, action: #selector(clearHistory)))
        diagnostic.font = .systemFont(ofSize: 13); diagnostic.numberOfLines = 2; diagnostic.textColor = .secondaryLabel
        diagnostic.text = UserDefaults.standard.string(forKey: "ai.lastDiagnostic")
        diagnostic.isHidden = diagnostic.text == nil
        settings.addArrangedSubview(diagnostic)
        root.addArrangedSubview(settingsScroll)
        contextPanel.axis = .vertical; contextPanel.spacing = 8
        contextPanel.isLayoutMarginsRelativeArrangement = true; contextPanel.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        contextPanel.backgroundColor = EasyTalkTheme.paper; contextPanel.layer.cornerRadius = 18
        contextPeriods.axis = .horizontal; contextPeriods.spacing = 4; contextPeriods.distribution = .fillEqually
        contextSummary.font = .systemFont(ofSize: 15); contextSummary.textColor = EasyTalkTheme.secondary; contextSummary.numberOfLines = 1
        contextMessage.font = .systemFont(ofSize: 15, weight: .medium); contextMessage.textColor = EasyTalkTheme.ink; contextMessage.numberOfLines = 2
        let contextActions = equalRow([primaryButton("Скопировать контекст", action: #selector(copyContext)), button("Вставить слова", height: 44, action: #selector(pasteWords))])
        for item in [contextPeriods, contextSummary, contextActions, contextMessage] as [UIView] { contextPanel.addArrangedSubview(item) }
        fixedHeight(contextPanel, Self.contextHeight); contextPanel.isHidden = true
        root.addArrangedSubview(contextPanel)
        studyTabs.selectedSegmentIndex = 0
        studyTabs.backgroundColor = EasyTalkTheme.muted; studyTabs.selectedSegmentTintColor = EasyTalkTheme.paper
        studyTabs.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: EasyTalkTheme.ink], for: .normal)
        studyTabs.addTarget(self, action: #selector(changeStudyTab), for: .valueChanged)
        fixedHeight(studyTabs, 34)
        lessonContent.axis = .vertical; lessonContent.spacing = 12; lessonContent.translatesAutoresizingMaskIntoConstraints = false
        lessonScroll.backgroundColor = EasyTalkTheme.canvas; lessonScroll.layer.cornerRadius = 18
        lessonScroll.addSubview(lessonContent)
        NSLayoutConstraint.activate([
            lessonContent.topAnchor.constraint(equalTo: lessonScroll.contentLayoutGuide.topAnchor, constant: 12),
            lessonContent.bottomAnchor.constraint(equalTo: lessonScroll.contentLayoutGuide.bottomAnchor, constant: -12),
            lessonContent.leadingAnchor.constraint(equalTo: lessonScroll.contentLayoutGuide.leadingAnchor, constant: 12),
            lessonContent.trailingAnchor.constraint(equalTo: lessonScroll.contentLayoutGuide.trailingAnchor, constant: -12),
            lessonContent.widthAnchor.constraint(equalTo: lessonScroll.frameLayoutGuide.widthAnchor, constant: -24)
        ])
        lessonHeight = lessonScroll.heightAnchor.constraint(equalToConstant: 320)
        lessonHeight?.priority = .init(999); lessonHeight?.isActive = true; root.addArrangedSubview(lessonScroll)
        status.font = .systemFont(ofSize: 15); status.numberOfLines = 3; status.textColor = EasyTalkTheme.ink
        fixedHeight(status, 56); root.addArrangedSubview(status)
        rewardTitle.font = .systemFont(ofSize: 19, weight: .bold); rewardTitle.textColor = EasyTalkTheme.ink
        let rewardText = UIStackView(arrangedSubviews: [rewardTitle, label("Английский без ошибок", size: 14)])
        rewardText.axis = .vertical; rewardText.spacing = 2
        rewardText.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let rewardIcon = label("✨", size: 27); fixedWidth(rewardIcon, 38)
        let rewardClose = iconButton("xmark", label: "Закрыть поздравление", action: #selector(dismissReward))
        let rewardRow = UIStackView(arrangedSubviews: [rewardIcon, rewardText, rewardClose]); rewardRow.spacing = 9; rewardRow.alignment = .center
        rewardBanner.addArrangedSubview(rewardRow); fixedHeight(rewardBanner, 64); rewardBanner.isHidden = true
        root.addArrangedSubview(rewardBanner)
        suggestionBar.onPick = { [weak self] suggestion in self?.applySuggestion(suggestion) }
        fixedHeight(suggestionBar, Self.suggestionHeight); suggestionBar.layer.cornerRadius = 9; suggestionBar.clipsToBounds = true
        root.addArrangedSubview(suggestionBar)
        // The user's iOS text replacements (and contact names, which are known words).
        requestSupplementaryLexicon { [weak self] lexicon in
            var replacements: [String: String] = [:]
            for entry in lexicon.entries where !entry.userInput.isEmpty {
                if entry.userInput.lowercased() != entry.documentText.lowercased() { replacements[entry.userInput.lowercased()] = entry.documentText }
            }
            DispatchQueue.main.async { self?.textReplacements = replacements; self?.updateSuggestions(); self?.render() }
        }
        keys.axis = .vertical; keys.spacing = 5; root.addArrangedSubview(keys)
        celebration.translatesAutoresizingMaskIntoConstraints = false; celebration.isUserInteractionEnabled = false; celebration.accessibilityElementsHidden = true
        view.addSubview(celebration)
        NSLayoutConstraint.activate([celebration.topAnchor.constraint(equalTo: view.topAnchor), celebration.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            celebration.leadingAnchor.constraint(equalTo: view.leadingAnchor), celebration.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        NotificationCenter.default.addObserver(self, selector: #selector(motionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        rebuildKeys(); render()
    }
    deinit { feedbackTimer?.invalidate(); speech.stop(); studyRequest?.cancel(); progressTimer?.invalidate(); rewardTimer?.invalidate(); request?.cancel(); NotificationCenter.default.removeObserver(self) }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDictationKey = false
        primaryLanguage = russian ? "ru-RU" : "en-US"
        let numericFields: [UIKeyboardType] = [.numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad, .numbersAndPunctuation]
        numbers = numericFields.contains(textDocumentProxy.keyboardType ?? .default); symbols = false
        shifted = false; autoShift = false; capsLock = false
        rebuildKeys(); updateAutoShift(); haptic.prepare()
        // The key, the dictionary and the history may have been changed in the app while the keyboard stayed loaded.
        if request == nil { connection = ConnectionStore.read() }
        store.reloadWords(); history.reload()
        // The user's own words: suggested first and never treated as misspellings.
        knownWords = WordSuggestions.vocabulary(from: history.entries.map(\.text))
        updateSuggestions()
        render()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelRequest(); clearReward(); keys.stopTouches()
        showingStudy = false; showingSettings = false; showingContext = false; flippingCard = false; archivingCard = false; cardPager.alpha = 1; cardPager.transform = .identity; cardPager.isUserInteractionEnabled = true; cardPager.isScrollEnabled = true
    }
    override func textDidChange(_ textInput: UITextInput?) { super.textDidChange(textInput); fieldChanged() }
    override func selectionDidChange(_ textInput: UITextInput?) { super.selectionDidChange(textInput); fieldChanged() }
    private func fieldChanged() {
        guard !applying else { return }
        recordSentText()
        // Proxy callbacks are frequent during a trackpad drag. Rebuilding the
        // panel mid-touch changes its coordinates and loses responsiveness.
        guard !cursorDragging else { return }
        updateAutoShift(); updateSuggestions()
        let current = snapshot()
        if showingStudy, let previous = studyHostSnapshot, current != previous {
            cancelStudyAction(); showingStudy = false; showingVocabulary = false; showingGame = false
            studyHostSnapshot = nil; flippingCard = false; keys.stopTouches()
        }
        if !cursorDragging { cursorPreferredX = nil }
        if let pending, snapshot() != pending {
            let revision = revisingMeaning; cancelRequest(); note = revision ? "Русский текст или курсор изменились. Уточни смысл ещё раз; прежний разбор сохранён." : "Текст изменился. Нажми «Перевести» ещё раз."
        }
        render()
    }
    private func fixedHeight(_ v: UIView, _ value: CGFloat) {
        let c = v.heightAnchor.constraint(equalToConstant: value); c.priority = .init(999); c.isActive = true
    }
    private func fixedWidth(_ v: UIView, _ value: CGFloat) {
        let c = v.widthAnchor.constraint(equalToConstant: value); c.priority = .init(999); c.isActive = true
    }
    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
        let l = UILabel(); l.text = text; l.numberOfLines = 0; l.font = .systemFont(ofSize: size, weight: weight); l.textColor = EasyTalkTheme.ink; return l
    }
    private func configure(_ b: UIButton, _ title: String, height: CGFloat, action: Selector) {
        b.setTitle(title, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        EasyTalkTheme.style(b)
        fixedHeight(b, height); b.addTarget(self, action: action, for: .touchUpInside)
    }
    private func button(_ title: String, height: CGFloat = 42, action: Selector) -> UIButton {
        let b = TextLinkButton(type: .system); configure(b, title, height: height, action: action); return b
    }
    private func iconButton(_ symbol: String, label text: String, action: Selector) -> UIButton {
        let b = button("", height: 44, action: action); fixedWidth(b, 44)
        b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
        b.accessibilityLabel = text; b.setContentHuggingPriority(.defaultHigh, for: .horizontal); return b
    }
    private func equalRow(_ items: [UIView]) -> UIStackView {
        let r = UIStackView(arrangedSubviews: items); r.axis = .horizontal; r.spacing = 5; r.distribution = .fillEqually; return r
    }
    private func empty(_ stack: UIStackView) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
    }
    private func key(_ title: String = "", symbol: String? = nil, width: CGFloat? = nil, keyHeight: CGFloat = 48, action: @escaping () -> Void) -> KeyboardKey {
        let key = KeyboardKey(); key.title = title; key.symbol = symbol; key.activate = action
        fixedHeight(key, keyHeight); if let width { fixedWidth(key, width) }; return key
    }
    private func rebuildKeys() {
        primaryLanguage = russian ? "ru-RU" : "en-US"
        keys.stopTouches(); empty(keys); letterKeys = []; letterRows = []; punctuationKeys = []; shiftKey = nil; deleteKey = nil
        if preferences.symbolRowEnabled && !preferences.symbols.isEmpty {
            let selected = preferences.symbols
            let columns = view.bounds.width > 0 && view.bounds.width < 360 ? 6 : 9
            let count = Int(ceil(Double(selected.count) / Double(columns)))
            let perRow = Int(ceil(Double(selected.count) / Double(count)))
            for start in stride(from: 0, to: selected.count, by: perRow) {
                let buttons = selected[start..<min(start + perRow, selected.count)].map { value -> KeyboardKey in
                    let k = key(value, keyHeight: 44) { [weak self] in self?.type(value) }
                    k.caption.font = .systemFont(ofSize: 22); k.accessibilityLabel = "Вставить \(value)"
                    punctuationKeys.append(k); return k
                }
                let row = equalRow(buttons); row.spacing = 4; keys.addArrangedSubview(row)
            }
        }
        let layouts = numbers ? (symbols ? ["[]{}#%^*+=", "_\\|~<>€$£•", ".,?!'@&"] : ["1234567890", "-/:;()₽&@\"", ".,?!'[]"]) :
            (russian ? ["йцукенгшщзх", "фывапролджэ", "ячсмитьбю"] : ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
        for (index, letters) in layouts.enumerated() {
            let buttons = letters.map { character -> KeyboardKey in
                let value = String(character)
                let k = key(value) { [weak self] in
                    guard let self else { return }
                    self.type(self.shifted && !self.numbers ? value.uppercased() : value)
                    self.afterLetter()
                }
                if russian && !numbers, let alternate = Self.alternates[value] {
                    k.behavior = .alternate; k.alternateTitle = alternate
                    k.alternateActivate = { [weak self] in
                        guard let self else { return }
                        self.type(self.shifted ? alternate.uppercased() : alternate)
                        self.afterLetter()
                    }
                    k.accessibilityHint = "Удерживай для «\(alternate)»"
                }
                letterKeys.append((k, value)); return k
            }
            let row = equalRow(buttons); row.spacing = 4; letterRows.append(row)
            if index == 2 {
                let shift = key(numbers ? (symbols ? "123" : "#+=") : "", symbol: numbers ? nil : "shift", width: 44) { [weak self] in self?.toggleShift() }
                shift.caption.font = .systemFont(ofSize: 16, weight: .medium); shift.accessibilityLabel = numbers ? "Символы" : "Shift"
                shiftKey = shift
                let delete = key(symbol: "delete.left", width: 44) { [weak self] in self?.backspace() }
                delete.behavior = .delete; delete.accessibilityLabel = "Удалить"; deleteKey = delete
                delete.accelerated = { [weak self] in self?.deleteWord() }
                let third = UIStackView(arrangedSubviews: [shift, row, delete]); third.spacing = 5; keys.addArrangedSubview(third)
            } else if !russian && !numbers && index == 1 {
                let left = UIView(), right = UIView(); fixedWidth(left, 16); fixedWidth(right, 16)
                keys.addArrangedSubview(UIStackView(arrangedSubviews: [left, row, right]))
            } else { keys.addArrangedSubview(row) }
        }
        let bottom = UIStackView(); bottom.spacing = 5
        let numeric = key(numbers ? "ABC" : "123", width: 44) { [weak self] in self?.toggleNumbers() }
        numeric.caption.font = .systemFont(ofSize: 16, weight: .medium); bottom.addArrangedSubview(numeric)
        let language = key(russian ? "RU" : "EN", width: 58) { [weak self] in self?.toggleLanguage() }
        language.caption.font = .systemFont(ofSize: 20, weight: .semibold); language.accessibilityLabel = "Переключить язык"; bottom.addArrangedSubview(language)
        if needsInputModeSwitchKey {
            let globe = key(symbol: "globe", width: 36) { [weak self] in self?.advanceToNextInputMode() }
            globe.accessibilityLabel = "Следующая клавиатура"; bottom.addArrangedSubview(globe)
        }
        let space = key("пробел") { [weak self] in self?.typeSpace() }
        space.caption.font = .systemFont(ofSize: 17); space.behavior = .space; spaceKey = space
        space.cursorMode = { [weak self, weak space] active in
            space?.title = active ? "↔ ↕ курсор" : "пробел"
            self?.cursorDragging = active; self?.cursorPreferredX = nil
            space?.accessibilityLabel = "Пробел. Удерживай для перемещения курсора"
            self?.keys.setCursorTracking(active, owner: space)
            if !active { self?.render() }
        }
        space.cursorMove = { [weak self] columns, rows in self?.moveCursor(columns, rows: rows) }; bottom.addArrangedSubview(space)
        let returnTitle = self.returnTitle
        let enter = returnTitle.map { title in key(title, width: 72) { [weak self] in self?.type("\n") } } ?? key(symbol: "return", width: 64) { [weak self] in self?.type("\n") }
        if returnTitle != nil { enter.caption.font = .systemFont(ofSize: 15, weight: .semibold); enter.caption.adjustsFontSizeToFitWidth = true }
        enter.accessibilityLabel = returnTitle ?? "Новая строка"; bottom.addArrangedSubview(enter); keys.addArrangedSubview(bottom)
        updateCase()
    }
    /// Long press on these Russian letters offers the second one.
    static let alternates = ["ь": "ъ", "е": "ё"]
    private func updateCase() {
        for (key, value) in letterKeys {
            key.title = shifted && !numbers ? value.uppercased() : value
            if let alternate = Self.alternates[value], key.behavior == .alternate { key.alternateTitle = shifted ? alternate.uppercased() : alternate }
        }
        if !numbers { shiftKey?.symbol = capsLock ? "capslock.fill" : (shifted ? "shift.fill" : "shift") }
        shiftKey?.accessibilityLabel = capsLock ? "Caps Lock включён" : (shifted ? "Shift включён" : "Shift")
    }
    /// One uppercase letter, unless caps lock is on.
    private func afterLetter() {
        guard shifted, !capsLock else { return }
        shifted = false; autoShift = false; updateCase()
    }
    private var capitalization: TypingRules.Capitalization {
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: return TypingRules.Capitalization.none
        case .words: return .words
        case .allCharacters: return .allCharacters
        default: return .sentences
        }
    }
    /// Uppercase at the start of a sentence, as the field asks; a user Shift is never undone here.
    private func updateAutoShift() {
        guard !numbers, !capsLock, previewSnapshot == nil else { return }
        let should = TypingRules.shouldCapitalize(before: textDocumentProxy.documentContextBeforeInput ?? "", mode: capitalization)
        if should && !shifted { shifted = true; autoShift = true; updateCase() }
        else if !should && shifted && autoShift { shifted = false; autoShift = false; updateCase() }
    }
    private var returnTitle: String? {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .send: return "Отпр."
        case .search, .google, .yahoo: return "Найти"
        case .go, .route: return "Перейти"
        case .done: return "Готово"
        case .next: return "Далее"
        case .join: return "Войти"
        default: return nil
        }
    }
    private func keyFeedback() {
        UIDevice.current.playInputClick()
        if preferences.hapticsEnabled && hasFullAccess { haptic.impactOccurred(intensity: 0.6) }
    }
    /// A quick second space after a word becomes «. ».
    private func typeSpace() {
        let now = Date()
        defer { lastSpaceAt = now }
        if !numbers, now.timeIntervalSince(lastSpaceAt) < 0.8, TypingRules.doubleSpaceMakesPeriod(before: snapshot().before ?? "") {
            if let previewDelete { previewDelete() } else { textDocumentProxy.deleteBackward() }
            type(". ")
        } else { type(" ") }
    }
    /// Held delete, after the first characters: the previous word with its trailing spaces.
    private func deleteWord() {
        let count = TypingRules.wordDeletionLength(before: snapshot().before ?? "")
        guard count > 0 else { return }
        sentDetector.noteDeletion()
        cancelRequest(); clearReward(); translatedSnapshot = nil; note = ""
        for _ in 0..<count { if let previewDelete { previewDelete() } else { textDocumentProxy.deleteBackward() } }
        updateAutoShift(); updateSuggestions(); render()
    }
    private func moveCursor(_ steps: Int, rows: Int = 0) {
        guard steps != 0 || rows != 0 else { return }; cancelRequest(); note = ""
        if steps != 0 {
            cursorPreferredX = nil
            if let previewMove { previewMove(steps) } else {
                let context = steps < 0 ? (textDocumentProxy.documentContextBeforeInput ?? "") : (textDocumentProxy.documentContextAfterInput ?? "")
                let fragment = steps < 0 ? String(context.suffix(-steps)) : String(context.prefix(steps))
                let offset = fragment.utf16.count * (steps < 0 ? -1 : 1)
                if offset != 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: offset) }
            }
        }
        if rows != 0 {
            let context = snapshot()
            let offset = CursorNavigation.vertical(before: context.before ?? "", after: context.after ?? "", rows: rows,
                width: Double(max(200, view.bounds.width - 40)), preferredX: &cursorPreferredX) { character in
                    Double((String(character) as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width)
                }
            if let previewMove { previewMove(offset.characters) }
            else if offset.utf16 != 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: offset.utf16) }
        }
    }
    private func renderSettings() {
        speakerGender.selectedSegmentIndex = SpeakerGender.allCases.firstIndex(of: preferences.speakerGender) ?? 0
        rewardsEnabled.isOn = preferences.rewardsEnabled; secondSkillEnabled.isOn = preferences.secondSkillEnabled
        historySwitch.isOn = preferences.historyEnabled; hapticsSwitch.isOn = preferences.hapticsEnabled
        suggestionsSwitch.isOn = preferences.suggestionsEnabled
        symbolsEnabled.isOn = preferences.symbolRowEnabled
        symbolsPreview.text = preferences.symbols.isEmpty ? "Нет выбранных знаков" : preferences.symbols.joined(separator: "   ")
        if symbolChoices.arrangedSubviews.isEmpty {
            let available = KeyboardPreferences.availableSymbols
            for start in stride(from: 0, to: available.count, by: 6) {
                let buttons = available[start..<min(start + 6, available.count)].map { value -> UIButton in
                    let b = button(value, height: 44, action: #selector(selectSymbol(_:)))
                    b.accessibilityIdentifier = value
                    b.titleLabel?.font = .systemFont(ofSize: 21, weight: .medium)
                    return b
                }
                symbolChoices.addArrangedSubview(equalRow(buttons))
            }
        }
        for row in symbolChoices.arrangedSubviews.compactMap({ $0 as? UIStackView }) {
            for b in row.arrangedSubviews.compactMap({ $0 as? UIButton }) {
                let value = b.accessibilityIdentifier ?? "", selected = preferences.symbols.contains(value)
                EasyTalkTheme.style(b, primary: selected)
                b.accessibilityLabel = "\(value), \(selected ? "включён" : "выключен")"
            }
        }
    }
    @objc private func toggleSymbolRow() { preferences.symbolRowEnabled = symbolsEnabled.isOn; rebuildKeys(); render() }
    @objc private func changeSpeakerGender() {
        guard SpeakerGender.allCases.indices.contains(speakerGender.selectedSegmentIndex) else { return }
        preferences.speakerGender = SpeakerGender.allCases[speakerGender.selectedSegmentIndex]
        cancelRequest(); render()
    }
    @objc private func selectSymbol(_ sender: UIButton) {
        guard let value = sender.accessibilityIdentifier else { return }
        let changed = preferences.toggle(value)
        settingsFeedback.text = changed ? nil : "Можно включить до 12 знаков. Сначала убери один из выбранных."
        settingsFeedback.isHidden = changed; rebuildKeys(); render()
    }
    @objc private func resetSymbols() { preferences.resetSymbols(); settingsFeedback.isHidden = true; rebuildKeys(); render() }
    @objc private func toggleHaptics() { preferences.hapticsEnabled = hapticsSwitch.isOn }
    @objc private func toggleSuggestions() { preferences.suggestionsEnabled = suggestionsSwitch.isOn; updateSuggestions(); render() }
    /// Suggestions for the word before the cursor; nothing is replaced unless the user taps one.
    private func updateSuggestions() {
        guard preferences.suggestionsEnabled, !numbers, previewSnapshot == nil else { suggestionBar.show([]); return }
        let word = WordSuggestions.currentWord(before: textDocumentProxy.documentContextBeforeInput ?? "")
        // Only at the end of a word: inside one, a suggestion would replace half of it.
        if let next = textDocumentProxy.documentContextAfterInput?.first, next.isLetter || next.isNumber { suggestionBar.show([]); return }
        guard !word.isEmpty else { suggestionBar.show([]); return }
        let language = WordSuggestions.language(of: word, russianLayout: russian)
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = spellChecker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language).location != NSNotFound
        let guesses = misspelled ? (spellChecker.guesses(forWordRange: range, in: word, language: language) ?? []) : []
        let completions = spellChecker.completions(forPartialWordRange: range, in: word, language: language) ?? []
        suggestionBar.show(WordSuggestions.suggest(for: word, replacements: textReplacements, vocabulary: knownWords,
                                                   isMisspelled: misspelled, guesses: guesses, completions: completions))
    }
    /// Replaces the word before the cursor with the chosen suggestion and a space.
    private func applySuggestion(_ suggestion: WordSuggestion) {
        let word = WordSuggestions.currentWord(before: textDocumentProxy.documentContextBeforeInput ?? "")
        guard !word.isEmpty else { return }
        for _ in word { if let previewDelete { previewDelete() } else { textDocumentProxy.deleteBackward() } }
        type(suggestion.text + " ")
    }
    @objc private func hideKeyboard() { dismissKeyboard() }
    @objc private func toggleHistory() { preferences.historyEnabled = historySwitch.isOn; sentDetector = SentTextDetector(); render() }
    @objc private func clearInputHistory() { history.clear(); sentDetector = SentTextDetector(); note = "История вводов очищена."; render() }
    @objc private func toggleRewards() { preferences.rewardsEnabled = rewardsEnabled.isOn; if !rewardsEnabled.isOn { clearReward() }; render() }
    @objc private func toggleSecondSkill() {
        preferences.secondSkillEnabled = secondSkillEnabled.isOn
        if !secondSkillEnabled.isOn { game = nil; showingGame = false; celebration.stop() }
        updateStudyTabs(); render()
    }
    private func updateStudyTabs() {
        let names = preferences.secondSkillEnabled ? ["Разбор", "Игра", "Словарь"] : ["Разбор", "Словарь"]
        if (0..<studyTabs.numberOfSegments).map({ studyTabs.titleForSegment(at: $0) ?? "" }) != names {
            studyTabs.removeAllSegments(); for (i, name) in names.enumerated() { studyTabs.insertSegment(withTitle: name, at: i, animated: false) }
            studyTabs.selectedSegmentIndex = showingGame ? 1 : (showingVocabulary ? dictionaryTabIndex : 0)
        }
    }
    private func render() {
        guard isViewLoaded else { return }
        updateStudyTabs()
        settingsScroll.isHidden = !showingSettings; studyTabs.isHidden = !showingStudy; lessonScroll.isHidden = !showingStudy
        contextPanel.isHidden = !showingContext
        translationControl.isHidden = showingPanel
        study.setTitle(view.bounds.width < 370 ? "Урок" : "Последний урок", for: .normal)
        translationControl.superview?.subviews.first(where: { $0.accessibilityIdentifier == "toolbar-spacer" })?.isHidden = showingPanel
        keys.isHidden = showingPanel
        // Hidden until there is a suggestion, so the keyboard is only taller while it helps.
        suggestionBar.isHidden = showingPanel || !preferences.suggestionsEnabled || !suggestionBar.hasSuggestions
        rewardBanner.isHidden = rewardTitle.text == nil || !preferences.rewardsEnabled || showingPanel
        status.isHidden = note.isEmpty || showingPanel || !rewardBanner.isHidden; status.text = note
        translate.setTitle(busy ? "Отменить" : "Перевести", for: .normal)
        translate.accessibilityLabel = snapshot().isSelection ? "Перевести выделение" : "Перевести текущий абзац"
        translate.isHidden = showingPanel; study.isHidden = translate.isHidden
        translate.isEnabled = busy || (!translate.isHidden && snapshot() != translatedSnapshot)
        translationControl.backgroundColor = .clear
        translationControl.layer.borderWidth = 0
        for b in [translate, study] { b.backgroundColor = .clear; b.layer.borderWidth = 0; b.setTitleColor(EasyTalkTheme.ink, for: .normal); b.setTitleColor(EasyTalkTheme.secondary, for: .disabled); b.tintColor = EasyTalkTheme.ink }
        translate.backgroundColor = EasyTalkTheme.creamEnd; translate.layer.cornerRadius = 10; translate.layer.borderWidth = 1
        translate.layer.borderColor = EasyTalkTheme.border.resolvedColor(with: traitCollection).cgColor
        study.layer.cornerRadius = 10; study.layer.borderWidth = 1
        study.layer.borderColor = EasyTalkTheme.border.resolvedColor(with: traitCollection).cgColor
        study.isEnabled = !store.lessons.isEmpty && !busy
        if showingStudy && studyHostSnapshot == nil { studyHostSnapshot = snapshot() }
        if !showingStudy { studyHostSnapshot = nil }
        panelTitle.isHidden = !(showingSettings || showingContext); panelTitle.text = showingContext ? "Контекст" : "Настройки"
        updateStudyIndicator(); if showingStudy { renderStudy() }; if showingSettings { renderSettings() }; if showingContext { renderContext() }; updateHeight()
    }
    @objc private func motionChanged() { updateStudyIndicator(); if UIAccessibility.isReduceMotionEnabled { celebration.stop() } }
    private func updateStudyIndicator() {
        study.layer.removeAnimation(forKey: "learning")
        study.accessibilityLabel = "Открыть последний разбор. Новых: \(store.unreadCount)"
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = Int(view.bounds.width)
        if width > 0 && lastKeyWidth != width && !cursorDragging { lastKeyWidth = width; rebuildKeys() }
        updateHeight()
    }
    private func updateHeight() {
        var sizes: [CGFloat] = [36]
        if showingSettings { sizes.append(340) }
        if showingContext { sizes.append(Self.contextHeight) }
        let panelHeight: CGFloat = showingGame ? 280 : 320
        lessonHeight?.constant = panelHeight
        if showingStudy { sizes.append(panelHeight) }
        if !status.isHidden { sizes.append(56) }; if !rewardBanner.isHidden { sizes.append(64) }
        if !suggestionBar.isHidden { sizes.append(Self.suggestionHeight) }
        if !keys.isHidden {
            let extraRows = keys.arrangedSubviews.count - 4
            sizes.append(4 * 48 + CGFloat(extraRows) * 44 + CGFloat(keys.arrangedSubviews.count - 1) * 5)
        }
        let value = sizes.reduce(0, +) + CGFloat(sizes.count - 1) * 6 + 16
        if height?.constant != value { height?.constant = value }
    }
    private func renderStudy() {
        if showingGame && (cardPager.moving || archivingCard) { return }
        empty(lessonContent)
        if busy || analysisFailed {
            let card = WarmCard(); card.addArrangedSubview(label(note, size: 18))
            card.addArrangedSubview(link(busy ? "Отменить" : "Попробовать снова", action: #selector(translateInput)))
            lessonContent.addArrangedSubview(card); return
        }
        if !note.isEmpty { let message = label(note, size: 16); message.textColor = EasyTalkTheme.secondary; lessonContent.addArrangedSubview(message) }
        if showingGame { renderGame(); return }
        if showingVocabulary { renderVocabulary(); return }
        guard !store.lessons.isEmpty else {
            let card = WarmCard()
            card.addArrangedSubview(label("Твой английский, шаг за шагом", size: 23, weight: .bold))
            card.addArrangedSubview(label("После перевода здесь появятся правки и слова, которые можно забрать в словарь.", size: 17))
            if preferences.secondSkillEnabled { card.addArrangedSubview(primaryButton("✨ Попробовать «Второй навык»", action: #selector(startGame))) }
            lessonContent.addArrangedSubview(card); return
        }
        lessonIndex = min(lessonIndex, store.lessons.count - 1)
        let lesson = store.lessons[lessonIndex]
        if store.lessons.count > 1 {
            let toggle = link(sessionExpanded ? "Свернуть список ↑" : "Разборы занятий · \(store.lessons.count) ↓", action: #selector(toggleSession))
            toggle.accessibilityIdentifier = "session-lessons"; lessonContent.addArrangedSubview(toggle)
            if sessionExpanded {
                for (index, item) in store.lessons.enumerated() {
                    let choose = link(item.response.corrected, action: #selector(chooseSessionLesson(_:)))
                    choose.tag = index; choose.isEnabled = index != lessonIndex; lessonContent.addArrangedSubview(choose)
                    lessonContent.addArrangedSubview(translationLink(for: item, index: index))
                    if expandedTranslations.contains(item.id) {
                        let russian = label(item.response.translated, size: 17); russian.accessibilityIdentifier = "session-translation-\(index)"; lessonContent.addArrangedSubview(russian)
                    }
                }
            }
        }
        let english = WarmCard()
        let phraseHeading = UIStackView(arrangedSubviews: [label("Твой английский", size: 14, weight: .semibold), speechButton(lesson.response.corrected)])
        phraseHeading.alignment = .center; english.addArrangedSubview(phraseHeading)
        english.addArrangedSubview(label(lesson.response.corrected, size: 21, weight: .semibold))
        let sourceButton = link(showingOriginal ? "Исходник ↑" : "Исходник ↓", action: #selector(toggleOriginal))
        sourceButton.accessibilityLabel = "Показать или скрыть исходный текст"
        let rephrase = link(studyBusy ? "Отменить" : "Стили", action: #selector(rephraseLesson))
        rephrase.accessibilityLabel = studyBusy ? "Отменить запрос перефразирования" : "Перефразировать в разных стилях"
        rephrase.accessibilityIdentifier = "rephrase-lesson"
        let actions = UIStackView(arrangedSubviews: [translationLink(for: lesson, index: lessonIndex), sourceButton, rephrase])
        actions.spacing = 8; actions.alignment = .center; actions.accessibilityIdentifier = "phrase-actions"
        sourceButton.accessibilityIdentifier = "show-original"
        if editedRussianMeaning(for: lesson) != nil {
            let clarify = link("Уточнить", action: #selector(clarifyMeaning))
            clarify.accessibilityLabel = "Уточнить смысл по русскому переводу"
            clarify.accessibilityIdentifier = "clarify-meaning"; actions.addArrangedSubview(clarify)
        }
        for b in actions.arrangedSubviews.compactMap({ $0 as? UIButton }) {
            b.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            b.titleLabel?.adjustsFontSizeToFitWidth = true; b.titleLabel?.minimumScaleFactor = 0.85
            b.setContentHuggingPriority(.required, for: .horizontal)
            b.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        english.addArrangedSubview(actions)
        if showingOriginal {
            let original = label(lesson.source, size: 18)
            let marked = NSMutableAttributedString(string: lesson.source, attributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: EasyTalkTheme.ink])
            let scalars = Array(lesson.source.unicodeScalars)
            for d in lesson.response.diffs {
                let start = String(String.UnicodeScalarView(scalars.prefix(d.start))).utf16.count
                let length = String(String.UnicodeScalarView(scalars[d.start..<d.end])).utf16.count
                marked.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: UIColor.systemOrange,
                    .backgroundColor: UIColor.systemOrange.withAlphaComponent(0.16)], range: NSRange(location: start, length: length))
            }
            original.accessibilityIdentifier = "original-text"; original.attributedText = marked; english.addArrangedSubview(original)
        }
        if expandedTranslations.contains(lesson.id) {
            let russian = label(lesson.response.translated, size: 17); russian.accessibilityIdentifier = "lesson-translation"; english.addArrangedSubview(russian)
        }
        if preferences.rewardsEnabled, let praise = rewardTitle.text { english.addArrangedSubview(label("✨ " + praise, size: 16, weight: .medium)) }
        let variants = lesson.variants ?? [], expanded = expandedVariantLessons.contains(lesson.id)
        if !variants.isEmpty {
            let toggle = link(expanded ? "Свернуть варианты ↑" : "Показать варианты · \(variants.count) ↓", action: #selector(toggleVariants))
            toggle.accessibilityIdentifier = "toggle-variants"; english.addArrangedSubview(toggle)
            if expanded {
                for variant in variants {
                    english.addArrangedSubview(separator())
                    let row = UIStackView(arrangedSubviews: [label(variant.label, size: 14, weight: .medium), speechButton(variant.text)])
                    row.alignment = .center; english.addArrangedSubview(row)
                    english.addArrangedSubview(label(variant.text, size: 20, weight: .semibold))
                    english.addArrangedSubview(label(variant.explanation, size: 16))
                }
                if variants.count > 1 { english.addArrangedSubview(link("К замечаниям · свернуть варианты ↑", action: #selector(toggleVariants))) }
            }
        }
        lessonContent.addArrangedSubview(english)
        if !lesson.response.hasErrors { lessonContent.addArrangedSubview(label("✓ Грамматических правок нет", size: 16, weight: .medium)) }
        let words = lesson.response.studyVocabulary
        var integrated = Set<Int>()
        for d in lesson.response.diffs {
            let card = WarmCard(padding: 12)
            card.addArrangedSubview(label("\(d.original) → \(d.corrected)", size: 18, weight: .semibold))
            card.addArrangedSubview(label(d.explanation, size: 17))
            for (index, word) in words.enumerated() where !integrated.contains(index) {
                let matches = d.corrected.range(of: word.term, options: .caseInsensitive) != nil || word.term.range(of: d.corrected, options: .caseInsensitive) != nil
                if matches { let row = suggestionRow(word, index: index); card.addArrangedSubview(row); card.setCustomSpacing(18, after: row); integrated.insert(index) }
            }
            lessonContent.addArrangedSubview(card)
        }
        let remaining = words.indices.filter { !integrated.contains($0) }
        if !remaining.isEmpty {
            lessonContent.addArrangedSubview(separator())
            for index in remaining { lessonContent.addArrangedSubview(suggestionRow(words[index], index: index)) }
        }
    }
    /// Reading a revised meaning is safe at any caret position: unlike translation, it never replaces the host text.
    private func currentRussianText(from captured: InputSnapshot) -> String? {
        guard captured.document != nil else { return nil }
        if let selected = captured.selected, selected.contains(where: { $0.isNewline }) { return selected }
        let left = captured.before?.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).last.map(String.init) ?? ""
        let right = captured.after?.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        return left + (captured.selected ?? "") + right
    }
    private func editedRussianMeaning(for lesson: Lesson) -> String? {
        let captured = snapshot()
        guard lesson.id == store.lessons.first?.id, let meaning = currentRussianText(from: captured),
              (!lesson.response.translated.contains(where: { $0.isNewline }) || captured.selected?.contains(where: { $0.isNewline }) == true),
              meaning.unicodeScalars.count <= 2000, meaning.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil,
              lastTranslationDocument == nil || lastTranslationDocument == captured.document,
              meaning.trimmingCharacters(in: .whitespacesAndNewlines) != lesson.response.translated.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return meaning
    }
    private func translationLink(for lesson: Lesson, index: Int) -> UIButton {
        let link = link(expandedTranslations.contains(lesson.id) ? "Перевод ↑" : "Перевод ↓", action: #selector(toggleTranslation(_:)))
        link.tag = index; link.accessibilityIdentifier = "show-translation-\(index)"; return link
    }
    @objc private func toggleTranslation(_ sender: UIButton) {
        guard store.lessons.indices.contains(sender.tag) else { return }; let id = store.lessons[sender.tag].id
        if !expandedTranslations.insert(id).inserted { expandedTranslations.remove(id) }; render()
    }
    private func separator() -> UIView {
        let line = UIView(); line.backgroundColor = EasyTalkTheme.muted; fixedHeight(line, 1); return line
    }
    private func suggestionRow(_ word: VocabularySuggestion, index: Int) -> UIView {
        let entry = word.dictionary?.validated ?? LexicalEntry.offline(word.term)
        let term = entry?.headword ?? word.term, meaning = entry?.meanings.joined(separator: "; ") ?? word.meaning
        let saved = store.contains(word.savedTerm)
        let text = UIStackView(arrangedSubviews: [label(term, size: 19, weight: .semibold), label(meaning, size: 16)])
        text.axis = .vertical; text.spacing = 3; text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let save = button(saved ? "В словаре" : "В словарь →", height: 44, action: #selector(saveWord(_:)))
        styleLink(save)
        save.setContentHuggingPriority(.required, for: .horizontal); save.setContentCompressionResistancePriority(.required, for: .horizontal)
        save.tag = index; save.accessibilityIdentifier = "save-word-\(index)"; save.isEnabled = !saved
        save.accessibilityLabel = saved ? "\(term) уже в словаре" : "Сохранить \(term) в словарь"
        let row = UIStackView(arrangedSubviews: [text, speechButton(term), save]); row.spacing = 5; row.alignment = .center
        row.accessibilityIdentifier = "suggestion-card-\(index)"; row.isLayoutMarginsRelativeArrangement = true; row.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0); return row
    }
    private func styleLink(_ b: UIButton) {
        b.backgroundColor = .clear; b.layer.borderWidth = 0; b.contentHorizontalAlignment = .left
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        b.setTitleColor(EasyTalkTheme.link, for: .normal); b.setTitleColor(EasyTalkTheme.link, for: .highlighted); b.setTitleColor(EasyTalkTheme.secondary, for: .disabled)
        (b as? TextLinkButton)?.showsLinkUnderline = true
        b.accessibilityTraits.remove(.button); b.accessibilityTraits.insert(.link)
    }
    private func link(_ text: String, action: Selector) -> UIButton { let b = button(text, height: 36, action: action); styleLink(b); return b }
    @objc private func toggleVariants() {
        guard store.lessons.indices.contains(lessonIndex) else { return }; let id = store.lessons[lessonIndex].id
        if !expandedVariantLessons.insert(id).inserted { expandedVariantLessons.remove(id) }
        render(); view.layoutIfNeeded(); lessonScroll.setContentOffset(.zero, animated: false)
    }
    @objc private func returnToInput() {
        cancelRequest(); clearReward(); analysisFailed = false; showingStudy = false; showingSettings = false; note = ""; render()
    }
    private func speechButton(_ text: String) -> UIButton {
        let b = iconButton("speaker.wave.2", label: "Произнести: " + text, action: #selector(pronounce(_:)))
        b.accessibilityValue = text; b.backgroundColor = .clear; b.layer.borderWidth = 0; return b
    }
    @objc private func pronounce(_ sender: UIButton) {
        #if !targetEnvironment(simulator)
        guard hasFullAccess else { note = "Для произношения включи «Полный доступ» клавиатуры."; render(); return }
        #endif
        guard let text = sender.accessibilityValue, speech.speak(text) else { note = "Английский голос недоступен. Проверь голоса в настройках iPhone."; render(); return }
    }
    private func cancelStudyAction() { studyGeneration += 1; studyRequest?.cancel(); studyRequest = nil; studyBusy = false; speech.stop() }
    private func performStudyAction(_ action: StudyAction, source: String, apply: @escaping (StudyActionResult) -> Void) {
        if studyBusy { cancelStudyAction(); note = "Запрос отменён."; render(); return }
        #if !targetEnvironment(simulator)
        guard hasFullAccess else { note = "Для AI включи «Полный доступ» клавиатуры."; render(); return }
        #endif
        guard let config = connection else { note = "Подключи AI в настройках easytalk."; render(); return }
        cancelStudyAction(); let token = studyGeneration; studyBusy = true; note = ""; render()
        studyRequest = StudyActionOperation(action, source: source, config: config) { [weak self] result in
            guard let self, token == self.studyGeneration else { return }
            self.studyRequest = nil; self.studyBusy = false
            switch result {
            case .success(let value): apply(value); self.note = ""
            case .failure(let error):
                self.note = error == .incomplete ? "AI вернул неполный ответ. Попробуй ещё раз." : error.message.replacingOccurrences(of: "Перевод", with: "Запрос").replacingOccurrences(of: "перевод", with: "запрос")
            }; self.render()
        }
    }
    @objc private func rephraseLesson() {
        guard store.lessons.indices.contains(lessonIndex) else { return }; let lesson = store.lessons[lessonIndex]
        performStudyAction(.rephrase, source: lesson.response.corrected) { [weak self] value in
            guard case .variants(let variants) = value else { return }; self?.store.setVariants(variants, lesson: lesson.id); self?.expandedVariantLessons.insert(lesson.id)
        }
    }
    @objc private func refineWord(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier.flatMap(UUID.init(uuidString:)), let word = store.words.first(where: { $0.id == id }) else { return }
        performStudyAction(.dictionary, source: word.displayTerm) { [weak self] value in
            guard let self, case .dictionary(let entry) = value else { return }
            self.store.setDictionary(entry, word: id); self.game?.refresh(from: self.practice.pool(words: self.store.words))
        }
    }
    private func primaryButton(_ text: String, action: Selector) -> UIButton {
        let b = button(text, height: 44, action: action); b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        EasyTalkTheme.style(b, primary: true); return b
    }
    @objc private func changeDictionaryFilter(_ sender: UIButton) {
        guard let filter = VocabularyFilter(rawValue: sender.tag) else { return }
        dictionaryFilter = filter; lessonScroll.setContentOffset(.zero, animated: false); render()
    }
    private func renderDictionaryFilters() {
        empty(dictionaryFilters); dictionaryFilters.spacing = 14; dictionaryFilters.alignment = .center
        dictionaryFilters.accessibilityIdentifier = "dictionary-filters"
        let spacer = UIView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        dictionaryFilters.addArrangedSubview(spacer)
        for filter in VocabularyFilter.allCases {
            let selected = dictionaryFilter == filter
            let choice = link(filter.title, action: #selector(changeDictionaryFilter(_:)))
            choice.tag = filter.rawValue; choice.accessibilityIdentifier = "dictionary-filter-\(filter.rawValue)"
            choice.setContentHuggingPriority(.required, for: .horizontal)
            choice.setContentCompressionResistancePriority(.required, for: .horizontal)
            choice.isEnabled = !selected
            if selected {
                choice.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
                choice.setTitleColor(EasyTalkTheme.ink, for: .disabled); choice.accessibilityTraits = [.selected]
            }
            choice.accessibilityLabel = "\(filter.title)\(selected ? ", выбран" : "")"
            dictionaryFilters.addArrangedSubview(choice)
        }
        lessonContent.addArrangedSubview(dictionaryFilters)
    }
    @objc private func toggleDictionaryCard(_ sender: UIButton) {
        let id = sender.accessibilityIdentifier; expandedCardID = expandedCardID == id ? nil : id; render()
    }
    @objc private func changeWordMastery(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier else { return }
        practice.setLearned(id, !practice.isLearned(id)); game = nil; render()
    }
    private func renderVocabulary() {
        renderDictionaryFilters()
        let entries = practice.dictionaryCards(words: store.words, filter: dictionaryFilter)
        if entries.isEmpty {
            let text = dictionaryFilter == .learned ? "Выученные слова появятся здесь." : (dictionaryFilter == .inGame ? "Все твои слова уже выучены." : "Сохраняй слова ссылкой «В словарь» у правки.")
            lessonContent.addArrangedSubview(label(text, size: 18)); return
        }
        for item in entries {
            let card = WarmCard(padding: 12)
            let term = label(item.term, size: 21, weight: .semibold)
            term.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let speaker = speechButton(item.term); speaker.accessibilityIdentifier = "dictionary-speaker"
            let termLine = UIStackView(arrangedSubviews: [term, speaker]); termLine.spacing = 3; termLine.alignment = .center
            termLine.accessibilityIdentifier = "dictionary-term"; termLine.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let reveal = iconButton(expandedCardID == item.id ? "chevron.up" : "chevron.down", label: "Примеры для \(item.term)", action: #selector(toggleDictionaryCard(_:)))
            reveal.backgroundColor = .clear; reveal.layer.borderWidth = 0
            reveal.setImage(UIImage(systemName: expandedCardID == item.id ? "chevron.up" : "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)), for: .normal)
            reveal.accessibilityIdentifier = item.id
            let gap = UIView(); gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [termLine, gap, reveal]); row.spacing = 5; row.alignment = .top
            card.addArrangedSubview(row); card.addArrangedSubview(label(item.meaning, size: 17))
            if expandedCardID == item.id {
                for example in item.examples { card.addArrangedSubview(exampleLabel(term: item.term, context: example)) }
                if item.personal {
                    let refine = link(studyBusy ? "Отменить запрос" : "Подробней о слове", action: #selector(refineWord(_:)))
                    refine.accessibilityIdentifier = String(item.id.dropFirst("word.".count)); card.addArrangedSubview(refine)
                    let remove = link("Удалить из словаря", action: #selector(removeWord(_:)))
                    remove.accessibilityIdentifier = String(item.id.dropFirst("word.".count)); card.addArrangedSubview(remove)
                }
            }
            let learned = practice.isLearned(item.id)
            let mastery = link(learned ? "Вернуть в карточки" : "Выучил", action: #selector(changeWordMastery(_:)))
            mastery.accessibilityIdentifier = item.id; mastery.contentHorizontalAlignment = .right
            card.addArrangedSubview(mastery); lessonContent.addArrangedSubview(card)
        }
    }
    private func renderGame() {
        guard preferences.secondSkillEnabled else { return }
        if game == nil { game = StudySession(candidates: practice.candidates(words: store.words)); gameFinishedRecorded = false }
        guard let game else { return }
        let pages = game.cards.enumerated().map { makeGameCard($0.element, index: $0.offset, back: $0.offset == game.index && game.showingBack) }
        let end = WarmCard()
        end.addArrangedSubview(label(game.initialCount == 0 ? "Все карточки отмечены" : (preferences.rewardsEnabled ? "✨ Маленький шаг вперёд!" : "Повторение завершено"), size: 23, weight: .bold))
        end.addArrangedSubview(label(game.initialCount == 0 ? "Можно повторить выученное или добавить новые слова в словарь." : "Выучено в этом раунде: \(game.rememberedCount). Раунд завершён.", size: 18))
        end.addArrangedSubview(primaryButton("Вернуться в словарь", action: #selector(closeGame)))
        
        if !game.cards.isEmpty { end.addArrangedSubview(label("Свайп вправо — вернуться к карточкам", size: 15)) }
        cardPager.onPage = { [weak self, weak game] index in
            guard let self, let game, self.game === game, self.showingGame, index != game.index else { return }
            self.speech.stop()
            while game.index != index { guard game.move(by: index > game.index ? 1 : -1) else { break } }
            self.finishGameMove()
        }
        cardPager.configure(pages + [end], index: game.index)
        cardPager.accessibilityIdentifier = game.showingBack ? "practice-back" : "practice-front"
        if cardPager.constraints.first(where: { $0.firstAttribute == .height && $0.secondItem == nil }) == nil { fixedHeight(cardPager, 256) }
        lessonContent.addArrangedSubview(cardPager)
    }
    private func makeGameCard(_ item: StudyCard, index: Int, back: Bool) -> UIView {
        let card = WarmCard(padding: 12); card.spacing = 6
        let tap = UITapGestureRecognizer(target: self, action: #selector(flipGameCard)); tap.delegate = self
        tap.require(toFail: cardPager.panGestureRecognizer); card.addGestureRecognizer(tap)
        let progress = label(learnedFeedback ?? "\(index + 1) / \(game!.cards.count)", size: 14, weight: learnedFeedback == nil ? .regular : .semibold)
        progress.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let head = UIStackView(arrangedSubviews: [progress, speechButton(item.term)]); head.spacing = 10
        if back {
            let remember = link(preferences.speakerGender == .female ? "Запомнила" : "Запомнил", action: #selector(learnGameCard))
            remember.accessibilityIdentifier = "remember-card"; remember.setContentHuggingPriority(.required, for: .horizontal)
            remember.setContentCompressionResistancePriority(.required, for: .horizontal)
            head.addArrangedSubview(remember)
        }
        head.accessibilityIdentifier = "practice-header"; head.alignment = .center; card.addArrangedSubview(head)
        let body = UIScrollView(); body.showsVerticalScrollIndicator = true; body.isDirectionalLockEnabled = true
        let content = UIStackView(); content.axis = .vertical; content.spacing = 7; content.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: body.contentLayoutGuide.topAnchor, constant: 2), content.bottomAnchor.constraint(equalTo: body.contentLayoutGuide.bottomAnchor, constant: -2),
            content.leadingAnchor.constraint(equalTo: body.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: body.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: body.frameLayoutGuide.widthAnchor)
        ])
        card.addArrangedSubview(body)
        if !back {
            content.distribution = .equalSpacing
            let fill = content.heightAnchor.constraint(greaterThanOrEqualTo: body.frameLayoutGuide.heightAnchor, constant: -4); fill.priority = .defaultHigh; fill.isActive = true
            let origin = label(item.personal ? "ИЗ ТВОЕГО СЛОВАРЯ" : "АНГЛИЙСКОЕ ВЫРАЖЕНИЕ", size: 12, weight: .medium)
            origin.textColor = EasyTalkTheme.secondary; origin.textAlignment = .center; content.addArrangedSubview(origin)
            let question = label(item.term, size: 28, weight: .semibold); question.textAlignment = .center
            question.accessibilityCustomActions = cardAccessibilityActions(); question.accessibilityIdentifier = "practice-question"; content.addArrangedSubview(question)
            let hint = label("Тап — переворот · свайп — дальше", size: 14); hint.textColor = EasyTalkTheme.secondary; hint.textAlignment = .center; content.addArrangedSubview(hint)
        } else {
            let meaning = label(item.meaning, size: 28, weight: .semibold); meaning.accessibilityIdentifier = "practice-meaning"
            meaning.accessibilityCustomActions = cardAccessibilityActions(); content.addArrangedSubview(meaning)
            let term = label(item.term, size: 16, weight: .medium); term.textColor = EasyTalkTheme.secondary; content.addArrangedSubview(term)
            content.addArrangedSubview(separator())
            for example in item.examples { content.addArrangedSubview(exampleLabel(term: item.term, context: example)) }
            if !item.lexical { let note = label("Перевод из твоей фразы", size: 14); note.textColor = EasyTalkTheme.secondary; content.addArrangedSubview(note) }
            if item.personal {
                let refine = link(studyBusy ? "Отменить запрос" : "Подробней о слове", action: #selector(refineWord(_:)))
                refine.accessibilityIdentifier = String(item.id.dropFirst("word.".count)); content.addArrangedSubview(refine)
            }
        }
        return card
    }
    private func cardAccessibilityActions() -> [UIAccessibilityCustomAction] {
        [UIAccessibilityCustomAction(name: "Перевернуть карточку", target: self, selector: #selector(accessibilityFlipCard)),
         UIAccessibilityCustomAction(name: "Следующая карточка", target: self, selector: #selector(accessibilityNextCard)),
         UIAccessibilityCustomAction(name: "Предыдущая карточка", target: self, selector: #selector(accessibilityPreviousCard))]
    }
    @objc private func accessibilityFlipCard() -> Bool { guard !flippingCard && !swipingCard else { return false }; flipGameCard(); return true }
    @objc private func accessibilityNextCard() -> Bool { moveGameCard(by: 1) }
    @objc private func accessibilityPreviousCard() -> Bool { moveGameCard(by: -1) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touched = touch.view
        while let view = touched { if view is UIControl { return false }; touched = view.superview }
        return true
    }
    @objc private func flipGameCard() { flipCard(animated: true) }
    private func flipCard(animated: Bool) {
        guard !flippingCard, !swipingCard, !archivingCard, showingGame, let game, game.flip() else { return }
        lessonScroll.setContentOffset(.zero, animated: false)
        guard animated && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled else { render(); return }
        flippingCard = true; cardPager.isScrollEnabled = false
        let direction: UIView.AnimationOptions = game.showingBack ? .transitionFlipFromRight : .transitionFlipFromLeft
        UIView.transition(with: lessonContent, duration: 0.42, options: [direction, .curveEaseInOut], animations: {
            self.renderStudy(); self.view.layoutIfNeeded()
        }, completion: { [weak self] _ in self?.flippingCard = false; self?.cardPager.isScrollEnabled = true })
    }
    @objc private func toggleOriginal() { showingOriginal.toggle(); render() }
    @objc private func startGame() { beginGame(reviewLearned: false) }
    private func beginGame(reviewLearned: Bool) { cancelStudyAction();
        guard preferences.secondSkillEnabled else { return }
        feedbackTimer?.invalidate(); learnedFeedback = nil; clearReward(); game = StudySession(candidates: practice.candidates(words: store.words, reviewLearned: reviewLearned))
        gameFinishedRecorded = false; flippingCard = false; cardPager.isScrollEnabled = true; showingStudy = true; showingSettings = false; showingVocabulary = false; showingGame = true
        studyTabs.selectedSegmentIndex = 1; lessonScroll.setContentOffset(.zero, animated: false); render()
    }
    @objc private func learnGameCard() { archiveGameCard(animated: true) }
    private func archiveGameCard(animated: Bool) {
        guard !flippingCard, !swipingCard, !archivingCard, let game, let item = game.archiveCurrent() else { return }
        cancelStudyAction(); practice.setLearned(item.id, true)
        learnedFeedback = preferences.rewardsEnabled ? "🌟 +1 выученное слово" : "Слово в «Выучил»"
        feedbackTimer?.invalidate()
        UIAccessibility.post(notification: .announcement, argument: "\(item.term). Слово выучено.")
        let finish = { [weak self, weak game] in
            guard let self else { return }; self.archivingCard = false; self.cardPager.alpha = 1; self.cardPager.transform = .identity; self.cardPager.isUserInteractionEnabled = true
            guard let game, self.game === game, self.showingGame else { return }
            self.finishGameMove()
            let timer = Timer(timeInterval: 1.8, repeats: false) { [weak self] _ in self?.learnedFeedback = nil; self?.render() }
            self.feedbackTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        guard animated && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled else { finish(); return }
        archivingCard = true; cardPager.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.22, animations: { self.cardPager.alpha = 0; self.cardPager.transform = CGAffineTransform(translationX: -36, y: 0) }, completion: { _ in finish() })
    }
    @objc private func nextGameCard() { _ = moveGameCard(by: 1) }
    @discardableResult private func moveGameCard(by direction: Int) -> Bool {
        guard !flippingCard, !swipingCard, !archivingCard, showingGame, let game, game.move(by: direction) else { return false }
        finishGameMove(); return true
    }
    private func finishGameMove() {
        guard let game else { return }
        if game.finished && game.initialCount > 0 && !gameFinishedRecorded {
            gameFinishedRecorded = true; practice.finishSession()
            if preferences.rewardsEnabled { view.layoutIfNeeded(); celebration.play() }
        }
        lessonScroll.setContentOffset(.zero, animated: false); render()
    }
    @objc private func closeGame() { cancelStudyAction(); feedbackTimer?.invalidate(); learnedFeedback = nil;
        game = nil; flippingCard = false; cardPager.isScrollEnabled = true; gameFinishedRecorded = false; showingGame = false; showingVocabulary = true; studyTabs.selectedSegmentIndex = dictionaryTabIndex
        celebration.stop(); lessonScroll.setContentOffset(.zero, animated: false); render()
    }
    private func exampleLabel(term: String, context: String) -> UILabel {
        let text = context.split(whereSeparator: { $0.isNewline }).first(where: { $0.range(of: term, options: .caseInsensitive) != nil }).map(String.init) ?? context
        let example = label(text, size: 18)
        let marked = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 18)])
        if let range = text.range(of: term, options: .caseInsensitive) {
            marked.addAttributes([.font: UIFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: UIColor.systemBlue], range: NSRange(range, in: text))
        }
        example.attributedText = marked; return example
    }
    private func cancelRequest() {
        cancelStudyAction()
        generation += 1; request?.cancel(); request = nil; pending = nil; busy = false; revisingMeaning = false
        progressTimer?.invalidate(); progressTimer = nil
    }

    private func snapshot() -> InputSnapshot {
        if let previewSnapshot { return previewSnapshot() }
        let p = textDocumentProxy
        return InputSnapshot(document: EasyTalkDocumentIdentifier(p) as UUID?, before: p.documentContextBeforeInput, after: p.documentContextAfterInput, selected: p.selectedText)
    }
    /// Automatic history: a field emptied by the host app (not by our delete key) was sent.
    private func recordSentText() {
        guard preferences.historyEnabled, previewSnapshot == nil else { return }
        let p = textDocumentProxy
        guard let sent = sentDetector.observe(document: EasyTalkDocumentIdentifier(p) as UUID?, before: p.documentContextBeforeInput,
                                              after: p.documentContextAfterInput, selected: p.selectedText) else { return }
        // Text produced by «Перевести» keeps the user's original and the corrected English.
        let lesson = store.lessons.first { lesson in
            let translated = lesson.response.translated.trimmingCharacters(in: .whitespacesAndNewlines)
            return !translated.isEmpty && sent.contains(translated)
        }
        history.reload(); history.add(sent, source: lesson?.source, corrected: lesson?.response.corrected)
    }
    private func type(_ value: String) {
        sentDetector.noteInsertion()
        cancelRequest(); clearReward(); translatedSnapshot = nil; note = ""
        if let previewType { previewType(value) } else { textDocumentProxy.insertText(value) }; updateAutoShift(); updateSuggestions(); render()
    }
    private func backspace() {
        sentDetector.noteDeletion()
        cancelRequest(); clearReward(); translatedSnapshot = nil; note = ""; if let previewDelete { previewDelete() } else { textDocumentProxy.deleteBackward() }; updateAutoShift(); updateSuggestions(); render()
    }
    private func toggleLanguage() { russian.toggle(); preferences.russianLayout = russian; rebuildKeys(); updateAutoShift() }
    private func toggleNumbers() { numbers.toggle(); symbols = false; shifted = false; rebuildKeys() }
    private func toggleShift() {
        if numbers { symbols.toggle(); rebuildKeys(); return }
        let now = Date()
        if capsLock { capsLock = false; shifted = false }
        else if shifted && !autoShift && now.timeIntervalSince(lastShiftTap) < 0.35 { capsLock = true; shifted = true }
        else { shifted.toggle() }
        autoShift = false; lastShiftTap = now; updateCase()
    }
    @objc private func toggleSettings() { cancelStudyAction(); showingSettings.toggle(); showingStudy = false; showingContext = false; render() }
    static let contextHeight: CGFloat = 196
    @objc private func toggleContext() {
        cancelStudyAction(); showingContext.toggle(); showingSettings = false; showingStudy = false
        contextMessage.text = nil; history.reload(); render()
    }
    private func renderContext() {
        let period = preferences.contextPeriod
        if contextPeriods.arrangedSubviews.isEmpty {
            for (index, item) in HistoryPeriod.allCases.enumerated() {
                let chip = button(item == .halfHour ? "30 мин" : (item == .all ? "Всё" : item.title), height: 34, action: #selector(chooseContextPeriod(_:)))
                chip.tag = index; chip.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
                chip.titleLabel?.adjustsFontSizeToFitWidth = true; chip.titleLabel?.minimumScaleFactor = 0.8
                chip.accessibilityLabel = "Период: " + item.title
                contextPeriods.addArrangedSubview(chip)
            }
        }
        for case let chip as UIButton in contextPeriods.arrangedSubviews {
            let selected = HistoryPeriod.allCases.indices.contains(chip.tag) && HistoryPeriod.allCases[chip.tag] == period
            chip.backgroundColor = selected ? EasyTalkTheme.creamEnd : .clear; chip.layer.cornerRadius = 9
            chip.layer.borderWidth = selected ? 1 : 0; chip.layer.borderColor = EasyTalkTheme.border.resolvedColor(with: traitCollection).cgColor
            chip.isSelected = selected; chip.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        let count = history.entries(in: period).count
        contextSummary.text = count == 0 ? "Сообщений \(period.phrase) нет" : "Сообщений \(period.phrase): \(count)"
        contextMessage.isHidden = contextMessage.text == nil
    }
    @objc private func chooseContextPeriod(_ sender: UIButton) {
        guard HistoryPeriod.allCases.indices.contains(sender.tag) else { return }
        preferences.contextPeriod = HistoryPeriod.allCases[sender.tag]; contextMessage.text = nil; render()
    }
    @objc private func copyContext() {
        guard hasFullAccess else { contextMessage.text = "Включи «Полный доступ» клавиатуры, чтобы копировать."; render(); return }
        let period = preferences.contextPeriod; history.reload()
        let entries = history.entries(in: period)
        guard !entries.isEmpty else { contextMessage.text = "Нечего копировать: выбери период длиннее."; render(); return }
        UIPasteboard.general.setItems([["public.utf8-plain-text": ContextExport.text(entries: entries, period: period)]], options: [.localOnly: true])
        contextMessage.text = "Скопировано: \(entries.count). Вставь в чат любого ИИ."
        UIAccessibility.post(notification: .announcement, argument: contextMessage.text); render()
    }
    @objc private func pasteWords() {
        guard hasFullAccess else { contextMessage.text = "Включи «Полный доступ» клавиатуры, чтобы вставить слова."; render(); return }
        let words = WordImport.parse(UIPasteboard.general.string ?? "")
        guard !words.isEmpty else { contextMessage.text = "В буфере нет списка слов. Скопируй ответ ИИ целиком."; render(); return }
        store.reloadWords(); let added = store.importWords(words)
        contextMessage.text = added == 0 ? "Все \(words.count) слов уже в словаре." : "Добавлено в словарь: \(added)." + (words.count > added ? " Уже были: \(words.count - added)." : "")
        UIAccessibility.post(notification: .announcement, argument: contextMessage.text); render()
    }
    @objc private func toggleStudy() { cancelStudyAction();
        showingStudy = true; showingSettings = false; showingVocabulary = false; showingGame = false; analysisFailed = false; note = ""
        studyHostSnapshot = snapshot(); lessonIndex = 0; studyTabs.selectedSegmentIndex = 0; markCurrentRead(); lessonScroll.setContentOffset(.zero, animated: false); render()
    }
    @objc private func changeStudyTab() { cancelStudyAction();
        if busy { cancelRequest() }
        analysisFailed = false; note = ""
        showingVocabulary = studyTabs.selectedSegmentIndex == dictionaryTabIndex; showingGame = preferences.secondSkillEnabled && studyTabs.selectedSegmentIndex == 1
        if showingGame && (game == nil || game!.finished) { beginGame(reviewLearned: false); return }
        if !showingVocabulary && !showingGame { markCurrentRead() }
        lessonScroll.setContentOffset(.zero, animated: false); render()
    }
    private func markCurrentRead() { if !showingVocabulary && !showingGame && store.lessons.indices.contains(lessonIndex) { store.markRead(store.lessons[lessonIndex].id) } }
    @objc private func toggleSession() { sessionExpanded.toggle(); render() }
    @objc private func chooseSessionLesson(_ sender: UIButton) { cancelRequest(); lessonIndex = sender.tag; sessionExpanded = false; showingOriginal = false; markCurrentRead(); lessonScroll.setContentOffset(.zero, animated: false); render() }
    @objc private func saveWord(_ sender: UIButton) {
        guard store.lessons.indices.contains(lessonIndex) else { return }; let lesson = store.lessons[lessonIndex]
        let words = lesson.response.studyVocabulary
        guard words.indices.contains(sender.tag) else { return }
        let offset = lessonScroll.contentOffset
        store.save(words[sender.tag], lesson: lesson); render(); lessonScroll.layoutIfNeeded()
        lessonScroll.setContentOffset(offset, animated: false)
    }
    @objc private func dismissWord(_ sender: UIButton) { changeSuggestion(sender, restore: false) }
    @objc private func restoreWord(_ sender: UIButton) { changeSuggestion(sender, restore: true) }
    private func changeSuggestion(_ sender: UIButton, restore: Bool) {
        guard store.lessons.indices.contains(lessonIndex) else { return }
        let lesson = store.lessons[lessonIndex], words = store.lessons[lessonIndex].response.studyVocabulary
        guard words.indices.contains(sender.tag) else { return }
        let offset = lessonScroll.contentOffset
        if restore { store.restoreSuggestion(words[sender.tag].term, lesson: lesson.id) }
        else { store.dismiss(words[sender.tag].term, lesson: lesson.id) }
        render(); lessonScroll.layoutIfNeeded(); lessonScroll.setContentOffset(offset, animated: false)
    }
    @objc private func removeWord(_ sender: UIButton) {
        guard let value = sender.accessibilityIdentifier, let id = UUID(uuidString: value) else { return }
        store.removeWord(id); practice.setLearned("word." + value, false); render()
    }
    @objc private func clearHistory() { cancelRequest(); store.clearLessons(); lessonIndex = 0; sessionExpanded = false; expandedTranslations.removeAll(); lastTranslationDocument = nil; note = "Занятие завершено. Словарь сохранён."; render() }

    @objc private func clarifyMeaning() {
        guard store.lessons.indices.contains(lessonIndex) else { return }
        let lesson = store.lessons[lessonIndex], captured = snapshot()
        guard let meaning = editedRussianMeaning(for: lesson) else {
            note = "Измени русский текст в поле сообщения: курсор может стоять в любом месте абзаца."; render(); return
        }
        guard lessonIndex == 0 else { note = "Уточнить можно последний перевод. Выбери его в разборах занятия."; render(); return }
        if let document = lastTranslationDocument, document != captured.document {
            note = "Вернись в поле последнего перевода, чтобы уточнить его смысл."; render(); return
        }
        guard var config = connection, config.url != nil, hasFullAccess else {
            note = "Для уточнения подключи AI и включи «Полный доступ»."; render(); return
        }
        config.speakerGender = preferences.speakerGender
        cancelRequest(); clearReward(); let token = generation, started = Date()
        pending = captured; busy = true; revisingMeaning = true; analysisFailed = false; note = "Уточняю смысл…"; render()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.busy else { return }
            self.note = "Уточняю смысл… \(Int(Date().timeIntervalSince(started))) с. Можно отменить."; self.render()
        }
        request = AnalysisOperation(source: lesson.source, config: config, intendedMeaning: meaning) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.busy = false; self.revisingMeaning = false; self.request = nil; self.pending = nil
                self.progressTimer?.invalidate(); self.progressTimer = nil
                switch result {
                case .success(let response): _ = self.finishMeaningRevision(response, captured: captured, lessonID: lesson.id)
                case .failure(let failure): self.note = failure.message + " Прежний разбор сохранён."
                }
                self.render()
            }
        }
    }
    @discardableResult private func finishMeaningRevision(_ response: LearningResponse, captured: InputSnapshot, lessonID: UUID) -> Bool {
        guard let meaning = currentRussianText(from: captured), snapshot() == captured, store.lessons.first?.id == lessonID,
              store.revise(lessonID, meaning: meaning, response: response) else {
            note = "Текст изменился. Прежний разбор сохранён; уточни смысл ещё раз."; return false
        }
        // The user's revised Russian text remains untouched in the host application.
        translatedSnapshot = captured; lastTranslationDocument = captured.document
        lessonIndex = 0; expandedVariantLessons.remove(lessonID); showingOriginal = false
        showingStudy = true; showingVocabulary = false; showingGame = false; analysisFailed = false
        studyTabs.selectedSegmentIndex = 0; note = "Разбор обновлён по твоему смыслу."; return true
    }

    @objc private func translateInput() {
        if busy { let revision = revisingMeaning; cancelRequest(); showingStudy = revision; note = revision ? "Уточнение отменено. Прежний разбор сохранён." : "Перевод отменён. Текст сохранён."; render(); return }
        let captured = snapshot()
        guard let source = captured.source else { note = "Напиши текст в поле сообщения или выдели фрагмент для перевода."; render(); return }
        guard captured.canReplace else { note = "Напиши текст в поле сообщения, затем нажми «Перевести»."; render(); return }
        guard source.unicodeScalars.count <= 2000 else { note = "Выдели фрагмент до 2000 символов."; render(); return }
        guard var config = connection, config.url != nil else {
            note = "AI ещё не подключён. Добавь ключ в настройках приложения easytalk."; showingSettings = true; render(); return
        }
        guard hasFullAccess else { note = "Для перевода включи «Полный доступ» в настройках клавиатуры iPhone."; render(); return }
        config.speakerGender = preferences.speakerGender
        cancelRequest(); clearReward(); let expectedGeneration = generation; let started = Date()
        pending = captured; busy = true; showingSettings = false; showingStudy = true; showingGame = false; showingVocabulary = false; studyTabs.selectedSegmentIndex = 0; analysisFailed = false; note = "Перевожу… 0 с"; render()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.busy else { return }
            let action = (self.request?.attempts ?? 1) > 1 ? "Проверяю разбор" : "Перевожу"
            self.note = "\(action)… \(Int(Date().timeIntervalSince(started))) с. Можно отменить."; self.render()
        }
        request = AnalysisOperation(source: source, config: config) { [weak self] result, trace in
            DispatchQueue.main.async {
                guard let self, self.generation == expectedGeneration else { return }
                self.busy = false; self.request = nil; self.pending = nil
                self.progressTimer?.invalidate(); self.progressTimer = nil
                let elapsed = Int(Date().timeIntervalSince(started))
                let detail: String
                switch result {
                case .success(let analysis):
                    detail = self.finishTranslation(analysis, captured: captured) ? "OK" : "stale"; if detail != "OK" { self.analysisFailed = true }
                case .failure(let failure):
                    detail = failure.code; self.analysisFailed = true; self.note = failure.message(details: trace.response) + " Исходный текст сохранён."
                }
                // Only timing and failure codes; never store keys, request bodies or user text.
                let diagnostic = "Последний перевод: \(elapsed) с · \(detail) · запросов \(trace.attempts)"
                self.diagnostic.text = diagnostic; self.diagnostic.isHidden = false
                UserDefaults.standard.set(diagnostic, forKey: "ai.lastDiagnostic"); self.render()
            }
        }
    }
    @discardableResult private func finishTranslation(_ result: LearningResponse, captured: InputSnapshot) -> Bool {
        guard let source = captured.source, result.isValid(for: source), snapshot() == captured else {
            note = "Поле или текст изменились. Нажми «Перевести» ещё раз."; return false
        }
        applying = true; defer { applying = false }
        if let previewReplace {
            guard previewReplace(captured, result.translated) else { note = "Не удалось заменить текст."; return false }
        } else if captured.isSelection { textDocumentProxy.insertText(result.translated) }
        else {
            // Delete only the accessible paragraph (both sides of the caret); preserve other paragraphs.
            if captured.trailingUTF16 > 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: captured.trailingUTF16) }
            for _ in source { textDocumentProxy.deleteBackward() }; textDocumentProxy.insertText(result.translated)
        }
        store.record(source: source, response: result); lessonIndex = 0; expandedVariantLessons.removeAll(); showingOriginal = false
        showingStudy = true; showingVocabulary = false; showingGame = false; analysisFailed = false; studyTabs.selectedSegmentIndex = 0
        translatedSnapshot = snapshot(); studyHostSnapshot = translatedSnapshot; lastTranslationDocument = captured.document
        let praise = rewards.record(source: source, hasErrors: result.hasErrors)
        note = ""
        if preferences.rewardsEnabled, let praise { showReward(praise) }
        if showingStudy { markCurrentRead() }; return true
    }
    private func showReward(_ title: String) {
        clearReward(); rewardTitle.text = title; render(); view.layoutIfNeeded()
        if !showingSettings { celebration.play() }
        UIAccessibility.post(notification: .announcement, argument: title + " Английский без ошибок.")
        let timer = Timer(timeInterval: 4, repeats: false) { [weak self] _ in self?.clearReward(); self?.render() }
        rewardTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func clearReward() { rewardTimer?.invalidate(); rewardTimer = nil; rewardTitle.text = nil; celebration.stop() }
    @objc private func dismissReward() { clearReward(); render() }
    @objc private func disconnectAI() {
        if connection != nil && !ConnectionStore.delete() { note = "Включи «Полный доступ», чтобы удалить подключение."; render(); return }
        cancelRequest(); connection = nil; showingSettings = false; note = "AI отключён. Обычный ввод работает."; render()
    }
    #if targetEnvironment(simulator)
    /// Exercise UIKit's real detached proxy before the preview supplies a field.
    /// Previously viewDidLoad crashed here while force-bridging a nil NSUUID.
    func runStartupRegression() {
        precondition(previewSnapshot == nil)
        loadViewIfNeeded(); viewWillAppear(false)
        let detached = snapshot()
        precondition(detached.document == nil && !detached.canReplace && detached.source == nil)
        textDidChange(nil); selectionDidChange(nil)
        viewWillDisappear(false); viewWillAppear(false)
        precondition(!keys.isHidden && letterKeys.count == 26)
        precondition(!hasDictationKey, "iOS must be allowed to provide its dictation key")
        let buttons = allButtons(in: view)
        precondition(!buttons.contains { ["voice-microphone", "voice-microphone-launch", "insert-voice-text"].contains($0.accessibilityIdentifier ?? "") }, "No app hop or manual dictation insertion controls")
        precondition(!root.arrangedSubviews.contains { $0 is UITextView }, "No intermediate transcript editor")
        // A detached UIInputViewController may not expose primaryLanguage:
        // UIKit owns the input-mode connection. Do not mistake nil for failure.
        let report: [String: Any] = ["result": "passed", "missing_document": true, "letter_keys": letterKeys.count,
            "startup_and_lifecycle": true, "replacement_blocked": true,
            "system_dictation_key_allowed": !hasDictationKey, "custom_voice_launch_controls": 0,
            "intermediate_dictation_fields": 0,
            "primary_language_observed": primaryLanguage ?? "unavailable-in-detached-controller"]
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-startup-check.json")
        try! JSONSerialization.data(withJSONObject: report, options: .sortedKeys).write(to: path)
    }
    func preparePreview(_ state: String) {
        loadViewIfNeeded(); translatedSnapshot = nil; let defaults = UserDefaults(suiteName: "easytalk.preview")!
        defaults.removePersistentDomain(forName: "easytalk.preview"); store = LearningStore(defaults: defaults); preferences = KeyboardPreferences(defaults: defaults); practice = StudyProgressStore(defaults: defaults); rewards = RewardProgress(defaults: defaults); rebuildKeys(); connection = nil; note = ""
        if ["words", "wordcards"].contains(state) { _ = finishTranslation(Self.multiFixture, captured: snapshot()); toggleStudy() }
        if ["translated", "study", "vocabulary"].contains(state) {
            _ = finishTranslation(Self.fixture, captured: snapshot()); if state != "translated" { toggleStudy() }
            if state == "vocabulary" { let b = UIButton(); b.tag = 0; saveWord(b); studyTabs.selectedSegmentIndex = dictionaryTabIndex; changeStudyTab() }
        }; render()
        if state == "settings" { toggleSettings() }
        if state == "reward" {
            let source = snapshot().source!
            _ = finishTranslation(LearningResponse(schema_version: 1, corrected: source, translated: "Я хочу учить английский", diffs: [], vocabulary: []), captured: snapshot()); render()
        }
        if state == "dictionary" {
            _ = finishTranslation(Self.multiFixture, captured: snapshot()); toggleStudy()
            let b = UIButton(); for i in 0..<3 { b.tag = i; saveWord(b) }
            studyTabs.selectedSegmentIndex = dictionaryTabIndex; changeStudyTab()
        }
        if ["game", "game-answer", "game-back", "game-flip", "game-done"].contains(state) {
            startGame()
            if ["game-answer", "game-back"].contains(state) { flipCard(animated: false) }
            if state == "game-flip" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.flipGameCard() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.flipGameCard() }
            }
            if state == "game-done", let game {
                while game.current != nil { _ = game.flip(); nextGameCard() }
            }
        }

        if state == "successful-back" {
            store.saveEntry(VocabularyEntry(term: "successful", meaning: "удачных", kind: "word", originalContext: "", correctedContext: "We had successful meetings."))
            game = StudySession(candidates: practice.pool(words: store.words)); showingStudy = true; showingGame = true; showingVocabulary = false; studyTabs.selectedSegmentIndex = 1
            flipCard(animated: false); render()
        }
        if ["benefit-archive", "game-achievement"].contains(state) {
            store.saveEntry(VocabularyEntry(term: "benefit", meaning: "пользу", kind: "word", originalContext: "", correctedContext: "It brings a benefit."))
            game = StudySession(candidates: practice.pool(words: store.words)); showingStudy = true; showingGame = true; showingVocabulary = false; studyTabs.selectedSegmentIndex = 1
            flipCard(animated: false); archiveGameCard(animated: false)
            if state == "benefit-archive" { closeGame(); dictionaryFilter = .learned; render() }
        }
        if state == "variants" {
            store.record(source: "I like coffee", response: LearningResponse(schema_version: 1, corrected: "I like coffee", translated: "Я люблю кофе", diffs: [], vocabulary: []))
            store.setVariants([PhraseVariant(label: "Нейтрально", text: "I enjoy drinking coffee.", explanation: "Та же мысль с глаголом enjoy."), PhraseVariant(label: "Разговорно", text: "I'm a coffee fan.", explanation: "Непринуждённый способ сказать о своей любви к кофе.")], lesson: store.lessons[0].id)
            expandedVariantLessons.insert(store.lessons[0].id); showingStudy = true; showingGame = false; render()
        }
        if state == "keypress" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.view.layoutIfNeeded()
                self.letterKeys.first?.0.press(at: .zero)
            }
        }
        if state == "wordcards" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.view.layoutIfNeeded(); self.lessonScroll.layoutIfNeeded()
                if let card = self.lessonContent.arrangedSubviews.first(where: { $0.accessibilityIdentifier == "suggestion-card-0" }) {
                    self.lessonScroll.setContentOffset(CGPoint(x: 0, y: max(0, card.frame.minY - 36)), animated: false)
                }
            }
        }
        if ["russian", "hard-sign", "trackpad", "clarification"].contains(state) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if state == "clarification" {
                    let captured = self.snapshot(); precondition(self.finishTranslation(Self.fixture, captured: captured))
                    precondition(self.previewReplace?(self.snapshot(), "Я предпочитаю чай") == true)
                    self.fieldChanged(); self.toggleStudy()
                } else {
                    self.russian = true; self.shifted = false; self.showingStudy = false; self.rebuildKeys(); self.render()
                    self.view.layoutIfNeeded()
                    if state == "hard-sign" {
                        let soft = self.letterKeys.first { $0.1 == "ь" }!.0
                        soft.press(at: CGPoint(x: soft.bounds.midX, y: 20)); soft.held()
                    } else if state == "trackpad" {
                        self.spaceKey?.press(at: CGPoint(x: 30, y: 24)); self.spaceKey?.held()
                    }
                }
                self.view.layoutIfNeeded()
                let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("visual-fixture-ready.txt")
                try! state.write(to: path, atomically: true, encoding: .utf8)
            }
        }
    }
    static let multiSource = "I want to купить coffee and встретиться with my друг"
    private static var multiFixture: LearningResponse {
        let pairs = [("купить", "buy"), ("встретиться", "meet"), ("друг", "friend")]
        let diffs = pairs.enumerated().map { index, pair -> LearningDiff in
            let range = multiSource.range(of: pair.0)!
            let start = multiSource[..<range.lowerBound].unicodeScalars.count
            return LearningDiff(id: "d\(index + 1)", type: .unknownWord, original: pair.0, corrected: pair.1,
                start: start, end: start + pair.0.unicodeScalars.count, explanation: "«\(pair.0)» — \(pair.1).")
        }
        return LearningResponse(schema_version: 1, corrected: "I want to buy coffee and meet with my friend",
            translated: "Я хочу купить кофе и встретиться с другом", diffs: diffs,
            vocabulary: pairs.map { VocabularySuggestion(term: $0.1, meaning: $0.0, kind: "word") })
    }
    func runMechanicsRegression() {
        showingStudy = false; showingSettings = false; note = ""; render(); view.layoutIfNeeded()
        let oldType = previewType, oldDelete = previewDelete, oldMove = previewMove, oldSnapshot = previewSnapshot
        var text = "", position = 0, deleteCount = 0
        previewType = { value in
            var chars = Array(text); chars.insert(contentsOf: Array(value), at: position)
            position += value.count; text = String(chars)
        }
        previewDelete = {
            if position > 0 { var chars = Array(text); chars.remove(at: position - 1); position -= 1; text = String(chars); deleteCount += 1 }
        }
        previewMove = { position = min(text.count, max(0, position + $0)) }
        let document = UUID()
        previewSnapshot = { InputSnapshot(document: document, before: String(text.prefix(position)), after: String(text.suffix(text.count - position)), selected: nil) }
        let letter = letterKeys.first { $0.1 == "a" }!.0
        letter.press(at: .zero); precondition(text == "a", "Touch-down must type immediately")
        letter.move(to: CGPoint(x: -20, y: -20)); letter.release(); precondition(text == "a", "Release outside must not lose or duplicate a tap")
        shiftKey!.press(at: .zero); shiftKey!.release()
        letter.press(at: .zero); letter.release()
        precondition(text == "aA" && letterKeys.first { $0.1 == "a" }!.0 === letter, "Shift must not rebuild keys during typing")
        let space = spaceKey!
        for _ in 0..<8 { space.press(at: .zero); space.release() }
        precondition(text == "aA" + String(repeating: " ", count: 8), "Fast space taps must each insert once")
        let original = text
        space.press(at: CGPoint(x: 30, y: 24)); space.held(); space.move(to: CGPoint(x: 10, y: 24)); space.release()
        precondition(text == original && position == text.count - 2, "Held space moves cursor without adding a space")
        letter.press(at: .zero); letter.release(); precondition(text.hasSuffix("a  "), "Typing after dragging must use the new cursor")
        space.press(at: .zero); space.release(cancelled: true); precondition(text.count == original.count + 1, "Cancelled space must not type")
        let row = letterRows[0]
        let first = row.arrangedSubviews[0], second = row.arrangedSubviews[1]
        let r1 = first.convert(first.bounds, to: keys), r2 = second.convert(second.bounds, to: keys)
        let gap = CGPoint(x: (r1.maxX + r2.minX) / 2, y: r1.midY)
        precondition(keys.hitTest(gap, with: nil) is KeyboardKey, "Visual gap must resolve to a key")
        precondition(space.bounds.width >= 140 && letter.bounds.height >= 48)
        // Vertical dragging preserves a column through a short intermediate line.
        text = "abcd\nx\nabcd"; position = 10
        space.press(at: CGPoint(x: 30, y: 60)); space.held()
        precondition(letter.caption.alpha == 0 && keys.hitTest(.zero, with: nil) == nil, "Trackpad blanks keys and ignores another finger")
        let touchHeight = height!.constant
        fieldChanged(); precondition(height!.constant == touchHeight && letter.caption.alpha == 0, "Proxy feedback must not relayout a held trackpad")
        space.move(to: CGPoint(x: 30, y: 28)); precondition(position == 6)
        space.move(to: CGPoint(x: 30, y: -4)); precondition(position == 3)
        space.move(to: CGPoint(x: 30, y: 60)); precondition(position == 10)
        space.release(); precondition(text == "abcd\nx\nabcd" && letter.caption.alpha == 1)
        // Deferred soft sign can turn into a hard sign without deleting host text.
        let typedBeforeSign = text
        russian = true; shifted = false; rebuildKeys(); render(); view.layoutIfNeeded()
        precondition(!letterKeys.contains { $0.1 == "ъ" })
        let soft = letterKeys.first { $0.1 == "ь" }!.0
        position = text.count
        soft.press(at: .zero); precondition(text == typedBeforeSign); soft.release()
        precondition(text == typedBeforeSign + "ь", "Quick soft-sign tap inserts exactly one character")
        soft.press(at: CGPoint(x: soft.bounds.midX, y: 20)); soft.held()
        precondition(text == typedBeforeSign + "ь" && !soft.subviews.first { $0.accessibilityIdentifier == "hard-sign-options" }!.isHidden)
        soft.release(); precondition(text == typedBeforeSign + "ьъ", "Held soft sign inserts hard sign without a preceding soft sign")
        soft.press(at: CGPoint(x: soft.bounds.midX, y: 20)); soft.held(); soft.move(to: CGPoint(x: -20, y: -20)); soft.release()
        precondition(text == typedBeforeSign + "ьъь", "Sliding back chooses soft sign")
        soft.press(at: .zero); soft.held(); soft.release(cancelled: true)
        precondition(text == typedBeforeSign + "ьъь", "Cancelling the alternate picker inserts nothing")
        shifted = true; updateCase(); soft.press(at: .zero); soft.held(); soft.release()
        precondition(text == typedBeforeSign + "ьъьЪ" && !shifted, "Uppercase hard sign consumes Shift once")
        text = typedBeforeSign; position = 10; russian = false; rebuildKeys(); render(); view.layoutIfNeeded()
        // Symbol selection survives a rebuilt keyboard and can be switched off.
        let question = punctuationKeys.first { $0.title == "?" }!
        question.press(at: .zero); question.release(); precondition(text == "abcd\nx\nabc?d")
        symbolsEnabled.isOn = false; toggleSymbolRow()
        precondition(punctuationKeys.isEmpty && keys.arrangedSubviews.count == 4)
        symbolsEnabled.isOn = true; toggleSymbolRow()
        let symbol = UIButton(); symbol.accessibilityIdentifier = "@"; selectSymbol(symbol)
        precondition(!punctuationKeys.contains { $0.title == "@" })
        selectSymbol(symbol); precondition(punctuationKeys.contains { $0.title == "@" })
        resetSymbols(); view.layoutIfNeeded()
        showingSettings = true; render()
        let firstChip = (symbolChoices.arrangedSubviews[0] as! UIStackView).arrangedSubviews[0]
        render(); precondition((symbolChoices.arrangedSubviews[0] as! UIStackView).arrangedSubviews[0] === firstChip)
        precondition(keys.isHidden && height!.constant <= 400)
        viewWillDisappear(false); viewWillAppear(false)
        precondition(!keys.isHidden && !showingSettings && !study.isHidden)
        precondition(translate.currentTitle == "Перевести" && translate.accessibilityLabel!.contains("абзац"))
        previewSnapshot = { InputSnapshot(document: document, before: "old text", after: "rest", selected: "new text") }
        render(); precondition(translate.currentTitle == "Перевести" && translate.accessibilityLabel!.contains("выделение"))
        previewSnapshot = { InputSnapshot(document: document, before: String(text.prefix(position)), after: String(text.suffix(text.count - position)), selected: nil) }
        // Three suggestions: saving the second must not silently save the first or third.
        for word in store.words { store.removeWord(word.id) }
        store.record(source: Self.multiSource, response: Self.multiFixture); lessonIndex = 0; showingStudy = true; render()
        let save = UIButton(); save.tag = 1; saveWord(save)
        precondition(store.contains("meet") && !store.contains("buy") && !store.contains("friend"))
        precondition(allButtons(in: lessonContent).contains { $0.accessibilityLabel == "Сохранить friend в словарь" })
        precondition(!allButtons(in: lessonContent).contains { ($0.accessibilityIdentifier ?? "").hasPrefix("dismiss-word-") })
        let skip = UIButton(); skip.tag = 0; dismissWord(skip)
        precondition(store.isDismissed("buy", lesson: store.lessons[0]) && store.words.count == 1)
        restoreWord(skip); precondition(!store.isDismissed("buy", lesson: store.lessons[0]) && !store.contains("buy"))
        save.tag = 2; saveWord(save); saveWord(save)
        precondition(store.words.count == 2 && store.contains("friend") && !store.contains("buy"))
        showingStudy = false; render(); view.layoutIfNeeded(); position = text.count
        let delete = deleteKey!
        let before = deleteCount; delete.press(at: .zero)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            precondition(deleteCount >= before + 3, "Held delete must repeat")
            delete.release(); let stopped = deleteCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                precondition(deleteCount == stopped, "Delete repetition must stop on release")
                self.previewType = oldType; self.previewDelete = oldDelete; self.previewMove = oldMove; self.previewSnapshot = oldSnapshot
                let result: [String: Any] = ["result": "passed", "touch_down": true, "gap_hit": true,
                    "space_taps": 8, "cursor_drag": true, "vertical_cursor": true, "delete_repeat": true, "individual_words": true,
                    "symbols": true, "no_decline_button": true, "scope_labels": true, "hard_sign_hold": true, "trackpad_no_relayout": true, "trackpad_second_touch_blocked": true,
                    "space_width": self.spaceKey!.bounds.width, "key_height": self.letterKeys[0].0.bounds.height]
                let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-mechanics-check.json")
                try! JSONSerialization.data(withJSONObject: result, options: .sortedKeys).write(to: path)
            }
        }
    }
    func runDesignRegression() {
        let oldSnapshot = previewSnapshot, oldReplace = previewReplace
        defer { previewSnapshot = oldSnapshot; previewReplace = oldReplace; clearReward() }
        var host = "I like coffee"
        let document = UUID()
        previewSnapshot = { InputSnapshot(document: document, before: host, after: "", selected: nil) }
        previewReplace = { captured, value in
            guard captured == InputSnapshot(document: document, before: host, after: "", selected: nil) else { return false }
            host = value; return true
        }
        showingStudy = false; showingSettings = false; showingVocabulary = false; showingGame = false
        studyTabs.selectedSegmentIndex = 0; preferences.rewardsEnabled = true; preferences.secondSkillEnabled = true
        let clean = LearningResponse(schema_version: 1, corrected: host, translated: "Я люблю кофе", diffs: [], vocabulary: [])
        let captured = snapshot(), beforeRewards = rewards.successes
        precondition(finishTranslation(clean, captured: captured)); render(); view.layoutIfNeeded()
        precondition(rewardTitle.text != nil && rewards.successes == beforeRewards + 1 && showingStudy)
        precondition(translationControl.isHidden && !studyTabs.isHidden && studyTabs.titleForSegment(at: 0) == "Разбор" && studyTabs.titleForSegment(at: 1) == "Игра" && studyTabs.titleForSegment(at: 2) == "Словарь")
        precondition(!allButtons(in: lessonContent).contains { $0.accessibilityIdentifier == "clarify-meaning" }, "No clarification action before Russian is changed")
        host += "!"; fieldChanged()
        precondition(!showingStudy && !keys.isHidden && store.lessons.first?.response == clean, "Host edit returns to keys while preserving lesson")
        toggleStudy()
        precondition(allButtons(in: lessonContent).contains { $0.accessibilityIdentifier == "clarify-meaning" }, "Changed Russian reveals clarification")
        host = clean.translated; fieldChanged(); toggleStudy()
        precondition(!allButtons(in: lessonContent).contains { $0.accessibilityIdentifier == "clarify-meaning" }, "Reverting Russian hides clarification again")
        let normalPreview = previewSnapshot
        previewSnapshot = { InputSnapshot(document: captured.document, before: "Я предпочитаю ", after: "чай", selected: nil) }; render()
        precondition(allButtons(in: lessonContent).contains { $0.accessibilityIdentifier == "clarify-meaning" } && editedRussianMeaning(for: store.lessons[0]) == "Я предпочитаю чай", "Clarification reads both sides of a cursor inside Russian text")
        previewSnapshot = { InputSnapshot(document: captured.document, before: "Я люблю ", after: "", selected: "кофе") }; render()
        precondition(!allButtons(in: lessonContent).contains { $0.accessibilityIdentifier == "clarify-meaning" }, "Selecting an unchanged Russian word is not an edit")
        let otherDocument = UUID()
        previewSnapshot = { InputSnapshot(document: otherDocument, before: "Я предпочитаю чай", after: "", selected: nil) }; render()
        precondition(!allButtons(in: lessonContent).contains { $0.accessibilityIdentifier == "clarify-meaning" }, "Another field cannot offer clarification for the last translation")
        previewSnapshot = normalPreview; render()
        fieldChanged(); precondition(showingStudy, "Unchanged proxy notification cannot close the new analysis")
        previewSnapshot = { InputSnapshot(document: document, before: "Я ", after: "люблю кофе", selected: nil) }
        selectionDidChange(nil)
        precondition(!showingStudy && !keys.isHidden && store.lessons.first?.response == clean, "Moving the caret returns to letters and retains lesson")
        previewSnapshot = normalPreview; toggleStudy(); view.layoutIfNeeded()
        precondition(translationControl.layer.borderWidth == 0 && translate.layer.borderWidth == 1 && study.layer.borderWidth == 1 && translationControl.spacing >= 8, "Translate and last lesson have separate touch controls")
        let wideBounds = view.bounds
        previewSnapshot = { InputSnapshot(document: document, before: "Я предпочитаю чай", after: "", selected: nil) }
        view.bounds.size.width = 320; render(); view.layoutIfNeeded()
        let narrowActions = allButtons(in: lessonContent).filter { ["show-translation-0", "show-original", "rephrase-lesson", "clarify-meaning"].contains($0.accessibilityIdentifier ?? "") }
        precondition(narrowActions.count == 4 && narrowActions.allSatisfy { $0.superview?.accessibilityIdentifier == "phrase-actions" && $0.bounds.height >= 36 }, "All four actions share a touchable row at narrow width")
        let actionBar = narrowActions[0].superview!
        precondition(narrowActions.allSatisfy { $0.frame.minX >= -0.5 && $0.frame.maxX <= actionBar.bounds.width + 0.5 }, "Action links fit within narrow phrase card")
        view.bounds = wideBounds; previewSnapshot = normalPreview; render(); view.layoutIfNeeded()
        toggleOriginal()
        let originalButton = allButtons(in: lessonContent).first { $0.accessibilityIdentifier == "show-original" }!
        let phraseActions = originalButton.superview as! UIStackView
        precondition(phraseActions.accessibilityIdentifier == "phrase-actions" && (phraseActions.arrangedSubviews.first as? UIButton)?.accessibilityIdentifier == "show-translation-0", "Translation then source share the first action row")
        let phraseCard = phraseActions.superview as! UIStackView
        let originalIndex = phraseCard.arrangedSubviews.firstIndex(of: phraseActions)!
        precondition(phraseCard.arrangedSubviews[originalIndex + 1].accessibilityIdentifier == "original-text", "Original expands immediately below its link")
        toggleOriginal()
        let translationButton = UIButton(); translationButton.tag = 0; toggleTranslation(translationButton)
        precondition((allLabels(in: lessonContent).first { $0.accessibilityIdentifier == "lesson-translation" })?.text == clean.translated, "Translation is available in the analysis without the host field")
        toggleTranslation(translationButton)
        sessionExpanded = true; render()
        let previousHost = host; translationButton.tag = 1; toggleTranslation(translationButton)
        precondition(allLabels(in: lessonContent).contains { $0.accessibilityIdentifier == "session-translation-1" } && host == previousHost && !busy, "Historical translation reveals without replacing the current host text or calling AI")
        sessionExpanded = false
        returnToInput(); view.layoutIfNeeded()
        precondition(!translate.isEnabled && !translate.isHidden && study.currentTitle != "Учёба", "Separate translation and last-lesson actions return to typing")
        precondition(translationControl.bounds.width < view.bounds.width - 40 && translate.bounds.height == 36 && study.bounds.height == 36 && study.frame.minX >= translate.frame.maxX + 8, "Separate buttons fit the input toolbar without overlapping")
        host += "!"; render(); precondition(translate.isEnabled, "External edits enable translation again"); host = clean.translated
        precondition(height!.constant <= 400 && !celebration.isUserInteractionEnabled)
        precondition(!finishTranslation(clean, captured: captured) && rewards.successes == beforeRewards + 1, "Stale result cannot earn another reward")
        rewardsEnabled.isOn = false; toggleRewards(); precondition(rewardBanner.isHidden && rewardTitle.text == nil)
        host = "I like coffee"; precondition(finishTranslation(clean, captured: snapshot()))
        precondition(rewardTitle.text == nil && rewardBanner.isHidden, "Disabled rewards never appear")
        rewardsEnabled.isOn = true; toggleRewards()
        let revisionID = store.lessons.first!.id, reviseRewards = rewards.successes, reviseWords = store.words.count
        host = "Я предпочитаю чай"; let intended = snapshot()
        let revised = LearningResponse(schema_version: 1, corrected: "I prefer tea", translated: "Чужой перевод", diffs: [LearningDiff(id: "meaning", type: .style, original: "I like coffee", corrected: "I prefer tea", start: 0, end: 13, explanation: "Уточнён твой смысл.")], vocabulary: [])
        precondition(finishMeaningRevision(revised, captured: intended, lessonID: revisionID))
        precondition(host == "Я предпочитаю чай" && store.lessons.first?.response.corrected == "I prefer tea" && store.lessons.first?.response.translated == host && rewards.successes == reviseRewards && store.words.count == reviseWords, "Clarification preserves host text and updates original analysis without a reward or dictionary mutation")
        host += "!"; precondition(!finishMeaningRevision(revised, captured: intended, lessonID: revisionID), "Edited Russian invalidates an old clarification")
        showingStudy = true; render()
        precondition(allButtons(in: lessonContent).contains { $0.accessibilityIdentifier == "session-lessons" } && !allButtons(in: lessonContent).contains { ($0.currentTitle ?? "").contains("Новее") || ($0.currentTitle ?? "").contains("Раньше") }, "Session uses a list without chronological arrow buttons")
        host = "I want to купить coffee"; precondition(finishTranslation(Self.fixture, captured: snapshot()))
        precondition(rewardTitle.text == nil, "Errors must not celebrate clean English")
        showingSettings = true; render(); view.layoutIfNeeded()
        precondition(translate.isHidden && !panelTitle.isHidden && translate.alpha == 1)
        speakerGender.selectedSegmentIndex = 2; changeSpeakerGender()
        precondition(preferences.speakerGender == .female)
        showingSettings = false; render(); showingSettings = true; render()
        precondition(speakerGender.selectedSegmentIndex == 2 && translate.isHidden, "Gender setting survives closing settings")
        func contrast(_ foreground: UIColor, _ background: UIColor, style: UIUserInterfaceStyle) -> Double {
            func luminance(_ color: UIColor) -> Double {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
                func linear(_ value: CGFloat) -> Double { let x = Double(value); return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
                return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
            }
            let a = luminance(foreground), b = luminance(background)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        let activeContrast = contrast(EasyTalkTheme.ink, EasyTalkTheme.creamEnd, style: .light)
        let disabledContrast = contrast(EasyTalkTheme.secondary, EasyTalkTheme.creamEnd, style: .light)
        let disabledDarkContrast = contrast(EasyTalkTheme.secondary, EasyTalkTheme.creamEnd, style: .dark)
        precondition(activeContrast >= 4.5 && disabledContrast >= 4.5 && disabledDarkContrast >= 4.5)
        precondition(translate.titleColor(for: .disabled) == EasyTalkTheme.secondary)
        showingSettings = false; render()
        let unchanged = host, sessions = practice.sessions, wordCount = store.words.count
        analysisFailed = true; note = "AI вернул неполный ответ"; showingStudy = true; studyTabs.selectedSegmentIndex = dictionaryTabIndex
        changeStudyTab(); precondition(!analysisFailed && note.isEmpty && showingVocabulary, "A failed analysis must not trap the user away from dictionary or game")
        startGame(); precondition(showingGame && game!.cards.count == 4 && game!.current!.personal)
        let first = game!.current!
        precondition(!game!.showingBack && !practice.isLearned(first.id))
        learnGameCard(); precondition(game!.index == 0 && !practice.isLearned(first.id), "Front cannot be marked learned")
        precondition(translate.isHidden && panelTitle.isHidden && !studyTabs.isHidden)
        precondition(cardPager.isPagingEnabled && cardPager.isDirectionalLockEnabled, "Use native paging and vertical reading")
        nextGameCard(); precondition(game!.index == 1 && game!.rememberedCount == 0)
        precondition(moveGameCard(by: -1) && game!.current == first && !game!.showingBack)
        view.layoutIfNeeded()
        precondition(lessonContent.arrangedSubviews.first!.bounds.height == 256 && lessonHeight!.constant == 280)
        precondition(lessonContent.arrangedSubviews.first!.gestureRecognizers?.contains { $0 is UIPanGestureRecognizer } == true)
        precondition(allButtons(in: lessonContent).allSatisfy { $0.accessibilityIdentifier != "flip-card" && $0.title(for: .normal) != "Повторить позже" })
        precondition(lessonContent.arrangedSubviews.first?.accessibilityIdentifier == "practice-front")
        flipCard(animated: false)
        precondition(game!.showingBack && !practice.isLearned(first.id))
        precondition(lessonContent.arrangedSubviews.first?.accessibilityIdentifier == "practice-back")
        view.layoutIfNeeded()
        let currentPage = lessonContent.arrangedSubviews.first!
        let remember = allButtons(in: currentPage).first { $0.accessibilityIdentifier == "remember-card" }!
        precondition(remember.superview?.accessibilityIdentifier == "practice-header" && remember.backgroundColor == .clear)
        precondition((remember as? TextLinkButton)?.hasVisibleLinkUnderline == true)
        precondition(!allButtons(in: currentPage).contains { $0.accessibilityLabel == "Закрыть повторение" })
        precondition(!allButtons(in: root).contains { ($0.currentTitle ?? "").contains("К вводу") })
        flipCard(animated: false); precondition(!game!.showingBack && game!.rememberedCount == 0)
        flipCard(animated: false); archiveGameCard(animated: false)
        precondition(practice.isLearned(first.id) && game!.index == 0 && game!.rememberedCount == 1 && game!.cards.count == 3 && !game!.cards.contains(first) && !game!.showingBack)
        precondition(learnedFeedback != nil && store.words.count == wordCount, "Mastery celebrates and archives, without deleting the word")
        precondition(practice.dictionaryCards(words: store.words, filter: .learned).contains { $0.id == first.id })
        precondition(!practice.dictionaryCards(words: store.words, filter: .inGame).contains { $0.id == first.id })
        closeGame(); precondition(practice.sessions == sessions, "Closing early is not a completed session")
        startGame(); precondition(!game!.cards.contains { $0.id == first.id })
        nextGameCard(); precondition(game!.index == 1 && !game!.showingBack && game!.rememberedCount == 0)
        while game!.current != nil { flipCard(animated: false); nextGameCard() }
        precondition(game!.finished && game!.rememberedCount == 0 && practice.sessions == sessions + 1)
        nextGameCard(); precondition(practice.sessions == sessions + 1)
        precondition(moveGameCard(by: -1) && !game!.finished && !game!.showingBack)
        nextGameCard(); precondition(practice.sessions == sessions + 1, "Revisiting end must not count a second session")
        precondition(host == unchanged && store.words.count == wordCount, "Game never edits the host field or saves words silently")
        toggleStudy()
        let variantsLesson = store.lessons[0]
        store.setVariants([PhraseVariant(label: "Нейтрально", text: "I'd like to buy coffee.", explanation: "Вежливо."), PhraseVariant(label: "Разговорно", text: "I'd love some coffee.", explanation: "Непринуждённо.")], lesson: variantsLesson.id)
        render(); _ = allButtons(in: lessonContent).first { $0.accessibilityIdentifier == "toggle-variants" }!
        precondition(!expandedVariantLessons.contains(variantsLesson.id))
        toggleVariants(); precondition(expandedVariantLessons.contains(variantsLesson.id))
        toggleVariants(); precondition(!expandedVariantLessons.contains(variantsLesson.id) && store.lessons[0].response.diffs == variantsLesson.response.diffs && !studyBusy)
        dictionaryFilter = .learned; showingVocabulary = true; render()
        precondition(allButtons(in: lessonContent).contains { $0.currentTitle == "Вернуть в карточки" })
        view.layoutIfNeeded()
        let dictionarySpeaker = allButtons(in: lessonContent).first { $0.accessibilityIdentifier == "dictionary-speaker" }!
        precondition(dictionarySpeaker.superview?.accessibilityIdentifier == "dictionary-term", "Dictionary speaker stays next to English term")
        let disclosure = allButtons(in: lessonContent).first { ($0.accessibilityLabel ?? "").hasPrefix("Примеры для") }!
        precondition(disclosure.backgroundColor == .clear && disclosure.layer.borderWidth == 0 && disclosure.currentImage!.size.height < 19 && disclosure.bounds.width >= 44, "Small bare dictionary chevron retains its touch target")
        let filters = allButtons(in: dictionaryFilters)
        precondition(filters.count == 3 && !filters[2].isEnabled && filters[0].isEnabled && (filters[0] as? TextLinkButton)?.hasVisibleLinkUnderline == true)
        precondition(!dictionaryFilters.subviews.contains { $0 is UISegmentedControl })
        secondSkillEnabled.isOn = false; toggleSecondSkill()
        precondition(game == nil && !showingGame && studyTabs.numberOfSegments == 2)
        secondSkillEnabled.isOn = true; toggleSecondSkill(); precondition(studyTabs.numberOfSegments == 3)
        showingStudy = false; showingSettings = false; showingVocabulary = false; studyTabs.selectedSegmentIndex = 0; render()
        let wordsBeforeSessionReset = store.words.count, previousGeneration = generation
        busy = true; revisingMeaning = true; pending = snapshot(); clearHistory()
        precondition(!busy && !revisingMeaning && pending == nil && generation > previousGeneration && store.lessons.isEmpty && store.words.count == wordsBeforeSessionReset, "Ending the session cancels pending results and keeps vocabulary")
        let result: [String: Any] = ["result": "passed", "conditional_clarification": true, "host_edit_returns_keys": true, "host_cursor_returns_keys": true, "separate_translate_lesson": true, "single_action_row": true, "clarification_mid_paragraph": true, "selection_is_not_edit": true, "foreign_field_no_clarification": true, "inline_original": true, "historical_translation": true, "quiet_dictionary_disclosure": true, "term_speaker": true, "session_reset_cancels_pending": true, "inline_save_no_skip": true, "four_cards": true,
            "learned_excluded": true, "game_does_not_edit_text": true, "game_toggle": true, "reward_toggle": true,
            "no_reward_on_errors_or_stale": true, "clarify_meaning_preserves_russian": true, "clarify_stale_guard": true, "session_list_no_arrows": true, "two_sided_cards": true, "system_globe_return": true, "no_input_footer": true, "dashed_links": true, "quiet_dictionary_filters": true, "header_mastery_no_cross": true, "gender_in_settings": true, "mastery_archives": true, "dictionary_filters": true, "collapsible_variants": true, "compact_neutral_toolbar": true, "navigation_after_error": true,
            "swipe_both_directions": true, "compact_cards": true, "translate_hidden_in_study": true, "active_contrast": activeContrast,
            "disabled_contrast": disabledContrast, "disabled_dark_contrast": disabledDarkContrast]
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-design-check.json")
        try! JSONSerialization.data(withJSONObject: result, options: .sortedKeys).write(to: path)
    }
    private func allLabels(in view: UIView) -> [UILabel] {
        (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { allLabels(in: $0) }
    }
    private func allButtons(in view: UIView) -> [UIButton] {
        (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { allButtons(in: $0) }
    }
    /// Uses native scrolling animations. Actual finger feel is verified on the phone.
    private func waitForCardAnimation(_ ready: @escaping () -> Bool, then action: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(3)
        func poll() {
            if ready() { action(); return }
            precondition(Date() < deadline, "Card animation did not settle")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
    }
    func runCardGestureRegression() {
        startGame(); view.layoutIfNeeded(); let original = snapshot(), learned = practice.learnedIDs
        flipCard(animated: true)
        waitForCardAnimation({ self.game!.showingBack && !self.flippingCard }) {
            let width = self.cardPager.bounds.width
            self.cardPager.setContentOffset(CGPoint(x: width * 0.25, y: 0), animated: false)
            precondition(abs(self.cardPager.contentOffset.x - width * 0.25) < 1, "Native paging follows distance without a transform multiplier")
            self.cardPager.navigate(to: 1, animated: true)
            self.waitForCardAnimation({ self.game!.index == 1 && !self.game!.showingBack && !self.swipingCard }) {
                self.flipCard(animated: false); self.cardPager.navigate(to: 0, animated: true)
                self.waitForCardAnimation({ self.game!.index == 0 && !self.game!.showingBack && !self.swipingCard }) {
                    precondition(self.snapshot() == original && self.practice.learnedIDs == learned && self.game!.rememberedCount == 0)
                    let report: [String: Any] = ["result": "passed", "native_flip": true, "native_paging": true, "left_right_transitions": true, "no_implicit_learning": true, "host_unchanged": true]
                    let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-card-gesture-check.json")
                    try! JSONSerialization.data(withJSONObject: report, options: .sortedKeys).write(to: path)
                    self.closeGame(); self.showingStudy = false; self.render()
                }
            }
        }
    }
    private static var fixture: LearningResponse {
        LearningResponse(schema_version: 1, corrected: "I want to buy coffee", translated: "Я хочу купить кофе",
            diffs: [LearningDiff(id: "d1", type: .unknownWord, original: "купить", corrected: "buy", start: 10, end: 16,
                explanation: "«Купить» здесь — buy. После want to используем начальную форму глагола.")],
            vocabulary: [VocabularySuggestion(term: "buy", meaning: "купить", kind: "word")])
    }
    func runPreviewRegression() {
        let capture = snapshot(); precondition(finishTranslation(Self.fixture, captured: capture))
        precondition(!finishTranslation(Self.fixture, captured: capture), "Old snapshot cannot replace the new message")
        precondition(store.lessons.count == 1 && store.unreadCount == 0 && showingStudy, "Translation opens its analysis automatically")
        toggleStudy(); precondition(store.unreadCount == 0 && showingStudy && keys.isHidden)
        view.layoutIfNeeded(); lessonScroll.layoutIfNeeded()
        let wordControls = allButtons(in: lessonContent).filter { ($0.accessibilityIdentifier ?? "").hasPrefix("save-word-") || ($0.accessibilityIdentifier ?? "").hasPrefix("dismiss-word-") }
        precondition(wordControls.count == 1 && wordControls.allSatisfy { $0.bounds.width >= 44 && $0.bounds.height >= 44 }, "Small marks must retain a 44 pt touch target")
        let b = UIButton(); b.tag = 0; saveWord(b); saveWord(b); precondition(store.words.count == 1)
        precondition(store.words[0].originalContext == "I want to купить coffee")
        viewWillDisappear(false); viewWillAppear(false)
        precondition(!showingStudy && !keys.isHidden)
        note = "Переведено. Разбор сохранён."; render(); view.layoutIfNeeded()
        precondition(translate.bounds.height == 36 && height!.constant <= 400)
        let result: [String: Any] = ["result": "passed", "button_height": translate.bounds.height,
            "keyboard_height": height!.constant, "lessons": store.lessons.count, "words": store.words.count]
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-ui-check.json")
        try! JSONSerialization.data(withJSONObject: result, options: .sortedKeys).write(to: path)
    }
    #endif
}

extension UIInputView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
