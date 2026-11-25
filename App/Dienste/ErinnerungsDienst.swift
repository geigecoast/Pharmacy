import Foundation
import SwiftData
import UserNotifications
import PharmaCore

/// Lokale Mitteilungen für Teilprüfungen, Anmeldeschlüsse, Fristen und das tägliche Lernen.
@MainActor
enum ErinnerungsDienst {
    static let praefix = "pharmatutor."
    /// iOS erlaubt höchstens 64 wartende Mitteilungen pro App.
    static let maximum = 60

    private struct Erinnerung {
        let datum: Date
        let kennung: String
        let titel: String
        let text: String
    }

    static func berechtigungAnfragen() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Entfernt alle bisherigen Erinnerungen der App und plant sie neu.
    static func planen(_ kontext: ModelContext) async {
        let zentrale = UNUserNotificationCenter.current()
        let wartend = await zentrale.pendingNotificationRequests()
        zentrale.removePendingNotificationRequests(withIdentifiers: wartend.map(\.identifier).filter { $0.hasPrefix(praefix) })

        let standard = UserDefaults.standard
        guard standard.bool(forKey: EinstellungsSchluessel.erinnerungenAktiv) else { return }
        let einstellungen = await zentrale.notificationSettings()
        guard einstellungen.authorizationStatus == .authorized || einstellungen.authorizationStatus == .provisional else { return }

        let jetzt = Date()
        let kalender = Calendar.deutsch
        var liste: [Erinnerung] = []

        func um(_ stunde: Int, _ tageVorher: Int, vor datum: Date) -> Date? {
            guard let tag = kalender.date(byAdding: .day, value: -tageVorher, to: kalender.startOfDay(for: datum)) else { return nil }
            return kalender.date(bySettingHour: stunde, minute: 0, second: 0, of: tag)
        }

        let teilpruefungen = (try? kontext.fetch(FetchDescriptor<Teilpruefung>())) ?? []
        for tp in teilpruefungen {
            guard let lv = tp.lehrveranstaltung, !lv.status.istAbgeschlossen, tp.ergebnis == .offen else { continue }
            let name = tp.titelMitLfdNr
            if let datum = tp.datum {
                for (tage, vorspann) in [(7, "In einer Woche"), (1, "Morgen")] {
                    if let zeitpunkt = um(18, tage, vor: datum) {
                        liste.append(Erinnerung(datum: zeitpunkt, kennung: "\(praefix)tp.\(tp.persistentModelID.hashValue).\(tage)",
                                                titel: "\(vorspann): \(name)",
                                                text: "\(lv.bezeichnung) – \(datum.datumUndUhrzeit). Schau in deinen Lernplan."))
                    }
                }
            }
            if tp.anmeldepflichtig, !tp.angemeldet, let schluss = tp.anmeldeschluss {
                for (tage, vorspann) in [(7, "noch 7 Tage"), (1, "nur noch bis morgen")] {
                    if let zeitpunkt = um(9, tage, vor: schluss) {
                        liste.append(Erinnerung(datum: zeitpunkt, kennung: "\(praefix)anm.\(tp.persistentModelID.hashValue).\(tage)",
                                                titel: "QIS/LSF-Anmeldung: \(vorspann)",
                                                text: "\(name). Eine verspätete Anmeldung ist nicht möglich."))
                    }
                }
            }
        }

        let fristen = (try? kontext.fetch(FetchDescriptor<Frist>())) ?? []
        for frist in fristen where !frist.erledigt {
            guard let datum = frist.datum else { continue }
            for (tage, vorspann) in [(14, "In zwei Wochen"), (7, "In einer Woche"), (1, "Morgen")] {
                if let zeitpunkt = um(9, tage, vor: datum) {
                    liste.append(Erinnerung(datum: zeitpunkt, kennung: "\(praefix)frist.\(frist.persistentModelID.hashValue).\(tage)",
                                            titel: "\(vorspann): \(frist.titel)",
                                            text: frist.hinweis.isEmpty ? frist.art.name : frist.hinweis))
                }
            }
        }

        let anstehend = liste.filter { $0.datum > jetzt }.sorted { $0.datum < $1.datum }.prefix(maximum)
        for erinnerung in anstehend {
            let inhalt = UNMutableNotificationContent()
            inhalt.title = erinnerung.titel
            inhalt.body = erinnerung.text
            inhalt.sound = .default
            let komponenten = kalender.dateComponents([.year, .month, .day, .hour, .minute], from: erinnerung.datum)
            let ausloeser = UNCalendarNotificationTrigger(dateMatching: komponenten, repeats: false)
            try? await zentrale.add(UNNotificationRequest(identifier: erinnerung.kennung, content: inhalt, trigger: ausloeser))
        }

        if standard.object(forKey: EinstellungsSchluessel.taeglicheErinnerung) as? Bool ?? true {
            let minuten = Standardwerte.ganzzahl(EinstellungsSchluessel.erinnerungUhrzeitMinuten, standard: Standardwerte.erinnerungUhrzeitMinuten)
            let inhalt = UNMutableNotificationContent()
            inhalt.title = "Zeit zum Lernen"
            inhalt.body = "Dein Lernplan für heute wartet – schon ein Block bringt dich weiter."
            inhalt.sound = .default
            var komponenten = DateComponents()
            komponenten.hour = minuten / 60
            komponenten.minute = minuten % 60
            let ausloeser = UNCalendarNotificationTrigger(dateMatching: komponenten, repeats: true)
            try? await zentrale.add(UNNotificationRequest(identifier: "\(praefix)taeglich", content: inhalt, trigger: ausloeser))
        }
    }
}
