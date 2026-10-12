# Архивы и восстановление

```sh
bash scripts/archive.sh checkpoint-name
```

`archive_project.py` создаёт `archive/YYYYMMDD-HHMMSS-метка.tar.gz`, отдельный SHA256 и внутренний `ARCHIVE_MANIFEST.json` с контрольными суммами файлов. После создания читает архив обратно и сверяет каждый обычный файл. Время — Europe/Kiev. Исходное дерево не меняется; архив имеет права 0600.

Сохраняются код, документация, источники данных и доказательства в docs/evidence. Исключены archive/, build/, .build/, node_modules/, .git/, __pycache__, .codex/, .agents/, xcuserdata, .env*, приватные сертификаты и профили подписи. Symlink сохраняется как ссылка, содержимое цели не обходится. Скрипт не читает Keychain и пользовательские Application Support/Preferences. Произвольные секреты, вручную вписанные в обычный исходник, нельзя надёжно распознать: ключи туда не помещать.

Архив `ios-034-checkpoint` — исходное состояние перед текущим этапом; `desktop-020-idioms-60` — следующий исходный снимок с Mac. Сборка приложения Mac хранится отдельным ZIP; она не заменяет архив исходников. Исходные архивы 0.3.4 не удалять.

Проверка SHA256: `shasum -a 256 -c имя.tar.gz.sha256` из archive/. Восстанавливать в новый каталог, затем читать docs/HANDOFF.md и выполнять команды проверок. Не распаковывать поверх рабочего проекта автоматически. Xcode signing/Keychain нужно настроить на новом компьютере отдельно.

Личные слова/уроки хранятся в контейнерах приложений и не входят в архив исходников. На Mac есть экспорт словаря JSON по явному действию; общего экспорта всего прогресса/синхронизации пока нет. Не удалять приложение/его контейнер ради обновления: обычная установка поверх сохраняет данные.

Текущий этап: исходный checkpoint `20261006-080134-before-study-036.tar.gz`, итоговый `*-ios-036-study-macos-021.tar.gz`. Mac 0.2.1 — `archive/releases/easytalk-macos-0.2.1-intel.zip`. Установлена iOS 0.3.6 поверх программы; личные контейнеры не удалялись.

## Локальная речь, 8 октября 2026

`archive/local-voice` отдельно сохраняет pinned ONNX-модель, словарь CMUdict/лицензию, оригинальный официальный ONNX Runtime iOS ZIP, исходный SPM package 1.19.2 без .git и 13 wheels Python 3.12/macOS Intel. `SHA256SUMS.json` — путь, размер, хеш каждого файла. Это нужно копировать вместе с исходным архивом: build/cache в snapshot не входят.

Восстановить модель без сети: скопировать `archive/local-voice/model` в `build/local-voice/model`. Python 3.12 → создать venv по LOCAL_VOICE.md → pip install `--no-index --find-links archive/local-voice/wheels-macos-intel -r local_voice/requirements-lock-macos-intel.txt`. Mac prototype по-прежнему использует эти пути; его ZIP отдельно от дерева не является автономным установщиком.

SPM source tarball — официальный upstream 1.19.2 / commit bbc428e168a0374eb7d0503cdb7c73fdc1d99751. Framework ZIP проверяется SHA 28787ee2f966a2c47eb293322c733c5dc4b5e3327cec321c1fe31a7c698edf68; восстановление в SwiftPM artifact cache допустимо после проверки; generated project/package resolution сохраняет upstream exact 1.19.2. На новой машине Xcode может потребовать сеть для собственного package-resolution даже при наличии архивов; альтернатива — локальная package reference в копии проекта. Не менять рабочую Personal Team автоматически.

Signed iPhone ZIP сохраняет приложение/extension/модель, без контейнеров/Keychain. Подпись Personal Team ограничена по сроку; для повторной установки понадобится обычная переподпись собственным аккаунтом. Архив никогда не заменяет личный словарь/ключи на устройстве.
