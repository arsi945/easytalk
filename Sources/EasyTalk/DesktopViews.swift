import AppKit
import SwiftUI
import EasyTalkCore
import EasyTalkLearning

enum DesktopPalette {
    static let goldInk = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedRed: 0.94, green: 0.76, blue: 0.36, alpha: 1) : NSColor(calibratedRed: 0.46, green: 0.33, blue: 0.09, alpha: 1) })
    static let gold = Color(red: 0.82, green: 0.60, blue: 0.12)
    static let blue = Color(red: 0.02, green: 0.42, blue: 0.91)
    static let cream = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedRed: 0.17, green: 0.15, blue: 0.11, alpha: 1) : NSColor(calibratedRed: 1, green: 0.98, blue: 0.91, alpha: 1) })
    static let paper = Color(nsColor: .controlBackgroundColor)
}
struct DesktopAction: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundColor(primary ? .white : .primary)
            .background(primary ? DesktopPalette.blue : DesktopPalette.paper)
            .cornerRadius(10).opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.44)
    }
}
private struct DashedLinkUnderline: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); return p }
}
struct StudyTextLink: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium)).foregroundColor(enabled ? DesktopPalette.goldInk : .secondary)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) { if enabled { DashedLinkUnderline().stroke(DesktopPalette.goldInk.opacity(0.8), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3])).frame(height: 1).allowsHitTesting(false) } }
            .padding(.vertical, 5).contentShape(Rectangle()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct DesktopRoot: View {
    @ObservedObject var model: DesktopModel
    @State private var selectionHelp = false
    private var activePage: DesktopPage { model.page == .idioms ? .dictionary : model.page }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if model.page == .settings {
                    Button(action: model.closeSettings) { Image(systemName: "chevron.left").font(.system(size: 17, weight: .regular)).frame(width: 28, height: 28) }.buttonStyle(.plain).help("Вернуться в приложение").accessibilityLabel("Вернуться в приложение")
                }
                Image(systemName: "text.bubble.fill").foregroundColor(DesktopPalette.gold)
                Text("easytalk").font(.system(size: 18, weight: .semibold))
                Spacer()
                if model.page != .settings {
                Button { model.compact.toggle(); if model.compact { model.page = .compose } } label: { Image(systemName: model.compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }.buttonStyle(.plain).help(model.compact ? "Раскрыть панель" : "Быстрый ввод")
                Button(action: model.openSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Настройки")
                }
            }
            if model.compact { composer(compact: true) }
            else {
                if model.page != .settings {
                    HStack(spacing: 5) {
                        ForEach([DesktopPage.compose, .study] + (model.gameEnabled ? [.game] : []) + [.dictionary]) { page in
                            Button(page == .compose ? "Ввод" : (page == .study ? "Разбор" : (page == .game ? "Игра" : "Словарь"))) {
                                if page == .study { model.openStudy() }
                                else if page == .game { if model.game == nil || model.game?.finished == true { model.startGame() } else { model.page = .game } }
                                else { model.page = page }
                            }.buttonStyle(.plain).font(.system(size: 13, weight: activePage == page ? .semibold : .regular))
                                .padding(.vertical, 8).frame(maxWidth: .infinity).background(activePage == page ? DesktopPalette.cream : Color.clear).cornerRadius(8)
                        }
                    }
                } else { Text("Настройки").font(.system(size: 22, weight: .semibold)) }
                Group {
                    switch model.page {
                    case .compose: ScrollView { composer(compact: false).frame(maxWidth: .infinity, alignment: .leading) }
                    case .study: DesktopStudy(model: model)
                    case .dictionary: DesktopDictionary(model: model, builtin: false)
                    case .idioms: DesktopDictionary(model: model, builtin: true)
                    case .game: DesktopGame(model: model)
                    case .settings: DesktopSettings(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.padding(14).frame(minWidth: 320, maxWidth: .infinity, minHeight: model.compact ? 205 : 490, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private func composer(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if !compact {
                Button(selectionHelp ? "Скрыть подсказку ↑" : "Как передать выделенный текст ↓") { selectionHelp.toggle() }.buttonStyle(StudyTextLink())
                if selectionHelp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Выдели текст в нужном приложении. Нажми правой кнопкой → Службы → Отправить в easytalk.")
                        Text("Также можно открыть меню приложения сверху → Службы → Отправить в easytalk.")
                        Text("Нет этого пункта? Системные настройки → Клавиатура → Сочетания клавиш → Службы: включи «Отправить в easytalk».")
                        Text("Или скопируй выделение (⌘C) и нажми здесь «Из буфера». Потом нажми «Перевести».")
                    }.font(.system(size: 13)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            DesktopGrowingEditor(model: model)
                .background(DesktopPalette.paper).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
            HStack {
                Button(model.insertionDestination != nil && !model.busy ? "Перевести и вставить" : model.translationTitle, action: model.translate).buttonStyle(DesktopAction()).disabled(!model.busy && model.alreadyTranslated)
                Spacer()
                Button("Из буфера") { model.onImportClipboard?() }.buttonStyle(StudyTextLink()).help("Скопируй выделенный текст через ⌘C, затем нажми здесь")
            }
            if let target = model.insertionDestination {
                Text("После перевода → \(target)").font(.system(size: 12)).foregroundColor(.secondary)
            }
            if !model.notice.isEmpty { Text(model.notice).font(.system(size: 13)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true).lineLimit(compact ? 2 : nil) }
            if !compact {
                HStack { Button("Скопировать", action: model.copyDraft).buttonStyle(StudyTextLink()).disabled(model.draft.isEmpty); Spacer(); Button("Вставить", action: model.pasteDraft).buttonStyle(StudyTextLink()).disabled(model.draft.isEmpty) }
                Text("⌘↩ перевод · ⌃⌥Пробел открыть").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }
}
private struct DesktopStudy: View {
    @ObservedObject var model: DesktopModel
    @State private var sessionExpanded = false
    @State private var translatedLessons = Set<UUID>()
    @State private var originalLessons = Set<UUID>()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let lesson = model.lesson {
                    if model.store.lessons.count > 1 {
                        Button(sessionExpanded ? "Свернуть список ↑" : "Разборы занятий · \(model.store.lessons.count) ↓") { sessionExpanded.toggle() }.buttonStyle(StudyTextLink())
                        if sessionExpanded {
                            ForEach(model.store.lessons, id: \.id) { item in
                                Button(item.response.corrected) { model.chooseLesson(item.id); sessionExpanded = false }.buttonStyle(StudyTextLink()).disabled(item.id == lesson.id)
                                translation(item)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { studySection("Естественный английский", text: lesson.response.corrected); Spacer(); Button { model.speak(lesson.response.corrected) } label: { Image(systemName: "speaker.wave.2") }.help("Произнести фразу") }
                        translation(lesson)
                        Button(originalLessons.contains(lesson.id) ? "Скрыть исходный текст ↑" : "Исходный текст ↓") { if !originalLessons.insert(lesson.id).inserted { originalLessons.remove(lesson.id) } }.buttonStyle(StudyTextLink())
                        if originalLessons.contains(lesson.id) { Text(lesson.source).font(.system(size: 17)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        if let praise = model.reward { Text(praise).font(.system(size: 16, weight: .semibold)).foregroundColor(DesktopPalette.gold) }
                        Button(model.studyBusy ? "Отменить запрос" : "Перефразировать в разных стилях", action: model.rephrase).buttonStyle(StudyTextLink())
                        if let variants = lesson.variants, !variants.isEmpty {
                            Button(model.variantsExpanded ? "Свернуть варианты ↑" : "Показать варианты · \(variants.count) ↓") { model.variantsExpanded.toggle() }.buttonStyle(StudyTextLink())
                            if model.variantsExpanded {
                                ForEach(Array(variants.enumerated()), id: \.offset) { _, variant in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack { Text(variant.label).font(.caption); Spacer(); Button { model.speak(variant.text) } label: { Image(systemName: "speaker.wave.2") } }
                                        Text(variant.text).font(.system(size: 20, weight: .medium)).textSelection(.enabled)
                                        Text(variant.explanation).foregroundColor(.secondary)
                                    }
                                }
                                Button("К замечаниям · свернуть варианты ↑") { model.variantsExpanded = false }.buttonStyle(StudyTextLink())
                            }
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(DesktopPalette.cream).cornerRadius(16)
                    if !model.studyNotice.isEmpty { Text(model.studyNotice).foregroundColor(.secondary) }
                    if lesson.response.diffs.isEmpty { Label("Грамматических правок нет", systemImage: "sparkles").foregroundColor(DesktopPalette.gold) }
                    ForEach(lesson.response.diffs, id: \.id) { diff in
                        VStack(alignment: .leading, spacing: 8) {
                            CorrectionMarkup.original(diff.original, corrected: diff.corrected).reduce(Text("")) { text, span in
                                text + Text(span.text).strikethrough(span.changed)
                            }.foregroundColor(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Text(diff.corrected).font(.system(size: 17, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Text(diff.explanation).foregroundColor(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            ForEach(lesson.response.studyVocabulary.filter { word in lesson.response.diffs.first(where: { matches(word, diff: $0) })?.id == diff.id }, id: \.term) { word in suggestion(word) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(DesktopPalette.paper).cornerRadius(12)
                    }
                    let remaining = lesson.response.studyVocabulary.filter { word in !lesson.response.diffs.contains { matches(word, diff: $0) } }
                    if !remaining.isEmpty { Divider(); ForEach(remaining, id: \.term) { word in suggestion(word) } }
                } else { empty("Здесь появятся подсказки", detail: "Напиши фразу и нажми «Перевести».", symbol: "text.book.closed") }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
        }
    }
    @ViewBuilder private func translation(_ lesson: Lesson) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(translatedLessons.contains(lesson.id) ? "Перевод ↑" : "Перевод ↓") {
                if !translatedLessons.insert(lesson.id).inserted { translatedLessons.remove(lesson.id) }
            }.buttonStyle(StudyTextLink())
            Spacer(minLength: 0)
            Button(model.copiedTranslationID == lesson.id ? "Скопировано" : "Скопировать перевод") { model.copyTranslation(lesson.id) }
                .buttonStyle(StudyTextLink()).help("Скопировать русский перевод этой фразы для вставки через ⌘V")
                .accessibilityLabel("Скопировать перевод: " + lesson.response.translated)
        }
        if translatedLessons.contains(lesson.id) { Text(lesson.response.translated).font(.system(size: 16)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
    private func matches(_ word: VocabularySuggestion, diff: LearningDiff) -> Bool {
        diff.corrected.localizedCaseInsensitiveContains(word.term) || word.term.localizedCaseInsensitiveContains(diff.corrected)
    }
    private func suggestion(_ word: VocabularySuggestion) -> some View {
        let dictionary = word.dictionary?.validated ?? LexicalEntry.offline(word.term)
        let saved = model.store.contains(word.savedTerm)
        let term = dictionary?.headword ?? word.term
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(term).font(.system(size: 18, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Button { model.speak(term) } label: { Image(systemName: "speaker.wave.2").font(.system(size: 14)) }.buttonStyle(.plain).help("Произнести слово")
                Spacer(minLength: 0)
            }
            Text(dictionary?.meanings.joined(separator: "; ") ?? word.meaning).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button(saved ? "В словаре" : "В словарь →") { model.save(word) }.disabled(saved).buttonStyle(StudyTextLink())
                    .accessibilityLabel(saved ? term + " уже в словаре" : "Сохранить " + term + " в словарь")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
    private func studySection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary); Text(text).font(.system(size: 19)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
}
private struct DesktopDictionary: View {
    @ObservedObject var model: DesktopModel
    let builtin: Bool
    @State private var search = ""
    @State private var category = "Все"
    @State private var expandedCards = Set<String>()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Поиск по слову или переводу", text: $search).textFieldStyle(.roundedBorder)
                if builtin {
                    Picker("Тема", selection: $category) { ForEach(["Все"] + Array(Set(IdiomCatalog.all.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 190)
                } else { Button("Экспорт…", action: model.exportWords).disabled(model.store.words.isEmpty) }
            }
            HStack { Button(builtin ? "← Мой словарь" : "Идиомы →") { model.page = builtin ? .dictionary : .idioms }.buttonStyle(StudyTextLink()); Spacer() }
            if !builtin {
                HStack(spacing: 18) {
                    Spacer()
                    ForEach(VocabularyFilter.allCases, id: \.self) { filter in
                        if model.dictionaryFilter == filter { Text(filter.title).font(.system(size: 14, weight: .semibold)).accessibilityLabel(filter.title + ", выбран") }
                        else { Button(filter.title) { model.dictionaryFilter = filter }.buttonStyle(StudyTextLink()) }
                    }
                }
                if model.gameEnabled && !model.progress.dictionaryCards(words: model.store.words, filter: .inGame).isEmpty { Button("Повторить в карточках", action: { model.startGame() }).buttonStyle(StudyTextLink()) }
                if !model.studyNotice.isEmpty { Text(model.studyNotice).font(.system(size: 14)).foregroundColor(.secondary) }
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    if builtin {
                        ForEach(IdiomCatalog.all.filter { (category == "Все" || $0.category == category) && matches($0.term + " " + $0.meaning) }) { idiom in
                            WordTile(term: idiom.term, meaning: idiom.meaning, example: idiom.example, note: idiom.note, saved: model.store.contains(idiom.term), source: URL(string: idiom.source), onSave: { model.saveIdiom(idiom) }, onDismiss: nil)
                        }
                    } else {
                        let cards = model.progress.dictionaryCards(words: model.store.words, filter: model.dictionaryFilter).filter { matches($0.term + " " + $0.meaning) }
                        ForEach(cards, id: \.id) { card in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Text(card.term).font(.system(size: 20, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        Button { model.speak(card.term) } label: { Image(systemName: "speaker.wave.2").font(.system(size: 14)) }.buttonStyle(.plain).help("Произнести слово")
                                    }
                                    Spacer(minLength: 0)
                                    Button { if !expandedCards.insert(card.id).inserted { expandedCards.remove(card.id) } } label: { Image(systemName: expandedCards.contains(card.id) ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .regular)).frame(width: 24, height: 28) }.buttonStyle(.plain).help("Примеры и сведения о слове")
                                }
                                Text(card.meaning).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
                                if expandedCards.contains(card.id) {
                                    ForEach(card.examples, id: \.self) { Text($0).font(.system(size: 14)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
                                }
                                HStack {
                                    if let word = model.store.words.first(where: { "word." + $0.id.uuidString == card.id }) {
                                        Button(model.studyBusy ? "Отменить запрос" : "Подробней о слове") { model.refine(word) }.buttonStyle(StudyTextLink())
                                        Menu { Button("Удалить из словаря") { model.remove(word) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 26)
                                    }
                                    Spacer()
                                    Button(model.progress.isLearned(card.id) ? "Вернуть в карточки" : "Выучил") { model.changeMastery(card.id) }.buttonStyle(StudyTextLink())
                                }
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(DesktopPalette.cream).cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesktopPalette.gold.opacity(0.28)))
                        }
                        if cards.isEmpty { empty(model.dictionaryFilter == .learned ? "Здесь будут выученные слова" : (model.dictionaryFilter == .inGame ? "Все слова уже выучены" : "Твой словарь начинается с одной фразы"), detail: "Сохраняй слова из разбора. «Запомнил» переносит карточку в «Выучил».", symbol: "bookmark") }
                    }
                }.padding(.bottom, 16)
            }
            if builtin { Text("Значения проверены по открытым источникам. Примеры подготовлены для easytalk.").font(.system(size: 12)).foregroundColor(.secondary) }
        }
    }
    private func matches(_ value: String) -> Bool { search.isEmpty || value.localizedCaseInsensitiveContains(search) }
}
private struct WordTile: View {
    let term: String, meaning: String, example: String, note: String
    let saved: Bool; let source: URL?
    let onSave: (() -> Void)?; let onDismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(term).font(.system(size: 20, weight: .semibold)).textSelection(.enabled)
                Text(meaning).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
                if !example.isEmpty { Text(example).font(.system(size: 14)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
                if !note.isEmpty { Text(note).font(.system(size: 12)).foregroundColor(.secondary) }
                if let source, source.scheme == "https" { Link("Источник значения ↗", destination: source).buttonStyle(StudyTextLink()) }
            }
            Spacer(minLength: 0)
            if let onSave {
                Button(action: onSave) { Image(systemName: saved ? "bookmark" : "arrow.right").font(.system(size: 18, weight: .regular)).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundColor(DesktopPalette.gold).disabled(saved).help(saved ? "Уже в словаре" : "Сохранить «\(term)» в словарь")
            }
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 14, weight: .regular)).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundColor(.secondary).help(saved ? "Удалить «\(term)» из словаря" : "Пропустить «\(term)»")
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(DesktopPalette.cream).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesktopPalette.gold.opacity(0.28)))
    }
}
private func empty(_ title: String, detail: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 14) { Image(systemName: symbol).font(.system(size: 30)).foregroundColor(DesktopPalette.gold); Text(title).font(.system(size: 22, weight: .semibold)); Text(detail).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(DesktopPalette.cream).cornerRadius(18)
}
private struct DesktopGame: View {
    @ObservedObject var model: DesktopModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var animating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let feedback = model.gameFeedback { Text(feedback).font(.system(size: 17, weight: .semibold)).foregroundColor(DesktopPalette.gold).transition(.opacity) }
            if let game = model.game, let card = game.current {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Text("\(game.index + 1) / \(game.cards.count)").font(.system(size: 13)).foregroundColor(.secondary)
                        Spacer()
                        Button { model.speak(card.term) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.plain).help("Произнести слово")
                        if game.showingBack { Button(model.gender == .female ? "Запомнила" : "Запомнил") { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { model.rememberCard() } }.buttonStyle(StudyTextLink()).disabled(animating) }
                    }
                    Text(card.personal ? "Из твоего словаря" : "Английская идиома").font(.system(size: 12)).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                    if game.showingBack {
                        ScrollView { VStack(alignment: .leading, spacing: 14) {
                            Text(card.meaning).font(.system(size: 32, weight: .semibold))
                            Text(card.term).font(.system(size: 16, weight: .medium)).foregroundColor(.secondary)
                            Divider()
                            ForEach(card.examples, id: \.self) { Text($0).font(.system(size: 17)) }
                            Text(card.note).font(.system(size: 13)).foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading) }
                    } else {
                        Spacer(); Text(card.term).font(.system(size: 32, weight: .semibold)).fixedSize(horizontal: false, vertical: true); Spacer()
                        Text("Попробуй вспомнить значение").foregroundColor(.secondary)
                    }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle()).onTapGesture(perform: flip)
                }.padding(26).frame(maxWidth: .infinity).frame(height: 244).background(DesktopPalette.cream).cornerRadius(22)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(DesktopPalette.gold.opacity(0.4)))
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                        guard !animating, abs(value.translation.width) > 55, abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                        model.moveCard(value.translation.width < 0 ? 1 : -1)
                    })
                    .accessibilityElement(children: .contain)
                    .accessibilityAction(named: "Перевернуть", flip)
                    .accessibilityAction(named: "Следующая карточка", { model.moveCard(1) })
                    .accessibilityAction(named: "Предыдущая карточка", { model.moveCard(-1) })
                HStack { Text("Нажми, чтобы перевернуть. Листай влево или вправо.").font(.system(size: 12)).foregroundColor(.secondary); Spacer() }
                HStack { Spacer()
                    if card.personal, let word = model.store.words.first(where: { "word." + $0.id.uuidString == card.id }) { Button(model.studyBusy ? "Отменить запрос" : "Подробней о слове") { model.refine(word) }.buttonStyle(StudyTextLink()) }
                }
                if !model.studyNotice.isEmpty { Text(model.studyNotice).foregroundColor(.secondary) }
            } else {
                empty(model.game?.cards.isEmpty == true ? "Всё повторено" : "Маленький шаг сделан", detail: "Слова становятся выученными только после твоей отметки. Можно начать новый раунд или вернуться стрелкой ←.", symbol: "sparkles")
                HStack { Button("Новый раунд", action: { model.startGame() }).buttonStyle(DesktopAction()); Button("Словарь") { model.page = .dictionary }.buttonStyle(StudyTextLink()) }
            }
            Spacer()
            Text("Пробел — перевернуть · ← → — листать").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }
    private func flip() {
        guard !animating else { return }
        if reduceMotion { model.flipCard(); return }
        guard let round = model.game else { return }
        let capturedIndex = round.index, capturedBack = round.showingBack
        animating = true
        withAnimation(.easeIn(duration: 0.14)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            guard model.page == .game, model.game === round, round.index == capturedIndex, round.showingBack == capturedBack else { angle = 0; animating = false; return }
            model.flipCard(); angle = -90
            withAnimation(.easeOut(duration: 0.16)) { angle = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { animating = false }
        }
    }
}
private struct DesktopSettings: View {
    @ObservedObject var model: DesktopModel
    @State private var key = ""
    @State private var showKey = false
    @State private var aiModel = "gpt-6-luna"
    @State private var endpoint = ""
    @State private var provider: AIProvider = .openai
    @State private var workspace = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("О тебе").font(.system(size: 19, weight: .semibold))
                    Text("Пол для перевода от первого лица").font(.system(size: 14))
                    Picker("Пол", selection: $model.gender) { ForEach(SpeakerGender.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu).labelsHidden()
                    Text("Помогает выбрать «сделал» или «сделала». Учитывается только в твоих фразах от первого лица.").font(.system(size: 13)).foregroundColor(.secondary)
                    Toggle("Поощрения за фразы без ошибок", isOn: $model.rewardsEnabled)
                    Toggle("Карточки «Второй навык»", isOn: $model.gameEnabled)
                }.padding(20).background(DesktopPalette.cream).cornerRadius(16)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Подключение AI").font(.system(size: 19, weight: .semibold))
                    Picker("Провайдер", selection: $provider) { ForEach(AIProvider.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu).labelsHidden()
                        .onChange(of: provider) { new in if model.connection?.provider != new { key = ""; aiModel = new.defaultModel; endpoint = new.defaultBaseURL } }
                    Text(provider.keyHelp).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Group { if showKey { TextField(provider.keyPlaceholder, text: $key) } else { SecureField(provider.keyPlaceholder, text: $key) } }.textFieldStyle(.roundedBorder)
                        Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }.buttonStyle(.plain).help(showKey ? "Скрыть ключ" : "Показать сохранённый ключ")
                    }
                    if model.connection != nil { Text("Ключ сохранён. Оставь поле пустым, чтобы сохранить прежний.").font(.system(size: 12)).foregroundColor(.secondary) }
                    TextField("Модель", text: $aiModel).textFieldStyle(.roundedBorder)
                    if provider.editableBaseURL { TextField(provider.addressHint, text: $endpoint).textFieldStyle(.roundedBorder) }
                    if provider.needsWorkspace { TextField("ID рабочего пространства: wrkspc_…", text: $workspace).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Сохранить подключение") { if model.saveConnection(key: key, model: aiModel, provider: provider, baseURL: endpoint, workspaceID: workspace) { key = model.connection?.token ?? ""; showKey = false } }.buttonStyle(DesktopAction(primary: true))
                        if model.connection != nil { Button("Отключить AI", action: model.disconnect).buttonStyle(DesktopAction()) }
                    }
                    Text("В AI отправляется выделение или текущий абзац, когда ты нажимаешь «Перевести». Ключ хранится в Keychain этого Mac.").font(.system(size: 13)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !model.notice.isEmpty { Text(model.notice).font(.system(size: 13)).foregroundColor(.secondary) }
                }.padding(20).background(DesktopPalette.paper).cornerRadius(16)
                Text("easytalk для macOS · 0.3.3\n⌃⌥Пробел открывает окно из другого приложения. Для автоматической вставки нужен доступ «Универсальный доступ»; обычное копирование работает сразу.").font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 16)
        }.onAppear { if let c = model.connection { key = c.token; provider = c.provider; aiModel = c.model; endpoint = c.baseURL; workspace = c.workspaceID } }
    }
}
