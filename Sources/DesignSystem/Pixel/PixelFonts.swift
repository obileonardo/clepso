import CoreText
import Foundation

/// The bundled faces (Resources/Fonts, pinned in its README). Registered once, for this process only.
/// 1.16: the product's own faces (design/brand): Clepso Pixel for display, Clepso Mono for text. PostScript names, which are
/// unambiguous where family names are not. The earlier faces (Silkscreen, Pixelify Sans, VT323) were removed on 18 Oct 2026.
public enum PixelFonts {
    public static let display = "ClepsoPixel-Regular"    // titles, figures, tags, buttons, menu bar text
    public static let body = "ClepsoMono-Regular"        // supporting text
    public static let bodyMedium = "ClepsoMono-Medium"   // labels and micro
    public static let bodyBold = "ClepsoMono-Bold"

    private static let registered: Bool = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        return !urls.isEmpty
    }()

    /// Safe to call often; the work happens on the first call.
    @discardableResult
    public static func ensureRegistered() -> Bool { registered }
}
