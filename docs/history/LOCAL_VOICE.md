# Локальный голос · прототип 0.5.0 / Mac 0.4.0

8 октября 2026. Автор выбрал **локальный анализатор**, а не облачный сервис оценки. Это заменяет прежнюю рекомендацию Azure в исследовании VOICE.md. Облачных голосовых подключений нет. Пользовательский голос/фразы и ключи при разработке не использовались; аудио тестов синтезировано системным голосом Samantha.

## Что реализовано

- Кнопка mic/stop в собственной iOS-клавиатуре. Build 15: live partial над буквами, окончание по паузе, ■ — досрочный stop. Основное приложение владеет аудио, расширение передаёт команды start/stop/cancel/poll и вставляет текст. Распознавание Apple Speech требует `requiresOnDeviceRecognition = true`: облачного fallback нет. Английский; наличие нужных системных речевых ресурсов проверяется отдельно на устройстве.
- Сессия подготавливается явной кнопкой в приложении на 5 минут. Пока она активна, горит системный индикатор микрофона; между диктовками буферы отбрасываются. Диктовка заканчивается сама после паузы трёх секунд, когда уже есть распознанный текст. Появление нового текста/звука продлевает фразу; RMS-порог 0,008 — простой quiet-pause gate, не обученный VAD, шум ещё нужно проверить. Лимит записи 45 секунд; после stop финал ждём до 1,2 секунды при имеющемся partial, иначе до 8 секунд; выключение/таймаут/прерывание останавливают engine. Автозапуска из выгруженного приложения нет.
- Локальная акустическая модель: запись известной английской фразы → фонемы из аудио → сопоставление с вариантами CMUdict → возможные расхождения по словам. На iPhone — основное приложение → «Произношение · локальная лаборатория»; на Mac — mic в верхней панели. Запись до 12 секунд. Модель не грузится в keyboard extension.
- Ни процент совпавшего текста, ни ASR confidence не объявляются оценкой произношения. В v1 нет балла /100, оценки ударения/интонации и проверенной статистики качества. Grammar/translation по-прежнему используют существующий текстовый AI API и требуют интернета. Локальная проверка звуков — отдельная функция.

## Выбор основы и источники

| Основа | Решение |
|---|---|
| [GOPT, авторский проект](https://github.com/YuanGongND/gopt) | GOP-признаки + оценщик; для своих WAV нужны акустическая модель, выравнивание и feature extraction. Не готовый мобильный тракт. Сохранён как направление для калиброванной оценки. |
| [OpenPronounce](https://github.com/Halleck45/OpenPronounce) | Полезный открытый пример фонемного сравнения, но два больших Wav2Vec2 checkpoint; default gTTS требует сеть. Не импортирован. |
| [nrshoudi/speech_ocean_wav2vec_mdd](https://huggingface.co/nrshoudi/speech_ocean_wav2vec_mdd) + [Buddy ONNX export](https://huggingface.co/asingingbird/buddy-pronunciation-onnx) | Выбран для первого запуска: готовый CPU int8 MatMul export английского CTC. Apache-2.0. Размер 357382272 байта. Это фонемный распознаватель, не обученный нами оценщик. |
| [Whisper phoneme CTC](https://huggingface.co/vb223/whisper-base-en-phoneme-ctc) | Перспективный более маленький кандидат со специализированным GOP-регрессором. Прочитан исходник/requirements; пока не запускался и не переносился. |
| [Microsoft ONNX Runtime](https://onnxruntime.ai/docs/get-started/with-obj-c.html) | Официальный Swift/Objective-C пакет 1.19.2, exact pin. CPU, два потока на iPhone, четыре на Mac. Нейронный ускоритель пока не включён. |
| [CMU Pronouncing Dictionary](https://github.com/cmusphinx/cmudict) | Несколько произношений слова; shortest path по альтернативам, вместо безусловного выбора первой записи. Офлайн-словарь из cmudict 1.1.1, BSD notice сохранён. |

Веса закреплены revision `bbc37113ff91fdda6b2b1a79f44fbb78bdc4c588`, SHA256 `616794bd723a99e00ed9d1ce5360e7fad9bf66a539ff2d843d4a58c0e5125e70`. Manifest: `local_voice/model_manifest.json`. Перед загрузкой проверяется checksum. Никакого выполнения удалённого Python-кода/torch pickle нет.

**Обнаруженные несовпадения сторонней документации:** vocab содержит 125 именованных ID, фактический output `logits` имеет **127 каналов**. CTC PAD — **124**, пробел — 0. Ширина берётся из тензора; неизвестные ID становятся «?», не теряются. Сначала на iPhone проверка не прошла именно из-за предположения 125; исправление защищено отдельными Swift/Python tests. Начальный неуспех сохранён в evidence/ios050/voice-model-check-before-shape-fix.json.

## Голосовой мост без App Groups

Подпись Personal Team, bundle IDs и Keychain прежние. NWListener слушает только **127.0.0.1:49723**, не LAN. Одно JSON-сообщение с newline на TCP-соединение, размер/время/число соединений ограничены. Случайный 256-bit session ticket на 5 минут передаётся через local-only typed pasteboard по явному нажатию «Подготовить микрофон». Это занимает буфер обмена; интерфейс предупреждает. Клавиатура забирает ticket по mic-tap, очищает только совпавшее служебное содержимое и временно кеширует ticket в своих defaults. API-ключ в этом протоколе отсутствует.

Request UUID + обе стороны курсора + выделение + document UUID охраняют доставку. Build17 исправляет пустое поле: UIKit вправе вернуть nil с обеих сторон, это не отсутствие поля. Нужен known document UUID; счётчик revision ловит text/selection callbacks при скрытом контексте, такой ответ требует явной вставки. Не требовать от пользователя сначала набрать букву ради диктовки. Повторный ответ не вставляется дважды. Изменённое поле не получает автоматическую вставку: остаётся явное «Вставить диктовку» после проверки места. Исчезновение клавиатуры/отмена отправляют cancel. Сервер помнит ID завершённых запросов до конца сессии, поздний start не оживляет отменённую диктовку. Не обещать exactly-once после аварийного завершения процесса в середине insert; постоянной очереди диктовок пока нет.

Build 15 добавляет bounded metadata diagnostic в `Documents/voice-diagnostic.json` отдельно у app/extension: фазы, счётчики frames/callbacks, наличие текста bool, код/allowlisted domain ошибки. Никаких audio/transcript/token/host text/keys в файле. Directory создаётся и в PluginKit container; preflight tap/full-access/session-ticket/document guard отмечаются до запуска, не только успешный start. Poll не пересекаются, старый recording reply не возвращает UI из processing; общий предел ожидания 60 секунд.

Мост протестирован двумя локальными компонентами на Mac. **Сам факт установки и локального акустического анализа на iPhone не подтверждает живую диктовку из Telegram/Notes в фоне**: нужны разрешения, реальная речь, переход в host, stop/cancel, airplane mode и звонок. Холодный старт не реализован; пользователь не переключает клавиатуру, но один раз подготавливает сессию в easytalk. App Store-допустимость постоянной готовности микрофона/IPC отдельно проверить; приложение не запускается из extension приватными API.

## Воспроизведение разработчиком

Python 3.12 на этом Intel Mac: `~/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`.

```sh
python3.12 -m venv build/local-voice/venv
build/local-voice/venv/bin/python -m pip install -r local_voice/requirements-lock-macos-intel.txt
build/local-voice/venv/bin/python local_voice/setup_model.py
python3 ios/generate_project.py
```

Setup — отдельное явное скачивание pinned весов, проверка SHA и экспорт CMUdict. Analyzer ничего не скачивает. Повторная установка Python без сети возможна через `--no-index --find-links archive/local-voice/wheels-macos-intel`. Эти wheels для macOS Intel/Python 3.12; для Windows/Android/iOS Python runtime не копировать.

```sh
# WAV mono/16kHz/PCM16; текст через stdin, не в argv/process list.
build/local-voice/venv/bin/python local_voice/analyzer.py --audio sample.wav --reference-stdin
# Введи эталон и EOF. Никакого облачного транспорта.
env DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer bash scripts/test_local_voice.sh
bash scripts/test_ios_core.sh
bash scripts/build.sh all
build/easytalk.app/Contents/MacOS/easytalk --desktop-check build/voice-mac-qa
```

iOS использует официальный SPM `microsoft/onnxruntime-swift-package-manager @ 1.19.2`, commit `bbc428e168a0374eb7d0503cdb7c73fdc1d99751`. ZIP Runtime SHA256 `28787ee2f966a2c47eb293322c733c5dc4b5e3327cec321c1fe31a7c698edf68`. Однажды SwiftPM оставил только Headers/LICENSE без framework: проверенный официальный ZIP восстановлен через `ditto -x -k`, исходный пакет не менялся. Кеш — build/ios-voice-packages, сохранённый ZIP — archive/local-voice. Не менять системный CLT/xcode-select.

Mac prototype использует Python/model из `build/local-voice`; runtime.json с локальными путями создаётся сборкой в .app. Это пока **не автономный дистрибутив Mac**. iPhone получает веса/лексикон внутрь .app и не зависит от Mac или Python во время анализа.

## Проверка качества и дальнейшая работа

Синтетическая чистая фраза и намеренно заменённое слово проверяют работоспособность, а не точность на человеческом акценте. Уже есть спорное замечание к редуцированной гласной в `visit` на системном голосе. Веса мы не обучали, human-rated corpus ещё не оценивался. Следующее: Speechocean test с независимыми оценками, false positives по словам, взрослые русскоязычные голоса с разрешением, слабые гласные/допустимые акценты, шум; после этого калибровать GOP/оценщик. Не «улучшать балл» под две синтетические записи.

Для телефона измерить память/батарею на 3/6/12 секунд, прерывания, отмену и выгрузку; затем компактная модель/quantization/CoreML. Словарь и фраза карточки могут стать эталоном следующего UX-этапа. Свободную диктовку нельзя оценивать относительно грамматически изменённого текста, который человек не произносил.

Основные файлы: `Sources/EasyTalkCore/VoiceDelivery.swift`, `PronunciationAlignment.swift`, `ios/Shared/VoiceBridge.swift`, `ios/EasyTalk/VoiceRecorder.swift`, `VoiceBridgeServer.swift`, `LocalAcousticModel.swift`, `LocalPronunciationController.swift`, `Sources/EasyTalk/LocalPronunciation.swift`, `local_voice/*`. Evidence: `docs/evidence/local-voice`, `ios050`, `macos040`. Архивы и точные проверки — `archive/LATEST.md`, `HANDOFF.md`.

## Проверка Apple Speech · build 17

Отдельный DEBUG `--voice-speech-check` читает только синтетический Documents/voice-test.wav, не включает микрофон, не читает AI connection/Keychain. `voice-speech-check.json` содержит count/flags/errors, не текст. На реальном iPhone английские6 слов совпали с эталоном, on-device=true,0.495 с. Это проверка Apple ASR, отдельно от ONNX фонемной модели и реальной диктовки. `--delayed-speech-check` начинает через 8 с с коротким UIKit background task для контролируемого фонового теста; обычный пользовательский сеанс использует аудио, не этот debug grant.

### Ручная проверка build 17

Пользователь подтвердил, что текст появился. Безопасные metadata `voice-diagnostic-passed-app.json` / `...-keyboard.json`: start→partial→pause-detected→stop-audio→result→insert. App background=false на этом запуске; место ввода ещё уточняется, не называть это фоновым микрофонным тестом. Предыдущий отказ был до Speech: guard отвергал nil/nil пустого поля; исправление tested отдельно от ASR. Фоновый synthetic-file check с UIKit grant прошёл за 1.087 с,6 слов,exact reference=true; он не заменяет проверку AVAudioEngine+extension в чужом host.

### Build18: 3 секунды и явное выключение

Автор попросил паузу ровно3секунды. VoiceEndpoint.pause=3; новая речь/partial продлевает фразу, ■ завершает сразу. В Notes пользователь получил unavailable, app trace показал disable в foreground до перехода к host, start в сервер не пришёл. Это не доказанная ошибка background Speech. Главная кнопка больше не toggle: повторная подготовка обновляет expiry300s существующего ticket/listener и копирует ticket; отдельная пунктирная ссылка «Выключить микрофон». Причины disable теперь типизированы (manual/preparation/expired/interruption/pronunciation/failure), переход/background-ready отмечаются без текста.


### Build 20: ручная подготовка отменена

Автор отверг timed prep и переход в app. Эксперимент фонового AudioRecordingIntent / LiveActivityIntent установлен; последующая проверка в Notes на iOS27 завершилась отказом: действие выполнилось внутри keyboard, запись не началась. Нового установленного исправления нет. Compile/подпись/6 свежих UIKit и 5 ticket + 12 bounded launch tests прошли. Нет внешних AI-запросов. Подробности и источники — VOICE.md. Не возвращать исторический prepare flow в UX.
