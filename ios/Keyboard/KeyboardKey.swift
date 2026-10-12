import UIKit

/// Letters activate on touch-down, including touches routed from visual gaps.
/// Space reserves a held touch for cursor movement; delete repeats while held.
final class KeyboardKey: UIControl {
    enum Behavior { case tap, space, delete, alternate }
    let caption = UILabel()
    private let icon = UIImageView()
    private let preview = UILabel()
    var behavior: Behavior = .tap { didSet { updateAlternateAction() } }
    /// Click sound and haptic on every press; set once by the keyboard controller.
    static var feedback: (() -> Void)?
    var activate: (() -> Void)?
    /// Held delete switches to whole words after a short run of single characters.
    var accelerated: (() -> Void)?
    var cursorMode: ((Bool) -> Void)?
    var cursorMove: ((Int, Int) -> Void)?
    var alternateTitle: String? { didSet { updateAlternateAction() } }
    var alternateActivate: (() -> Void)?
    private let alternateBubble = UIView(), baseOption = UILabel(), alternateOption = UILabel()
    private var choosingAlternate = false, alternateSelected = true, trackpadAppearance = false
    private var alternateCancelled = false
    private var hold: Timer?, repeatTimer: Timer?, repeats = 0
    private var trackingPress = false, dragging = false
    private var lastPoint = CGPoint.zero
    private var cursorMotion = SpaceCursorMotion()
    var title: String = "" { didSet { caption.text = title; accessibilityLabel = title } }
    var symbol: String? {
        didSet { icon.image = symbol.flatMap { UIImage(systemName: $0) }; icon.isHidden = symbol == nil; caption.isHidden = symbol != nil }
    }
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted || trackpadAppearance ? EasyTalkTheme.muted : EasyTalkTheme.paper
            caption.transform = isHighlighted ? CGAffineTransform(translationX: 0, y: -1) : .identity
            preview.isHidden = !isHighlighted || symbol != nil || title.count != 1 || behavior != .tap
            preview.text = title
            layer.zPosition = isHighlighted ? 20 : 0
            superview?.layer.zPosition = isHighlighted ? 20 : 0
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPreview()
        layoutAlternate()
    }
    private func layoutPreview() {
        var x = (bounds.width - 52) / 2
        if let window {
            let point = convert(CGPoint(x: x, y: 0), to: window)
            x += max(4 - point.x, 0) - max(point.x + 52 - window.bounds.maxX + 4, 0)
        }
        preview.frame = CGRect(x: x, y: -54, width: 52, height: 58)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = EasyTalkTheme.paper; layer.cornerRadius = 9
        isAccessibilityElement = true; accessibilityTraits = .keyboardKey
        caption.font = .systemFont(ofSize: 25); caption.textColor = EasyTalkTheme.ink; caption.textAlignment = .center
        caption.isUserInteractionEnabled = false; icon.isUserInteractionEnabled = false
        icon.tintColor = EasyTalkTheme.ink; icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        for v in [caption, icon] {
            v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v)
            NSLayoutConstraint.activate([v.centerXAnchor.constraint(equalTo: centerXAnchor), v.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        preview.font = .systemFont(ofSize: 32); preview.textColor = EasyTalkTheme.ink
        preview.textAlignment = .center; preview.backgroundColor = EasyTalkTheme.paper
        preview.layer.cornerRadius = 12; preview.layer.borderWidth = 0.5
        preview.layer.borderColor = EasyTalkTheme.ink.withAlphaComponent(0.16).cgColor
        preview.layer.shadowOpacity = 0.12; preview.layer.shadowRadius = 4
        preview.layer.shadowOffset = CGSize(width: 0, height: 2)
        preview.isHidden = true; preview.isUserInteractionEnabled = false
        preview.isAccessibilityElement = false; addSubview(preview)
        alternateBubble.backgroundColor = EasyTalkTheme.paper; alternateBubble.layer.cornerRadius = 12
        alternateBubble.layer.borderWidth = 0.5; alternateBubble.layer.borderColor = EasyTalkTheme.border.cgColor
        alternateBubble.layer.shadowOpacity = 0.15; alternateBubble.layer.shadowRadius = 4
        alternateBubble.isUserInteractionEnabled = false; alternateBubble.isHidden = true
        alternateBubble.accessibilityIdentifier = "hard-sign-options"
        for option in [baseOption, alternateOption] {
            option.font = .systemFont(ofSize: 27); option.textColor = EasyTalkTheme.ink; option.textAlignment = .center
            option.layer.cornerRadius = 9; option.clipsToBounds = true; alternateBubble.addSubview(option)
        }
        addSubview(alternateBubble)
        symbol = nil
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityActivate() -> Bool { activate?(); return true }
    private func updateAlternateAction() {
        accessibilityCustomActions = behavior == .alternate ? [UIAccessibilityCustomAction(name: "Ввести " + (alternateTitle ?? ""), target: self, selector: #selector(activateAlternate))] : nil
    }
    @objc private func activateAlternate() -> Bool { guard behavior == .alternate else { return false }; alternateActivate?(); return true }
    func setTrackpadAppearance(_ active: Bool) {
        trackpadAppearance = active; caption.alpha = active ? 0 : 1; icon.alpha = active ? 0 : 1
        backgroundColor = active || isHighlighted ? EasyTalkTheme.muted : EasyTalkTheme.paper
    }
    private func layoutAlternate() {
        var x = (bounds.width - 104) / 2
        if let window {
            let origin = convert(CGPoint(x: x, y: 0), to: window)
            x += max(4 - origin.x, 0) - max(origin.x + 104 - window.bounds.maxX + 4, 0)
        }
        alternateBubble.frame = CGRect(x: x, y: -62, width: 104, height: 58)
        baseOption.frame = CGRect(x: 4, y: 4, width: 46, height: 50)
        alternateOption.frame = CGRect(x: 54, y: 4, width: 46, height: 50)
        baseOption.text = title; alternateOption.text = alternateTitle
        baseOption.backgroundColor = alternateSelected ? .clear : EasyTalkTheme.muted
        alternateOption.backgroundColor = alternateSelected ? EasyTalkTheme.muted : .clear
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { press(at: touch.location(in: self)); return true }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { move(to: touch.location(in: self)); return true }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { release() }
    override func cancelTracking(with event: UIEvent?) { release(cancelled: true) }
    func press(at point: CGPoint) {
        release(cancelled: true); layoutPreview(); trackingPress = true; isHighlighted = true; lastPoint = point; cursorMotion.reset()
        Self.feedback?()
        if behavior == .tap || behavior == .delete { activate?() }
        if behavior == .space || behavior == .delete || behavior == .alternate {
            let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in self?.held() }
            hold = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    func held() {
        guard trackingPress else { return }
        hold?.invalidate(); hold = nil
        if behavior == .space {
            dragging = true; cursorMotion.reset(); cursorMode?(true)
            UISelectionFeedbackGenerator().selectionChanged()
        } else if behavior == .alternate {
            choosingAlternate = true; alternateSelected = true; alternateCancelled = false
            layoutAlternate(); alternateBubble.isHidden = false
            UISelectionFeedbackGenerator().selectionChanged()
        } else if behavior == .delete {
            repeats = 0
            let timer = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.repeats += 1
                // After ~1 s of characters, one word every other tick.
                if self.repeats > 12, let accelerated = self.accelerated { if self.repeats % 2 == 0 { accelerated() } } else { self.activate?() }
            }
            repeatTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    func move(to point: CGPoint) {
        guard trackingPress else { return }
        if dragging {
            let move = cursorMotion.move(dx: Double(point.x - lastPoint.x), dy: Double(point.y - lastPoint.y))
            if move.columns != 0 || move.rows != 0 { cursorMove?(move.columns, move.rows) }
        } else if choosingAlternate {
            alternateCancelled = point.y > bounds.maxY + 35
            if point.x < bounds.midX - 12 { alternateSelected = false }
            else if point.x > bounds.midX + 12 { alternateSelected = true }
            layoutAlternate(); alternateBubble.alpha = alternateCancelled ? 0.4 : 1
        }
        lastPoint = point
    }
    func release(cancelled: Bool = false) {
        hold?.invalidate(); repeatTimer?.invalidate(); hold = nil; repeatTimer = nil
        let wasTracking = trackingPress, wasDragging = dragging, usedAlternate = choosingAlternate && alternateSelected
        let cancelledAlternate = alternateCancelled
        trackingPress = false; dragging = false; choosingAlternate = false; alternateCancelled = false
        alternateBubble.isHidden = true; alternateBubble.alpha = 1; isHighlighted = false
        // Callbacks can render or rebuild keys. End the touch first to make
        // cancellation/release idempotent even when that rendering re-enters us.
        if wasDragging { cursorMode?(false) }
        if wasTracking && behavior == .space && !wasDragging && !cancelled { activate?() }
        if wasTracking && behavior == .alternate && !cancelled && !cancelledAlternate {
            if usedAlternate { alternateActivate?() } else { activate?() }
        }
    }
    deinit { hold?.invalidate(); repeatTimer?.invalidate() }
}

/// Fill visual gaps with the nearest key's touch area, without changing key widths.
final class KeyboardKeyArea: UIStackView {
    private var cursorTracking = false
    func setCursorTracking(_ active: Bool, owner: KeyboardKey?) {
        cursorTracking = active
        subviews.flatMap { allKeys(in: $0) }.filter { $0 !== owner }.forEach { $0.setTrackpadAppearance(active) }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, !cursorTracking, alpha > 0.01, bounds.contains(point) else { return nil }
        let candidates = subviews.flatMap { allKeys(in: $0) }.filter { !$0.isHidden && $0.isEnabled }
        return candidates.min { distance(to: $0, point: point) < distance(to: $1, point: point) }
    }
    private func allKeys(in view: UIView) -> [KeyboardKey] {
        if let key = view as? KeyboardKey { return [key] }
        return view.subviews.flatMap { allKeys(in: $0) }
    }
    private func distance(to key: UIView, point: CGPoint) -> CGFloat {
        let rect = key.convert(key.bounds, to: self)
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
    func stopTouches() { subviews.flatMap { allKeys(in: $0) }.forEach { $0.release(cancelled: true) } }
}
