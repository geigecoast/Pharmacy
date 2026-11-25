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

extension Stoffgebiet {
    /// Jedes Stoffgebiet hat eine eigene, ruhige Farbe.
    var farbe: Color {
        switch self {
        case .e: Color(hell: 0x2A9D8F, dunkel: 0x5CC8BA)
        case .f: Color(hell: 0xD9773A, dunkel: 0xF0A070)
        case .g: Color(hell: 0x5A9E4B, dunkel: 0x8CC77E)
        case .h: Color(hell: 0x3A6EA5, dunkel: 0x74A6DC)
        case .i: Color(hell: 0x8E5BA8, dunkel: 0xBC94D4)
        case .k: Color(hell: 0x8A7F72, dunkel: 0xB8AEA2)
        }
    }
}

extension LVStatus {
    var farbe: Color {
        switch self {
        case .offen: .secondary
        case .angemeldet: .orange
        case .laeuft: .blue
        case .bestanden: .green
        case .nichtBestanden: .red
        case .wiederholung: .pink
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
        case .bestanden: .green
        case .freigeschaltet: .blue
        case .blockiert: .secondary
        }
    }
}

extension Lehrveranstaltung {
    var farbe: Color { hauptStoffgebiet?.farbe ?? .accentColor }
}

enum Layout {
    static let eckenradius: CGFloat = 12
    static let abstand: CGFloat = 16
}
