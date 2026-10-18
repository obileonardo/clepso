import CoreText
import Foundation

/// The bundled faces (Resources/Fonts, pinned in its README). Registered once, for this process only.
/// 1.16: the product's own faces (design/brand): Pulse Pixel for display, Pulse Mono for text. PostScript names, which are
/// unambiguous where family names are not. Silkscreen, Pixelify Sans and VT323 stay bundled but are no longer used.
public enum PixelFonts {
    public static let display = "ClepsoPixel-Regular"    // titles, figures, tags, buttons, menu bar text
    public static let body = "ClepsoMono-Regular"        // supporting text
    public static let bodyMedium = "ClepsoMono-Medium"   // labels and micro
    public static let bodyBold = "ClepsoMono-Bold"
    public static let number = "Pixelify Sans"          // pixel numerals that stay legible at large sizes
    public static let terminal = "VT323"                // terminal face for the Matrix-style details

    private static let registered: Bool = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        return !urls.isEmpty
    }()

    /// Safe to call often; the work happens on the first call.
    @discardableResult
    public static func ensureRegistered() -> Bool { registered }
}
