import SwiftUI
import PharmaCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// Farbe mit eigenen Werten für hellen und dunklen Modus (Hex, sRGB).
    init(hell: UInt32, dunkel: UInt32) {
        func komponenten(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
        }
        let h = komponenten(hell)
        let d = komponenten(dunkel)
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { erscheinung in
            let dunkelModus = erscheinung.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = dunkelModus ? d : h
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        self.init(uiColor: UIColor { eigenschaften in
            let c = eigenschaften.userInterfaceStyle == .dark ? d : h
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
}

extension LVStatus {
    var farbe: Color {
        switch self {
        case .offen: Thema.tinteTertiaer
        case .angemeldet: Thema.tinte
        case .laeuft: Thema.tinte
        case .bestanden: Thema.tinteTertiaer
        case .nichtBestanden: Stoffgebiet.i.farbe
        case .wiederholung: Stoffgebiet.i.farbe
        }
    }

    var symbol: String {
        switch self {
        case .offen: "circle"
        case .angemeldet: "checkmark.circle"
        case .laeuft: "play.circle.fill"
        case .bestanden: "checkmark.seal.fill"
        case .nichtBestanden: "xmark.octagon.fill"
        case .wiederholung: "arrow.counterclockwise.circle.fill"
        }
    }
}

extension Freigabe {
    var farbe: Color {
        switch self {
        case .bestanden: Thema.tinteTertiaer
        case .freigeschaltet: Thema.tinte
        case .blockiert: Thema.tinteTertiaer
        }
    }
}

extension Lehrveranstaltung {
    var farbe: Color { hauptStoffgebiet?.farbe ?? Thema.tinteTertiaer }
    var hintergrundfarbe: Color { hauptStoffgebiet?.hintergrund ?? Thema.flaecheGedaempft }
}

enum Layout {
    static let eckenradius: CGFloat = 12
    static let abstand: CGFloat = 16
}
