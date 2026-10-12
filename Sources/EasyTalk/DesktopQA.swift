import AppKit
import SwiftUI
import EasyTalkCore
import EasyTalkLearning

/// Runs before real services are constructed: no Keychain, AI, clipboard or AX access.
enum DesktopQA {
    private final class Transport: URLProtocol {
        static var count = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.count += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    private final class Cancellation: DesktopCancellation { var cancelled = false; func cancel() { cancelled = true } }
    private final class FakeAnalyzer: DesktopAnalyzer {
        var sources: [String] = []; var configs: [ConnectionSettings] = []
        var callbacks: [(Result<LearningResponse, AnalysisFailure>) -> Void] = []; var operations: [Cancellation] = []
        func start(source: String, config: ConnectionSettings, completion: @escaping (Result<LearningResponse, AnalysisFailure>) -> Void) -> DesktopCancellation {
            sources.append(source); configs.append(config); callbacks.append(completion)
            let op = Cancellation(); operations.append(op); return op
        }
    }
    static func run(to path: String) {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { fputs("QA directory unavailable\n", stderr); exit(1) }
        let suite = "easytalk.mac.qa." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeAnalyzer(); let vault = MemoryCredentialVault()
        let model = DesktopModel(defaults: defaults, vault: vault, analyzer: fake)
        var checks: [[String: Any]] = []
        func check(_ value: Bool, _ name: String) { checks.append(["name": name, "passed": value]); if !value { fputs("FAIL: \(name)\n", stderr) } }
        model.translate()
        check(model.page == .settings && model.notice.contains("ключ") && fake.sources.isEmpty, "click without a key opens settings with a visible explanation")
        model.closeSettings(); check(model.page == .compose, "settings back action returns to input")
        model.page = .dictionary; model.openSettings(); model.closeSettings()
        check(model.page == .dictionary && !model.compact, "settings remembers the originating page")
        model.page = .compose; model.compact = true; model.openSettings(); model.closeSettings()
        check(model.page == .compose && model.compact, "settings return restores quick input")
        model.compact = false
        let controller = DesktopWindowController(model: model)
        check(controller.window!.styleMask.contains(.miniaturizable) && !controller.window!.styleMask.contains(.utilityWindow) && controller.window!.styleMask.contains(.titled), "panel has standard title bar with minimize control")
        model.page = .compose
        let panelArea = NSRect(x: 0, y: 0, width: 1440, height: 880)
        let expanded = DesktopPanelGeometry.frame(in: panelArea, compact: false), compact = DesktopPanelGeometry.frame(in: panelArea, compact: true)
        check(expanded.width == 392 && expanded.maxX == panelArea.maxX - 12 && expanded.maxY == panelArea.maxY - 12 && compact.height == 260 && compact.maxY == expanded.maxY, "expanded and compact panels stay at the right top edge")
        let emptyHeight = DesktopEditorMetrics.height(for: "", width: 364, maximum: 320)
        let oneLineHeight = DesktopEditorMetrics.height(for: "Hello!", width: 364, maximum: 320)
        let wrapped = String(repeating: "I am learning to write English. ", count: 5)
        let wrappedHeight = DesktopEditorMetrics.height(for: wrapped, width: 364, maximum: 320)
        check(emptyHeight == 64 && oneLineHeight == emptyHeight && wrappedHeight > oneLineHeight, "empty editor is one line and grows with wrapped text")
        check(DesktopEditorMetrics.height(for: wrapped, width: 250, maximum: 320) > wrappedHeight, "narrowing the panel grows the editor for wrapped lines")
        check(DesktopEditorMetrics.height(for: "Hello!\n", width: 364, maximum: 320) > oneLineHeight, "Enter reserves a visible empty final line")
        check(DesktopEditorMetrics.height(for: String(repeating: "More text.\n", count: 100), width: 364, maximum: 320) == 320, "long editor stops growing so its native scroll remains usable")
        let growing = DesktopPanelGeometry.frame(in: panelArea, compact: true, inputHeight: 184)
        check(growing.height == 380 && growing.maxX == compact.maxX && growing.maxY == compact.maxY, "quick input expands downwards without moving its top right edge")
        check(model.importSelection("Selected first.\nSelected second.") && model.scope?.source == "Selected first.\nSelected second." && fake.sources.isEmpty, "explicit service import selects the whole fragment without sending it to AI")
        check(!model.importSelection(String(repeating: "a", count: 2001)) && model.draft == "Selected first.\nSelected second.", "oversized service text cannot replace the draft")
        let editor = DesktopTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        let coordinator = DesktopEditor.Coordinator(model); editor.delegate = coordinator
        editor.string = "I learn English.\n"; editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.didChangeText()
        check(model.draft == editor.string && model.scope?.source == "I learn English.", "native text editing publishes a translatable paragraph after Enter")
        check(DesktopModel(defaults: defaults, vault: vault, analyzer: fake).draft == editor.string, "draft survives reopening the panel")
        let service = DesktopSelectionService { model.importSelection($0) }
        let serviceBoard = NSPasteboard.withUniqueName(); defer { serviceBoard.releaseGlobally() }
        serviceBoard.setString("Only this selection", forType: .string)
        var serviceError: NSString?
        service.sendToEasyTalk(serviceBoard, userData: nil, error: &serviceError)
        check(serviceError == nil && model.draft == "Only this selection" && fake.sources.isEmpty, "system service consumes only the supplied selection pasteboard")
        serviceBoard.clearContents(); service.sendToEasyTalk(serviceBoard, userData: nil, error: &serviceError)
        check(serviceError != nil && model.draft == "Only this selection", "empty service request reports an error and preserves the draft")
        let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [Transport.self]
        let isolated = URLSession(configuration: sessionConfig); defer { isolated.invalidateAndCancel() }
        let live = DesktopModel(defaults: UserDefaults(suiteName: suite + ".transport")!, vault: vault, analyzer: LiveDesktopAnalyzer(session: isolated))
        defer { UserDefaults(suiteName: suite + ".transport")?.removePersistentDomain(forName: suite + ".transport") }
        _ = live.saveConnection(key: "mock-not-a-real-key", model: "gpt-6-luna", provider: .openai)
        live.edit("I learn English.\n", selection: NSRange(location: 17, length: 0)); live.translate()
        check(live.busy && live.notice.contains("Перевожу"), "translation click immediately exposes progress with the real analyzer")
        let deadline = Date().addingTimeInterval(2)
        while live.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(Transport.count == 1 && !live.busy && live.notice.contains("503") && live.draft == "I learn English.\n", "real analyzer sends one mocked request and makes the failure visible")
        let text = "First paragraph stays.\nI learn English.\nLast paragraph stays."
        let location = (text as NSString).range(of: "learn").location
        model.edit(text, selection: NSRange(location: location, length: 0))
        check(model.scope?.source == "I learn English.", "only current paragraph is submitted")
        check(model.saveConnection(key: "mock-not-a-real-key", model: "gpt-6-luna", provider: .openai), "credential saved through injected vault")
        model.gender = .female; model.translate()
        check(model.busy && fake.sources == ["I learn English."] && fake.configs.last?.speakerGender == .female, "request contains source scope and settings gender")
        let good = LearningResponse(corrected: "I learn English.", translated: "Я учу английский.", diffs: [], vocabulary: [VocabularySuggestion(term: "learn English", meaning: "учить английский", kind: "phrase")])
        fake.callbacks[0](.success(good))
        check(model.draft == "First paragraph stays.\nЯ учу английский.\nLast paragraph stays.", "translation replaces just one paragraph")
        check(!model.busy && model.reward != nil && model.store.lessons.count == 1, "successful verified translation records lesson and praise")
        check(model.page == .study && !model.canTranslate && model.alreadyTranslated, "unchanged translation button becomes muted")
        var copied: [String] = []; model.onCopy = { copied.append($0) }
        let translatedDraft = model.draft; let translatedSelection = model.selection
        model.copyTranslation(model.lesson!.id)
        check(copied == [good.translated] && model.copiedTranslationID == model.lesson!.id && model.draft == translatedDraft && model.selection == translatedSelection, "copy translation copies only Russian and preserves editor scope")
        let count = fake.sources.count; model.translate(); check(fake.sources.count == count, "keyboard shortcut cannot resubmit unchanged translation")
        model.openStudy(); check(model.store.unreadCount == 0, "opening study marks latest lesson read")
        let suggestion = good.vocabulary[0]; model.dismiss(suggestion)
        check(model.store.isDismissed(suggestion.term, lesson: model.lesson!) && model.store.words.isEmpty, "cross skips the named word without saving")
        model.restoreSkipped(); model.save(suggestion); model.save(suggestion)
        check(model.store.words.count == 1 && model.store.words.first?.term == "learn English", "arrow saves the exact term once")
        var exported: Data?; model.onExport = { exported = $0 }; model.exportWords()
        check(exported.flatMap { try? JSONDecoder().decode(DesktopModel.VocabularyExport.self, from: $0) }?.words.count == 1 && !(String(data: exported ?? Data(), encoding: .utf8) ?? "").contains("mock-not-a-real-key"), "dictionary export excludes credentials")
        model.edit("I learn English.", selection: NSRange(location: 3, length: 0)); model.translate()
        let old = fake.callbacks.last!; model.edit("I learn English. More text.", selection: NSRange(location: 25, length: 0)); old(.success(good))
        check(model.draft == "I learn English. More text." && !model.busy && fake.operations.last!.cancelled, "editing cancels pending result and preserves new text")
        model.edit("I learn English.", selection: NSRange(location: 3, length: 0)); model.translate()
        let cursorCallback = fake.callbacks.last!; model.edit(model.draft, selection: NSRange(location: 4, length: 0)); cursorCallback(.success(good))
        check(model.draft == "I learn English.", "cursor changes invalidate pending replacement")
        model.translate(); model.translate(); fake.callbacks.last!(.success(good))
        check(!model.busy && model.draft == "I learn English.", "explicit cancellation ignores a late success")
        model.translate(); fake.callbacks.last!(.failure(.network(URLError.timedOut.rawValue)))
        check(model.draft == "I learn English." && !model.busy && model.notice.contains("30"), "timeout leaves original text and actionable error")
        model.translate(); fake.callbacks.last!(.success(LearningResponse(corrected: "", translated: "", diffs: [], vocabulary: [])))
        check(model.draft == "I learn English." && model.store.lessons.count == 1, "incomplete response cannot replace or create lesson")
        let long = String(repeating: "a", count: 2001); model.edit(long, selection: NSRange(location: 0, length: 0)); let requests = fake.sources.count; model.translate()
        check(fake.sources.count == requests && model.notice.contains("2000"), "oversized paragraph is not submitted")
        let emoji = "A😀B\r\nSecond.\n"; let scope = DraftScope(document: emoji, selection: NSRange(location: 0, length: 4))
        check(scope?.source == "A😀B" && scope?.isSelection == true, "UTF16 selection preserves emoji")
        check(DraftScope(document: emoji, selection: NSRange(location: 2, length: 0)) == nil, "invalid surrogate boundary rejected")
        check(DraftScope(document: emoji, selection: NSRange(location: 4, length: 0))?.source == "A😀B", "CRLF removed from paragraph payload")
        check(DraftScope(document: emoji, selection: NSRange(location: emoji.utf16.count, length: 0))?.source == "Second.", "Enter after a paragraph still translates the last nonempty paragraph")
        check(DraftScope(document: "   ", selection: NSRange(location: 0, length: 0)) == nil, "blank draft cannot be translated")
        check(scope?.replacing(with: "X", current: emoji + "changed", selection: scope!.selection) == nil, "stale document refused independently of model")
        check(!model.saveConnection(key: "", model: "", provider: .openai) && vault.settings?.model == "gpt-6-luna", "invalid settings leave stored credential intact")
        check(model.saveConnection(key: "", model: "gpt-6-luna", provider: .openai) && vault.settings?.token == "mock-not-a-real-key", "empty key field keeps previous credential")
        check(IdiomCatalog.all.count == 60 && Array(IdiomCatalog.all.prefix(12)).map(\.id) == (1...12).map { "second-skill.i\($0)" }, "shared 60-entry catalogue retains twelve IDs")
        model.saveIdiom(IdiomCatalog.all[12]); model.saveIdiom(IdiomCatalog.all[12])
        check(model.store.words.count == 2, "built-in idiom save is explicit and deduplicated")
        check(LearningStore(defaults: defaults).words.count == 2, "personal dictionary survives model reconstruction")
        model.startGame(); check(model.game?.cards.count == 4 && model.game?.current?.personal == true, "four-card round starts with personal words")
        let first = model.game!.current!; model.flipCard(); check(model.game!.showingBack && !model.progress.isLearned(first.id), "flipping alone does not learn word")
        model.rememberCard(); check(model.progress.isLearned(first.id) && model.game!.cards.count == 3 && !model.game!.cards.contains(first) && !model.game!.showingBack && model.gameFeedback != nil, "remember celebrates, archives, and exposes next card")
        model.moveCard(1); model.moveCard(-1); check(model.game!.index == 0 && !model.game!.showingBack, "bidirectional paging works through remaining cards")
        check(model.progress.dictionaryCards(words: model.store.words, filter: .learned).contains { $0.id == first.id } && !model.progress.dictionaryCards(words: model.store.words, filter: .inGame).contains { $0.id == first.id }, "dictionary tabs retain archived words")
        model.changeMastery(first.id); check(!model.progress.isLearned(first.id) && model.game == nil && model.progress.dictionaryCards(words: model.store.words, filter: .inGame).contains { $0.id == first.id }, "dictionary link restores card for next round")
        model.startGame()
        while model.game!.current != nil { model.flipCard(); model.rememberCard() }; let sessions = model.progress.sessions
        check(model.game!.cards.isEmpty && model.game!.initialCount == 4 && sessions == 1 && model.game!.rememberedCount == 4, "fully archived round completes and counts four achievements once")
        model.moveCard(-1); model.rememberCard(); check(model.progress.sessions == sessions, "empty archived round cannot count twice")
        let variantLesson = model.lesson!
        model.store.setVariants([PhraseVariant(label: "Нейтрально", text: "I enjoy learning English.", explanation: "Нейтрально."), PhraseVariant(label: "Разговорно", text: "I like picking up English.", explanation: "Разговорно.")], lesson: variantLesson.id)
        let variantRequests = fake.sources.count; model.variantsExpanded = true; model.variantsExpanded = false
        check(model.lesson?.response == variantLesson.response && model.lesson?.variants?.count == 2 && fake.sources.count == variantRequests, "collapse preserves analysis and variants without AI request")
        model.rewardsEnabled = false; model.gameEnabled = false
        check(!KeyboardPreferences(defaults: defaults).rewardsEnabled && model.game == nil, "reward and game preferences persist independently")
        model.gameEnabled = true; model.startGame()
        let source = "I go to store."
        let response = LearningResponse(corrected: "I go to the store.", translated: "Я иду в магазин.", diffs: [LearningDiff(id: "d1", type: .error, original: "store", corrected: "the store", start: 8, end: 13, explanation: "С конкретным магазином нужен артикль the.")], vocabulary: [VocabularySuggestion(term: "go to the store", meaning: "идти в магазин", kind: "phrase")])
        check(response.normalized(for: source) != nil, "local preview fixture is structurally valid")
        model.store.record(source: source, response: response); model.changed()
        let selectedLesson = model.lesson!.id, requestsBeforeCopy = fake.sources.count
        model.copyTranslation(variantLesson.id)
        check(copied.last == good.translated && model.lesson?.id == selectedLesson && fake.sources.count == requestsBeforeCopy, "historical copy uses that lesson's translation without selecting it or calling AI")
        let copiesBeforeMissing = copied.count
        model.copyTranslation(UUID()); check(copied.count == copiesBeforeMissing, "missing lesson cannot copy unrelated draft")
        let wordsDefaults = UserDefaults(suiteName: suite + ".words")!
        defer { wordsDefaults.removePersistentDomain(forName: suite + ".words") }
        let wordsModel = DesktopModel(defaults: wordsDefaults, vault: MemoryCredentialVault(), analyzer: FakeAnalyzer())
        let mixedSource = "I хочу узнать how to use this keyboard and стать увереннее."
        let mixed = LearningResponse(corrected: "I want to learn how to use this keyboard and become more confident.", translated: "Я хочу узнать, как пользоваться этой клавиатурой, и стать увереннее.", diffs: [
            LearningDiff(id: "unknown-1", type: .unknownWord, original: "хочу узнать", corrected: "want to learn", start: 0, end: 0, explanation: "want to learn — хотеть узнать или научиться."),
            LearningDiff(id: "unknown-2", type: .unknownWord, original: "стать увереннее", corrected: "become more confident", start: 0, end: 0, explanation: "become more confident — стать увереннее.")
        ], vocabulary: [])
        check(mixed.normalized(for: mixedSource) != nil && mixed.studyVocabulary.count == 2, "unknown words remain individually saveable when vocabulary is absent")
        wordsModel.store.record(source: mixedSource, response: mixed)
        wordsModel.save(mixed.studyVocabulary[0]); wordsModel.save(mixed.studyVocabulary[1]); wordsModel.save(mixed.studyVocabulary[0])
        check(wordsModel.store.words.count == 2 && Set(wordsModel.store.words.map(\.term)) == Set(mixed.studyVocabulary.map(\.savedTerm)), "each unknown word saves exactly its own term once")
        wordsModel.store.removeWord(wordsModel.store.words[0].id); wordsModel.store.removeWord(wordsModel.store.words[0].id); wordsModel.changed()
        render(wordsModel, page: .study, name: "study-unknown", directory: directory)
        render(wordsModel, page: .study, name: "study-unknown-narrow", directory: directory, width: 340)
        wordsModel.edit("", selection: NSRange(location: 0, length: 0)); render(wordsModel, page: .compose, name: "compose-empty", directory: directory)
        wordsModel.edit(wrapped, selection: NSRange(location: wrapped.utf16.count, length: 0)); render(wordsModel, page: .compose, name: "compose-grown", directory: directory)
        model.edit("I want to learn English. Иногда сложно, but I keep trying.", selection: NSRange(location: 4, length: 0))
        render(model, page: .compose, name: "compose", directory: directory)
        model.page = .study; render(model, page: .study, name: "study", directory: directory)
        render(model, page: .dictionary, name: "dictionary", directory: directory)
        render(model, page: .idioms, name: "idioms", directory: directory)
        model.startGame(); render(model, page: .game, name: "card-front", directory: directory)
        model.flipCard(); render(model, page: .game, name: "card-back", directory: directory)
        render(model, page: .game, name: "card-back-dark", directory: directory, dark: true)
        render(model, page: .settings, name: "settings", directory: directory)
        for name in ["compose", "study", "dictionary", "idioms", "card-front", "card-back", "card-back-dark", "settings"] {
            let image = NSImage(contentsOf: directory.appendingPathComponent(name + ".png"))
            check(image?.size.width == 392 && image?.size.height == 800, "rendered \(name) at narrow panel size")
        }
        model.compact = true; render(model, page: .compose, name: "compact", directory: directory)
        let compactImage = NSImage(contentsOf: directory.appendingPathComponent("compact.png"))
        check(compactImage?.size.width == 392 && compactImage?.size.height == 280, "quick input fits a compact plaque")
        model.compact = false
        check(model.store.lessons.count > 1 && LearningStore(defaults: defaults).lessons.count == 1, "session list is available now and does not accumulate across restarts")
        model.disconnect(); check(vault.settings == nil && model.store.words.count == 2, "disconnect retains learning data")
        let markup = CorrectionMarkup.original("I want good examples because it help me learn English.", corrected: "I want good examples because they help me learn English.")
        check(markup.filter(\.changed).map(\.text).joined() == "it", "only replaced word is crossed out in a broad correction")
        check(markup.map(\.text).joined() == "I want good examples because it help me learn English.", "correction markup preserves the exact original")
        check(CorrectionMarkup.original("i learn English.", corrected: "I learn English.").allSatisfy { !$0.changed }, "case-only correction does not cross out otherwise correct words")
        check(CorrectionMarkup.original("I go to store.", corrected: "I go to the store.").allSatisfy { !$0.changed }, "inserting a missing word does not strike retained words")
        check(CorrectionMarkup.original("very very good", corrected: "very good").filter(\.changed).map(\.text).joined() == "very", "repeated words retain one occurrence and strike only the duplicate")
        let unicodeSource = "Я хочу 😀 learn English.\n"
        let unicodeSpans = CorrectionMarkup.original(unicodeSource, corrected: "I want to 😀 learn English.\n")
        check(unicodeSpans.map(\.text).joined() == unicodeSource && unicodeSpans.filter(\.changed).map(\.text).joined() == "Яхочу", "mixed Unicode and emoji retain exact spacing without striking common English")
        check(CorrectionMarkup.original("", corrected: "Hello").isEmpty && CorrectionMarkup.original("Hello", corrected: "").filter(\.changed).map(\.text).joined() == "Hello", "empty sides are supported")
        let large = String(repeating: "word ", count: 2400) + "wrong end"
        let bounded = CorrectionMarkup.original(large, corrected: String(repeating: "word ", count: 2400) + "right end")
        check(bounded.map(\.text).joined() == large && bounded.filter(\.changed).map(\.text).joined() == "wrong", "bounded fallback preserves large common prefix and suffix")
        let insertionDefaults = UserDefaults(suiteName: suite + ".insertion")!
        defer { insertionDefaults.removePersistentDomain(forName: suite + ".insertion") }
        let insertionAnalyzer = FakeAnalyzer()
        let insertionModel = DesktopModel(defaults: insertionDefaults, vault: MemoryCredentialVault(), analyzer: insertionAnalyzer)
        _ = insertionModel.saveConnection(key: "mock-not-a-real-key", model: "gpt-6-luna", provider: .openai)
        var prepared = 0, deliveries: [String] = []
        insertionModel.onPrepareInsertion = { prepared += 1; return { deliveries.append($0) } }
        insertionModel.edit(text, selection: NSRange(location: location, length: 0)); insertionModel.translate()
        insertionAnalyzer.callbacks.last!(.success(good))
        check(prepared == 0 && deliveries.isEmpty, "ordinary translation never reads an external field or pastes")
        insertionModel.edit(text, selection: NSRange(location: location, length: 0)); insertionModel.insertionDestination = "Test app"; insertionModel.translate()
        let delivered = insertionAnalyzer.callbacks.last!; delivered(.success(good)); delivered(.success(good))
        check(prepared == 1 && deliveries == [good.translated] && insertionModel.insertionDestination == nil, "armed translation delivers only the translated fragment once")
        insertionModel.edit(text, selection: NSRange(location: location, length: 0)); insertionModel.insertionDestination = "Test app"; insertionModel.translate()
        let cancelled = insertionAnalyzer.callbacks.last!; insertionModel.translate(); cancelled(.success(good))
        check(deliveries.count == 1, "cancelled translation cannot insert a late response")
        insertionModel.insertionDestination = "Test app"; insertionModel.translate()
        let stale = insertionAnalyzer.callbacks.last!; insertionModel.edit(text + " changed", selection: NSRange(location: location, length: 0)); stale(.success(good))
        check(deliveries.count == 1 && insertionModel.insertionDestination == nil, "editing disarms target and prevents stale insertion")
        insertionModel.edit(text, selection: NSRange(location: location, length: 0)); insertionModel.insertionDestination = "Test app"; insertionModel.translate()
        insertionAnalyzer.callbacks.last!(.failure(.network(URLError.timedOut.rawValue)))
        check(deliveries.count == 1, "network failure cannot insert anything into the target")
        insertionModel.insertionDestination = "Test app"; insertionModel.edit(text, selection: NSRange(location: location + 1, length: 0)); insertionModel.translate()
        insertionAnalyzer.callbacks.last!(.success(good))
        check(deliveries.count == 1, "cursor edit requires selecting the destination again")
        let broadSource = "I want good examples because it help me learn English."
        let broadRange = (broadSource as NSString).range(of: "it help")
        let broadResponse = LearningResponse(corrected: "I want good examples because they help me learn English.", translated: "Я хочу хорошие примеры: они помогают мне учить английский.", diffs: [LearningDiff(id: "broad", type: .error, original: broadSource, corrected: "I want good examples because they help me learn English.", start: 0, end: broadSource.utf16.count, explanation: "Examples — множественное число, поэтому используем they. После they глагол help остаётся без окончания -s.")], vocabulary: [])
        check(broadRange.location != NSNotFound && broadResponse.normalized(for: broadSource) != nil, "selective correction preview is a valid local fixture")
        insertionModel.store.record(source: broadSource, response: broadResponse); insertionModel.changed()
        render(insertionModel, page: .study, name: "selective-correction", directory: directory)
        let failed = checks.filter { ($0["passed"] as? Bool) != true }.count
        let report: [String: Any] = ["version": "macos-0.4.1", "result": failed == 0 ? "passed" : "failed", "checks": checks, "externalRequests": 0, "realCredentialsRead": false, "physicalPhoneUsed": false]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: directory.appendingPathComponent("desktop-check.json")) }
        print("desktop checks: \(checks.count - failed)/\(checks.count)")
        if failed > 0 { exit(1) }
    }
    private static func render(_ model: DesktopModel, page: DesktopPage, name: String, directory: URL, dark: Bool = false, width: CGFloat = 392) {
        model.page = page
        let view = NSHostingView(rootView: DesktopRoot(model: model).environment(\.colorScheme, dark ? .dark : .light))
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: model.compact ? 280 : 800), styleMask: [], backing: .buffered, defer: false)
        window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: width, height: model.compact ? 280 : 800)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1)); view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: directory.appendingPathComponent(name + ".png")) }
        window.contentView = nil
    }
}
