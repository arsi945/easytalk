import UIKit

/// Native paging follows the finger and resolves distance/velocity with UIScrollView.
/// Vertical content inside a page remains independently scrollable.
final class StudyPagingView: UIScrollView, UIScrollViewDelegate {
    private let pages = UIStackView()
    private var pendingIndex: Int?
    var onPage: ((Int) -> Void)?
    private(set) var pageCount = 0
    var moving: Bool { isDragging || isDecelerating }
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; isPagingEnabled = true; isDirectionalLockEnabled = true
        decelerationRate = .fast; showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        alwaysBounceVertical = false; alwaysBounceHorizontal = false
        contentInsetAdjustmentBehavior = .never
        pages.axis = .horizontal; pages.spacing = 0; pages.translatesAutoresizingMaskIntoConstraints = false; addSubview(pages)
        NSLayoutConstraint.activate([
            pages.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            pages.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            pages.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            pages.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            pages.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ views: [UIView], index: Int) {
        guard !moving else { return }
        pages.arrangedSubviews.forEach { pages.removeArrangedSubview($0); $0.removeFromSuperview() }
        pageCount = views.count
        for view in views { pages.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor).isActive = true }
        pendingIndex = max(0, min(index, pageCount - 1)); setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let index = pendingIndex, bounds.width > 0 { pendingIndex = nil; setContentOffset(CGPoint(x: CGFloat(index) * bounds.width, y: 0), animated: false) }
    }
    func navigate(to index: Int, animated: Bool) {
        layoutIfNeeded()
        guard (0..<pageCount).contains(index), bounds.width > 0 else { return }
        setContentOffset(CGPoint(x: CGFloat(index) * bounds.width, y: 0), animated: animated)
        if !animated { settled() }
    }
    private func settled() {
        guard bounds.width > 0 else { return }
        onPage?(max(0, min(Int((contentOffset.x / bounds.width).rounded()), pageCount - 1)))
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settled() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { settled() } }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settled() }
}
