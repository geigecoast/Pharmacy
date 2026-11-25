import Foundation
import SwiftData

/// Ein freigeschaltetes Abzeichen (Kennung = `Gamification.Abzeichen.rawValue`).
@Model
final class Erfolg {
    var kennung: String = ""
    var erreichtAm: Date = Date()

    init(kennung: String, erreichtAm: Date = Date()) {
        self.kennung = kennung
        self.erreichtAm = erreichtAm
    }
}
