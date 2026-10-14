import UIKit

/// «Как пользоваться»: adding the keyboard and its main gestures, in short cards.
final class GuideViewController: UIViewController {
    private let preferences = KeyboardPreferences(defaults: SharedStorage.defaults())
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let message = SettingsUI.label("", size: 15, color: EasyTalkTheme.secondary)

    /// Title and lines of each card, in the order of a first day with the keyboard.
    static let sections: [(String, [String])] = [
        ("Подключить клавиатуру", [
            "1. Настройки iPhone → easytalk → Клавиатуры.",
            "2. Включи easytalk и «Полный доступ»: без него нет перевода, словаря и истории.",
            "3. В любом поле зажми 🌐 и выбери easytalk.",
        ]),
        ("Перевести", [
            "Пиши по-английски, как получается. Незнакомые слова можно вставлять по-русски: I want to купить coffee.",
            "«Перевести» заменит всё сообщение переводом и откроет разбор: как правильно по-английски и почему.",
            "Выдели часть текста — переведётся только она. Абзац или предложение вместо сообщения — в настройках.",
            "Нужен ключ AI: Настройки → Перевод через AI.",
        ]),
        ("Словарь", [
            "В разборе «В словарь →» сохраняет слово из правки.",
            "Выдели слово или фразу в тексте — на панели появится «В словарь».",
            "Без ключа AI слово сохранится без перевода: его переведёт любой ИИ через «Скопировать контекст».",
            "В «Игре»: тап — переворот карточки, свайп — следующая. «Запомнил» переносит слово в выученные.",
        ]),
        ("Разбор в любом ИИ", [
            "📋 на клавиатуре или «История и контекст» в приложении копирует твои сообщения за период с готовым заданием.",
            "Вставь в ChatGPT, Claude или другой чат — он найдёт повторяющиеся ошибки.",
            "Скопируй ответ целиком и нажми «Вставить слова» — новые слова попадут в словарь.",
        ]),
        ("Набор", [
            "Удерживай пробел и веди палец — курсор двигается по тексту, в том числе вверх и вниз.",
            "Удерживай «ь» — будет «ъ», удерживай «е» — «ё».",
            "Двойной пробел ставит точку. Двойное нажатие ⇧ — Caps Lock.",
            "Подсказки слов над клавишами включаются в настройках; без автозамены.",
        ]),
        ("Диктовка", [
            "Нажми системный 🎙 внизу клавиатуры: iOS вставит слова прямо в поле.",
        ]),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Как пользоваться"
        view.backgroundColor = EasyTalkTheme.canvas
        SettingsUI.layout(scroll, stack, in: view)
        for (index, section) in Self.sections.enumerated() {
            let card = SettingsUI.card()
            let header = SettingsUI.label(section.0, size: 20, weight: .semibold)
            header.accessibilityTraits.insert(.header)
            card.addArrangedSubview(header)
            for line in section.1 { card.addArrangedSubview(SettingsUI.label(line, size: 16)) }
            if index == 0 {
                card.addArrangedSubview(SettingsUI.secondaryButton("Открыть настройки iPhone", self, #selector(openSystemSettings)))
            }
            stack.addArrangedSubview(card)
        }
        stack.addArrangedSubview(SettingsUI.link("Показать советы на клавиатуре снова", self, #selector(showTipsAgain)))
        message.isHidden = true
        stack.addArrangedSubview(message)
    }

    @objc private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    @objc private func showTipsAgain() {
        preferences.resetTips()
        message.text = "Готово: советы начнутся заново при следующем появлении клавиатуры."
        message.isHidden = false
    }
}
