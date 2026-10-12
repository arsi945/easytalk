# Архитектура easytalk

Актуально8октября: iOS0.5.0/26, Mac0.4.1/11. SYSTEM_DICTATION_026.md заменяет прежний voice-return UX. Пользователь отверг app hops/return prompt/preview/Insert. Текущая клавиатура разрешает нижнюю системную диктовку iOS через hasDictationKey=false; нет собственного voice launch/control/result pipeline. Dictation text приходит в родительское поле средствами iOS, AI читает его через обычный proxy. Пользователь подтвердил живое распознавание на лету; английская диктовка пока неверно трактует русские вставки. primaryLanguage передаёт EN или RU, не одновременно два языка. Публичного управления смешанным системным распознаванием или inline stop-control в исследованных keyboard API не найдено; см. SYSTEM_DICTATION_026.md и bilingual-research.json. Не считать bilingual typing доказательством bilingual dictation.

В app/keyboard build phases исключены legacy VoiceReturn/host observer/VoiceRecorder/server/voice intents и SwiftUI mic controls; main app больше не обрабатывает voice-return URL. Historical source сохранён, флаг private observer выключен в Debug/Release. Widget target/IDs retained, activity не создаётся в текущем потоке. Lab собственный AVAudioRecorder независим, перед cleanup деактивирует свою сессию. Native system speech raw audio приложению не передаётся.

## Mac0.4.1: корректировки и одноразовая внешняя цель

CorrectionMarkup — presentation-only token LCS, bounded matrix/fallback, исходный текст/AI ranges не меняются. SwiftUI corrections selectable. DesktopModel.onPrepareInsertion захватывает callback только при вооружённой пользователем цели; successful validated result передаёт лишь translated fragment. Edit/cancel/generation guards предотвращают позднюю доставку.

DesktopWindowController наблюдает активацию приложения, не клавиши/текст. DesktopInsertionTarget читает AX element/range/value только при Translate, сохраняет process-local hash, исключает secure/unknown fields. Перед paste повторяет PID/focus/range/hash, при конфликте clipboard fallback. AX field text не идёт AI/на диск/в диагностику. Живая интеграция ещё не проверена.

## Исторический отвергнутый iOS25: preview-only возврат

VoiceReturnTransaction принадлежит одному controller; async fresh host query, deadline и fixed route. На реальном iOS27 controller/document меняются, fresh callback после app hop отсутствует. resumeForPreview передаёт ownership только при timeout в пределах30s и известном current document, automatic insertion запрещена. Старый controller не может отменить запрос нового. Result отображается readonly/selectable UITextView72–144pt; явное Insert пишет текущим proxy. Ticket loopback authenticated/bounded, no AppGroups. User subsequently confirmed explicit Insert works in Telegram; iOS showed the open-Telegram confirmation for public tg:// return. Automatic insertion/Notes remain unconfirmed. Отдельная ONNX модель в этом тракте не вызывается.

## История эксперимента automatic voice return (21–24)

VOICE_RETURN_PROTOTYPE.md описывает результаты. Свежий async host query → fixed public URL → main-app recorder → Notes/Telegram return → подтверждение поля.21 не получил initial host;22–24 включали audio, но fresh return callback отсутствовал; в23 проверка точного UUID тоже не помогла.25 добавляет preview-only путь, описанный выше. Private MIT observer только Debug keyboard, app/Release без реализации; App Groups нет.

## Историческое исследование перед21, без изменения кода

Исследование [VOICE_RETURN_RESEARCH.md](VOICE_RETURN_RESEARCH.md) отделяет автоматический app roundtrip от ручной подготовки. Найден новый host resolver для iOS26.4+, но открытая реализация использует private API, а готовый KeyboardKit10.9.7 несовместим с текущим Xcode16.2. Разрешение автоматического UX пока уточняется; интеграции/установки нет. При будущем roundtrip необходима фаза ожидаемого исчезновения keyboard: сейчас viewWillDisappear отменяет голос, transient nil/nil callback повышает revision. Защиту вставки в исходное поле сохранять.

## Результат проверки голоса, build 20

На iOS27 в Notes cold Button(intent:) не маршрутизировал запись в app: пользователь получил локальную ошибку extension, app audio не запустился. Этот путь не работает в текущем окружении. Shortcuts URL — другой системный запуск, но сохранение host на экране не доказано; не внедрять его как тихую замену. Диагностика после проверки использует process-wide lock и disk read/append/write, чтобы intent/controller instances не затирали события; app/extension файлы раздельны. Подробнее VOICE.md. Нового установленного выпуска нет.

## Предыдущее описание эксперимента, build 20

Manual warm session / foreground handoff ниже — история, отвергнутая автором. Сейчас экспериментируем с SwiftUI Button(intent:) из клавиатуры → AudioRecordingIntent + LiveActivityIntent → основное приложение + WidgetKit recording indicator. App implementation отделена EASYTALK_MAIN_APP; extension implementation пишет безопасное событие и бросает ошибку, никогда не создаёт аудиодвижок. Перед dispatch сохраняется VoiceDelivery context, затем polling authenticated loopback. Routing именно из keyboard ещё не подтверждён. URL VoiceLaunch только сериализация параметра, URL handler/redirect отсутствуют. Разовая permission кнопка не включает запись. Детали и источники: VOICE.md.

Обновлено 2026-10-07. Текущее состояние и проверенные сборки — в `HANDOFF.md`.

## Продуктовый цикл

Пользователь пишет английский с возможными русскими вставками в обычное поле. Кнопка «Перевести» запускает анализ и перевод на русский. Проверенный ответ заменяет только исходный фрагмент. Правки и подсказки доступны в «Учёбе». Каждое слово сохраняется «В словарь →» рядом с правкой; крестика отказа больше нет. Карточка: лицевая сторона — английское выражение, оборот — крупный русский смысл, меньший английский оригинал и примеры; переворот и перелистывание не означают «выучено». Пол хранится только в настройках и относится к первому лицу автора.

## Общие модули

- `Sources/EasyTalkCore`: Foundation, контракты JSON, согласование смещений/правок, работа с текстом, коллекция идиом. Смещения AI — Unicode scalar, позиции NSTextView — UTF16. Не смешивать эти единицы.
- `ios/Shared`: хранилище уроков и слов, предпочтения, игровые сессии, прогресс поощрений, запросы AI. На Mac собирается как `EasyTalkLearning`, на iOS эти файлы включаются непосредственно в targets. Условный import Core нужен для обоих вариантов.
- `glossary/idioms-en-ru.json`: единственный редактируемый источник идиом. Генератор создаёт Core/IdiomCatalog.swift.
- `prompts/analyze_translate.md`: источник промпта; `ios/generate_project.py` создаёт Shared/AnalysisPrompt.swift. Не редактировать сгенерированный промпт отдельно.

## iOS

Два targets: приложение `EasyTalk` (настройка ключа и поле для пробы) и extension `EasyTalkKeyboard`. Клавиатура использует `textDocumentProxy`: весь файл другого приложения недоступен. Обрабатывается доступное выделение или текущий фрагмент абзаца по правилам `KeyboardDraft`. Перед заменой повторно проверяются текст, курсор и идентификатор документа. Мост nullable `documentIdentifier` в Objective-C обязателен: на некоторых полях прямой Swift-доступ приводил к аварии.

У приложения и клавиатуры отдельные контейнеры, UserDefaults и Keychain. App Groups не используются. Настройки соединения передаются из приложения в клавиатуру явно через буфер. Для сети/импорта нужен Full Access. Нельзя обещать автоматическую синхронизацию ключа или слов между ними.

## macOS 0.3

`DesktopModel` хранит состояние окна и принимает внедряемые `DesktopAnalyzer` / `MacCredentialVault`. Реальный анализ выполняет тот же `AnalysisOperation`, что iOS. `DesktopRoot` — SwiftUI; `DesktopEditor` оборачивает NSTextView для выделения и undo. NSPanel/меню/хоткей — AppKit/Carbon. Новый интерфейс — плавающая панель справа шириной 392 pt, раскрытая полосой или компактная 260 pt высотой. Явная отправка выделения через DesktopSelectionService + NSServices, импорт без автоматического AI. Старые PanelController/Settings/AIClient сохранены для исторического прототипа и его `--snapshot`, но не используются основным потоком.

`DraftScope` отправляет выделение либо один абзац своего редактора. Модель отменяет запрос при редактировании или смене курсора и игнорирует поздние ответы по поколению запроса. До замены проверяется совпадение исходного документа и выделения. Ошибка/таймаут сохраняют исходный текст. Обычный Enter добавляет строку; ⌘Enter переводит; Escape отменяет текущий запрос.

Хранение Mac: секрет в Keychain, уроки/слова/предпочтения в UserDefaults bundle `app.easytalk.mac`. Никакой синхронизации с телефоном пока нет. Экспорт JSON содержит только личный словарь; импорт и миграция между платформами — следующий этап. Список разборов текущего процесса хранится в памяти, на диске только последний; 200 личных слов отдельно.

Вставка в чужое приложение — отдельное действие либо явный новый сценарий «Перевести и вставить» (MACOS_041.md). Исторический отдельный поток: Цель захватывается при открытии окна из другого приложения. Перед ⌘V повторно проверяется frontmost PID. Без Accessibility или цели текст копируется для ручного ⌘V. Приложение не читает автоматически общий буфер или чужие поля. «Из буфера» читает по явному нажатию; Services получает только отдельный pasteboard выделения. Гарантия вставки в конкретное чужое поле зависит от поведения самого приложения; нужна ручная проверка.

## AI и защита данных

Для личного прототипа есть прямой OpenAI API с личным ключом и режим собственного HTTPS-сервера. Провайдер не вызывается автоматически при старте. Анализ ограничен 2000 Unicode scalar; ответ локально валидируется. Сеть имеет срок ожидания и отмену. Отдельные Python/Cloudflare providers используют общий контракт. Личные ключи не должны попасть в исходники, логи, примеры, скриншоты, JSON-экспорт или архивы проекта.

Проверки Mac используют фиктивный ключ, MemoryCredentialVault, FakeAnalyzer и отдельный UserDefaults suite. QA запускается до создания реального хранилища. Запросы пользователя не посылаются в AI для отладки без его актуального разрешения.

## Учебные действия 0.3.6

`StudyContent.swift`: словарный профиль и варианты; `StudyActionService`: два дополнительных запроса с отменой и таймаутом. `StudyPagingView`: native UIScrollView, paging + directional lock. `SpeechPlayer`: установленный английский голос AVSpeechSynthesizer. Точные контракт/миграция/источники — STUDY_036.md. Codable optional metadata сохраняет совместимость; strict response требует новый dictionary. Старые contextual meaning не превращать в словарную форму механической заменой окончаний.

## Учебное состояние 0.3.7

`StudySession.archiveCurrent()` удаляет карточку из текущего раунда только после reveal, хранит achievement ID и `initialCount`. `StudyProgressStore.dictionaryCards` фильтрует All/InGame/Learned; `practice.introduced` сохраняет явно выученные builtin идиомы после возврата в игру. Словарь и learned-state независимы. iOS верхняя строка переключается между компактным translate control и segmented study; variantsExpanded по lesson ID меняет лишь представление. Mac использует то же Core/Learning хранилище, UI состояние variantsExpanded и DictionaryFilter, но отдельный bundle/Keychain. `LexicalEntry.offline` содержит narrow fix benefit без массового преобразования contextual переводов. Детали и тесты — STUDY_037.md.

## Ссылки 0.3.8

Общий UIKit TextLinkButton рисует CAShapeLayer под фактическим titleLabel; стиль задаёт Keyboard.styleLink. Mac StudyTextLink рисует тот же dash через SwiftUI Shape. Словарные фильтры — спокойный trailing ряд, без второй segmented панели. Карточка хранит mastery action в header, tap flip относится только к телу на Mac и не принимает UIControl touches на iOS. Никакого iOS footer «К вводу»; lifecycle при смене системной клавиатуры возвращает обычные буквы. Детали — LINKS_038.md.

## Уточнение смысла 0.3.9

AnalyzeTranslateRequest содержит optional intended_meaning; при наличии op=revise_analysis. AnalysisOperation сохраняет его и при repair. Lesson.intendedMeaning Codable optional для старых данных. LearningStore.revise сохраняет UUID/исходник, обновляет response и очищает варианты; перевод фиксируется ровно по русскому смыслу. iOS не пишет в родительское поле, проверяет snapshot/current lesson/document, не начисляет повторное поощрение. Детали и текущие ограничения — PANEL_MEANING_039.md.

## UX 0.4.0 / Mac 0.3.1

currentRussianText читает доступный русский абзац с обеих сторон курсора, selected включается в реконструкцию; это чтение, замены host нет. editedRussianMeaning сравнивает со stored translated и проверяет known document/последний урок. Для нескольких абзацев нужно полное выделение. Раскрытые переводы keyed UUID, исходник соседствует со своей ссылкой. Mac NSPanel с обычным title bar без utilityWindow, настройки возвращают page/compact; masked key prefill + eye. Одноразовый provisioning через stdin применяется явно по просьбе пользователя, не в автозапуске. Детали/проверки — UX_040.md.

## Mac 0.3.2

DesktopGrowingEditor измеряет текст TextKit по ширине и задаёт ограниченную высоту вместо maxHeight infinity. Компактная геометрия зависит от inputHeight, растёт вниз; полный ввод прокручивается. copyTranslation(UUID) копирует только stored Russian данного урока, отзыв через copiedTranslationID; не редактирует draft/selection и не отправляет AI. Word suggestion вертикальная, save под meaning, привязка к первой подходящей diff. Services metadata/protocol прежние, маршрут раскрывается над вводом. MACOS_032.md и evidence/macos032.

## Клавиатура 0.4.2 / общий промпт Mac 0.3.3

studyHostSnapshot сравнивается с доступным родительским полем в textDidChange/selectionDidChange: изменённое поле показывает буквы, урок остаётся. Во время applying/space drag callbacks не перестраивают UI; неизменённый snapshot не закрывает свежий разбор. У raw tap в чужом редакторе нет гарантированной доставки события. Последний урок открывает отдельный control без анализа. Phrase actions — один ряд с условным уточнением, источник под рядом; полные имена в accessibility.

SpaceCursorMotion — Foundation-направление/накопление пальца с порогами и сбросом при развороте. CursorNavigation по-прежнему переводит строки в смещение доступного текста, soft wraps оцениваются. KeyboardKey .alternate откладывает ь до release и раскрывает ь/ъ при hold, завершает жест до callback; KeyboardKeyArea блокирует новые касания во время trackpad. Клавиши/координаты не пересоздаются посреди drag. Публичного доступа к layout чужого UITextView нет.

prompts/analyze_translate.md просит правило, объяснение и пример в 2–4 предложениях; JSON schema/protocol прежние. ios/generate_project.py и scripts/make_worker.sh генерируют native/worker копии. Старые анализы не регенерируются. Simulator copy regression использует память и private pasteboard через conditional compilation; device/обычный clipboard поток прежние. Подробности, первичные источники и проверки — KEYBOARD_042.md.

## Голос и локальная акустика · 0.5.0 / Mac 0.4.0

VoiceRecorder в main app владеет AVAudioEngine; Speech request обязательно on-device, буферы вне диктовки отбрасываются, finite session 300s; build 15 live partial и VoiceEndpoint quiet pause 3 s после текста (RMS 0.008), stop final 1.2/8 s, audio buffers/endpoint под NSLock. VoiceBridgeServer/Client — bounded newline JSON на authenticated loopback TCP, ticket typed local-only pasteboard по явной подготовке. App Groups и приватные URL launch не используются. VoiceDelivery проверяет UUID запроса, host document, обе стороны курсора и выделение, потребляет ответ до вставки. Stale result → явная вставка, исчезновение extension → cancel. Реальная фоновая диктовка ещё требует ручного теста; local transport proof на Mac не заменяет iOS IPC/permission/asset validation.

LocalAcousticModel — ONNX Runtime 1.19.2 CPU в main app, не extension. Проверенный pinned int8 Wav2Vec2 export + CMU lexicon; 127 каналов logits, 125 именованных ID, PAD124. PronunciationAlignment Foundation декодирует CTC/альтернативы через lattice edit path; не calibrated score. Audio capture в лаборатории — AVAudioRecorder PCM16/16kHz/mono до12s, временный файл удаляется. iPhone bundling model/dictionary/license; Mac Python analyzer process со stdin reference, offline runtime paths из build, bounded wait/cancel и pipes drain. UI моделям не передаёт Keychain/подключение текстового API.

Реальный iPhone synthetic WAV proof 0.210s inference/1.303s cold total; human quality, long-clip memory/battery и background диктовка ещё не доказаны. Полный продуктовый контракт, первичные источники/лицензии/воспроизведение/ограничения — LOCAL_VOICE.md и VOICE.md.
