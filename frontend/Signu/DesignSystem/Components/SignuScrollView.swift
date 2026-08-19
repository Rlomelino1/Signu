import SwiftUI

@Observable
final class TabBarState {
    private(set) var hidden = false

    @ObservationIgnored private var lastOffset: CGFloat = 0
    @ObservationIgnored private var synced = false

    func reset() {
        hidden = false
        synced = false
    }

    func update(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let maxOffset = contentHeight - viewportHeight
        defer { lastOffset = offset }

        guard maxOffset > 24 else {
            hidden = false
            return
        }
        guard synced else {
            synced = true
            return
        }
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

            let report: @MainActor () -> Void = { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                let insets = scroll.adjustedContentInset
                self.onChange(
                    scroll.contentOffset.y + insets.top,
                    scroll.contentSize.height + insets.top + insets.bottom,
                    scroll.bounds.height
                )
            }
            observations = [
                scroll.observe(\.contentOffset, options: [.initial]) { _, _ in
                    MainActor.assumeIsolated { report() }
                },
                scroll.observe(\.contentSize) { _, _ in
                    MainActor.assumeIsolated { report() }
                },
            ]
        }
    }
}
