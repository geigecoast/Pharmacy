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

    // Lernplan
    static let lernzeiten = "lernzeitenWoche"
    static let vorlaufTage = "lernplanVorlaufTage"
    static let praktikumMinuten = "lernplanPraktikumMinuten"
    static let lernplanWarnungen = "lernplanWarnungen"
    static let letzteLernplanAktualisierung = "letzteLernplanAktualisierung"

    // Erinnerungen
    static let erinnerungenAktiv = "erinnerungenAktiv"
    static let taeglicheErinnerung = "taeglicheErinnerung"
    static let erinnerungUhrzeitMinuten = "erinnerungUhrzeitMinuten"

    // Systemkalender
    static let kalenderLerneinheitenExport = "kalenderLerneinheitenExport"
    static let systemkalenderID = "systemkalenderID"
}

/// Standardwerte der Einstellungen (müssen mit den @AppStorage-Vorgaben übereinstimmen).
enum Standardwerte {
    static let vorlaufTage = 28
    static let praktikumMinuten = 60
    static let erinnerungUhrzeitMinuten = 17 * 60

    static var wochenplan: Wochenplan {
        UserDefaults.standard.string(forKey: EinstellungsSchluessel.lernzeiten).flatMap(Wochenplan.init(rawValue:)) ?? .standard
    }

    static func ganzzahl(_ schluessel: String, standard: Int) -> Int {
        UserDefaults.standard.object(forKey: schluessel) as? Int ?? standard
    }
}

extension Calendar {
    /// Gregorianischer Kalender mit Wochenbeginn Montag (deutsche Konvention).
    static var deutsch: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.locale = .deutsch
        kalender.timeZone = .current
        kalender.firstWeekday = 2
        kalender.minimumDaysInFirstWeek = 4
        return kalender
    }
}
