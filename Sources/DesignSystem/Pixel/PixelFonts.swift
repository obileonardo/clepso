import CoreText
import Foundation

/// The bundled pixel faces (Resources/Fonts, SIL OFL 1.1, pinned in its README). Registered once, for this process only.
public enum PixelFonts {
    public static let display = "Silkscreen"            // blocky capitals: titles, tags, buttons
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
