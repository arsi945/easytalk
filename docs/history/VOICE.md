# Голос в easytalk

**Этот app-owned keyboard dictation путь отвергнут автором8октября и отключён в26.** Техническая вставка25 в Telegram не означает согласия на app hop/системный запрос возврата/preview/Insert. Актуальный путь — нижний системный 🎙 iOS; SYSTEM_DICTATION_026.md. Ниже исторические результаты.

**Актуально8октября: iPhone0.5.0/build25 установлен.** Читать VOICE_RETURN_PROTOTYPE.md. Пользователь подтвердил полный путь с явным «Вставить диктовку» в Telegram; система запросила разрешение открыть Telegram при возврате через tg://. Автовставка и вставка в Notes не подтверждены. Пауза3s, automatic brief app hop. Это Apple Speech on-device, не ONNX pronunciation model. Автор попросил оставить обычное распознавание, оценку речи пока отложить. Ручную подготовку/5-minute кнопку не возвращать. Этот верх заменяет следующие исторические состояния20–24/ожидания. Mac0.4.1/11 установлен, MACOS_041.md.

## История исследования и прежних сборок

**Актуально8октября: [VOICE_RETURN_PROTOTYPE.md](VOICE_RETURN_PROTOTYPE.md).** Автор разрешил оба automatic app hop/return пути. **22 установлен:** app открылся, микрофон работал в фоне, но наша повторная проверка host отменила запись после timeout.23 исправляет подтверждение возвращённого поля. Ручную подготовку не возвращать. Нижние «ответа нет / redirect удалён / телефон20» — история. SDK текущим Xcode не импортируется.

**Новое исследование 8 октября:** [VOICE_RETURN_RESEARCH.md](VOICE_RETURN_RESEARCH.md). В актуальном KeyboardKit исправлено определение host, Wispr Flow описывает автоматическое открытие recorder и возврат. Это новый кандидат, но не готовый фикс easytalk. Автоматический переход вынесен на отдельное уточнение: ручная подготовка и отсутствие любых визуальных переходов — разные требования. Ответ пока не получен; поведение не изменено. На телефоне прежний неудачный build20.

## Решение автора, 8 октября 2026

Диктовка должна начинаться кнопкой 🎙 нашей клавиатуры: нажал → сказал → 3 секунды тишины → текст в текущем поле. Автор **отверг ручную подготовку сессии, переход в основное приложение и смену клавиатур**. Первые системные разрешения микрофона/речи — отдельная разовая настройка; они не должны включать таймер готовности или аудиозапись.

**Установлен iOS 0.5.0 / build 20 — проверка в Заметках на iOS27 завершилась отказом: микрофон не запустился.** Подготовка удалена из UI. Redirect/Link/openURL и экран возврата удалены из сборки; отвергнутая реализация сохранена в archive/20261008-041549-voice-handoff-and-intent-research.tar.gz. Пользователь подтвердил локальную ошибку keyboard. Тот же путь больше не считать кандидатом на рабочее исправление. Не выдавать успешную компиляцию за доступ к фоновому микрофону.

## Подтверждённый результат, 8 октября

Клавиатура: `tap-cold-launch` → `background-intent-request` → `error` → `cancel` за ~61 мс. App trace содержит только старое `entered-background`, engineRunning=false. Пользователь подтвердил сообщение «iOS запустила действие внутри клавиатуры и не дала включить микрофон». Таким образом, холодный `Button(intent:)` из keyboard не запустил app-owned capture в этом окружении. Это ошибка нашего выбора точки запуска, не повод повторно просить выдать разрешения или разблокировать телефон.

Сохранены metadata-only `evidence/ios050/voice-cold-failure20*.json`. Отдельный дефект журнала: у разных VoiceDiagnostics instances были собственные events arrays; intent event затирался следующим controller write. После проверки исправлено сериализацией read/append/write под общим NSLock; временные тестовые файлы изолированы от пользовательских контейнеров. Эта правка **не устраняет ограничение запуска**. Новая сборка после неудачного пользовательского теста на iPhone не устанавливалась.

## Реализация установленного неудачного эксперимента

На iOS 18+ холодная кнопка — SwiftUI `Button(intent:)` с `StartEasyTalkVoiceIntent: AudioRecordingIntent, LiveActivityIntent`. PrimitiveButtonStyle сначала захватывает документ/курсор, затем запускает intent; одинаковая последовательность для tap и VoiceOver. Параметр содержит случайные UUID/IPC capability и срок до 5 минут; исходный текст в него не попадает. URL используется только как сериализация параметра, URL-схема не регистрируется и не открывается.

Основной target компилируется с EASYTALK_MAIN_APP: проверка уже предоставленных разрешений → Live Activity → AVAudioEngine / on-device Apple Speech → authenticated loopback bridge. Новое расширение com.easytalk.personal.voiceactivity показывает индикатор и «Выключить микрофон». Существующие app/keyboard IDs и Personal Team сохранены; App Groups не добавлены. Apple требует Live Activity, пока AudioRecordingIntent записывает звук: [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent).

Клавиатурная реализация intent **никогда не создаёт аудиодвижок**. Если SwiftUI выполнит intent локально в extension, пишет только событие audio-intent-extension и возвращает явную ошибку. Если система выберет app, там будет audio-intent-app. Теперь локальное выполнение подтверждено пользователем: документация Apple гарантирует app process для LiveActivityIntent в виджетах, но не обещает такую маршрутизацию для произвольной keyboard view. [Apple: interactive widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

Клавиатура ждёт запуска до 10 секунд, затем показывает ошибку без скрытого перехода в другое приложение. Готовая сессия управляется прежним loopback IPC. Нет обращения к AI API, облачного ASR или записи файлов диктовки. После результата вставка только при совпадении исходного поля/курсора; иначе явная «Вставить диктовку». При закрытии клавиатуры запрос отменяется.

## Что уже подтверждено

В build 17/18 пользователь получил реальный текст с микрофона в пустом поле самого easytalk, автоматически по паузе. Это foreground, не доказательство диктовки в Notes. Последующие попытки Notes не имели включённой сессии; автор затем уточнил, что включать её вручную вообще не собирался. Их ошибки нельзя трактовать как тест работавшего фонового аудио.

Apple Speech на синтетическом WAV прошёл на реальном iPhone: 6 слов точно, 0,495 с foreground и 1,087 с background с кратким debug UIKit grant, без микрофона. Локальная акустическая ONNX-модель на iPhone: 0,210 с inference / 1,303 с cold total. Это отдельные проверки, не пользовательская фоновая диктовка.

Build 20: device и Simulator compilation, подпись всех targets, 6 свежих UIKit reports, Foundation/Core, 8 Python + 31 voice checks + 5 ticket + 12 launch validations и реальный loopback transport прошли. Evidence: docs/evidence/ios050 и local-voice. **Последующий пользовательский тест cold mic в чужом host завершился отказом.**

## Проверенные продукты и следующие варианты

[Wispr Flow](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone) описывает открытие приложения из клавиатуры с автоматическим возвратом; fallback требует системного жеста назад. Его [Shortcuts](https://docs.wisprflow.ai/articles/1986921789-How-to-Set-Up-Flow-Shortcuts-for-iPhone) поддерживают запуск записи без открытия приложения и требуют Live Activities.

[Outspoken, описание разработчика](https://www.useoutspoken.com/blog/the-keyboard-is-a-remote-control): готовый background процесс, затем заранее созданный Shortcut с AudioRecordingIntent, затем redirect. Между фразами сохраняет hardware capture на ограниченное время. Это полезный первичный источник, но нельзя переносить его гарантии на наш код или добавлять искусственный audio keep-alive.

### Что проверено в публичных системных API

- [Apple: Shortcuts URL](https://support.apple.com/en-au/guide/shortcuts/apd624386f42/ios) запускает предварительно сохранённую команду. Это возможный путь через системный executor, но документация не гарантирует сохранение Notes/Telegram на экране или возврат в произвольное родительское приложение. В проект он не добавлен как будто требование «без переходов» выполнено.
- [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent) — нужный тип системного действия; требует Live Activity при записи. Доступ к правильному исполнителю важнее названия протокола. Успех из Siri/Control Center/Shortcuts не доказывает вызов с keyboard mic.
- [AppIntent.callAsFunction](https://developer.apple.com/documentation/appintents/appintent/callasfunction%28donate%3A%29-7v1om) разрешает параметры и вызывает perform; это не межпроцессный dispatch.
- [RunSystemShortcutIntent.perform](https://developer.apple.com/documentation/appintents/runsystemshortcutintent/perform%28%29?changes=_7) работает только при вызове кнопкой widget; для keyboard это не решение. В Xcode16.2 SDK18.2 этот новый тип также отсутствует.
- [Apple: Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) запрещает keyboard extension захватывать микрофон; Full Access этого не меняет.

**Текущий предел:** готового публичного маршрута «холодное приложение → mic в keyboard → запись без переходов/подготовки» у проекта нет. Это не доказательство невозможности всех реализаций, но оснований обещать готовность больше нет. Следующий прототип имеет смысл только с новой проверяемой системной точкой запуска; не повторять локальный Button(intent:), не вводить отвергнутый UX без согласования. Приватные selectors/responder-chain/UIApplication suspend и искусственный audio keep-alive не добавлять.

## Локальное произношение

Лаборатория iPhone/Mac: известный английский эталон, запись до 12 секунд, ONNX-фонемы и CMUdict, гипотезы расхождений по словам. Нет притворных баллов /100 или замены фонетики confidence ASR. Перевод/грамматика всё ещё используют существующий текстовый AI API. Модель, лицензии, восстановление и ограничения: [LOCAL_VOICE.md](LOCAL_VOICE.md).
