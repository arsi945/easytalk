import UIKit
import Security

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        SharedStorage.migrateLegacyDefaults(to: SharedStorage.defaults(), process: "app")
        #if targetEnvironment(simulator)
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--keyboard-preview") {
            let args = ProcessInfo.processInfo.arguments
            let state = i + 1 < args.count ? args[i + 1] : "empty"
            window.rootViewController = KeyboardPreviewController(state: state)
        } else {
            window.rootViewController = UINavigationController(rootViewController: TryViewController())
        }
        #else
        var prepared = false
        #if DEBUG
        if let config = pendingPersonalConnection() { prepared = ConnectionStore.write(config) }
        #endif
        let navigation = UINavigationController(rootViewController: TryViewController(importPrepared: prepared))
        window.rootViewController = navigation
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--check-ai") {
            window.rootViewController = DeviceAICheckController()
        }
        #endif
        #endif
        window.makeKeyAndVisible(); self.window = window
        return true
    }
    #if DEBUG
    /// One-use local provisioning file, supplied through the developer's paired device.
    private func pendingPersonalConnection() -> ConnectionSettings? {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("personal-connection.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        do { try FileManager.default.removeItem(at: path) } catch { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expires = object["expires"] as? Double, expires > Date().timeIntervalSince1970,
              let value = object["connection"], let encoded = try? JSONSerialization.data(withJSONObject: value),
              let config = try? JSONDecoder().decode(ConnectionSettings.self, from: encoded), config.url != nil else { return nil }
        return config
    }
    #endif
}

#if DEBUG
/// Invoked only by an explicit developer launch flag; uses invented text, no Notes contents.
final class DeviceAICheckController: UIViewController {
    private let message = UILabel()
    private var task: AnalysisOperation?
    private var networkTask: URLSessionDataTask?
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = EasyTalkTheme.canvas
        UIApplication.shared.isIdleTimerDisabled = true
        message.text = "Проверяю подключение AI…"; message.font = .systemFont(ofSize: 21); message.numberOfLines = 0
        message.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(message)
        NSLayoutConstraint.activate([message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), message.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        guard let config = ConnectionStore.read(), config.url != nil else {
            finish(["result": "missing connection"]); return
        }
        guard config.provider == .openai else { analyze(config); return }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!, timeoutInterval: 10)
        request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
        let started = Date()
        networkTask = AnalysisService.session.dataTask(with: request) { [weak self] _, response, error in
            var check: [String: Any] = ["seconds": Date().timeIntervalSince(started)]
            check["http"] = (response as? HTTPURLResponse)?.statusCode
            check["error"] = error.map { ($0 as NSError).code }
            let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("device-network-check.json")
            if let data = try? JSONSerialization.data(withJSONObject: check, options: .sortedKeys) { try? data.write(to: path) }
            DispatchQueue.main.async { self?.analyze(config) }
        }; networkTask?.resume()
    }
    private func analyze(_ config: ConnectionSettings) {
        let source = "Yesterday I go to the office and meet my friend. We drink coffee and discuss our new project. I want to договориться about the deadline and send him the documents tomorrow."
        task = AnalysisOperation(source: source, config: config) { [weak self] result, trace in
            let data = trace.response
            // This fixture contains only the fixed invented test text, never a user's document.
            if let data, let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = envelope["choices"] as? [[String: Any]], let choice = choices.first,
               let message = choice["message"] as? [String: Any], let content = message["content"] as? String,
               let payload = content.data(using: .utf8), let analysis = try? JSONSerialization.jsonObject(with: payload) {
                let fixture: [String: Any] = ["source": source, "response": analysis, "finish_reason": choice["finish_reason"] ?? "?"]
                let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("device-ai-fixture.json")
                if let encoded = try? JSONSerialization.data(withJSONObject: fixture, options: .sortedKeys) { try? encoded.write(to: path) }
            }
            var check: [String: Any] = ["seconds": trace.seconds, "attempts": trace.attempts, "model": config.model,
                "bytes_sent": trace.bytesSent, "bytes_received": trace.bytesReceived, "checked_at": Date().timeIntervalSince1970]
            if let http = trace.http { check["http"] = http }
            switch result {
            case .success(let analysis): check["result"] = "passed"; check["corrections"] = analysis.diffs.count; check["words"] = analysis.studyVocabulary.count
            case .failure(let failure): check["result"] = failure.code
            }
            DispatchQueue.main.async { self?.finish(check) }
        }
    }
    private func finish(_ check: [String: Any]) {
        UIApplication.shared.isIdleTimerDisabled = false
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("device-ai-check.json")
        if let data = try? JSONSerialization.data(withJSONObject: check, options: .sortedKeys) { try? data.write(to: path) }
        message.text = "Проверка: \(check["result"] ?? "?")\n\(Int(check["seconds"] as? Double ?? 0)) секунд.\nМожно вернуться в Заметки."
    }
}
#endif

final class TryViewController: UIViewController {
    private let importPrepared: Bool
    private let test = UITextView()
    private let voiceInfo = UILabel()
    init(importPrepared: Bool = false) { self.importPrepared = importPrepared; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "easytalk"
        view.backgroundColor = EasyTalkTheme.canvas
        navigationController?.navigationBar.tintColor = EasyTalkTheme.ink
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(setup))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Настройки подключения"
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        let welcome = WarmCard(padding: 18)
        welcome.addArrangedSubview(textLabel("✨ Маленькие шаги. Свободный английский.", size: 26, weight: .bold))
        welcome.addArrangedSubview(textLabel("Пиши своими словами. easytalk поможет с переводом и сохранит полезное для учёбы.", size: 18))
        stack.addArrangedSubview(welcome)
        let voice = WarmCard(padding: 14)
        voice.addArrangedSubview(textLabel("🎙 Диктовка с клавиатуры", size: 20, weight: .medium))
        voiceInfo.font = .systemFont(ofSize: 16); voiceInfo.numberOfLines = 0; voiceInfo.textColor = EasyTalkTheme.ink
        voiceInfo.text = "Для диктовки нажми системный 🎙 внизу справа, когда открыта наша клавиатура. iOS вставляет слова прямо в поле сообщения. easytalk не открывается и не показывает дополнительное поле. Язык и доступность диктовки задаются средствами iPhone."
        voice.addArrangedSubview(voiceInfo); stack.addArrangedSubview(voice)
        let history = UIButton(type: .system); history.setTitle("История и «Скопировать контекст» →", for: .normal)
        EasyTalkTheme.style(history, primary: true, blue: true)
        history.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold); history.heightAnchor.constraint(equalToConstant: 48).isActive = true
        history.addTarget(self, action: #selector(openHistory), for: .touchUpInside); stack.addArrangedSubview(history)
        if importPrepared { stack.addArrangedSubview(textLabel("Ключ сохранён. Клавиатура подхватит его сама.", size: 17, weight: .medium)) }
        stack.addArrangedSubview(textLabel("Попробуй свою фразу", size: 21, weight: .semibold))
        test.font = .systemFont(ofSize: 21); test.textColor = EasyTalkTheme.ink
        test.backgroundColor = EasyTalkTheme.paper; test.layer.cornerRadius = 16
        test.layer.borderWidth = 1; test.layer.borderColor = EasyTalkTheme.border.resolvedColor(with: traitCollection).cgColor
        test.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        test.accessibilityLabel = "Поле сообщения"; test.accessibilityIdentifier = "messageField"
        test.heightAnchor.constraint(equalToConstant: 110).isActive = true; stack.addArrangedSubview(test)
        test.inputAccessoryView = keyboardDoneBar(self, #selector(hideKeyboard))
        scroll.keyboardDismissMode = .interactive
        let tap = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)); tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        stack.addArrangedSubview(textLabel("Нажми на поле и выбери easytalk через 🌐.", size: 17))
        for (title, detail) in [
            ("1 · Пиши", "По-английски, как получается. Русские слова тоже можно: I want to купить coffee."),
            ("2 · Переводи", "«Перевести ↓» заменит доступный абзац русским текстом. Для отдельного фрагмента сначала выдели его."),
            ("3 · Забирай полезное", "Разбор откроется сразу. «В словарь →» сохраняет слово. В «Игре»: тап — переворот, свайп — следующая карточка. «Запомнил» переносит слово в «Выучил».")
        ] {
            let card = WarmCard(padding: 14); card.addArrangedSubview(textLabel(title, size: 20, weight: .semibold))
            card.addArrangedSubview(textLabel(detail, size: 17)); stack.addArrangedSubview(card)
        }
        stack.addArrangedSubview(textLabel("Первое подключение — через «Настройки». Клавиатуру добавь в настройках iPhone: Основные → Клавиатура → Клавиатуры → Новые клавиатуры.", size: 16))
        stack.addArrangedSubview(textLabel("В ⚙ клавиатуры можно настроить символы, выключить поздравления и скрыть «Второй навык».", size: 16))

    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if importPrepared { test.becomeFirstResponder() }
    }
    @objc private func setup() { navigationController?.pushViewController(SetupViewController(), animated: true) }
    @objc private func hideKeyboard() { view.endEditing(true) }
    @objc private func openHistory() { navigationController?.pushViewController(HistoryViewController(), animated: true) }

}

/// The standard bar above any keyboard (ours or the system one) with «Готово», which hides it.
private func keyboardDoneBar(_ target: Any, _ action: Selector) -> UIToolbar {
    let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
    bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), UIBarButtonItem(title: "Готово", style: .done, target: target, action: action)]
    bar.sizeToFit()
    return bar
}

private func textLabel(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
    let l = UILabel(); l.text = text; l.numberOfLines = 0; l.font = .systemFont(ofSize: size, weight: weight); l.textColor = EasyTalkTheme.ink; return l
}

final class SetupViewController: UIViewController, UITextFieldDelegate {
    private let scroll = UIScrollView()
    private let prefill: ConnectionSettings?
    init(prefill: ConnectionSettings? = nil) { self.prefill = prefill ?? ConnectionStore.read(); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private let providers = AIProvider.allCases
    private lazy var providerControl = UISegmentedControl(items: providers.map(\.title))
    private let providerHelp = UILabel()
    private let model = UITextField()
    private let endpoint = UITextField()
    private let token = UITextField()
    private let keyInfo = UILabel()
    private let modelButton = UIButton(type: .system)
    private var loadedModels: [String] = [], modelsTask: URLSessionDataTask?, modelsTimer: Timer?
    private let message = UILabel()
    private let preferences = KeyboardPreferences(defaults: SharedStorage.defaults())
    private let speakerGender = UISegmentedControl(items: SpeakerGender.allCases.map { $0.title })
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Настройки"; view.backgroundColor = EasyTalkTheme.canvas
        scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        // The visible area ends where any keyboard begins, so nothing stays hidden under it.
        scroll.keyboardDismissMode = .interactive
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        stack.addArrangedSubview(textLabel("Пол для перевода", size: 21))
        if !preferences.hasSpeakerGender, let prefill { preferences.speakerGender = prefill.speakerGender }
        speakerGender.selectedSegmentIndex = SpeakerGender.allCases.firstIndex(of: preferences.speakerGender) ?? 0
        speakerGender.accessibilityLabel = "Пол говорящего для перевода"
        speakerGender.heightAnchor.constraint(equalToConstant: 36).isActive = true
        speakerGender.addTarget(self, action: #selector(changeSpeakerGender), for: .valueChanged)
        stack.addArrangedSubview(speakerGender)
        stack.addArrangedSubview(textLabel("Выбери форму для фраз от первого лица: «я сделал» или «я сделала». Настройка общая с клавиатурой, её можно изменить и в ⚙ клавиатуры.", size: 16))
        stack.addArrangedSubview(textLabel("Подключение AI", size: 21))
        stack.addArrangedSubview(textLabel("Нужен только для кнопки «Перевести». «Скопировать контекст» работает без ключа. Ключ свой: клавиатура обращается к выбранному провайдеру напрямую.", size: 17))
        providerControl.selectedSegmentIndex = providers.firstIndex(of: prefill?.provider ?? .openai) ?? 0
        providerControl.accessibilityLabel = "Провайдер AI"
        providerControl.addTarget(self, action: #selector(changeProvider), for: .valueChanged)
        providerControl.heightAnchor.constraint(equalToConstant: 36).isActive = true
        stack.addArrangedSubview(providerControl)
        providerHelp.numberOfLines = 0; providerHelp.font = .systemFont(ofSize: 15); providerHelp.textColor = EasyTalkTheme.secondary
        stack.addArrangedSubview(providerHelp)
        endpoint.keyboardType = .URL; endpoint.autocapitalizationType = .none
        endpoint.autocorrectionType = .no; endpoint.borderStyle = .roundedRect
        endpoint.accessibilityLabel = "Адрес API своего региона"
        token.isSecureTextEntry = true
        token.addTarget(self, action: #selector(keyChanged), for: .editingChanged)
        modelButton.showsMenuAsPrimaryAction = true; modelButton.contentHorizontalAlignment = .leading
        modelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium); modelButton.tintColor = EasyTalkTheme.link
        modelButton.accessibilityLabel = "Выбрать модель из списка"
        keyInfo.numberOfLines = 0; keyInfo.font = .systemFont(ofSize: 14)
        token.autocorrectionType = .no; token.autocapitalizationType = .none; token.borderStyle = .roundedRect
        model.borderStyle = .roundedRect; model.autocapitalizationType = .none; model.autocorrectionType = .no
        model.accessibilityLabel = "Модель"
        let tap = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)); tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        for f in [endpoint, model, token] {
            f.inputAccessoryView = keyboardDoneBar(self, #selector(hideKeyboard)); f.delegate = self; f.returnKeyType = .done
            f.font = .systemFont(ofSize: 17); f.backgroundColor = EasyTalkTheme.paper; f.textColor = EasyTalkTheme.ink; let h = f.heightAnchor.constraint(equalToConstant: 44)
            h.priority = .init(999); h.isActive = true; stack.addArrangedSubview(f)
            if f === token { stack.addArrangedSubview(keyInfo) }
            if f === model { stack.addArrangedSubview(modelButton) }
        }
        changeProvider()
        if let prefill { token.text = prefill.token; model.text = prefill.model; endpoint.text = prefill.baseURL }
        keyChanged(); loadModels()
        let save = UIButton(type: .system); save.setTitle("Сохранить", for: .normal)
        EasyTalkTheme.style(save, primary: true, blue: true)
        save.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        save.heightAnchor.constraint(equalToConstant: 44).isActive = true
        save.addTarget(self, action: #selector(saveSettings), for: .touchUpInside); stack.addArrangedSubview(save)
        let check = UIButton(type: .system); check.setTitle("Проверить подключение", for: .normal)
        EasyTalkTheme.style(check)
        check.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        check.heightAnchor.constraint(equalToConstant: 44).isActive = true
        check.addTarget(self, action: #selector(checkConnection), for: .touchUpInside); stack.addArrangedSubview(check)
        message.numberOfLines = 0; message.font = .systemFont(ofSize: 16); message.textColor = EasyTalkTheme.ink; stack.addArrangedSubview(message)
        if prefill != nil { message.text = "Ключ сохранён. Клавиатура использует его автоматически." }
        stack.addArrangedSubview(textLabel("В настройках клавиатуры iPhone включи «Полный доступ»: без него iOS не даёт клавиатуре ни сеть, ни общий ключ.", size: 17))
        stack.addArrangedSubview(textLabel("Ключ хранится только на этом iPhone, в защищённом хранилище, общем для приложения и клавиатуры. В буфер обмена он не копируется. Текст отправляется только по кнопке «Перевести».", size: 15))
    }
    private var provider: AIProvider { providers.indices.contains(providerControl.selectedSegmentIndex) ? providers[providerControl.selectedSegmentIndex] : .openai }
    /// A key belongs to one provider: switching clears it and restores that provider's defaults.
    @objc private func changeProvider() {
        let provider = self.provider
        endpoint.isHidden = !provider.editableBaseURL; endpoint.text = provider.defaultBaseURL
        endpoint.placeholder = "https://…aliyuncs.com/compatible-mode/v1"
        model.text = provider.defaultModel; model.placeholder = "Модель \(provider.title)"
        token.placeholder = provider.keyPlaceholder; token.text = ""
        providerHelp.text = provider.keyHelp + " Модель можно заменить на любую доступную вашему ключу."
        modelsTask?.cancel(); loadedModels = []; updateModelMenu(status: nil)
        keyChanged()
    }
    @objc private func hideKeyboard() { view.endEditing(true) }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
    /// Keep the edited field and the «Сохранить» button under it above the keyboard.
    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let frame = textField.convert(textField.bounds, to: self.scroll)
            self.scroll.scrollRectToVisible(CGRect(x: frame.minX, y: frame.minY - 16, width: frame.width, height: frame.height + 96), animated: true)
        }
    }
    @objc private func changeSpeakerGender() {
        guard SpeakerGender.allCases.indices.contains(speakerGender.selectedSegmentIndex) else { return }
        preferences.speakerGender = SpeakerGender.allCases[speakerGender.selectedSegmentIndex]
        if var saved = ConnectionStore.read() { saved.speakerGender = preferences.speakerGender; ConnectionStore.write(saved) }
    }
    private var formConfig: ConnectionSettings {
        ConnectionSettings(provider: provider, apiKey: (token.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            model: (model.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: (endpoint.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), speakerGender: preferences.speakerGender)
    }
    /// The key stays hidden; a masked summary and a warning show whether it is the right, complete key.
    @objc private func keyChanged() {
        // A new key: reload the provider's model list shortly after typing or pasting stops.
        modelsTimer?.invalidate()
        modelsTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.loadModels() }
        let key = ConnectionSettings.cleanKey(token.text ?? "")
        guard !key.isEmpty else { keyInfo.text = "Ключ не введён."; keyInfo.textColor = EasyTalkTheme.secondary; return }
        if let warning = provider.keyWarning(key) {
            keyInfo.text = ConnectionSettings.keySummary(key) + "\n⚠️ " + warning; keyInfo.textColor = .systemOrange
        } else {
            keyInfo.text = ConnectionSettings.keySummary(key); keyInfo.textColor = EasyTalkTheme.secondary
        }
    }
    /// The models this key can use, from the provider; the built-in list until then or on failure.
    @objc private func loadModels() {
        modelsTask?.cancel()
        let config = formConfig
        guard provider.keyWarning(config.token) == nil, let request = ModelCatalog.request(config: config) else { updateModelMenu(status: nil); return }
        updateModelMenu(status: "Загружаю список моделей…")
        let provider = self.provider
        modelsTask = AnalysisService.session.dataTask(with: request) { [weak self] data, response, _ in
            let models = (response as? HTTPURLResponse)?.statusCode == 200 ? data.map { ModelCatalog.parse($0, provider: provider) } ?? [] : []
            DispatchQueue.main.async {
                guard let self, self.provider == provider else { return }
                self.loadedModels = models
                self.updateModelMenu(status: models.isEmpty ? "Список с сервера не получен — показаны рекомендуемые" : nil)
            }
        }
        modelsTask?.resume()
    }
    private func updateModelMenu(status: String?) {
        let fromServer = !loadedModels.isEmpty
        let models = fromServer ? loadedModels : provider.suggestedModels
        let title = status ?? (fromServer ? "Выбрать модель: \(models.count) доступно вашему ключу ▾" : "Выбрать из рекомендуемых моделей ▾")
        modelButton.setTitle(title, for: .normal)
        let current = (model.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let choices = models.map { name in
            UIAction(title: name, subtitle: name == provider.defaultModel ? "по умолчанию" : nil, state: name == current ? .on : .off) { [weak self] _ in
                self?.model.text = name; self?.updateModelMenu(status: nil)
            }
        }
        let reload = UIAction(title: "Обновить список с сервера", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.loadModels() }
        modelButton.menu = UIMenu(title: fromServer ? "Модели \(provider.title) с сервера" : "Рекомендуемые модели \(provider.title)",
                                  children: [UIMenu(options: .displayInline, children: choices), reload])
    }
    private var checkOperation: AnalysisOperation?
    /// One request with an invented phrase (never the user's text): shows time and the provider's answer or reason.
    @objc private func checkConnection() {
        view.endEditing(true)
        let config = formConfig
        guard config.url != nil else {
            message.text = provider.editableBaseURL ? "Введи ключ, модель и HTTPS-адрес Model Studio (…aliyuncs.com)." : "Введи ключ \(provider.title) и название модели."; return
        }
        checkOperation?.cancel(); message.text = "Проверяю на тестовой фразе «I want to купить coffee.»…"
        let started = Date()
        checkOperation = AnalysisOperation(source: "I want to купить coffee.", config: config) { [weak self] result, trace in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checkOperation = nil
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                switch result {
                case .success(let analysis):
                    self.message.text = "Работает: \(config.provider.title) · \(config.model) · \(seconds) с.\nПеревод: «\(analysis.translated)». Не забудь «Сохранить»."
                case .failure(let failure):
                    self.message.text = "Не работает (\(failure.code), \(seconds) с). " + failure.message(details: trace.response)
                }
                UIAccessibility.post(notification: .announcement, argument: self.message.text)
            }
        }
    }
    @objc private func saveSettings() {
        let config = formConfig
        guard config.url != nil else {
            message.text = provider.editableBaseURL ? "Введи ключ, модель и HTTPS-адрес Model Studio (…aliyuncs.com)." : "Введи ключ \(provider.title) и название модели."; return
        }
        guard ConnectionStore.write(config) else {
            message.text = "Не удалось сохранить подключение. Ключ остался в поле."; return
        }
        message.text = "Ключ сохранён. Клавиатура использует его автоматически."; view.endEditing(true)
    }
    #if targetEnvironment(simulator)
    func runConnectionRegression() {
        ConnectionStore.isolatedPreview = true
        ConnectionStore.previewConnection = nil
        let previousGender = preferences.hasSpeakerGender ? preferences.speakerGender : nil
        defer {
            if let previousGender { preferences.speakerGender = previousGender }
            ConnectionStore.previewConnection = nil; ConnectionStore.isolatedPreview = false
        }
        loadViewIfNeeded(); let expected = token.text
        speakerGender.selectedSegmentIndex = 2; changeSpeakerGender()
        saveSettings(); let first = ConnectionStore.read()
        saveSettings(); let repeated = ConnectionStore.read()
        precondition(first?.token == expected && repeated?.token == expected, "Saving twice keeps the same key")
        precondition(repeated?.speakerGender == .female, "Gender is saved with the connection")
        precondition(token.text == expected && token.isSecureTextEntry, "Save must keep the masked key for retry")
        let reopened = SetupViewController(); reopened.loadViewIfNeeded()
        precondition(reopened.token.text == expected, "Reopening settings must restore the saved key")
        precondition(reopened.speakerGender.selectedSegmentIndex == 2, "Gender must persist")
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("connection-retry-check.json")
        try! Data("{\"result\":\"passed\",\"repeated_save\":true,\"reopen\":true,\"isolated_credentials\":true}".utf8).write(to: path)
        print("CONNECTION RETRY REGRESSION PASSED")
    }
    #endif
}

#if targetEnvironment(simulator)
/// Render the real keyboard view, without requiring manual Settings navigation in Simulator.
final class KeyboardPreviewController: UIViewController {
    private let keyboard = KeyboardViewController()
    private let output = UILabel()
    private let state: String
    private let dark: Bool
    private var insertionCount = 0
    private var hostText = "I want to купить coffee"
    private let document = UUID()
    init(state: String) { self.dark = state.hasSuffix("-dark"); self.state = state.replacingOccurrences(of: "-dark", with: ""); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = EasyTalkTheme.canvas
        if dark { overrideUserInterfaceStyle = .dark }
        if ["words", "wordcards", "dictionary"].contains(state) { hostText = KeyboardViewController.multiSource }
        if state == "reward" { hostText = "I want to learn English" }
        let title = textLabel("Сообщение", size: 24, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(title)
        output.numberOfLines = 0; output.font = .systemFont(ofSize: 22)
        output.text = hostText
        output.backgroundColor = .secondarySystemBackground
        output.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(output)
        addChild(keyboard)
        if state == "regression" { keyboard.runStartupRegression() }
        keyboard.previewSnapshot = { [unowned self] in InputSnapshot(document: self.document, before: self.hostText, after: "", selected: nil) }
        keyboard.previewType = { [unowned self] text in self.hostText += text; self.output.text = self.hostText }
        keyboard.previewDelete = { [unowned self] in if !self.hostText.isEmpty { self.hostText.removeLast() }; self.output.text = self.hostText }
        keyboard.previewReplace = { [unowned self] captured, text in
            guard captured == InputSnapshot(document: self.document, before: self.hostText, after: "", selected: nil) else { return false }
            self.hostText = text; self.output.text = text; self.insertionCount += 1; return true
        }
        keyboard.view.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(keyboard.view)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            output.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            output.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            output.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            output.heightAnchor.constraint(equalToConstant: 100),
            keyboard.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        keyboard.didMove(toParent: self); keyboard.preparePreview(state)
        if state == "regression" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.keyboard.runPreviewRegression()
                precondition(self.output.text == "Я хочу купить кофе")
                precondition(self.insertionCount == 1, "Repeated insert must not duplicate the message")
                SetupViewController(prefill: ConnectionSettings(apiKey: "test-only-key")).runConnectionRegression()
                self.keyboard.runMechanicsRegression()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.keyboard.runDesignRegression(); self.keyboard.runCardGestureRegression()
                }
            }
        }
    }
}
#endif
