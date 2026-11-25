import SwiftUI

/// Was in der Detailspalte angezeigt wird.
enum Bereich: Hashable {
    case heute
    case kalender
    case dashboard
    case voraussetzungen
    case einstellungen
    case semester(Semester)
    case lehrveranstaltung(Lehrveranstaltung)
}

struct NavigationsAuswahlSchluessel: FocusedValueKey {
    typealias Value = Binding<Bereich?>
}

extension FocusedValues {
    var navigationsAuswahl: Binding<Bereich?>? {
        get { self[NavigationsAuswahlSchluessel.self] }
        set { self[NavigationsAuswahlSchluessel.self] = newValue }
    }
}
