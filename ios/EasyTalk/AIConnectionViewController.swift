import UIKit

/// «Перевод через AI». The first time, a wizard: provider → where to get a key → paste it → automatic check.
/// Once connected, a compact card: check, model, change, delete. Region, address and workspace appear only
/// for the providers that need them.
final class AIConnectionViewController: UIViewController, UITextFieldDelegate {
    private enum Step: Int {
        case provider = 1, getKey, enterKey, checking, summary
    }
    /// An invented phrase, never the user's text.
    static let testPhrase = "I want to купить coffee."

    private let preferences = KeyboardPreferences(defaults: SharedStorage.defaults())
    private var saved = ConnectionStore.read() {
        didSet {
            guard oldValue?.provider != saved?.provider else { return }
            loadedModels = []
            modelsProvider = nil
        }
    }
    private lazy var step: Step = saved == nil ? .provider : .summary
    private lazy var provider: AIProvider = saved?.provider ?? .openai
    private lazy var draftModel: String = saved?.model ?? provider.defaultModel

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private lazy var keyField = SettingsUI.field("Ключ", self, done: #selector(hideKeyboard))
    private lazy var workspaceField = SettingsUI.field("ID рабочего пространства: wrkspc_…", self, done: #selector(hideKeyboard))
    private lazy var regionField = SettingsUI.field("Регион, например us-east-1", self, done: #selector(hideKeyboard))
    private lazy var addressField = SettingsUI.field("Адрес API своего региона", self, done: #selector(hideKeyboard))
    private let keyInfo = SettingsUI.label("", size: 14)
    private let status = SettingsUI.label("", size: 16)
    private let modelButton = UIButton(type: .system)
    /// After a failed check: the key may be right and only the network down.
    private var offerUncheckedSave = false
    private var checkOperation: AnalysisOperation?
    private var modelsTask: URLSessionDataTask?
    private var loadedModels: [String] = []
    /// The provider whose list was requested, so re-rendering does not ask again.
    private var modelsProvider: AIProvider?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Перевод через AI"
        view.backgroundColor = EasyTalkTheme.canvas
        SettingsUI.layout(scroll, stack, in: view)
        let tap = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        keyField.isSecureTextEntry = true
        keyField.addTarget(self, action: #selector(keyChanged), for: .editingChanged)
        regionField.keyboardType = .asciiCapable
        addressField.keyboardType = .URL
        for field in [keyField, workspaceField, regionField, addressField] { field.delegate = self }
        modelButton.showsMenuAsPrimaryAction = true
        modelButton.contentHorizontalAlignment = .leading
        EasyTalkTheme.style(modelButton)
        modelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        modelButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        SettingsUI.height(modelButton, 44)
        fillFields()
        render()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        checkOperation?.cancel()
        checkOperation = nil
        modelsTask?.cancel()
        if loadedModels.isEmpty { modelsProvider = nil }
        if step == .checking { step = .enterKey }
    }

    // MARK: Screens

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch step {
        case .provider: renderProvider()
        case .getKey: renderGetKey()
        case .enterKey: renderEnterKey()
        case .checking: renderChecking()
        case .summary: renderSummary()
        }
    }

    private func addHeader(_ title: String) {
        if step != .summary {
            let progress = SettingsUI.label("Шаг \(step.rawValue) из 4", size: 14, weight: .medium, color: EasyTalkTheme.secondary)
            stack.addArrangedSubview(progress)
        }
        let header = SettingsUI.label(title, size: 26, weight: .bold)
        header.accessibilityTraits.insert(.header)
        stack.addArrangedSubview(header)
    }

    private func renderProvider() {
        addHeader("Какой AI подключить?")
        let intro = "Перевод работает через твой аккаунт у провайдера: платишь ему напрямую, по использованию. "
            + "Выбирай тот, где у тебя уже есть аккаунт. Без ключа всё остальное в easytalk работает."
        stack.addArrangedSubview(SettingsUI.label(intro, size: 16))
        addStatus()
        let card = SettingsUI.card()
        for (index, item) in AIProvider.allCases.enumerated() {
            let row = SettingsRow(title: item.title, detail: item.tagline)
            row.isChosen = item == saved?.provider
            row.tag = index
            row.addTarget(self, action: #selector(chooseProvider(_:)), for: .touchUpInside)
            card.addArrangedSubview(row)
        }
        stack.addArrangedSubview(card)
        if saved != nil {
            stack.addArrangedSubview(SettingsUI.link("Отмена — оставить текущее подключение", self, #selector(showSummary)))
        }
    }

    private func renderGetKey() {
        addHeader("Получи ключ \(provider.title)")
        let card = SettingsUI.card()
        for (index, text) in provider.keySteps.enumerated() {
            card.addArrangedSubview(SettingsUI.label("\(index + 1). \(text)", size: 17))
        }
        stack.addArrangedSubview(card)
        let site = provider.keyPageURL.host ?? "сайт провайдера"
        stack.addArrangedSubview(SettingsUI.primaryButton("Открыть \(site)", self, #selector(openKeyPage)))
        let note = "Ключ — длинная строка вроде пароля. Его показывают один раз: сразу скопируй целиком и вернись сюда."
        stack.addArrangedSubview(SettingsUI.label(note, size: 15, color: EasyTalkTheme.secondary))
        stack.addArrangedSubview(SettingsUI.secondaryButton("Ключ скопирован — дальше", self, #selector(showEnterKey)))
        stack.addArrangedSubview(SettingsUI.link("← Другой провайдер", self, #selector(showProviders)))
    }

    private func renderEnterKey() {
        addHeader("Вставь ключ")
        stack.addArrangedSubview(SettingsUI.secondaryButton("Вставить из буфера", self, #selector(pasteKey)))
        keyField.placeholder = provider.keyPlaceholder
        stack.addArrangedSubview(keyField)
        stack.addArrangedSubview(keyInfo)
        if provider.needsWorkspace || provider.editableBaseURL {
            stack.addArrangedSubview(SettingsUI.sectionTitle("Дополнительно для \(provider.title)"))
        }
        if provider.needsWorkspace {
            stack.addArrangedSubview(SettingsUI.label("ID рабочего пространства — в разделе Workspaces.", size: 15))
            stack.addArrangedSubview(workspaceField)
        }
        if provider.usesRegion {
            stack.addArrangedSubview(SettingsUI.label("Регион, где создан ключ. Если не менял — us-east-1.", size: 15))
            stack.addArrangedSubview(regionField)
        } else if provider.editableBaseURL {
            stack.addArrangedSubview(SettingsUI.label("Адрес API своего региона, вида \(provider.addressHint).", size: 15))
            stack.addArrangedSubview(addressField)
        }
        let model = "Модель: \(draftModel). Сменить можно после проверки."
        stack.addArrangedSubview(SettingsUI.label(model, size: 15, color: EasyTalkTheme.secondary))
        stack.addArrangedSubview(SettingsUI.primaryButton("Проверить и сохранить", self, #selector(checkAndSave)))
        addStatus()
        if offerUncheckedSave {
            stack.addArrangedSubview(SettingsUI.link("Сохранить без проверки", self, #selector(saveUnchecked)))
        }
        stack.addArrangedSubview(SettingsUI.link("← Где взять ключ", self, #selector(showGetKey)))
    }

    private func renderChecking() {
        addHeader("Проверяю ключ…")
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = EasyTalkTheme.secondary
        spinner.startAnimating()
        stack.addArrangedSubview(spinner)
        let note = "Отправляю \(provider.title) тестовую фразу «\(Self.testPhrase)» — не твой текст. Обычно это несколько секунд."
        stack.addArrangedSubview(SettingsUI.label(note, size: 16))
        stack.addArrangedSubview(SettingsUI.link("Отменить", self, #selector(cancelCheck)))
    }

    private func renderSummary() {
        guard let saved else {
            step = .provider
            render()
            return
        }
        addHeader("Перевод через AI")
        let card = SettingsUI.card()
        card.addArrangedSubview(SettingsUI.label("✓ Подключено: \(saved.provider.title)", size: 19, weight: .semibold, color: EasyTalkTheme.green))
        card.addArrangedSubview(SettingsUI.label(ConnectionSettings.keySummary(saved.token), size: 15, color: EasyTalkTheme.secondary))
        if let warning = saved.provider.keyWarning(saved.token) {
            card.addArrangedSubview(SettingsUI.label("⚠️ " + warning, size: 15, color: .systemOrange))
        }
        if saved.provider.needsWorkspace {
            card.addArrangedSubview(SettingsUI.label("Рабочее пространство: \(saved.workspaceID)", size: 15, color: EasyTalkTheme.secondary))
        }
        if let region = saved.provider.region(from: saved.baseURL) {
            card.addArrangedSubview(SettingsUI.label("Регион: \(region)", size: 15, color: EasyTalkTheme.secondary))
        }
        card.addArrangedSubview(SettingsUI.label(lastCheckText(for: saved), size: 15, color: EasyTalkTheme.secondary))
        stack.addArrangedSubview(card)
        stack.addArrangedSubview(SettingsUI.primaryButton("Проверить", self, #selector(checkSaved)))
        addStatus()
        stack.addArrangedSubview(modelButton)
        updateModelMenu(loading: false)
        loadModels(for: saved)
        stack.addArrangedSubview(SettingsUI.secondaryButton("Сменить провайдера или ключ", self, #selector(showProviders)))
        stack.addArrangedSubview(SettingsUI.link("Удалить ключ", self, #selector(confirmDelete), danger: true))
        let privacy = "Ключ хранится только на этом iPhone, в защищённом хранилище, общем для приложения и клавиатуры. "
            + "Текст уходит провайдеру только по кнопкам «Перевести» и «В словарь»."
        stack.addArrangedSubview(SettingsUI.label(privacy, size: 14, color: EasyTalkTheme.secondary))
        let access = "Клавиатура видит ключ, когда у неё включён «Полный доступ»."
        stack.addArrangedSubview(SettingsUI.label(access, size: 14, color: EasyTalkTheme.secondary))
    }

    private func addStatus() {
        guard !(status.text ?? "").isEmpty else { return }
        stack.addArrangedSubview(status)
    }

    private func showStatus(_ text: String?, warning: Bool = false) {
        status.text = text
        status.textColor = warning ? .systemOrange : EasyTalkTheme.ink
        render()
        if let text { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    // MARK: Steps

    @objc private func chooseProvider(_ sender: UIControl) {
        guard AIProvider.allCases.indices.contains(sender.tag) else { return }
        provider = AIProvider.allCases[sender.tag]
        fillFields()
        offerUncheckedSave = false
        status.text = nil
        step = .getKey
        render()
        scroll.setContentOffset(.zero, animated: false)
    }
    @objc private func showProviders() { go(to: .provider) }
    @objc private func showGetKey() { go(to: .getKey) }
    @objc private func showEnterKey() { go(to: .enterKey) }
    @objc private func showSummary() {
        guard let saved else { return }
        provider = saved.provider
        fillFields()
        go(to: .summary)
    }
    private func go(to next: Step) {
        view.endEditing(true)
        status.text = nil
        offerUncheckedSave = false
        step = next
        render()
        scroll.setContentOffset(.zero, animated: false)
    }
    @objc private func openKeyPage() { UIApplication.shared.open(provider.keyPageURL) }

    /// The saved values when the provider is the same, its defaults otherwise.
    private func fillFields() {
        let same = saved?.provider == provider ? saved : nil
        keyField.text = same?.token ?? ""
        workspaceField.text = same?.workspaceID ?? ""
        regionField.text = same.flatMap { provider.region(from: $0.baseURL) } ?? AIProvider.defaultRegion
        addressField.text = same?.baseURL ?? provider.defaultBaseURL
        draftModel = same?.model ?? provider.defaultModel
        keyChanged()
    }

    private var formConfig: ConnectionSettings {
        var address: String? = nil
        if provider.usesRegion {
            address = provider.baseURL(region: regionField.text ?? "") ?? ""
        } else if provider.editableBaseURL {
            address = (addressField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ConnectionSettings(provider: provider, apiKey: keyField.text ?? "", model: draftModel, baseURL: address,
                                  workspaceID: workspaceField.text ?? "", speakerGender: preferences.speakerGender)
    }

    /// The key stays hidden; a masked summary and a warning show whether it is the right, complete key.
    @objc private func keyChanged() {
        let key = ConnectionSettings.cleanKey(keyField.text ?? "")
        guard !key.isEmpty else {
            keyInfo.text = "Ключ не вставлен."
            keyInfo.textColor = EasyTalkTheme.secondary
            return
        }
        if let warning = provider.keyWarning(key) {
            keyInfo.text = ConnectionSettings.keySummary(key) + "\n⚠️ " + warning
            keyInfo.textColor = .systemOrange
        } else {
            keyInfo.text = ConnectionSettings.keySummary(key)
            keyInfo.textColor = EasyTalkTheme.secondary
        }
    }

    @objc private func pasteKey() {
        guard let text = UIPasteboard.general.string, !ConnectionSettings.cleanKey(text).isEmpty else {
            showStatus("В буфере нет текста. Скопируй ключ на сайте провайдера.", warning: true)
            return
        }
        keyField.text = ConnectionSettings.cleanKey(text)
        keyChanged()
        status.text = nil
        render()
    }

    @objc private func checkAndSave() {
        view.endEditing(true)
        let config = formConfig
        if let problem = config.setupProblem {
            showStatus(problem, warning: true)
            return
        }
        status.text = nil
        step = .checking
        render()
        runCheck(config) { [weak self] ok, text in
            guard let self else { return }
            guard ok else {
                self.offerUncheckedSave = true
                self.step = .enterKey
                self.showStatus(text, warning: true)
                return
            }
            guard ConnectionStore.write(config) else {
                self.step = .enterKey
                self.showStatus("Ключ работает, но сохранить его не удалось. Попробуй ещё раз.", warning: true)
                return
            }
            self.saved = config
            self.offerUncheckedSave = false
            self.step = .summary
            self.showStatus("Готово! " + text + " Клавиатура уже может переводить.")
        }
    }

    @objc private func saveUnchecked() {
        let config = formConfig
        if let problem = config.setupProblem {
            showStatus(problem, warning: true)
            return
        }
        guard ConnectionStore.write(config) else {
            showStatus("Не удалось сохранить ключ. Попробуй ещё раз.", warning: true)
            return
        }
        saved = config
        offerUncheckedSave = false
        step = .summary
        showStatus("Сохранено без проверки. Когда будет интернет, нажми «Проверить».")
    }

    @objc private func cancelCheck() {
        checkOperation?.cancel()
        checkOperation = nil
        step = saved == nil || keyField.text?.isEmpty == false ? .enterKey : .summary
        showStatus("Проверка отменена.")
    }

    @objc private func checkSaved() {
        guard let saved else { return }
        showStatus("Проверяю…")
        runCheck(saved) { [weak self] ok, text in
            self?.showStatus(text, warning: !ok)
        }
    }

    private func runCheck(_ config: ConnectionSettings, completion: @escaping (Bool, String) -> Void) {
        checkOperation?.cancel()
        let started = Date()
        checkOperation = AnalysisOperation(source: Self.testPhrase, config: config) { [weak self] result, trace in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checkOperation = nil
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                switch result {
                case .success(let analysis):
                    self.recordCheck(config, ok: true)
                    completion(true, "Перевод работает: «\(analysis.translated)» · \(seconds) с.")
                case .failure(let failure):
                    self.recordCheck(config, ok: false)
                    completion(false, "Не получилось (\(failure.code)). " + failure.message(details: trace.response))
                }
            }
        }
    }

    @objc private func confirmDelete() {
        let message = "Кнопка «Перевести» перестанет работать, пока не подключишь AI снова. Словарь и история не изменятся."
        let alert = UIAlertController(title: "Удалить ключ?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            guard let self else { return }
            guard ConnectionStore.delete() else {
                self.showStatus("Не удалось удалить ключ. Попробуй ещё раз.", warning: true)
                return
            }
            self.saved = nil
            self.fillFields()
            self.step = .provider
            self.showStatus("Ключ удалён с этого iPhone.")
        })
        present(alert, animated: true)
    }

    // MARK: Model

    private func loadModels(for config: ConnectionSettings) {
        guard modelsProvider != config.provider, let request = ModelCatalog.request(config: config) else { return }
        modelsTask?.cancel()
        modelsProvider = config.provider
        updateModelMenu(loading: true)
        let provider = config.provider
        modelsTask = AnalysisService.session.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let models = ok ? data.map { ModelCatalog.parse($0, provider: provider) } ?? [] : []
            DispatchQueue.main.async {
                guard let self, self.saved?.provider == provider else { return }
                self.loadedModels = models
                self.updateModelMenu(loading: false)
            }
        }
        modelsTask?.resume()
    }

    private func updateModelMenu(loading: Bool) {
        guard let saved else { return }
        let models = loadedModels.isEmpty ? saved.provider.suggestedModels : loadedModels
        let title = loading ? "Модель: \(saved.model) · загружаю список…" : "Модель: \(saved.model) ▾"
        modelButton.setTitle(title, for: .normal)
        modelButton.accessibilityLabel = "Модель: \(saved.model). Выбрать другую"
        let choices = models.map { name in
            UIAction(title: name, subtitle: name == saved.provider.defaultModel ? "по умолчанию" : nil,
                     state: name == saved.model ? .on : .off) { [weak self] _ in self?.chooseModel(name) }
        }
        let menuTitle = loadedModels.isEmpty ? "Рекомендуемые модели" : "Доступно вашему ключу: \(models.count)"
        modelButton.menu = UIMenu(title: menuTitle, children: choices)
    }

    private func chooseModel(_ name: String) {
        guard var config = saved, config.model != name else { return }
        config.model = name
        guard ConnectionStore.write(config) else {
            showStatus("Не удалось сохранить модель.", warning: true)
            return
        }
        saved = config
        draftModel = name
        showStatus("Модель: \(name). Нажми «Проверить», чтобы убедиться, что она работает.")
    }

    // MARK: Last check

    private func recordCheck(_ config: ConnectionSettings, ok: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: "ai.check.date")
        defaults.set(ok, forKey: "ai.check.ok")
        defaults.set(config.provider.rawValue + "|" + config.model, forKey: "ai.check.target")
    }

    private func lastCheckText(for config: ConnectionSettings) -> String {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "ai.check.target") == config.provider.rawValue + "|" + config.model,
              let date = defaults.object(forKey: "ai.check.date") as? Date else { return "Модель \(config.model) ещё не проверена." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        let result = defaults.bool(forKey: "ai.check.ok") ? "работает" : "не прошла"
        return "Проверка \(formatter.string(from: date)): \(result) · \(config.model)"
    }

    // MARK: Keyboard

    @objc private func hideKeyboard() { view.endEditing(true) }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    /// Keep the edited field and the button under it above the keyboard.
    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let frame = textField.convert(textField.bounds, to: self.scroll)
            let visible = CGRect(x: frame.minX, y: frame.minY - 16, width: frame.width, height: frame.height + 110)
            self.scroll.scrollRectToVisible(visible, animated: true)
        }
    }

    #if targetEnvironment(simulator)
    static func runConnectionRegression() {
        ConnectionStore.isolatedPreview = true
        ConnectionStore.previewConnection = nil
        defer {
            ConnectionStore.previewConnection = nil
            ConnectionStore.isolatedPreview = false
        }
        let wizard = AIConnectionViewController()
        wizard.loadViewIfNeeded()
        precondition(wizard.step == .provider, "Without a key the wizard starts with the provider")
        wizard.provider = .deepseek
        wizard.fillFields()
        wizard.go(to: .enterKey)
        precondition(!wizard.workspaceField.isDescendant(of: wizard.view) && !wizard.regionField.isDescendant(of: wizard.view),
                     "Workspace and region appear only for the providers that need them")
        wizard.keyField.text = "test-only-key"
        wizard.saveUnchecked()
        precondition(ConnectionStore.read()?.token == "test-only-key" && wizard.step == .summary, "The key is saved")
        let reopened = AIConnectionViewController()
        reopened.loadViewIfNeeded()
        precondition(reopened.step == .summary && reopened.keyField.text == "test-only-key", "A saved key opens the summary card")
        reopened.provider = .claudeAWS
        reopened.fillFields()
        reopened.go(to: .enterKey)
        precondition(reopened.workspaceField.isDescendant(of: reopened.view) && reopened.regionField.isDescendant(of: reopened.view)
                     && reopened.keyField.text == "", "Another provider starts with an empty key and its extra fields")
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("connection-retry-check.json")
        try! Data("{\"result\":\"passed\",\"wizard\":true,\"reopen\":true,\"isolated_credentials\":true}".utf8).write(to: path)
        print("CONNECTION WIZARD REGRESSION PASSED")
    }
    #endif
}
