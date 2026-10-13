import Foundation
import Combine
import EasyTalkCore
import EasyTalkLearning

enum DesktopPage: String, CaseIterable, Identifiable {
    case compose, study, dictionary, idioms, game, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .compose: return "Написать"; case .study: return "Учёба"; case .dictionary: return "Мой словарь"; case .idioms: return "Идиомы"; case .game: return "Второй навык"; case .settings: return "Настройки" }
    }
    var symbol: String {
        switch self { case .compose: return "square.and.pencil"; case .study: return "text.book.closed"; case .dictionary: return "bookmark"; case .idioms: return "books.vertical"; case .game: return "sparkles"; case .settings: return "gearshape" }
    }
}
protocol DesktopCancellation { func cancel() }
extension AnalysisOperation: DesktopCancellation {}
protocol DesktopAnalyzer {
    func start(source: String, config: ConnectionSettings, completion: @escaping (Result<LearningResponse, AnalysisFailure>) -> Void) -> DesktopCancellation
}
struct LiveDesktopAnalyzer: DesktopAnalyzer {
    var session: URLSession = AnalysisService.session
    func start(source: String, config: ConnectionSettings, completion: @escaping (Result<LearningResponse, AnalysisFailure>) -> Void) -> DesktopCancellation {
        AnalysisOperation(source: source, config: config, session: session) { result, _ in completion(result) }
    }
}

/// All mutations happen on the main queue. Providers must deliver their callback there.
final class DesktopModel: ObservableObject {
    @Published private var selectedLessonID: UUID?
    private let defaults: UserDefaults
    @Published var compact = false { didSet { defaults.set(compact, forKey: "desktop.compact"); onCompactChange?(compact) } }
    var onCompactChange: ((Bool) -> Void)?
    @Published private(set) var inputHeight: CGFloat = 64
    var onInputHeightChange: (() -> Void)?
    private var settingsReturnPage: DesktopPage = .compose
    private var settingsReturnCompact = false
    var onImportClipboard: (() -> Void)?
    @Published var page: DesktopPage = .compose { didSet { if oldValue != page { cancelStudy() } } }
    @Published private(set) var draft = ""
    @Published private(set) var selection = NSRange(location: 0, length: 0)
    @Published private(set) var busy = false
    @Published var notice = "Напиши по-английски. Русские вставки тоже можно."
    @Published private(set) var reward: String?
    @Published private(set) var copiedTranslationID: UUID?
    @Published private(set) var revision = 0
    @Published private(set) var connection: ConnectionSettings?
    @Published var gender: SpeakerGender { didSet { preferences.speakerGender = gender; invalidateRequest() } }
    @Published var rewardsEnabled: Bool { didSet { preferences.rewardsEnabled = rewardsEnabled; if !rewardsEnabled { reward = nil } } }
    @Published var gameEnabled: Bool { didSet { preferences.secondSkillEnabled = gameEnabled; if !gameEnabled { game = nil; if page == .game { page = .dictionary } }; changed() } }
    let store: LearningStore
    let progress: StudyProgressStore
    let preferences: KeyboardPreferences
    private let rewards: RewardProgress
    private let vault: MacCredentialVault
    private let analyzer: DesktopAnalyzer
    private var operation: DesktopCancellation?
    private var generation = 0
    @Published private(set) var studyBusy = false
    @Published private(set) var studyNotice = ""
    @Published var variantsExpanded = false
    @Published var dictionaryFilter: VocabularyFilter = .all
    @Published private(set) var gameFeedback: String?
    private var feedbackTimer: Timer?
    private var studyOperation: StudyActionOperation?
    private var studyGeneration = 0
    private let speech = SpeechPlayer()
    private(set) var game: StudySession?
    private var recordedRound = false
    private var lastTranslation: (document: String, selection: NSRange)?
    var onCopy: ((String) -> Void)?
    var onPaste: ((String) -> Void)?
    @Published var insertionDestination: String?
    var onPrepareInsertion: (() -> ((String) -> Void)?)?
    var onExport: ((Data) -> Void)?
    var exportMessage: String?
    var lesson: Lesson? { store.lessons.first { $0.id == selectedLessonID } ?? store.lessons.first }
    var scope: DraftScope? { DraftScope(document: draft, selection: selection) }
    var alreadyTranslated: Bool { lastTranslation?.document == draft && lastTranslation?.selection == selection }
    var canTranslate: Bool { scope != nil && !alreadyTranslated }
    var translationTitle: String { busy ? "Отменить" : (connection == nil ? "Подключить AI" : "Перевести ↓") }

    init(defaults: UserDefaults = .standard, vault: MacCredentialVault = MacKeychainVault(), analyzer: DesktopAnalyzer = LiveDesktopAnalyzer()) {
        self.defaults = defaults
        store = LearningStore(defaults: defaults); progress = StudyProgressStore(defaults: defaults)
        preferences = KeyboardPreferences(defaults: defaults); rewards = RewardProgress(defaults: defaults)
        self.vault = vault; self.analyzer = analyzer
        let saved = vault.read()
        connection = saved; gender = preferences.hasSpeakerGender ? preferences.speakerGender : saved?.speakerGender ?? .unspecified
        rewardsEnabled = preferences.rewardsEnabled; gameEnabled = preferences.secondSkillEnabled
        draft = defaults.string(forKey: "desktop.draft") ?? ""; selection = NSRange(location: draft.utf16.count, length: 0); compact = defaults.bool(forKey: "desktop.compact")
    }
    deinit { operation?.cancel(); studyOperation?.cancel(); feedbackTimer?.invalidate(); speech.stop() }
    func changed() { revision += 1 }
    func edit(_ text: String, selection: NSRange) {
        guard draft != text || self.selection != selection else { return }
        let wasBusy = busy
        insertionDestination = nil
        invalidateRequest(); draft = text; self.selection = selection; defaults.set(text, forKey: "desktop.draft"); reward = nil
        notice = wasBusy ? "Текст или курсор изменились. Перевод отменён; нажми ещё раз." : ""
    }
    private func invalidateRequest() { cancelStudy(); generation += 1; operation?.cancel(); operation = nil; busy = false }
    func translate() {
        precondition(Thread.isMainThread)
        if busy { invalidateRequest(); notice = "Перевод отменён. Текст сохранён."; return }
        guard var config = connection, config.url != nil else { openSettings(); notice = "Добавь ключ AI в настройках."; return }
        guard !alreadyTranslated else { notice = "Измени текст или выбери другой абзац."; return }
        guard let captured = scope else { notice = "Напиши текст или выдели фрагмент для перевода."; return }
        guard captured.source.unicodeScalars.count <= 2000 else { notice = "Выдели фрагмент до 2000 символов."; return }
        let deliver = insertionDestination == nil ? nil : onPrepareInsertion?()
        insertionDestination = nil
        config.speakerGender = gender
        invalidateRequest(); let expected = generation; busy = true; reward = nil; notice = "Перевожу… Исходный текст можно продолжать редактировать."
        operation = analyzer.start(source: captured.source, config: config) { [weak self] result in
            guard let self, self.generation == expected else { return }
            precondition(Thread.isMainThread); self.busy = false; self.operation = nil
            switch result {
            case .failure(let error): self.notice = error.message + " Исходный текст сохранён."
            case .success(let response):
                guard let valid = response.normalized(for: captured.source), valid.isValid(for: captured.source),
                      let replaced = captured.replacing(with: valid.translated, current: self.draft, selection: self.selection) else {
                    self.notice = "Текст или выделение изменились. Повтори перевод."; return
                }
                self.draft = replaced.text; self.selection = replaced.cursor; self.defaults.set(self.draft, forKey: "desktop.draft")
                self.lastTranslation = (self.draft, self.selection)
                self.copiedTranslationID = nil
                self.selectedLessonID = nil
                self.store.record(source: captured.source, response: valid)
                let praise = self.rewards.record(source: captured.source, hasErrors: valid.hasErrors)
                self.reward = self.rewardsEnabled ? praise : nil
                self.notice = "Переведено."
                self.variantsExpanded = false; self.openStudy()
                self.changed()
                deliver?(valid.translated)
            }
        }
    }
    @discardableResult func importSelection(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.unicodeScalars.count <= 2000 else { notice = "Выдели текст до 2000 символов."; return false }
        edit(text, selection: NSRange(location: 0, length: text.utf16.count)); page = .compose; compact = false
        notice = "Выделенный текст готов. Нажми «Перевести»."; return true
    }
    func openSettings() {
        if page != .settings { settingsReturnPage = page; settingsReturnCompact = compact }
        compact = false; page = .settings
    }
    func closeSettings() { page = settingsReturnPage; compact = settingsReturnCompact }
    func updateInputHeight(_ height: CGFloat) {
        guard abs(inputHeight - height) > 0.5 else { return }
        inputHeight = height; if compact { onInputHeightChange?() }
    }
    func chooseLesson(_ id: UUID) { cancelStudy(); variantsExpanded = false; studyNotice = ""; selectedLessonID = id; store.markRead(id); changed() }
    func openStudy() { compact = false; page = .study; if let lesson { store.markRead(lesson.id); changed() } }
    func save(_ word: VocabularySuggestion) { guard let lesson else { return }; store.save(word, lesson: lesson); changed() }
    func speak(_ text: String) { if !speech.speak(text) { studyNotice = "Английский голос недоступен в настройках macOS." } }
    func cancelStudy() { studyGeneration += 1; studyOperation?.cancel(); studyOperation = nil; studyBusy = false; speech.stop() }
    private func studyAction(_ action: StudyAction, source: String, apply: @escaping (StudyActionResult) -> Void) {
        if studyBusy { cancelStudy(); studyNotice = "Запрос отменён."; return }
        guard let connection else { studyNotice = "Подключи AI в настройках."; return }
        cancelStudy(); let token = studyGeneration; studyBusy = true; studyNotice = ""
        studyOperation = StudyActionOperation(action, source: source, config: connection) { [weak self] result in
            guard let self, self.studyGeneration == token else { return }
            self.studyOperation = nil; self.studyBusy = false
            switch result {
            case .success(let value): apply(value); self.studyNotice = ""
            case .failure(let error): self.studyNotice = error == .incomplete ? "AI вернул неполный ответ. Попробуй ещё раз." : error.message
            }; self.changed()
        }
    }
    func rephrase() {
        guard let lesson else { return }
        studyAction(.rephrase, source: lesson.response.corrected) { [weak self] value in
            if case .variants(let variants) = value { self?.store.setVariants(variants, lesson: lesson.id); self?.variantsExpanded = true }
        }
    }
    func refine(_ word: VocabularyEntry) {
        studyAction(.dictionary, source: word.displayTerm) { [weak self] value in
            guard let self, case .dictionary(let entry) = value else { return }
            self.store.setDictionary(entry, word: word.id); self.game?.refresh(from: self.progress.pool(words: self.store.words))
        }
    }
    func dismiss(_ word: VocabularySuggestion) { guard let lesson else { return }; store.dismiss(word.term, lesson: lesson.id); changed() }
    func restoreSkipped() { guard let lesson else { return }; for term in lesson.dismissedTerms ?? [] { store.restoreSuggestion(term, lesson: lesson.id) }; changed() }
    func remove(_ word: VocabularyEntry) { progress.setLearned("word." + word.id.uuidString, false); store.removeWord(word.id); game = nil; changed() }
    func changeMastery(_ id: String) { progress.setLearned(id, !progress.isLearned(id)); game = nil; changed() }
    func saveIdiom(_ idiom: IdiomEntry) {
        store.saveEntry(VocabularyEntry(term: idiom.term, meaning: idiom.meaning, kind: "idiom", originalContext: "", correctedContext: idiom.example))
        if progress.isLearned(idiom.id), let word = store.words.first(where: { $0.term.lowercased() == idiom.term.lowercased() }) { progress.setLearned("word." + word.id.uuidString, true) }
        changed()
    }
    func startGame(reviewLearned: Bool = false) {
        guard gameEnabled else { return }
        feedbackTimer?.invalidate(); gameFeedback = nil
        game = StudySession(candidates: progress.candidates(words: store.words, reviewLearned: reviewLearned)); recordedRound = false; page = .game; reward = nil; changed()
    }
    func flipCard() { _ = game?.flip(); changed() }
    func moveCard(_ direction: Int) {
        guard game?.move(by: direction) == true else { return }
        finishRound()
        changed()
    }
    private func finishRound() {
        if let game, game.finished && !recordedRound && game.initialCount > 0 { progress.finishSession(); recordedRound = true }
    }
    func rememberCard() {
        guard let card = game?.archiveCurrent() else { return }
        cancelStudy(); progress.setLearned(card.id, true); finishRound()
        gameFeedback = rewardsEnabled ? "🌟 +1 выученное слово" : "Слово в «Выучил»"
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in self?.gameFeedback = nil }
        changed()
    }
    @discardableResult func saveConnection(key: String, model: String, provider: AIProvider, baseURL: String = "") -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty field keeps the saved key, but only for the same provider.
        let secret = key.isEmpty && connection?.provider == provider ? connection?.token ?? "" : key
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = ConnectionSettings(provider: provider, apiKey: secret, model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                                        baseURL: base.isEmpty ? nil : base, speakerGender: gender)
        guard config.url != nil else { notice = "Укажи ключ \(provider.title) и модель" + (provider.editableBaseURL ? " и адрес вида \(provider.addressHint)." : "."); return false }
        guard vault.write(config) else { notice = "Не удалось сохранить ключ в Keychain. Поле не очищено."; return false }
        invalidateRequest(); connection = config; notice = "Подключение сохранено в Keychain."; changed(); return true
    }
    func disconnect() { guard vault.delete() else { notice = "Не удалось удалить ключ."; return }; invalidateRequest(); connection = nil; notice = "AI отключён. Словарь и карточки доступны." }
    func copyDraft() { guard !draft.isEmpty else { return }; onCopy?(draft); notice = "Текст скопирован." }
    func copyTranslation(_ id: UUID) {
        guard let lesson = store.lessons.first(where: { $0.id == id }), let copy = onCopy else { return }
        copy(lesson.response.translated); copiedTranslationID = id
    }
    func pasteDraft() { guard !draft.isEmpty else { return }; onPaste?(draft) }
    func exportWords() {
        let export = VocabularyExport(schemaVersion: 1, exportedAt: Date(), words: store.words)
        if let data = try? JSONEncoder().encode(export) { onExport?(data) }
    }
    struct VocabularyExport: Codable { let schemaVersion: Int; let exportedAt: Date; let words: [VocabularyEntry] }
}
