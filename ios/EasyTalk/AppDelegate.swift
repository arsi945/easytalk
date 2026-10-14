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
    /// Shown until the AI is connected: the wizard is one tap away.
    private let setupHint = SettingsRow(title: "Подключи AI для кнопки «Перевести»", detail: "Пошагово, за пару минут")
    init(importPrepared: Bool = false) { self.importPrepared = importPrepared; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "easytalk"
        view.backgroundColor = EasyTalkTheme.canvas
        navigationController?.navigationBar.tintColor = EasyTalkTheme.ink
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(setup))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Настройки"
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
        let hintCard = SettingsUI.card()
        setupHint.addTarget(self, action: #selector(openConnection), for: .touchUpInside)
        hintCard.addArrangedSubview(setupHint)
        stack.addArrangedSubview(hintCard)
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
            ("2 · Переводи", "«Перевести» заменит всё сообщение русским текстом. Для отдельного фрагмента сначала выдели его."),
            ("3 · Забирай полезное", "Разбор откроется сразу. «В словарь →» сохраняет слово; можно и выделить слово в тексте → «В словарь». В «Игре»: тап — переворот, свайп — следующая карточка.")
        ] {
            let card = WarmCard(padding: 14); card.addArrangedSubview(textLabel(title, size: 20, weight: .semibold))
            card.addArrangedSubview(textLabel(detail, size: 17)); stack.addArrangedSubview(card)
        }
        let guide = SettingsUI.secondaryButton("Как пользоваться клавиатурой →", self, #selector(openGuide))
        stack.addArrangedSubview(guide)
        stack.addArrangedSubview(textLabel("Клавиатуру добавь в настройках iPhone: easytalk → Клавиатуры → включи easytalk и «Полный доступ».", size: 16))

    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupHint.superview?.isHidden = ConnectionStore.read() != nil
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if importPrepared { test.becomeFirstResponder() }
    }
    @objc private func setup() { navigationController?.pushViewController(SettingsViewController(), animated: true) }
    @objc private func openConnection() { navigationController?.pushViewController(AIConnectionViewController(), animated: true) }
    @objc private func openGuide() { navigationController?.pushViewController(GuideViewController(), animated: true) }
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
                AIConnectionViewController.runConnectionRegression()
                self.keyboard.runMechanicsRegression()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.keyboard.runDesignRegression(); self.keyboard.runCardGestureRegression()
                }
            }
        }
    }
}
#endif
