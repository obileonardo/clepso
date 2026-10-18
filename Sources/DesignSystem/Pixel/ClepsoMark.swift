#if canImport(AppKit)
import SwiftUI

/// The Clepso mark (design/brand/logo/svg/clepso-symbol-*.svg): a heartbeat inside a pixel ring. Drawn from the menu
/// bar icon's 16×16 matrix (`MenuBarIcon.pixels(.beat)`), so the app, the menu bar and the brand files share one
/// drawing. Size it in multiples of 16 points so every pixel lands on whole points.
public struct ClepsoMark: View {
    let role: ColorToken
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(role: ColorToken = .accent) { self.role = role }

    public static let label = "Clepso"

    /// The mark's pixels as (x, y) on its 16×16 grid.
    public static let pixels: [(x: Int, y: Int)] = MenuBarIcon.pixels(.beat, staleMark: false).sorted().map { ($0 % 16, $0 / 16) }

    public var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 16
            let origin = CGPoint(x: (size.width - unit * 16) / 2, y: (size.height - unit * 16) / 2)
            var path = Path()
            for p in Self.pixels {
                path.addRect(CGRect(x: origin.x + CGFloat(p.x) * unit, y: origin.y + CGFloat(p.y) * unit, width: unit, height: unit))
            }
            context.fill(path, with: .color(theme.color(role, scheme)))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Self.label)
    }
}
#endif
