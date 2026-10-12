import UIKit

enum EasyTalkTheme {
    private static func color(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let canvas = color(0xF5F2E9, 0x1E1D1A)
    static let paper = color(0xFFFEFA, 0x2C2A24)
    static let cream = color(0xFFFBEA, 0x373020)
    static let creamEnd = color(0xFFF5D6, 0x2E291D)
    static let border = color(0xEAD492, 0x6B5831)
    static let ink = color(0x3D2B0A, 0xF9EACA)
    static let secondary = color(0x796032, 0xD2B98A)
    static let gold = color(0xE8AC32, 0xE8AC32)
    static let link = color(0x745113, 0xEED08F)
    static let goldInk = UIColor(red: 0.24, green: 0.17, blue: 0.04, alpha: 1)
    static let blue = UIColor(red: 0.13, green: 0.36, blue: 0.75, alpha: 1)
    static let muted = color(0xEAE5D8, 0x343128)
    static let green = color(0x287248, 0x9FD4AD)
    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
    static func style(_ button: UIButton, primary: Bool = false, blue: Bool = false) {
        button.layer.cornerRadius = 11; button.layer.borderWidth = primary ? 0 : 1
        button.layer.borderColor = border.resolvedColor(with: button.traitCollection).cgColor
        let foreground = blue ? UIColor.white : (primary ? goldInk : ink)
        button.backgroundColor = blue ? self.blue : (primary ? gold : paper)
        button.tintColor = foreground
        for state in [UIControl.State.normal, .highlighted, .selected, .disabled] { button.setTitleColor(foreground, for: state) }
        button.titleLabel?.adjustsFontSizeToFitWidth = true; button.titleLabel?.minimumScaleFactor = 0.85
        button.alpha = 1
    }
}

/// One link appearance for all secondary text actions; the underline follows the caption.
final class TextLinkButton: UIButton {
    private let underline = CAShapeLayer()
    var showsLinkUnderline = false { didSet { setNeedsLayout() } }
    var hasVisibleLinkUnderline: Bool { !underline.isHidden && underline.path != nil }
    override init(frame: CGRect) {
        super.init(frame: frame)
        underline.fillColor = nil; underline.lineWidth = 1; underline.lineDashPattern = [2, 3]
        underline.lineCap = .round; underline.isHidden = true; layer.addSublayer(underline)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard showsLinkUnderline, isEnabled, let titleLabel, !(currentTitle ?? "").isEmpty else { underline.isHidden = true; return }
        let caption = titleLabel.convert(titleLabel.bounds, to: self)
        guard caption.width > 0 else { underline.isHidden = true; return }
        let path = UIBezierPath(); let y = min(bounds.maxY - 2, caption.maxY + 2)
        path.move(to: CGPoint(x: caption.minX, y: y)); path.addLine(to: CGPoint(x: caption.maxX, y: y))
        underline.frame = bounds; underline.path = path.cgPath
        underline.strokeColor = (currentTitleColor).resolvedColor(with: traitCollection).cgColor
        underline.opacity = isHighlighted ? 0.45 : 0.8; underline.isHidden = false
    }
    override var isHighlighted: Bool { didSet { setNeedsLayout() } }
    override var isEnabled: Bool { didSet { setNeedsLayout() } }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) { super.traitCollectionDidChange(previous); setNeedsLayout() }
}

/// A native, adaptable version of the warm Second Skill card, with no web view.
final class WarmCard: UIStackView {
    private let gradient = CAGradientLayer()
    init(padding: CGFloat = 14) {
        super.init(frame: .zero); axis = .vertical; spacing = 9
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        layer.cornerRadius = 18; layer.borderWidth = 1; clipsToBounds = true
        gradient.startPoint = .zero; gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)
        refreshColors()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) { super.traitCollectionDidChange(previous); refreshColors() }
    private func refreshColors() {
        gradient.colors = [EasyTalkTheme.cream.resolvedColor(with: traitCollection).cgColor, EasyTalkTheme.creamEnd.resolvedColor(with: traitCollection).cgColor]
        layer.borderColor = EasyTalkTheme.border.resolvedColor(with: traitCollection).cgColor
    }
}

/// Short bounded animation; never receives touches or changes the host document.
final class CelebrationOverlay: UIView {
    private var generation = 0
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    func play() {
        stop(); let expected = generation; guard !UIAccessibility.isReduceMotionEnabled else { return }
        let colors = [EasyTalkTheme.gold, EasyTalkTheme.blue, UIColor.systemGreen, UIColor.systemOrange]
        for i in 0..<24 {
            let particle = CALayer(); particle.backgroundColor = colors[i % colors.count].cgColor
            particle.cornerRadius = i % 2 == 0 ? 3 : 0
            particle.bounds = CGRect(x: 0, y: 0, width: 5, height: 8)
            let x = bounds.width * CGFloat(i + 1) / 25
            particle.position = CGPoint(x: x, y: 16); particle.opacity = 0
            layer.addSublayer(particle)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = CGPoint(x: bounds.midX, y: 20)
            move.toValue = CGPoint(x: x, y: min(bounds.height - 20, 170 + CGFloat(i % 4) * 20))
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.12, 0.65, 1]
            let turn = CABasicAnimation(keyPath: "transform.rotation"); turn.fromValue = 0; turn.toValue = Double(i % 5 + 1) * .pi
            let group = CAAnimationGroup(); group.animations = [move, fade, turn]; group.duration = 1.25
            group.timingFunction = CAMediaTimingFunction(name: .easeOut); particle.add(group, forKey: "celebration")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in if self?.generation == expected { self?.stop() } }
    }
    func stop() { generation += 1; layer.sublayers?.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() } }
}
