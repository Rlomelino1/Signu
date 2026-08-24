import SwiftUI

/// The Signu mark: two counter-rotated half-circle arcs, the upper one opening
/// left-and-up and the lower one right-and-down, stacked so their strokes
/// overlap. The same mark the auth emails carry as a hosted image.
///
/// Each half is half a ring rather than half a disc, so the two are drawn from
/// one shape and the lower one is the upper rotated 180°. The halves take
/// independent horizontal offsets because the boot splash slides them apart and
/// back together — at rest both are zero and the mark reads as one figure.
struct SignuArcsMark: View {
    /// Side of one arc's square. Both halves are this wide.
    static let arcSize: CGFloat = 148
    /// Ring thickness, drawn inside `arcSize` the way a CSS border is.
    static let strokeWidth: CGFloat = 30
    /// How far down the lower arc sits. Less than `arcSize`, so they overlap.
    static let stride: CGFloat = 116
    /// Full height of the stacked pair.
    static let height: CGFloat = stride + arcSize

    var color: Color = SignuColor.bootMark
    var upperOffset: CGFloat = 0
    var lowerOffset: CGFloat = 0
    var upperOpacity: Double = 1
    var lowerOpacity: Double = 1

    var body: some View {
        ZStack(alignment: .top) {
            half
                .opacity(upperOpacity)
                .offset(x: upperOffset)

            half
                .rotationEffect(.degrees(180))
                .opacity(lowerOpacity)
                .offset(x: lowerOffset, y: Self.stride)
        }
        .frame(width: Self.arcSize, height: Self.height, alignment: .top)
    }

    /// The upper half: the left and top quadrants of a ring.
    ///
    /// `Circle`'s path starts at three o'clock and runs clockwise, so 0.375 is
    /// the lower-left diagonal and 0.875 the upper-right one — the same two
    /// cuts a CSS border makes when only `border-top` and `border-left` carry a
    /// colour. The inset is half the stroke because `stroke` straddles the path
    /// while a border sits inside the box.
    private var half: some View {
        Circle()
            .inset(by: Self.strokeWidth / 2)
            .trim(from: 0.375, to: 0.875)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: Self.strokeWidth, lineCap: .butt)
            )
            .frame(width: Self.arcSize, height: Self.arcSize)
    }
}

#Preview("Arcs mark") {
    ZStack {
        SignuColor.bootBackdrop
        SignuArcsMark()
    }
    .ignoresSafeArea()
}

#Preview("Arcs mark · apart") {
    ZStack {
        SignuColor.bootBackdrop
        SignuArcsMark(upperOffset: -90, lowerOffset: 90, upperOpacity: 0.4, lowerOpacity: 0.4)
    }
    .ignoresSafeArea()
}
