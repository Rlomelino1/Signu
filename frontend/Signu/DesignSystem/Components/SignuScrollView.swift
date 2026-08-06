import SwiftUI

/// Drives the floating tab bar's Safari-style auto-hide (see the tab bar
/// behavior contract in the data-model doc): visible by default, hidden on
/// downward scroll, revealed by any upward scroll or reaching the very
/// bottom. Unscrollable content never hides the bar.
@Observable
final class TabBarState {
    private(set) var hidden = false

    @ObservationIgnored private var lastOffset: CGFloat = 0
    @ObservationIgnored private var synced = false

    /// Call on tab switches — the new screen starts with the bar visible.
    func reset() {
        hidden = false
        synced = false
    }

    func update(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let maxOffset = contentHeight - viewportHeight
        defer { lastOffset = offset }

        // Content too short to scroll: the bar must never be unreachable.
        guard maxOffset > 24 else {
            hidden = false
            return
        }
        // First report after a reset only records the baseline.
        guard synced else {
            synced = true
            return
        }
        // Near the top, or at the very bottom: always reveal.
        if offset <= 8 || offset >= maxOffset - 8 {
            hidden = false
            return
        }
        let delta = offset - lastOffset
        if delta > 2 {
            hidden = true
        } else if delta < -2 {
            hidden = false
        }
    }
}

/// ScrollView for tab screens: reports scroll metrics to the shell's
/// TabBarState when hosted in it; standalone (previews) it's inert.
///
/// Metrics come from KVO on the enclosing UIScrollView — the SwiftUI
/// preference-key pipeline proved unreliable here (verified empirically:
/// preferences from scroll content never re-propagated on scroll).
struct SignuScrollView<Content: View>: View {
    var anchor: UnitPoint = .top
    @ViewBuilder var content: () -> Content

    @Environment(TabBarState.self) private var tabBarState: TabBarState?

    var body: some View {
        ScrollView {
            content()
                .background {
                    ScrollViewObserver { offset, contentHeight, viewportHeight in
                        tabBarState?.update(
                            offset: offset,
                            contentHeight: contentHeight,
                            viewportHeight: viewportHeight
                        )
                    }
                }
        }
        .defaultScrollAnchor(anchor)
    }
}

/// Invisible view that finds its enclosing UIScrollView and observes
/// contentOffset/contentSize. Reports offsets normalized so 0 = top and
/// (contentHeight - viewportHeight) = bottom, insets included.
private struct ScrollViewObserver: UIViewRepresentable {
    let onChange: (CGFloat, CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> ObserverView {
        ObserverView(onChange: onChange)
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: UIView {
        var onChange: (CGFloat, CGFloat, CGFloat) -> Void
        private var observations: [NSKeyValueObservation] = []
        private weak var observedScrollView: UIScrollView?

        init(onChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        private func attachIfNeeded() {
            var candidate = superview
            while candidate != nil, !(candidate is UIScrollView) {
                candidate = candidate?.superview
            }
            guard let scroll = candidate as? UIScrollView, scroll !== observedScrollView else { return }
            observedScrollView = scroll

            let report = { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                let insets = scroll.adjustedContentInset
                self.onChange(
                    scroll.contentOffset.y + insets.top,
                    scroll.contentSize.height + insets.top + insets.bottom,
                    scroll.bounds.height
                )
            }
            observations = [
                scroll.observe(\.contentOffset, options: [.initial]) { _, _ in report() },
                scroll.observe(\.contentSize) { _, _ in report() },
            ]
        }
    }
}
