# Облачная сборка (GitHub Actions)

Репозиторий: приватный `arsi945/easytalk`. Mac для сборки не нужен: всё выполняется на macOS-раннерах GitHub (`macos-26`, Xcode 26.x). Apple принимает в App Store Connect только сборки с iOS 26 SDK (Xcode 26+), поэтому `macos-15` / Xcode 16 для TestFlight больше не подходят.

## 1. CI — автоматически на каждый push в `main` и на каждый PR

Файл `.github/workflows/ci.yml`. Секреты не нужны, живой AI не вызывается.

| Задача | Что проверяет |
|---|---|
| Core / iOS logic tests | `scripts/generate_idioms.py --check`, совпадение Xcode-проекта и промптов с генератором, `scripts/test_ios_core.sh` |
| macOS app build + QA | `scripts/build.sh all`, `build/selftest`, `--desktop-check` (скриншоты QA — в artifacts прогона) |
| iOS build ×2 | `xcodebuild build` для симулятора и для устройства, без подписи |

Посмотреть: вкладка **Actions** в репозитории или `gh run list` / `gh run view`.

Если CI пишет «run python3 ios/generate_project.py»: после изменения промпта, идиом или генератора запустите генератор (на Windows теперь тоже работает) и закоммитьте результат.

## 2. TestFlight — вручную, нужна платная подписка Apple Developer

Файл `.github/workflows/testflight.yml`. Подпись автоматическая (cloud-managed) через ключ App Store Connect API. Сертификаты `.p12` и профили вручную создавать не нужно.

### Разовая подготовка (делает автор, ключи Claude не передаются)

1. **Apple Developer Program** ($99/год). Team ID — в developer.apple.com → Membership.
2. **Ключ API.** App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → «+», роль **Admin** (нужна для облачных сертификатов и профилей). Скачайте `.p8` (скачивается один раз), запишите Key ID и Issuer ID.
3. **iPhone в списке устройств.** developer.apple.com → Devices → «+». Подпись Release-архива использует development-профиль, а для него нужно хотя бы одно устройство. UDID iPhone показывает Finder на Mac или приложение Apple Devices на Windows.
4. **Секреты GitHub:** Settings → Secrets and variables → Actions → New repository secret:
   - `APPLE_TEAM_ID` — Team ID;
   - `ASC_KEY_ID` — Key ID;
   - `ASC_ISSUER_ID` — Issuer ID;
   - `ASC_PRIVATE_KEY` — всё содержимое `.p8`, включая строки `BEGIN/END PRIVATE KEY`.

   То же из терминала (выполнять самому):
   ```bash
   gh secret set ASC_PRIVATE_KEY --repo arsi945/easytalk < AuthKey_XXXXXXXXXX.p8
   ```
5. **Пробный прогон без загрузки:** Actions → TestFlight → Run workflow → снять галочку «Загрузить». Xcode сам зарегистрирует bundle IDs и создаст профили.
   - Приложение и клавиатура используют App Group `group.com.easytalk.personal` (общие данные и ключ). Автоматическая подпись должна зарегистрировать его сама. Если сборка падает с ошибкой про App Groups, создайте группу вручную: developer.apple.com → Identifiers → App Groups → «+», затем включите App Groups у обоих App ID.
   - Если Apple отвечает, что идентификатор `com.easytalk.personal` недоступен (занят прежней Personal Team), задайте переменную репозитория `BUNDLE_ID_PREFIX`, например `com.arsi945.easytalk`: Settings → Secrets and variables → Actions → Variables. Префикс меняется только в копии на раннере, для app и обоих extensions одинаково.
6. **Запись приложения в App Store Connect:** My Apps → «+» → New App. Платформа iOS, bundle ID из списка, имя должно быть уникальным в App Store (например, «easytalk personal»). Без этой записи загрузка не пройдёт.
7. **Загрузка:** Run workflow с включённой галочкой. Номер сборки = 26 + номер запуска workflow, растёт автоматически. Через 5–30 минут сборка появится в App Store Connect → TestFlight. Добавьте себя во внутреннюю группу тестировщиков и установите через приложение TestFlight на iPhone.

### Что важно знать

- **Сертификат разработчика** для архива создаётся один раз и хранится в кэше GitHub Actions (зашифрован паролем, производным от ключа App Store Connect). Раньше каждая сборка на чистой машине создавала новый сертификат, и аккаунт упёрся в лимит («Your account has reached the maximum number of certificates»). Если это снова случится: developer.apple.com → Certificates → отозвать старые «Apple Development» и запустить сборку.

- **Внутренние сборки TestFlight** не проходят ревью Apple, но живут 90 дней.
- **Смена команды подписи.** Если сменится bundle ID, на телефоне появится второе, отдельное приложение: словарь и уроки прежнего не перенесутся, ключ API нужно ввести заново. Если bundle ID останется прежним, а команда новая, контейнер данных обычно сохраняется. Но Keychain привязан к Team ID, поэтому ключ API, скорее всего, придётся ввести снова. Перед переходом стоит выписать нужные слова из словаря.
- **Логи и `.ipa`** каждого прогона сохраняются в artifacts на 14 дней.
- **Первый прогон TestFlight может упасть** на шаге подписи. Это нормально для первой настройки: смотрите `archive.log` / `export.log` в artifacts и исправляйте по сообщению. Workflow ещё ни разу не запускался с настоящими ключами.
