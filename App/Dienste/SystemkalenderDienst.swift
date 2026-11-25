import Foundation
import EventKit
import SwiftData
import CoreGraphics

/// Überträgt Termine in einen eigenen Kalender „PharmaTutor“ im Systemkalender.
@MainActor
final class SystemkalenderDienst {
    static let shared = SystemkalenderDienst()

    private let store = EKEventStore()
    static let kalenderName = "PharmaTutor"

    enum Fehler: LocalizedError {
        case keinZugriff
        case keineQuelle

        var errorDescription: String? {
            switch self {
            case .keinZugriff:
                return "Kein Zugriff auf den Kalender. Bitte erlaube PharmaTutor den Kalenderzugriff in den Systemeinstellungen unter „Datenschutz & Sicherheit“."
            case .keineQuelle:
                return "Es wurde kein Kalenderkonto gefunden, in dem PharmaTutor einen Kalender anlegen kann."
            }
        }
    }

    /// Ersetzt alle Einträge im Kalender „PharmaTutor“ durch den aktuellen Stand. Gibt die Anzahl der Termine zurück.
    func abgleichen(_ kontext: ModelContext, mitLerneinheiten: Bool) async throws -> Int {
        let erlaubt = try await store.requestFullAccessToEvents()
        guard erlaubt else { throw Fehler.keinZugriff }
        let kalender = try pharmaKalender()

        let jetzt = Date()
        let zeitraumStart = Calendar.current.date(byAdding: .year, value: -1, to: jetzt) ?? jetzt
        let zeitraumEnde = Calendar.current.date(byAdding: .year, value: 3, to: jetzt) ?? jetzt
        let vorhandene = store.events(matching: store.predicateForEvents(withStart: zeitraumStart, end: zeitraumEnde, calendars: [kalender]))
        for termin in vorhandene {
            try store.remove(termin, span: .thisEvent, commit: false)
        }

        var anzahl = 0
        let teilpruefungen = (try? kontext.fetch(FetchDescriptor<Teilpruefung>())) ?? []
        for tp in teilpruefungen {
            guard let datum = tp.datum, let lv = tp.lehrveranstaltung else { continue }
            let termin = EKEvent(eventStore: store)
            termin.calendar = kalender
            termin.title = tp.titelMitLfdNr
            termin.location = tp.ort.isEmpty ? nil : tp.ort
            termin.notes = [lv.bezeichnung, tp.hinweis].filter { !$0.isEmpty }.joined(separator: "\n")
            if let ende = tp.ende, ende > datum {
                termin.isAllDay = true
                termin.startDate = datum
                termin.endDate = ende
            } else {
                termin.startDate = datum
                termin.endDate = datum.addingTimeInterval(2 * 3600)
                if tp.ergebnis == .offen && !lv.status.istAbgeschlossen {
                    termin.addAlarm(EKAlarm(relativeOffset: -24 * 3600))
                }
            }
            try store.save(termin, span: .thisEvent, commit: false)
            anzahl += 1

            if tp.anmeldepflichtig, !tp.angemeldet, let schluss = tp.anmeldeschluss {
                let anmeldung = EKEvent(eventStore: store)
                anmeldung.calendar = kalender
                anmeldung.title = "Anmeldeschluss QIS/LSF: \(tp.titelMitLfdNr)"
                anmeldung.isAllDay = true
                anmeldung.startDate = schluss
                anmeldung.endDate = schluss
                try store.save(anmeldung, span: .thisEvent, commit: false)
                anzahl += 1
            }
        }

        let fristen = (try? kontext.fetch(FetchDescriptor<Frist>())) ?? []
        for frist in fristen {
            guard let datum = frist.datum else { continue }
            let termin = EKEvent(eventStore: store)
            termin.calendar = kalender
            termin.title = frist.titel
            termin.notes = frist.hinweis
            termin.isAllDay = true
            termin.startDate = datum
            termin.endDate = datum
            try store.save(termin, span: .thisEvent, commit: false)
            anzahl += 1
        }

        if mitLerneinheiten {
            let heute = Calendar.current.startOfDay(for: jetzt)
            let einheiten = (try? kontext.fetch(FetchDescriptor<Lerneinheit>())) ?? []
            for einheit in einheiten where !einheit.erledigt && einheit.tag >= heute {
                let termin = EKEvent(eventStore: store)
                termin.calendar = kalender
                termin.title = "Lernen (\(einheit.dauerMinuten) min): \(einheit.thema)"
                termin.isAllDay = true
                termin.startDate = einheit.tag
                termin.endDate = einheit.tag
                try store.save(termin, span: .thisEvent, commit: false)
                anzahl += 1
            }
        }

        try store.commit()
        return anzahl
    }

    private func pharmaKalender() throws -> EKCalendar {
        let standard = UserDefaults.standard
        if let kennung = standard.string(forKey: EinstellungsSchluessel.systemkalenderID),
           let kalender = store.calendar(withIdentifier: kennung) {
            return kalender
        }
        if let kalender = store.calendars(for: .event).first(where: { $0.title == Self.kalenderName && $0.allowsContentModifications }) {
            standard.set(kalender.calendarIdentifier, forKey: EinstellungsSchluessel.systemkalenderID)
            return kalender
        }
        let quelle = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        guard let quelle else { throw Fehler.keineQuelle }
        let kalender = EKCalendar(for: .event, eventStore: store)
        kalender.title = Self.kalenderName
        kalender.source = quelle
        kalender.cgColor = CGColor(srgbRed: 0.16, green: 0.62, blue: 0.56, alpha: 1)
        try store.saveCalendar(kalender, commit: true)
        standard.set(kalender.calendarIdentifier, forKey: EinstellungsSchluessel.systemkalenderID)
        return kalender
    }
}
