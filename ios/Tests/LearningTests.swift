import Foundation

@main
enum LearningTests {
    static func main() {
        var failures = 0
        func check(_ value: Bool, _ message: String) { print("\(value ? "ok" : "FAIL")  \(message)"); if !value { failures += 1 } }
        let source = "I want to купить coffee"
        let response = LearningResponse(schema_version: 1, corrected: "I want to buy coffee", translated: "Я хочу купить кофе",
            diffs: [LearningDiff(id: "d1", type: .unknownWord, original: "купить", corrected: "buy", start: 10, end: 16, explanation: "Купить — buy.")],
            vocabulary: [VocabularySuggestion(term: "buy", meaning: "купить", kind: "word")])
        check(response.isValid(for: source) && response.hasErrors && response.hasLearning, "mixed text has analysis and translation")
        var wrong = response; wrong.diffs[0].start = 999; wrong.diffs[0].end = 1000
        check(wrong.normalized(for: source) == response, "model offset fixed using exact fragment")
        wrong = response; wrong.corrected = "I want coffee"
        check(wrong.normalized(for: source) == nil, "missing or conflicting correction fails safely")
        wrong = response; wrong.diffs[0].explanation = ""
        check(!wrong.isValid(for: source), "missing explanation rejected")
        wrong = response; wrong.diffs.append(response.diffs[0])
        check(wrong.normalized(for: source) == nil, "overlap rejected instead of claiming grammatical success")
        wrong = response; wrong.translated = "  "
        check(!wrong.isValid(for: source), "empty translation rejected")
        wrong = response; wrong.vocabulary[0].term = "invented idiom"
        check(!wrong.isValid(for: source), "vocabulary must belong to corrected context")
        wrong = response; wrong.schema_version = 2
        check(!wrong.isValid(for: source), "unknown schema rejected")
        wrong = response; wrong.vocabulary = [VocabularySuggestion(term: "to purchase", meaning: "покупать", kind: "phrase")]
        check(wrong.normalized(for: source)?.vocabulary.isEmpty == true, "optional vocabulary cannot block a valid translation")
        let adjacentSource = "The app became всё лучше."
        let adjacent = LearningResponse(schema_version: 1, corrected: "The app keeps getting better.", translated: "Приложение становится всё лучше.",
            diffs: [LearningDiff(id: "x", type: .unknownWord, original: "всё лучше", corrected: "keeps getting better", start: 15, end: 24, explanation: "Становится всё лучше — keeps getting better.")],
            vocabulary: [VocabularySuggestion(term: "get better", meaning: "становиться лучше", kind: "phrase")])
        let reconciled = adjacent.normalized(for: adjacentSource)
        check(reconciled?.isValid(for: adjacentSource) == true && reconciled?.diffs[0].original == "became всё лучше", "adjacent omitted verb is included in the existing correction")
        check(reconciled?.hasErrors == true && reconciled?.vocabulary.isEmpty == true, "reconciled correction keeps its error and skips unattested dictionary form")
        var invented = adjacent; invented.diffs[0].original = "невидимое слово"
        check(invented.normalized(for: adjacentSource) == nil, "a nonexistent original fragment is never repaired or dropped")
        invented = adjacent; invented.diffs[0].corrected = "keeps losing quality"
        check(invented.normalized(for: adjacentSource) == nil, "contradictory replacement absent from final English is rejected")
        invented = adjacent; invented.diffs = []
        check(invented.normalized(for: adjacentSource) == nil, "unexplained English rewrite cannot masquerade as correct input")
        invented = adjacent; invented.diffs[0].type = .style
        check(invented.normalized(for: adjacentSource) == nil, "incomplete style suggestion cannot absorb errors and earn praise")
        let correct = LearningResponse(schema_version: 1, corrected: "I like coffee", translated: "Я люблю кофе", diffs: [], vocabulary: [])
        check(correct.isValid(for: "I like coffee") && !correct.hasErrors && !correct.hasLearning, "correct text can earn praise")
        let uuid = UUID()
        let end = InputSnapshot(document: uuid, before: "Earlier paragraph\n" + source, after: "", selected: nil)
        check(end.source == source, "only accessible current paragraph is replaced")
        let selected = InputSnapshot(document: uuid, before: "prefix", after: "suffix", selected: source)
        check(selected.source == source && selected.isSelection, "selected text overrides context")
        let middle = InputSnapshot(document: uuid, before: "I want", after: " coffee", selected: nil)
        check(middle.source == "I want coffee" && middle.canReplace && middle.trailingCount == 7, "cursor inside a paragraph uses the whole paragraph, no manual move to the end")
        let inFirst = InputSnapshot(document: uuid, before: "One\nTwo", after: " three\nFour", selected: nil)
        check(inFirst.source == "Two three" && inFirst.trailingCount == 6 && end.trailingCount == 0, "only the line around the cursor is used")
        let emojiAfter = InputSnapshot(document: UUID(), before: "I want ", after: "coffee 😀☕️ now\nNext", selected: nil)
        check(emojiAfter.trailingCount == 13 && emojiAfter.trailingUTF16 == 15 && emojiAfter.source == "I want coffee 😀☕️ now",
              "the caret moves to the paragraph end in UTF-16 units, past emoji")
        let missing = InputSnapshot(document: uuid, before: nil, after: nil, selected: nil)
        check(!missing.canReplace, "missing context cannot translate")
        let detached = InputSnapshot(document: nil, before: source, after: "", selected: nil)
        check(detached.source == nil && !detached.canReplace, "detached proxy cannot translate or replace text")
        let detachedSelection = InputSnapshot(document: nil, before: "", after: "", selected: source)
        check(detachedSelection.source == nil && !detachedSelection.canReplace, "selection without a document cannot be sent or replaced")
        do {
            var detachedAfterRequest = end; detachedAfterRequest.document = nil
            check(detachedAfterRequest != end && !detachedAfterRequest.canReplace, "detaching invalidates a pending translation")
        }
        var changed = end; changed.before! += "!"
        check(changed != end, "edited document invalidates snapshot")
        changed = end; changed.document = UUID()
        check(changed != end, "switching input fields invalidates snapshot")
        let defaults = UserDefaults(suiteName: "easytalk.learning.tests")!
        defaults.removePersistentDomain(forName: "easytalk.learning.tests")
        let store = LearningStore(defaults: defaults)
        store.record(source: source, response: response)
        check(store.unreadCount == 1, "new learning remains unread until opened")
        let lesson = store.lessons[0]
        store.save(response.vocabulary[0], lesson: lesson); store.save(response.vocabulary[0], lesson: lesson)
        check(store.words.count == 1 && store.words[0].originalContext == source, "vocabulary deduplicated with original context")
        store.markRead(lesson.id)
        let reopened = LearningStore(defaults: defaults)
        check(reopened.unreadCount == 0 && reopened.words.count == 1, "history and dictionary survive restart")
        for _ in 0..<35 { store.record(source: source, response: response) }
        check(store.lessons.count == 36, "all analyses remain available during the current session")
        check(LearningStore(defaults: defaults).lessons.count == 1, "only last analysis survives a new session")
        store.clearLessons(); check(store.lessons.isEmpty && store.words.count == 1, "clear history preserves saved vocabulary")
        store.removeWord(store.words[0].id); check(store.words.isEmpty, "saved word can be removed")
        store.record(source: source, response: response)
        let declineID = store.lessons[0].id
        store.dismiss("buy", lesson: declineID)
        check(store.words.isEmpty && store.isDismissed("buy", lesson: store.lessons[0]), "declining never adds a word to the dictionary")
        store.record(source: source, response: response)
        check(!store.isDismissed("buy", lesson: store.lessons[0]), "decline belongs only to that lesson")
        let afterDecline = LearningStore(defaults: defaults)
        check(afterDecline.lessons.count == 1 && !afterDecline.isDismissed("buy", lesson: afterDecline.lessons[0]), "older session lessons do not return on restart")
        store.restoreSuggestion("buy", lesson: declineID)
        check(!store.isDismissed("buy", lesson: store.lessons[1]), "declined suggestion can be restored")
        let preferences = KeyboardPreferences(defaults: defaults)
        check(preferences.speakerGender == .unspecified && !preferences.hasSpeakerGender, "old install does not assume the speaker's gender")
        preferences.speakerGender = .female
        check(KeyboardPreferences(defaults: defaults).speakerGender == .female, "speaker gender persists separately from key and keyboard layout")
        check(preferences.symbolRowEnabled && preferences.symbols == KeyboardPreferences.defaultSymbols, "main symbol row enabled with requested punctuation")
        preferences.toggle("@"); preferences.symbolRowEnabled = false
        let reopenedPreferences = KeyboardPreferences(defaults: defaults)
        check(!reopenedPreferences.symbolRowEnabled && !reopenedPreferences.symbols.contains("@"), "symbol choices and row switch persist")
        preferences.resetSymbols(); check(preferences.symbols.contains("@"), "default symbols restored")
        for value in KeyboardPreferences.availableSymbols { preferences.toggle(value) }
        check(preferences.symbols.count <= 12, "symbol row bounded to twelve selectable signs")
        check(preferences.rewardsEnabled && preferences.secondSkillEnabled, "celebrations and manual game enabled by default")
        preferences.rewardsEnabled = false; preferences.secondSkillEnabled = false
        check(!KeyboardPreferences(defaults: defaults).rewardsEnabled && !KeyboardPreferences(defaults: defaults).secondSkillEnabled, "celebration and game switches persist independently")
        let progress = StudyProgressStore(defaults: defaults)
        let archive = SecondSkillCards.all
        check(archive.count == 60 && Set(archive.map { $0.id }).count == 60, "sixty shared idioms retain stable unique IDs")
        check(Array(archive.prefix(12)).map { $0.id } == (1...12).map { "second-skill.i\($0)" }, "original twelve IDs survive catalogue expansion")
        let personalWord = VocabularyEntry(term: "learn English", meaning: "учить английский", kind: "phrase", originalContext: "I want to learn English", correctedContext: "I want to learn English")
        let candidates = progress.candidates(words: [personalWord])
        check(candidates.first?.personal == true, "game prioritizes the user's saved words")
        let round = StudySession(candidates: candidates + candidates)
        check(round.cards.count == 4 && Set(round.cards.map { $0.id }).count == 4, "session has four distinct cards")
        check(!round.showingBack && round.rememberedCount == 0, "new flashcard starts with the English front")
        check(!round.advance(remembered: true) && round.index == 0, "front cannot be skipped or counted as learned")
        let firstCard = round.current!
        check(round.flip() && round.showingBack && round.current == firstCard, "flip reveals the same card's translation and example")
        check(!progress.isLearned(firstCard.id) && store.words.isEmpty, "looking at the back never learns or saves a word automatically")
        check(round.flip() && !round.showingBack && !round.advance(), "card can flip back without advancing")
        _ = round.flip()
        progress.setLearned(firstCard.id, true)
        check(!StudyProgressStore(defaults: defaults).candidates(words: [personalWord]).contains { $0.id == firstCard.id }, "explicit learned state persists and excludes future sessions")
        check(progress.candidates(words: [personalWord], reviewLearned: true).contains { $0.id == firstCard.id }, "learned cards can be reviewed deliberately")
        progress.setLearned(firstCard.id, false)
        check(progress.candidates(words: [personalWord]).contains { $0.id == firstCard.id }, "word can return to normal repetition")
        check(round.advance(remembered: true) && round.rememberedCount == 1 && !round.showingBack, "explicit remembered decision advances to a fresh front")
        check(!round.advance(remembered: true) && round.rememberedCount == 1, "double tap cannot mark the next unseen card learned")
        while round.current != nil { _ = round.flip(); _ = round.advance() }
        check(round.finished && round.rememberedCount == 1 && !round.advance() && !round.flip(), "finite flashcard session ends without inflating learned count")
        progress.finishSession(); check(StudyProgressStore(defaults: defaults).sessions == 1, "completed session count survives reopening")
        let emptyRound = StudySession(candidates: [])
        check(emptyRound.finished && !emptyRound.showingBack && !emptyRound.flip(), "empty learned pool has a finite empty state")
        let carousel = StudySession(candidates: candidates)
        check(!carousel.move(by: -1) && carousel.move(by: 1) && carousel.index == 1 && carousel.rememberedCount == 0, "swipe on front pages without silently learning")
        _ = carousel.flip()
        check(carousel.move(by: -1) && carousel.index == 0 && !carousel.showingBack, "backward swipe resets the previous card to its front")
        check(!carousel.setRemembered(true), "front cannot be marked remembered")
        _ = carousel.flip(); _ = carousel.setRemembered(true); _ = carousel.setRemembered(true)
        check(carousel.rememberedCount == 1 && carousel.index == 0, "remembering is explicit, unique, and does not page")
        _ = carousel.move(by: 1); _ = carousel.move(by: -1); _ = carousel.flip(); _ = carousel.setRemembered(true)
        check(carousel.rememberedCount == 1, "revisiting a remembered card cannot inflate the session count")
        _ = carousel.setRemembered(false)
        check(carousel.rememberedCount == 0, "remembered decision can be undone before leaving the card")
        while carousel.move(by: 1) {}
        check(carousel.finished && carousel.move(by: -1) && carousel.current == carousel.cards.last, "end of session can swipe back to the last card")
        check(!emptyRound.move(by: 1) && !emptyRound.move(by: -1), "empty game has no swipe loop")
        let praise = RewardProgress(defaults: defaults)
        check(praise.record(source: "I like coffee", hasErrors: false) == RewardProgress.phrases[0] && praise.successes == 1, "verified English earns varied encouragement")
        check(praise.record(source: "I go yesterday", hasErrors: true) == nil && praise.successes == 1, "errors never receive a clean-English reward")
        check(praise.record(source: "Я люблю кофе", hasErrors: false) == nil && praise.successes == 1, "Russian-only input is not counted as English practice")
        check(praise.record(source: "I want to learn English", hasErrors: false) == RewardProgress.phrases[1] && RewardProgress(defaults: defaults).successes == 2, "praise varies and progress persists")
        var motion = SpaceCursorMotion()
        let still = motion.move(dx: 2, dy: -2)
        check(still.columns == 0 && still.rows == 0, "trackpad ignores initial finger jitter")
        motion.reset()
        let horizontalDrag = motion.move(dx: 20, dy: 6)
        check(horizontalDrag.columns == 2 && horizontalDrag.rows == 0, "horizontal trackpad movement cannot accidentally change line")
        let reverseDrag = motion.move(dx: -11, dy: 0)
        check(reverseDrag.columns == -1 && reverseDrag.rows == 0, "trackpad reversal responds without previous direction debt")
        let turnDown = motion.move(dx: 0, dy: 32)
        check(turnDown.columns == 0 && turnDown.rows == 1, "drag can turn from horizontal into vertical")
        motion.reset()
        let verticalDrag = motion.move(dx: 4, dy: -64)
        check(verticalDrag.columns == 0 && verticalDrag.rows == -2, "vertical drag ignores sideways drift")
        let turnRight = motion.move(dx: 20, dy: 0)
        check(turnRight.columns == 2 && turnRight.rows == 0, "vertical drag can turn horizontally")
        motion.reset()
        var noiseColumns = 0, noiseRows = 0
        for i in 0..<30 { let delta = motion.move(dx: 5, dy: i % 2 == 0 ? 1 : -1); noiseColumns += delta.columns; noiseRows += delta.rows }
        check(noiseColumns == 15 && noiseRows == 0, "small repeated vertical noise cannot accumulate into a line jump")
        motion.reset()
        check(motion.move(dx: 0, dy: 0).columns == 0 && motion.move(dx: 0, dy: 0).rows == 0, "new trackpad gesture starts without residual movement")
        var preferred: Double?
        let upShort = CursorNavigation.vertical(before: "abcd\nx\nabc", after: "d", rows: -1, width: 80, preferredX: &preferred) { _ in 1 }
        check(upShort.characters == -4 && preferred == 3, "vertical move clamps to a short line but remembers column")
        let upLong = CursorNavigation.vertical(before: "abcd\nx", after: "\nabcd", rows: -1, width: 80, preferredX: &preferred) { _ in 1 }
        check(upLong.characters == -3, "next vertical move restores the original column")
        let downTwo = CursorNavigation.vertical(before: "abc", after: "d\nx\nabcd", rows: 2, width: 80, preferredX: &preferred) { _ in 1 }
        check(downTwo.characters == 7, "vertical drag can move down multiple lines")
        preferred = nil
        let wrapped = CursorNavigation.vertical(before: "abcdefg", after: "h", rows: -1, width: 4, preferredX: &preferred) { _ in 1 }
        check(wrapped.characters == -4, "vertical movement across estimated soft wraps")
        preferred = nil
        let blank = CursorNavigation.vertical(before: "abc\n\nx", after: "y", rows: -1, width: 80, preferredX: &preferred) { _ in 1 }
        check(blank.characters == -2, "empty lines remain navigable")
        preferred = nil
        let emojiMove = CursorNavigation.vertical(before: "🙂x\n🙂x", after: "", rows: -1, width: 80, preferredX: &preferred) { _ in 1 }
        check(emojiMove.characters == -3 && emojiMove.utf16 == -4, "vertical movement preserves emoji boundaries")
        let boundary = CursorNavigation.vertical(before: "", after: "text", rows: -1, width: 80, preferredX: &preferred) { _ in 1 }
        check(boundary.characters == 0, "vertical movement cannot leave available context")
        let direct = ConnectionSettings(apiKey: "test-key")
        check(direct.url?.absoluteString == "https://api.openai.com/v1/chat/completions" && direct.provider == .openai, "OpenAI key mode")
        wrong = response; wrong.vocabulary = []
        check(wrong.studyVocabulary == response.vocabulary, "unknown word stays saveable when AI omits vocabulary")
        check(response.studyVocabulary.count == 1, "unknown word does not duplicate an existing suggestion")
        let revisedRequest = AnalysisService.makeRequest(source: source, config: direct, intendedMeaning: "Я предпочитаю чай")!
        let revisedBody = try! JSONSerialization.jsonObject(with: revisedRequest.httpBody!) as! [String: Any]
        let revisedMessages = revisedBody["messages"] as! [[String: Any]]
        let revisedInput = try! JSONSerialization.jsonObject(with: Data((revisedMessages[1]["content"] as! String).utf8)) as! [String: Any]
        check(revisedInput["op"] as? String == "revise_analysis" && revisedInput["text"] as? String == source && revisedInput["intended_meaning"] as? String == "Я предпочитаю чай", "clarification sends original attempt and exact intended Russian meaning")
        check(AnalysisService.makeRequest(source: source, config: direct, intendedMeaning: " ") == nil && AnalysisService.makeRequest(source: source, config: direct, intendedMeaning: String(repeating: "я", count: 2001)) == nil, "clarification rejects blank and oversized meaning")
        let reviseID = store.lessons.first!.id, savedWords = store.words.count, lessonCount = store.lessons.count
        check(store.revise(reviseID, meaning: "Я предпочитаю чай", response: response) && store.lessons.first?.source == source && store.lessons.first?.response.translated == "Я предпочитаю чай" && store.lessons.count == lessonCount && store.words.count == savedWords, "clarification replaces one analysis while preserving original, session and dictionary")
        check(!store.revise(UUID(), meaning: "Я предпочитаю чай", response: response), "stale lesson cannot receive a clarification")
        let request = AnalysisService.makeRequest(source: source, config: direct)!
        let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        func directInput(_ config: ConnectionSettings, repair: Data? = nil) -> [String: Any] {
            let request = AnalysisService.makeRequest(source: source, config: config, repair: repair)!
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            return try! JSONSerialization.jsonObject(with: Data((messages[1]["content"] as! String).utf8)) as! [String: Any]
        }
        check(directInput(direct)["speaker_gender"] == nil, "unspecified gender adds no assumption to the AI request")
        for gender in [SpeakerGender.male, .female] {
            let config = ConnectionSettings(apiKey: "test-key", speakerGender: gender)
            let decoded = try! JSONDecoder().decode(ConnectionSettings.self, from: JSONEncoder().encode(config))
            check(decoded.speakerGender == gender && decoded.token == "test-key", "connection copy retains \(gender.rawValue) and key")
            check(directInput(config)["speaker_gender"] as? String == gender.rawValue && directInput(config)["text"] as? String == source, "AI receives \(gender.rawValue) metadata without changing original text")
            let claude = ConnectionSettings(provider: .anthropic, apiKey: "test", speakerGender: gender)
            let claudeBody = try! JSONSerialization.jsonObject(with: AnalysisService.makeRequest(source: source, config: claude)!.httpBody!) as! [String: Any]
            let claudeInput = try! JSONSerialization.jsonObject(with: Data((((claudeBody["messages"] as! [[String: Any]])[0])["content"] as! String).utf8)) as! [String: Any]
            check(claudeInput["speaker_gender"] as? String == gender.rawValue, "Claude receives \(gender.rawValue) too")
        }
        check(body["reasoning_effort"] as? String == "none" && request.timeoutInterval == 30, "fast language request with a bounded wait")
        let format = body["response_format"] as! [String: Any]
        let schemaConfig = format["json_schema"] as! [String: Any]
        let schema = schemaConfig["schema"] as! [String: Any]
        check(format["type"] as? String == "json_schema" && schemaConfig["strict"] as? Bool == true &&
              Set(schema["required"] as! [String]) == Set(["schema_version", "corrected", "translated", "diffs", "vocabulary"]), "direct provider must return every analysis field")
        check(AnalysisFailure.network(URLError.timedOut.rawValue).message.contains("30 секунд"), "timeout identified explicitly")
        check(AnalysisFailure.network(URLError.notConnectedToInternet.rawValue).message.contains("Нет интернета"), "offline distinguished from AI failure")
        check(AnalysisFailure.http(429).message.contains("баланс"), "API limit identified explicitly")
        // Keys: invisible characters removed, masked summary, warnings for the wrong or shortened key.
        check(ConnectionSettings.cleanKey(" sk-ant-abc\u{200B}def\n ghi\t") == "sk-ant-abcdefghi", "spaces, line breaks and invisible characters removed from a key")
        check(ConnectionSettings(provider: .anthropic, apiKey: "sk-ant-abc def").token == "sk-ant-abcdef", "the saved key is cleaned")
        check(ConnectionSettings.keySummary("sk-ant-api03-0123456789abcdefWXYZ") == "Ключ: sk-ant-ap…WXYZ · 33 символов", "masked key summary")
        check(AIProvider.anthropic.keyWarning("sk-proj-0123456789") != nil && AIProvider.openai.keyWarning("sk-ant-0123") != nil, "a key of another provider is flagged")
        check(AIProvider.anthropic.keyWarning("sk-ant-api03-…AbCd") != nil && AIProvider.anthropic.keyWarning("sk-ant-api03-0123456789") == nil, "a shortened key is flagged, a full one is not")
        // Model lists: only text models, a fixed host, Anthropic paging.
        let anthropicModels = Data(#"{"data":[{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5"},{"id":"claude-haiku-5-5"},{"id":"claude-opus-5-5"}],"has_more":false}"#.utf8)
        check(ModelCatalog.parse(anthropicModels, provider: .anthropic) == ["claude-opus-5-5", "claude-haiku-5-5"], "Claude models keep the provider's order without duplicates")
        let openAIModels = Data(#"{"data":[{"id":"text-embedding-3-large"},{"id":"gpt-6-luna"},{"id":"whisper-1"},{"id":"gpt-image-2"},{"id":"gpt-6-mini"},{"id":"tts-2"}]}"#.utf8)
        check(ModelCatalog.parse(openAIModels, provider: .openai) == ["gpt-6-luna", "gpt-6-mini"], "OpenAI list keeps text models only")
        check(ModelCatalog.parse(Data("{}".utf8), provider: .deepseek).isEmpty, "unexpected answer gives no list")
        let modelsRequest = ModelCatalog.request(config: ConnectionSettings(provider: .anthropic, apiKey: "sk-ant-test"))!
        check(modelsRequest.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=100" && modelsRequest.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test",
              "Claude model list asks the official host with the key header")
        check(ModelCatalog.request(config: ConnectionSettings(provider: .qwen, apiKey: "k", baseURL: "https://evil.example/v1")) == nil, "model list never goes to a foreign host")
        check(AIProvider.allCases.allSatisfy { $0.suggestedModels.first == $0.defaultModel }, "the default model heads each built-in list")
        let anthropicError = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"model: claude-x not found"}}"#.utf8)
        check(AnalysisFailure.http(404).message(details: anthropicError).contains("model: claude-x not found"), "provider's reason is shown with the error")
        let noCredit = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#.utf8)
        check(AnalysisFailure.http(400).message(details: noCredit).contains("Пополни баланс"), "empty balance explained in Russian")
        check(AnalysisFailure.network(-1001).message(details: anthropicError) == AnalysisFailure.network(-1001).message && AnalysisFailure.http(500).message(details: Data("<html>".utf8)) == AnalysisFailure.http(500).message,
              "no provider reason: the plain message")
        let fixtureData = try! JSONEncoder().encode(response)
        let http = HTTPURLResponse(url: direct.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        if case .success = AnalysisService.decode(fixtureData, response: http, error: nil, source: source, provider: nil) {
            check(true, "valid server response accepted")
        } else { check(false, "valid server response accepted") }
        let incomplete = Data("{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"content\":\"{}\"}}]}".utf8)
        if case .failure(.incomplete) = AnalysisService.decode(incomplete, response: http, error: nil, source: source, provider: .openai) {
            check(true, "truncated AI response cannot replace text")
        } else { check(false, "truncated AI response cannot replace text") }
        var unsafe = direct; unsafe.baseURL = "https://other.example/v1"
        check(unsafe.url == nil, "a key cannot be sent to an arbitrary host")
        let oldServer = Data("{\"endpoint\":\"https://example.com/v1/ai\",\"token\":\"old\"}".utf8)
        check((try? JSONDecoder().decode(ConnectionSettings.self, from: oldServer)) == nil, "removed own-server settings are not reused")
        let oldOpenAI = Data("{\"mode\":\"openai\",\"endpoint\":\"https://api.openai.com/v1/chat/completions\",\"token\":\"old\",\"model\":\"gpt-6-luna\"}".utf8)
        let migrated = try? JSONDecoder().decode(ConnectionSettings.self, from: oldOpenAI)
        check(migrated?.provider == .openai && migrated?.token == "old" && migrated?.url != nil && migrated?.speakerGender == .unspecified,
              "OpenAI settings saved before providers still work")
        let mismatchData = try! Data(contentsOf: URL(fileURLWithPath: "ios/Tests/Fixtures/preposition-mismatch.json"))
        let mismatch = try! JSONSerialization.jsonObject(with: mismatchData) as! [String: Any]
        let longSource = mismatch["source"] as! String
        let badResponse = mismatch["response"] as! [String: Any]
        var fixedResponse = badResponse
        var edits = fixedResponse["diffs"] as! [[String: Any]]
        edits[4]["original"] = "договориться about"
        fixedResponse["diffs"] = edits
        func envelope(_ value: [String: Any]) -> Data {
            let content = String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
            return try! JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]])
        }
        let boundaryData = envelope(badResponse), fixedData = envelope(fixedResponse)
        if case .success(let local) = AnalysisService.decode(boundaryData, response: http, error: nil, source: longSource, provider: .openai) {
            check(local.diffs.count == 5 && local.diffs[4].original == "договориться about" && local.isValid(for: longSource), "real preposition boundary repaired locally without dropping corrections")
        } else { check(false, "real preposition boundary repaired locally without dropping corrections") }
        var conflictingResponse = badResponse
        var conflictingEdits = conflictingResponse["diffs"] as! [[String: Any]]
        conflictingEdits[4]["corrected"] = "agree about"
        conflictingResponse["diffs"] = conflictingEdits
        let badData = envelope(conflictingResponse)
        if case .failure(.incomplete) = AnalysisService.decode(badData, response: http, error: nil, source: longSource, provider: .openai) {
            check(true, "inconsistent replacement rejected safely")
        } else { check(false, "inconsistent replacement rejected safely") }
        let repaired = AnalysisService.makeRequest(source: longSource, config: direct, repair: badData)!
        let repairedBody = try! JSONSerialization.jsonObject(with: repaired.httpBody!) as! [String: Any]
        check(repairedBody["reasoning_effort"] as? String == "low", "repair request asks AI to check inconsistent edits")
        let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [AnalysisMockProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        AnalysisMockProtocol.responses = [(200, boundaryData)]
        var localComplete = false, locallyHandled = false
        let localOperation = AnalysisOperation(source: longSource, config: direct, session: session) { result, trace in
            if case .success(let local) = result { locallyHandled = trace.attempts == 1 && local.isValid(for: longSource) && local.diffs.count == 5 }
            localComplete = true
        }
        let localLimit = Date().addingTimeInterval(3)
        while !localComplete && Date() < localLimit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(localComplete && locallyHandled, "recoverable boundary needs one request instead of a slow AI retry")
        withExtendedLifetime(localOperation) {}
        AnalysisMockProtocol.responses = [(200, badData), (200, fixedData)]
        var complete = false, repairedOK = false
        let operation = AnalysisOperation(source: longSource, config: direct, session: session) { result, trace in
            if case .success = result { repairedOK = trace.attempts == 2 }; complete = true
        }
        let limit = Date().addingTimeInterval(3)
        while !complete && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(complete && repairedOK, "inconsistent AI response repaired once before replacing text")
        withExtendedLifetime(operation) {}
        AnalysisMockProtocol.responses = [(200, badData), (200, badData)]
        complete = false; var failedSafely = false
        let failing = AnalysisOperation(source: longSource, config: direct, session: session) { result, trace in
            if case .failure(.incomplete) = result { failedSafely = trace.attempts == 2 }; complete = true
        }
        let secondLimit = Date().addingTimeInterval(3)
        while !complete && Date() < secondLimit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(complete && failedSafely, "repair is bounded and never applies inconsistent text")
        withExtendedLifetime(failing) {}
        let repeatedSource = "He go home. She go home."
        let repeated = LearningResponse(schema_version: 1, corrected: "He goes home. She goes home.", translated: "Он идёт домой. Она идёт домой.", diffs: [
            LearningDiff(id: "a", type: .error, original: "go", corrected: "goes", start: 3, end: 5, explanation: "После he нужно goes."),
            LearningDiff(id: "b", type: .error, original: "go", corrected: "goes", start: 16, end: 18, explanation: "После she нужно goes.")], vocabulary: [])
        check(repeated.normalized(for: repeatedSource)?.diffs.map(\.start) == [3, 16], "repeated fragments remain attached to separate occurrences")
        var overlapping = repeated; overlapping.diffs[1].start = 3
        check(overlapping.normalized(for: repeatedSource) == nil, "repeated overlapping corrections cannot be merged or dropped")
        AnalysisMockProtocol.responses = [(200, fixedData)]
        var cancelledCallback = false
        let cancelled = AnalysisOperation(source: longSource, config: direct, session: session) { _, _ in cancelledCallback = true }
        cancelled.cancel(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(!cancelledCallback, "cancelled request cannot deliver a late replacement")
        // Optional real-provider fixtures are produced without saving an API key.
        let lexical = LexicalEntry(headword: "successful", meanings: ["успешный", "удачный"], examples: ["The meeting was successful.", "She runs a successful business."])
        check(lexical.validated != nil && LexicalEntry(headword: "", meanings: ["x"], examples: lexical.examples).validated == nil, "dictionary requires an English headword and examples")
        let contextual = VocabularyEntry(term: "successful", meaning: "удачных", kind: "word", originalContext: "", correctedContext: "We had successful meetings.")
        check(contextual.displayMeaning == "успешный; удачный; результативный" && contextual.examples.count == 3, "legacy successful uses base meanings rather than contextual inflection")
        let beforeLexical = store.words.count
        let canonical = VocabularySuggestion(term: "buy", meaning: "купил", kind: "word", dictionary: LexicalEntry(headword: "buy", meanings: ["покупать; купить"], examples: ["I buy bread every morning.", "We bought a new car."]))
        store.save(canonical, lesson: store.lessons[0])
        let word = store.words.first { $0.term == "buy" }!
        check(store.words.count == beforeLexical + 1 && word.displayMeaning == "покупать; купить" && word.examples.count == 2, "saving keeps dictionary form separate from sentence context")
        let beforeID = word.id, currentRound = StudySession(candidates: progress.pool(words: [word]))
        _ = currentRound.flip(); _ = currentRound.setRemembered(true)
        store.setDictionary(LexicalEntry(headword: "buy", meanings: ["покупать"], examples: canonical.dictionary!.examples), word: beforeID)
        currentRound.refresh(from: progress.pool(words: store.words))
        check(currentRound.current!.id == "word." + beforeID.uuidString && currentRound.showingBack && currentRound.rememberedCount == 1 && currentRound.current!.meaning == "покупать", "dictionary refinement preserves word ID and round position/mastery")
        let afterLexical = LearningStore(defaults: defaults).words.first { $0.id == beforeID }!
        check(afterLexical.lexical != nil && afterLexical.examples.count == 2, "canonical dictionary metadata survives reopen")
        let variants = [PhraseVariant(label: "Нейтрально", text: "I'd like to buy coffee.", explanation: "Вежливая просьба."), PhraseVariant(label: "Разговорно", text: "I'd love some coffee.", explanation: "Непринуждённый вариант.")]
        let studyData = try! JSONEncoder().encode(RephraseResponse(variants: variants))
        let sourcePhrase = store.lessons[0].response.corrected
        store.setVariants(variants, lesson: store.lessons[0].id)
        check(LearningStore(defaults: defaults).lessons[0].variants == variants && store.lessons[0].response.corrected == sourcePhrase, "rephrasing persists variants without replacing corrected sentence")
        let variantsRequest = StudyActionService.makeRequest(.rephrase, source: sourcePhrase, config: direct)!
        let variantsBody = try! JSONSerialization.jsonObject(with: variantsRequest.httpBody!) as! [String: Any]
        let messages = variantsBody["messages"] as! [[String: Any]]
        let studyInput = try! JSONSerialization.jsonObject(with: (messages[1]["content"] as! String).data(using: .utf8)!) as! [String: Any]
        check(studyInput["op"] as? String == "rephrase" && studyInput["text"] as? String == sourcePhrase && studyInput["context"] == nil && messages[0]["role"] as? String == "developer", "rephrase sends only correct sentence as data, isolated from instructions")
        if case .success(.variants(let result)) = StudyActionService.decode(.rephrase, source: sourcePhrase, data: studyData, response: http, error: nil, provider: nil) { check(result == variants, "valid variants decode") } else { check(false, "valid variants decode") }
        let duplicate = try! JSONEncoder().encode(RephraseResponse(variants: [variants[0], variants[0]]))
        if case .failure(.incomplete) = StudyActionService.decode(.rephrase, source: sourcePhrase, data: duplicate, response: http, error: nil, provider: nil) { check(true, "duplicate variants rejected") } else { check(false, "duplicate variants rejected") }
        let dictData = try! JSONSerialization.data(withJSONObject: ["schema_version": 1, "entry": ["headword": lexical.headword, "meanings": lexical.meanings, "examples": lexical.examples]])
        if case .success(.dictionary(let entry)) = StudyActionService.decode(.dictionary, source: "successful", data: dictData, response: http, error: nil, provider: nil) { check(entry == lexical, "dictionary action returns multiple base meanings/examples") } else { check(false, "dictionary action returns multiple base meanings/examples") }
        let dictEnvelope = try! JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": String(data: dictData, encoding: .utf8)!]]]])
        AnalysisMockProtocol.responses = [(200, dictEnvelope)]
        var studyFinished = false
        var studyOperation: StudyActionOperation? = StudyActionOperation(.dictionary, source: "successful", config: direct, session: session) { value in if case .success(.dictionary) = value { studyFinished = true } }
        weak var weakStudyOperation = studyOperation
        let studyLimit = Date().addingTimeInterval(1)
        while !studyFinished && Date() < studyLimit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        studyOperation = nil
        check(studyFinished && weakStudyOperation == nil, "study request completes and releases without a closure retain cycle")
        AnalysisMockProtocol.responses = [(200, dictEnvelope)]
        var studyCancelledCallback = false
        let cancelledStudy = StudyActionOperation(.dictionary, source: "successful", config: direct, session: session) { _ in studyCancelledCallback = true }
        cancelledStudy.cancel(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(!studyCancelledCallback, "cancelled study action ignores late response")
        // Archive semantics: all learned cards can disappear yet the round stays countable.
        let archiveRound = StudySession(candidates: Array(progress.pool(words: store.words).prefix(3)))
        check(archiveRound.archiveCurrent() == nil && archiveRound.cards.count == 3, "mastery requires revealed translation")
        let archivedID = archiveRound.current!.id
        _ = archiveRound.flip(); let archived = archiveRound.archiveCurrent()!
        progress.setLearned(archived.id, true)
        check(archived.id == archivedID && archiveRound.cards.count == 2 && archiveRound.index == 0 && !archiveRound.showingBack && archiveRound.rememberedCount == 1, "mastery archives current card and immediately exposes next front")
        check(!archiveRound.cards.contains { $0.id == archivedID } && !progress.candidates(words: store.words).contains { $0.id == archivedID }, "archived card cannot reappear by backward paging or new round")
        while archiveRound.current != nil { _ = archiveRound.flip(); _ = archiveRound.archiveCurrent() }
        check(archiveRound.finished && archiveRound.initialCount == 3 && archiveRound.cards.isEmpty && archiveRound.rememberedCount == 3, "fully archived round retains initial count and achievements")
        check(progress.dictionaryCards(words: store.words, filter: .learned).contains { $0.id == archivedID } && !progress.dictionaryCards(words: store.words, filter: .inGame).contains { $0.id == archivedID }, "dictionary tabs separate learned from active cards without deleting words")
        progress.setLearned(archivedID, false)
        check(progress.dictionaryCards(words: store.words, filter: .inGame).contains { $0.id == archivedID }, "return to cards restores archived personal word")
        let builtinID = SecondSkillCards.all.first!.id
        progress.setLearned(builtinID, true)
        check(progress.dictionaryCards(words: store.words, filter: .learned).contains { $0.id == builtinID }, "explicitly learned built-in idiom appears in dictionary archive")
        progress.setLearned(builtinID, false)
        check(progress.dictionaryCards(words: store.words, filter: .inGame).contains { $0.id == builtinID }, "returning built-in idiom keeps it visible in dictionary")
        let legacyBenefit = VocabularyEntry(term: "benefit", meaning: "пользу", kind: "word", originalContext: "", correctedContext: "This brings benefit.")
        let repairedBenefit = VocabularyEntry(id: legacyBenefit.id, term: "benefit", meaning: "пользу", kind: "word", originalContext: "", correctedContext: "", dictionary: LexicalEntry(headword: "benefit", meanings: ["пользу"], examples: ["We benefit from practice.", "This brings a benefit."]))
        check(legacyBenefit.displayMeaning.contains("польза") && repairedBenefit.displayMeaning.contains("выгода") && repairedBenefit.examples.count == 3 && legacyBenefit.id == repairedBenefit.id, "old contextual benefit and known malformed metadata display canonical dictionary values, preserving ID")
        // Typing conventions: capitalization, double-space period, word deletion.
        check(TypingRules.shouldCapitalize(before: "", mode: .sentences), "empty field starts with a capital")
        check(TypingRules.shouldCapitalize(before: "Hi. ", mode: .sentences) && TypingRules.shouldCapitalize(before: "Привет!  ", mode: .sentences),
              "capital after a sentence end and spaces")
        check(TypingRules.shouldCapitalize(before: "Line one\n", mode: .sentences), "capital on a new line")
        check(!TypingRules.shouldCapitalize(before: "I want ", mode: .sentences) && !TypingRules.shouldCapitalize(before: "Hi.", mode: .sentences),
              "no capital inside a sentence or right after a period without space")
        check(TypingRules.shouldCapitalize(before: "New York ", mode: .words) && !TypingRules.shouldCapitalize(before: "New", mode: .words), "words mode")
        check(!TypingRules.shouldCapitalize(before: "", mode: .none) && TypingRules.shouldCapitalize(before: "abc", mode: .allCharacters), "none and all-caps modes")
        check(TypingRules.doubleSpaceMakesPeriod(before: "Hello ") && TypingRules.doubleSpaceMakesPeriod(before: "в 2026 "), "second space after a word or number makes a period")
        check(!TypingRules.doubleSpaceMakesPeriod(before: "Hello. ") && !TypingRules.doubleSpaceMakesPeriod(before: " ") && !TypingRules.doubleSpaceMakesPeriod(before: "Hello"),
              "no period after punctuation, at the start or without a space")
        check(TypingRules.wordDeletionLength(before: "I want coffee") == 6 && TypingRules.wordDeletionLength(before: "Я хочу  ") == 6,
              "word deletion removes the word and its trailing spaces")
        check(TypingRules.wordDeletionLength(before: "don't") == 5 && TypingRules.wordDeletionLength(before: "Hi!") == 1 && TypingRules.wordDeletionLength(before: "") == 0,
              "apostrophes stay in the word; punctuation goes one character at a time")

        // «Скопировать контекст»: prompt, numbered messages, translation details, newest kept when too long.
        let exportDate = Date(timeIntervalSince1970: 1_800_000_000)
        let exported = ContextExport.text(entries: [
            HistoryEntry(date: exportDate.addingTimeInterval(-60), text: "I want to купить coffee"),
            HistoryEntry(date: exportDate, text: "Я хочу купить кофе", source: "I want to купить coffee", corrected: "I want to buy coffee")
        ], period: .today, prompt: "TASK")
        check(exported.hasPrefix("TASK\n\nМои сообщения за сегодня: 2"), "context starts with the task and the period")
        check(exported.contains("1. [") && exported.contains("] I want to купить coffee\n2. ["), "messages are numbered in writing order")
        check(exported.contains("Написал сам: «I want to купить coffee». Правильно по-английски: «I want to buy coffee»."), "translated message keeps the original and corrected English")
        check(contextExportPrompt.contains(WordImport.startMarker) && contextExportPrompt.contains(WordImport.endMarker), "default prompt asks for the importable word block")
        let long = (0..<100).map { HistoryEntry(date: exportDate.addingTimeInterval(Double($0)), text: "message \($0) " + String(repeating: "x", count: 1000)) }
        let trimmed = ContextExport.text(entries: long, period: .all, prompt: "TASK")
        check(trimmed.count <= ContextExport.maxCharacters + 1000 && trimmed.contains("message 99 ") && !trimmed.contains("message 0 ") && trimmed.contains("более старых не поместились"),
              "too long context keeps the newest messages and says how many were left out")

        // «Вставить слова»: the block from an AI answer, as chats actually format it.
        let answer = """
        Отличная работа! Вот разбор…
        Формат: EASYTALK-WORDS … END-EASYTALK-WORDS
        ```
        EASYTALK-WORDS
        английское слово или выражение | значение по-русски | короткий пример по-английски
        - agree on | договориться о | We agreed on the price.
        **look forward to** | ждать с нетерпением | I look forward to it.
        | get used to | привыкнуть | You'll get used to it. |
        agree on | дубликат | x
        ---|---|---
        nomeaning |
        END-EASYTALK-WORDS
        ```
        Удачи!
        """
        let imported = WordImport.parse(answer)
        check(imported.map(\.term) == ["agree on", "look forward to", "get used to"], "word block parsed through bullets, bold, table pipes; header, duplicates and broken lines skipped")
        check(imported.first?.meaning == "договориться о" && imported.first?.example == "We agreed on the price.", "meaning and example are read")
        check(WordImport.parse("no block here").isEmpty, "text without the block gives nothing")
        let importName = "easytalk.import.tests"
        UserDefaults().removePersistentDomain(forName: importName)
        let importStore = LearningStore(defaults: UserDefaults(suiteName: importName)!)
        importStore.saveEntry(VocabularyEntry(term: "get used to", meaning: "привыкнуть", kind: "phrase", originalContext: "", correctedContext: ""))
        check(importStore.importWords(imported) == 2 && importStore.words.count == 3, "import adds new words and skips existing ones")
        check(importStore.words.first?.term == "agree on" && importStore.words.first?.kind == "phrase" && importStore.words.first?.examples == ["We agreed on the price."],
              "imported words keep list order, kind and example")
        check(importStore.importWords(imported) == 0, "importing the same answer twice adds nothing")
        check(LearningStore(defaults: UserDefaults(suiteName: importName)!).words.count == 3, "imported words persist")
        UserDefaults().removePersistentDomain(forName: importName)

        // Automatic history: retention, periods, repeated callbacks, translation details.
        let historyName = "easytalk.history.tests"
        UserDefaults().removePersistentDomain(forName: historyName)
        let historyDefaults = UserDefaults(suiteName: historyName)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let history = InputHistoryStore(defaults: historyDefaults, now: now)
        history.add("Ancient message", at: now.addingTimeInterval(-91 * 24 * 3600))
        history.add("Old message", at: now.addingTimeInterval(-3 * 24 * 3600))
        check(history.add("  I want to купить coffee  ", at: now.addingTimeInterval(-20 * 60)), "sent message recorded")
        check(!history.add("I want to купить coffee", at: now.addingTimeInterval(-19 * 60)), "repeated callback is not a second message")
        check(!history.add("   ", at: now) && !history.add("👍", at: now), "empty or letterless text is ignored")
        history.add("Я хочу купить кофе", source: "I want to купить coffee", corrected: "I want to buy coffee", at: now.addingTimeInterval(-5 * 60))
        check(history.entries.count == 3 && !history.entries.contains { $0.text == "Ancient message" }, "entries older than 90 days are removed")
        check(history.entries(in: .halfHour, now: now).map(\.text) == ["I want to купить coffee", "Я хочу купить кофе"], "period filter, oldest first")
        check(history.entries(in: .today, now: now, calendar: utc).count == 2, "today starts at midnight")
        check(history.entries(in: .week, now: now).count == 3 && history.entries(in: .all, now: now).count == 3, "week and all time")
        check(history.entries(in: .hour, now: now).last?.corrected == "I want to buy coffee", "translated message keeps original and corrected English")
        let reloadedHistory = InputHistoryStore(defaults: historyDefaults, now: now)
        check(reloadedHistory.entries == history.entries, "history persists")
        reloadedHistory.clear()
        check(InputHistoryStore(defaults: historyDefaults, now: now).entries.isEmpty, "history can be cleared")
        UserDefaults().removePersistentDomain(forName: historyName)

        // Sending is detected when the host app empties the field.
        var detector = SentTextDetector()
        let chat = UUID()
        _ = detector.observe(document: chat, before: "", after: "")
        detector.noteInsertion(); _ = detector.observe(document: chat, before: "Hello there", after: "")
        check(detector.observe(document: chat, before: "", after: "") == "Hello there", "host cleared the field: message sent")
        detector.noteInsertion(); _ = detector.observe(document: chat, before: "Draft", after: "")
        detector.noteDeletion(); _ = detector.observe(document: chat, before: "Draf", after: "")
        detector.noteDeletion()
        check(detector.observe(document: chat, before: "", after: "") == nil, "erasing with our delete key is not sending")
        _ = detector.observe(document: chat, before: "Dictated text", after: "")
        check(detector.observe(document: chat, before: "", after: "") == "Dictated text", "dictated text that is sent is recorded")
        _ = detector.observe(document: chat, before: "Text before", after: " and after")
        check(detector.observe(document: chat, before: nil, after: nil) == "Text before and after", "text on both sides of the cursor is recorded")
        _ = detector.observe(document: chat, before: "Chat A draft", after: "")
        check(detector.observe(document: UUID(), before: "", after: "") == nil, "switching to another field is not sending")

        // Stored data that cannot be read is kept; readable entries survive.
        let damagedName = "easytalk.learning.damaged"
        UserDefaults().removePersistentDomain(forName: damagedName)
        let damaged = UserDefaults(suiteName: damagedName)!
        let goodWord = VocabularyEntry(term: "agree on", meaning: "договориться о", kind: "phrase", originalContext: "", correctedContext: "")
        var storedWords = try! JSONSerialization.jsonObject(with: JSONEncoder().encode([goodWord])) as! [Any]
        storedWords.append(["term": 42])
        damaged.set(try! JSONSerialization.data(withJSONObject: storedWords), forKey: "learning.words")
        let recovered = LearningStore(defaults: damaged)
        let backupKeys = { damaged.dictionaryRepresentation().keys.filter { $0.hasPrefix("learning.words" + LearningStore.unreadableSuffix) } }
        check(recovered.words.map(\.term) == ["agree on"], "one unreadable word does not discard the others")
        check(backupKeys().count == 1, "unreadable dictionary data is kept as a copy")
        damaged.set(Data("not json".utf8), forKey: "learning.words")
        let broken = LearningStore(defaults: damaged)
        broken.saveEntry(goodWord)
        check(broken.words.count == 1 && !backupKeys().isEmpty, "saving after unreadable data keeps the copy")
        UserDefaults().removePersistentDomain(forName: damagedName)

        // One-time move of the keyboard's own data into the shared App Group container.
        let legacyName = "easytalk.legacy.tests", sharedName = "easytalk.shared.tests"
        for name in [legacyName, sharedName] { UserDefaults().removePersistentDomain(forName: name) }
        let legacy = UserDefaults(suiteName: legacyName)!, shared = UserDefaults(suiteName: sharedName)!
        legacy.set(Data("old".utf8), forKey: "learning.words"); legacy.set("female", forKey: "keyboard.speakerGender")
        legacy.set("x", forKey: "unrelated.key"); shared.set("male", forKey: "keyboard.speakerGender")
        SharedStorage.migrateLegacyDefaults(from: legacy, to: shared, process: "keyboard")
        check(shared.data(forKey: "learning.words") == Data("old".utf8), "migration copies keyboard data into the shared container")
        check(shared.string(forKey: "keyboard.speakerGender") == "male" && shared.object(forKey: "unrelated.key") == nil,
              "migration never overwrites shared data or copies unrelated keys")
        shared.removeObject(forKey: "learning.words")
        SharedStorage.migrateLegacyDefaults(from: legacy, to: shared, process: "keyboard")
        check(shared.object(forKey: "learning.words") == nil, "migration runs once per process")
        SharedStorage.migrateLegacyDefaults(from: legacy, to: shared, process: "app")
        check(shared.data(forKey: "learning.words") == Data("old".utf8), "each process migrates its own old data once")
        for name in [legacyName, sharedName] { UserDefaults().removePersistentDomain(forName: name) }

        // A key goes only to its provider's hosts; only Qwen takes a region/workspace address.
        for base in ["http://dashscope-us.aliyuncs.com/compatible-mode/v1", "https://evil.example/compatible-mode/v1",
                     "https://user:pw@dashscope-us.aliyuncs.com/compatible-mode/v1", "https://dashscope-us.aliyuncs.com/compatible-mode/v1?key=x"] {
            check(ConnectionSettings(provider: .qwen, apiKey: "k", baseURL: base).url == nil, "unsafe or foreign Qwen address rejected")
        }
        check(ConnectionSettings(provider: .qwen, apiKey: "k", baseURL: "https://ws1.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/").url?.absoluteString
              == "https://ws1.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions", "Qwen workspace address accepted")
        check(ConnectionSettings(provider: .anthropic, apiKey: "k", baseURL: "https://evil.example/v1").url?.host == "api.anthropic.com", "fixed providers ignore a custom address")
        check(ConnectionSettings(provider: .deepseek, apiKey: " ").url == nil, "an empty key is not a connection")
        let roundTrip = try? JSONDecoder().decode(ConnectionSettings.self, from: JSONEncoder().encode(ConnectionSettings(provider: .qwen, apiKey: "k", model: "qwen3.8-max",
            baseURL: "https://ws1.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1")))
        check(roundTrip?.provider == .qwen && roundTrip?.model == "qwen3.8-max" && roundTrip?.baseURL.hasPrefix("https://ws1.") == true, "provider settings persist")

        // Claude: Messages API format, schema output, refusals and cut-off answers rejected.
        let claudeConfig = ConnectionSettings(provider: .anthropic, apiKey: "test-key")
        let claudeRequest = AnalysisService.makeRequest(source: source, config: claudeConfig)!
        let claudeBody = try! JSONSerialization.jsonObject(with: claudeRequest.httpBody!) as! [String: Any]
        let claudeOutput = claudeBody["output_config"] as! [String: Any]
        let claudeFormat = claudeOutput["format"] as! [String: Any]
        check(claudeRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages" && claudeRequest.value(forHTTPHeaderField: "x-api-key") == "test-key"
              && claudeRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01" && claudeRequest.value(forHTTPHeaderField: "Authorization") == nil,
              "Claude request uses the Messages API with x-api-key")
        check(claudeBody["model"] as? String == "claude-opus-5-5" && claudeBody["system"] as? String == analysisPrompt && (claudeBody["messages"] as! [[String: Any]]).count == 1
              && claudeBody["response_format"] == nil && claudeBody["temperature"] == nil, "Claude gets the prompt as system and one user message")
        check(claudeFormat["type"] as? String == "json_schema" && claudeOutput["effort"] as? String == "low"
              && Set((claudeFormat["schema"] as! [String: Any])["required"] as! [String]) == Set(["schema_version", "corrected", "translated", "diffs", "vocabulary"]),
              "Claude returns the analysis schema at low effort")
        check(claudeBody["fallbacks"] as? String == "default" && claudeRequest.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01",
              "Opus refusals fall back server-side")
        let haikuRequest = AnalysisService.makeRequest(source: source, config: ConnectionSettings(provider: .anthropic, apiKey: "k", model: "claude-haiku-5-5"))!
        check((try! JSONSerialization.jsonObject(with: haikuRequest.httpBody!) as! [String: Any])["fallbacks"] == nil && haikuRequest.value(forHTTPHeaderField: "anthropic-beta") == nil,
              "models without fallbacks get no fallback parameter")
        let analysisJSON = String(data: try! JSONEncoder().encode(response), encoding: .utf8)!
        func claudeEnvelope(_ stop: String, _ text: String) -> Data {
            try! JSONSerialization.data(withJSONObject: ["stop_reason": stop, "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]]])
        }
        if case .success = AnalysisService.decode(claudeEnvelope("end_turn", analysisJSON), response: http, error: nil, source: source, provider: .anthropic) {
            check(true, "Claude answer accepted, thinking blocks skipped")
        } else { check(false, "Claude answer accepted, thinking blocks skipped") }
        for stop in ["refusal", "max_tokens"] {
            if case .failure(.incomplete) = AnalysisService.decode(claudeEnvelope(stop, analysisJSON), response: http, error: nil, source: source, provider: .anthropic) {
                check(true, "Claude \(stop) cannot replace text")
            } else { check(false, "Claude \(stop) cannot replace text") }
        }
        // Qwen and DeepSeek: OpenAI-compatible chat completions with JSON mode.
        for provider in [AIProvider.qwen, .deepseek] {
            let request = AnalysisService.makeRequest(source: source, config: ConnectionSettings(provider: provider, apiKey: "k"))!
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            check(request.url?.absoluteString == provider.defaultBaseURL + "/chat/completions" && request.value(forHTTPHeaderField: "Authorization") == "Bearer k"
                  && messages[0]["role"] as? String == "system" && (body["response_format"] as? [String: Any])?["type"] as? String == "json_object"
                  && body["model"] as? String == provider.defaultModel && body["max_tokens"] as? Int == 6000, "\(provider.title) uses chat completions with JSON mode")
        }
        // Study actions go through the same provider formats.
        let claudeStudy = StudyActionService.makeRequest(.rephrase, source: "I want to buy coffee.", config: claudeConfig)!
        let claudeStudyBody = try! JSONSerialization.jsonObject(with: claudeStudy.httpBody!) as! [String: Any]
        check(claudeStudyBody["system"] as? String == studyActionsPrompt
              && ((claudeStudyBody["output_config"] as! [String: Any])["format"] as! [String: Any])["type"] as? String == "json_schema",
              "Claude study actions use the study prompt and schema")
        session.invalidateAndCancel()
        for path in CommandLine.arguments.dropFirst() {
            let obj = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
            let input = obj["source"] as! String
            let data = try! JSONSerialization.data(withJSONObject: obj["response"]!)
            let result = (try? JSONDecoder().decode(LearningResponse.self, from: data))?.normalized(for: input)
            check(result != nil, "real provider fixture: \(URL(fileURLWithPath: path).lastPathComponent)")
        }
        defaults.removePersistentDomain(forName: "easytalk.learning.tests")
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED"); exit(failures == 0 ? 0 : 1)
    }
}

final class AnalysisMockProtocol: URLProtocol {
    static var responses: [(Int, Data)] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard !Self.responses.isEmpty else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let (status, data) = Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
