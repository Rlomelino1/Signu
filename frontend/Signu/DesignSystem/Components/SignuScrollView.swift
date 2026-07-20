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

private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
}

private struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue = ScrollMetrics()
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        value = nextValue()
    }
}

/// ScrollView for tab screens: reports scroll metrics to the shell's
/// TabBarState when hosted in it; standalone (previews) it's inert.
struct SignuScrollView<Content: View>: View {
    var anchor: UnitPoint = .top
    @ViewBuilder var content: () -> Content

    @Environment(TabBarState.self) private var tabBarState: TabBarState?

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollMetricsKey.self,
                                value: ScrollMetrics(
                                    offset: -proxy.frame(in: .named("signuScroll")).minY,
                                    contentHeight: proxy.size.height
                                )
                            )
                        }
                    }
            }
            .coordinateSpace(name: "signuScroll")
            .defaultScrollAnchor(anchor)
            .onPreferenceChange(ScrollMetricsKey.self) { metrics in
                tabBarState?.update(
                    offset: metrics.offset,
                    contentHeight: metrics.contentHeight,
                    viewportHeight: viewport.size.height
                )
            }
        }
    }
}
