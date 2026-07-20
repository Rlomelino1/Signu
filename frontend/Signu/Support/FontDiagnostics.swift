#if DEBUG
import UIKit

/// Launch-arg diagnostics (`--font-check`): verifies the bundled Inter faces
/// registered, and measures the hero amount row against real font metrics to
/// find the widest hero-XL size that never truncates.
enum FontDiagnostics {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--font-check") else { return }
        var lines: [String] = []
        defer {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fontcheck.txt")
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }

        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
            lines.append("FONTCHECK \(name) \(UIFont(name: name, size: 12) != nil ? "OK" : "MISSING")")
        }

        // Hero amount row budget: screen - screen padding (2×20) - card padding (2×24),
        // minus unit text, spacings, and the widest date-slot column.
        let worstAmount = "R$\u{00A0}449,90"
        let worstValue = "Jul 18 · in 5 days"
        let worstLabel = "PAID THROUGH"

        let unit = width("/mo", face: "Inter-Regular", size: 15)
        let value = width(worstValue, face: "Inter-SemiBold", size: 15)
        let label = width(worstLabel, face: "Inter-SemiBold", size: 13) + 1.1 * CGFloat(worstLabel.count - 1)
        let column = max(value, label)
        let fixed = 2 + unit + 8 + column

        for screen in [402.0, 393.0, 375.0] {
            let available = screen - 40 - 48 - fixed
            var safe = 0.0
            for size in stride(from: 44.0, through: 24.0, by: -0.5) {
                if width(worstAmount, face: "Inter-Bold", size: size, tabular: true) <= available {
                    safe = size
                    break
                }
            }
            let at44 = width(worstAmount, face: "Inter-Bold", size: 44, tabular: true)
            lines.append("FONTCHECK screen \(screen): amount@44=\(Int(at44))pt available=\(Int(available))pt maxSafe=\(safe)pt")
        }

        // Header row: avatar + spacing + subtitle + spacer + chip vs card inner.
        let states: [(subtitle: String, chip: String)] = [
            ("Monthly · Visa – 4821", "Active"),
            ("Monthly · Master – 7730", "Overdue"),
            ("Monthly · Visa – 4821", "Cancelled"),
            ("Monthly · Visa – 4821", "Ended"),
        ]
        for state in states {
            let subtitle = width(state.subtitle, face: "Inter-Regular", size: 13.5)
            let chip = width(state.chip, face: "Inter-SemiBold", size: 14) + 22
            let needed = 46 + 13 + subtitle + 6 + chip
            lines.append("FONTCHECK header [\(state.chip)] subtitle=\(Int(subtitle)) chip=\(Int(chip)) needed=\(Int(needed)) inner402=314 inner393=305")
        }
    }

    private static func width(_ text: String, face: String, size: CGFloat, tabular: Bool = false) -> CGFloat {
        var descriptor = UIFontDescriptor(name: face, size: size)
        if tabular {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
        }
        let font = UIFont(descriptor: descriptor, size: size)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
#endif
