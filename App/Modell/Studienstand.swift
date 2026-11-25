import Foundation
import PharmaCore

extension StudienStand {
    /// Baut den Studienstand aus allen Lehrveranstaltungen und den Zulassungen.
    @MainActor
    static func aus(_ lehrveranstaltungen: [Lehrveranstaltung], ph1: Bool) -> StudienStand {
        var stand = StudienStand(zulassungen: ph1 ? ["Ph1"] : [])
        for lv in lehrveranstaltungen {
            let teile = lv.lfdNrTeile
            switch lv.status {
            case .bestanden:
                stand.bestandeneKurse.formUnion(teile)
                stand.teilgenommeneKurse.formUnion(teile)
            case .laeuft, .wiederholung, .nichtBestanden:
                stand.teilgenommeneKurse.formUnion(teile)
            case .offen, .angemeldet:
                break
            }
            for tp in lv.teilpruefungen ?? [] where tp.ergebnis == .bestanden {
                for teil in teile {
                    stand.bestandeneTeilpruefungen.insert(TeilpruefungSchluessel(lfdNr: teil, typ: tp.typ))
                }
            }
        }
        return stand
    }
}

extension Lehrveranstaltung {
    @MainActor
    func freigabe(in stand: StudienStand) -> Freigabe {
        Freigabe.ermitteln(status: status, regel: voraussetzungen, stand: stand)
    }
}

/// Schlüssel für Einstellungen in den UserDefaults.
enum EinstellungsSchluessel {
    static let zulassungPh1 = "zulassungPh1"
    static let onboardingAbgeschlossen = "onboardingAbgeschlossen"
    static let ausgewaehltesSemester = "ausgewaehltesSemester"
}
