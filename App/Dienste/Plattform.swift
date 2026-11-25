import SwiftUI
#if os(macOS)
import AppKit
typealias PlattformFarbe = NSColor
typealias PlattformBild = NSImage
#else
import UIKit
typealias PlattformFarbe = UIColor
typealias PlattformBild = UIImage
#endif
import PharmaCore

extension MarkierungsFarbe {
    var plattformFarbe: PlattformFarbe {
        PlattformFarbe(red: rgb.rot, green: rgb.gruen, blue: rgb.blau, alpha: 1)
    }

    var farbe: Color {
        Color(red: rgb.rot, green: rgb.gruen, blue: rgb.blau)
    }
}

extension PlattformBild {
    var cgBild: CGImage? {
        #if os(macOS)
        var rechteck = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rechteck, context: nil, hints: nil)
        #else
        return cgImage
        #endif
    }
}
