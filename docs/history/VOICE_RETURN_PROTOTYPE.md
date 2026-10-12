# Автоматическая диктовка: состояние 8 октября 2026

**Этот app-owned keyboard dictation путь отвергнут автором8октября и отключён в26.** Техническая вставка25 в Telegram не означает согласия на app hop/системный запрос возврата/preview/Insert. Актуальный путь — нижний системный 🎙 iOS; SYSTEM_DICTATION_026.md. Ниже исторические результаты.

Этот документ заменяет прежние ожидания «ответа ещё нет / интеграции нет» в VOICE_RETURN_RESEARCH.md и исторических разделах. Автор разрешил «проверяем оба», подключил iPhone и просил продолжать. Разрешён личный Debug-эксперимент автоматического открытия recorder и возврата; ручную подготовку не возвращать.

## Текущее состояние: build25, подтверждена явная вставка в Telegram

**iOS0.5.0/build25 установлен, версия проверена. Mac0.4.1/11 установлен отдельно (MACOS_041.md).** Автор уточнил: оставить обычное распознавание диктовки, оценку произношения пока отложить. Все эти dictation prototypes использовали **Apple Speech on-device**, не скачанную ONNX-модель. Акустическая лаборатория независима, сохранена для дальнейшей работы.

Пользователь сначала сообщил о тексте в предпросмотре и уточнил, что Insert не нажимал. **Затем подтвердил: кнопка «Вставить диктовку» работает; проверка была в Telegram, не в Notes.** При автоматическом возврате система спросила разрешение easytalk открыть Telegram. Это соответствует `VoiceReturnRoute.telegram → tg:// → UIApplication.shared.open`. Для текущего сценария нужно разрешить переход, чтобы вернуться в Telegram. Не обещать, что система никогда не спросит снова; из этого отчёта периодичность неизвестна.

**End-to-end распознавание с явной вставкой в Telegram подтверждено пользовательским отчётом.** Автоматическая вставка без Insert и вставка в Notes не подтверждены. Новый отдельный evidence: `voice-return25/telegram-user-confirmation.json`; после отчёта код/версия/установки не менялись.

Metadata `evidence/voice-return25/{keyboard,app}-live.json` показывает: fresh Notes query → public app URL → AVAudioEngine/Speech → Notes return opened → background frames/ASR callbacks → pause → result; keyboard timeout → preview-only → result hasText. Текст/аудио/ключи в evidence отсутствуют.

### Почему появился предпросмотр

После app hop iOS27 заменяет controller/document UUID, а свежий callback host observer не приходит. Автоматически доказать прежнее поле не удалось в23/24. Build25 `resumeForPreview` при **timeout** (не свежем conflicting host/cancel), известном текущем документе и пределах30s передаёт одноразовое владение новому controller, но не право автоматической записи. Запись продолжается до паузы3s, результат показывается readonly/selectable UITextView72–144pt. «Вставить диктовку» явно пишет текущим `textDocumentProxy`. Cancel/новая диктовка/скрытие убирают preview. Старый controller не может завершить transaction нового owner или послать cancel за него.

Это подтверждённый в Telegram путь: распознать → предпросмотр → явная вставка; Insert остаётся дополнительным шагом. Мигание — public automatic app hop для микрофона. Ручной подготовки нет; wholly keyboard-owned recording не реализован. Полностью автоматическая вставка без этого шага остаётся незавершённой.

## Реальные предыдущие результаты

- **21:** установлен, host unresolved, новый app audio не запускался.
- **22:** установлен, fresh Notes query, app/audio/background frames и возврат достигнуты. Повторный host query0events → наша защита cancel.
- **23:** установлен/проверен, sameOwner=false/sameDocument=false/sameContext=false. Точный прежний document UUID не подтверждает возвращённое поле; снова cancel.
- **24:** установлен/проверен, снова ошибка подтверждения возврата. Early viewWillAppear + baseline последней инвалидации +4s ожидания всё равно0fresh events. App получил ASR callback в фоне, но наш guard отменил запись.
- **25:** установлен/проверен, user subsequently confirms explicit Insert works in Telegram; system open prompt observed. Status/evidence отдельно, не смешивать с прежними накопленными events в bounded журнале.

## Build22: асинхронный host query

Build21 синхронно крутил runloop50мс. `VoiceHostQuery` теперь ждёт новый callback до1с через main dispatch, не блокируя клавиши; повторные ping на0.25/0.6с, максимум3. Исторический bundle ID не удовлетворяет query. Исчезновение/смена владельца отменяет query; snapshot поля до ожидания должен совпасть перед открытием app. Повторный tap на время query отключён.

Upstream hook отмечает установку до проверки наличия класса. Локальный wrapper повторяет установку, только если destination method появился, а original IMP ещё не сохранён. Уже установленный trampoline не перехватывается повторно. Upstream .m/.h остаются неизменными. Private hook/его retry — только Debug keyboard; Release и основной процесс не содержат реализации.

На появлении клавиатуры один ограниченный query пишет metadata без mic. `host-query-observed/timedOut/cancelled`, bit mask, число событий и закрытая категория `none/notes/telegram/easytalk/other`; реальные чужие bundle IDs, текст, аудио, token, UUID документов и ключи не логируются.

| Bit | hostFlags |
|---:|---|
| 1 | arbiter client class |
| 2 | destination class |
| 4 | enabled method |
| 8 | destination callback method |
| 16 | enabled IMP — наш trampoline |
| 32 | callback IMP — наш trampoline, original IMP сохранён |
| 64 | automatic client getter |
| 128 | getter вернул client |
| 256 | client поддерживает checkConnection |

Mask511 не гарантирует новый callback. `hostEvents=0` при старой категории notes не подтверждает новый холодный запуск.

## Build23: независимое подтверждение исходного поля

Повторный arbiter callback не гарантирован. Возврат теперь можно подтвердить по **точному совпадению публичного document UUID и полного VoiceFieldContext** (обе стороны курсора, выделение, revision), но только при timeout query. Простое совпадение текста недостаточно. Cancelled query, свежий неизвестный/противоречащий host, новый документ, изменённый курсор/текст, неизвестный UUID или истёкший30с transaction не допускают этот путь.

UIKit может заменить controller при app hop. После подтверждения точного поля transaction **однократно** передаёт владение новому видимому controller. Старый owner больше не получает результат; phase returned не позволяет второе resume. Это заменяет прежнее правило «любой новый controller всегда manual». При известном правильном host, но изменённом поле остаётся только явная вставка. `VoiceDelivery.consume` по-прежнему повторно проверяет context непосредственно перед вставкой и потребляет ответ один раз.

Metadata `handoff-return-field-check` содержит только sameOwner/sameDocument/sameContext booleans. Эти флаги покажут, сохраняет ли iOS идентичность поля при фактическом возврате.

## Полная схема

SwiftUI mic → свежий host (allowlist Notes/Telegram/своё app) → одноразовый `easytalk://voice-return` с request/token/expiry/route, **без текста/аудио** → active app → AVAudioEngine + обязательный on-device Apple Speech ready → публичная фиксированная `mobilenotes://` или `tg://` → подтверждение host либо точного исходного поля → authenticated loopback polling → **3с тишины** → одноразовая вставка. Максимум записи45с, ожидание return30с, отсутствующий ack выключает mic по watchdog. Ручной подготовки нет. Внутренний предел warm session300с не является пользовательской кнопкой подготовки.

VoiceReturnTransaction отделяет ожидаемое исчезновение от отмены. Неактивный controller не забирает ответ, transient callbacks не повышают revision во время ожидаемого перехода. Произвольного обратного URL/private open/suspend/App Groups нет. Публичная схема сама по себе не гарантирует ту же заметку/чат/фокус — именно поэтому нужна проверка поля.

## Второй вариант: готовый SDK

KeyboardKit10.9.0 и10.9.7 проверены минимальным import в Xcode16.2/Swift6.0.3: оба не компилируются (FoundationModels отсутствует в SDK18.2, интерфейс Swift6.3.3). Логи evidence/voice-return21. Лицензия не покупалась, SDK в targets не добавлялся.

[Package.swift11.0.0](https://github.com/KeyboardKit/KeyboardKit/blob/11.0.0/Package.swift) тоже определяет HostPlugin/DictationPlugin как **binary targets**, требует Swift6.2. Новые plugins не дают открытого source resolver для старого toolchain. Бинарник не дизассемблировался. [Описание plugins](https://keyboardkit.com/blog/2026/09/27/keyboardkit-11-the-final-beta).

iMac18,3(2017) официально ограничен Ventura; текущая14.8.7 уже вне официальной поддержки. Нужная новому Xcode macOS этим Mac официально не поддерживается. Системное ПО/CLT/xcode-select не менялись. Новый Xcode сам по себе не даёт keyboard extension микрофон.

## Проверки и сохранение

Build21:46 route/transaction,162 Foundation,8 Python/31 voice/5ticket+12launch/loopback, Core14/Mac75,6 UIKit, device/Simulator/codesign/install. Build22:60 checks включая ответ через80мс/stale/timeout/cancel,162 Foundation, voice/loopback, writer10, device/Simulator/codesign/install. Живые результаты описаны отдельно выше.

Build23:70 route/query/transaction checks, включая отсутствие callback при совпавшем поле, однократную передачу owner и запреты неизвестного/другого поля, revision, fresh conflict, expiry. Device/codesign/install/version прошли. Simulator/UI прогон сохранён отдельно. Mac/native повторно не менялись/не устанавливались.

Build23 Simulator и6 свежих UIKit прошли, signed ZIP23 CRC/3target versions/SHA проверены. Build24:74 checks, в том числе callback через1.2с и максимум3ping; device/codesign/install прошли. Живой результат24: снова return-confirmation error (см. верх), fresh callback отсутствует. Before24: archive/20261008-100436-before-voice-appearance-return-24.tar.gz,490файлов, включает23 live failure. Не возвращать23 как готовое исправление.

Before21: archive/20261008-045841-before-voice-return-prototypes.tar.gz. Before22: archive/20261008-094150-before-voice-host-diagnostics-22.tar.gz(475файлов). Before23: archive/20261008-095706-before-voice-field-return-23.tar.gz(479файлов), включает22 source и live failure metadata. Все manifest/SHA проверены. Итоговые source/signed ZIP/evidence — archive/LATEST.md. Крупные модели/runtime сохранены отдельно, см.BACKUP.md; build/local-voice не удалять.

Диагностических AI-запросов, чтения личных ключей и инструментальных аудиозаписей0. Реальное включение mic выше произошло по явному нажатию пользователя.

## Проверки и сохранение build25

87VoiceReturn checks прошли: fresh async host/delay/cancel/stale, routes/replay/deadlines, ownership, preview-only конфликт/timeout, защита старого owner.6свежих UIKit reports25 прошли; device/Simulator builds/codesign/install подтверждены. UIKit reports проверяют общие startup/mechanics/design/connection/card cases, не доказывают реальную mic-вставку. Foundation162/Core14 и Mac90 также прошли. User phrases/audio в AI для отладки не отправлялись, ключи не читались.

Before25: archive/20261008-101149-before-voice-manual-delivery-25.tar.gz. Signed ZIP: archive/releases/easytalk-ios-0.5.0-build25-personal.zip, CRC/три версии/SHA256 проверены. Итоговые исходники/evidence: archive/LATEST.md. Прежние23/24ZIP и checkpoints сохранены.
