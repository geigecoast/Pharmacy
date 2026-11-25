import Foundation
import SwiftData
import PharmaCore

/// Erstellt und aktualisiert den automatischen Lernplan.
@MainActor
enum LernplanDienst {
    struct Ergebnis {
        var geplanteEinheiten: Int
        var ziele: Int
        var warnungen: [String]

        var meldung: String {
            if ziele == 0 {
                return "Keine anstehenden Teilprüfungen mit Termin – trage Prüfungstermine ein, damit ein Lernplan entsteht."
            }
            if warnungen.isEmpty {
                return "Lernplan aktualisiert: \(geplanteEinheiten) Lerneinheiten für \(ziele) Teilprüfungen geplant."
            }
            return "Lernplan aktualisiert – die verfügbare Zeit reicht nicht für alle Prüfungen."
        }
    }

    /// Plant alle automatischen, nicht erledigten Lerneinheiten ab heute neu.
    /// Erledigte und selbst angelegte/verschobene Einheiten bleiben erhalten.
    @discardableResult
    static func aktualisieren(_ kontext: ModelContext, jetzt: Date = Date()) -> Ergebnis {
        let kalender = Calendar.deutsch
        let heute = kalender.startOfDay(for: jetzt)
        let teilpruefungen = (try? kontext.fetch(FetchDescriptor<Teilpruefung>())) ?? []
        let einheiten = (try? kontext.fetch(FetchDescriptor<Lerneinheit>())) ?? []

        for einheit in einheiten where !einheit.manuell && !einheit.erledigt {
            kontext.delete(einheit)
        }
        let verbleibend = einheiten.filter { $0.manuell || $0.erledigt }

        // Ziele aus anstehenden Teilprüfungen
        var ziele: [LernZiel] = []
        var nachID: [String: Teilpruefung] = [:]
        for (index, tp) in teilpruefungen.enumerated() {
            guard let lv = tp.lehrveranstaltung, !lv.status.istAbgeschlossen,
                  tp.ergebnis == .offen, let datum = tp.datum,
                  kalender.startOfDay(for: datum) > heute, tp.lernaufwandMinuten > 0 else { continue }
            let id = "tp\(index)"
            let geleistet = verbleibend
                .filter { $0.teilpruefung == tp && ($0.erledigt || $0.tag >= heute) }
                .reduce(0) { $0 + $1.dauerMinuten }
            ziele.append(LernZiel(id: id, pruefungstag: datum, bedarfMinuten: tp.lernaufwandMinuten,
                                  erledigtMinuten: geleistet, istEingangspruefung: tp.typ.istEingangspruefung))
            nachID[id] = tp
        }

        // Bereits belegte Zeit: selbst geplante Einheiten und heute schon Erledigtes
        var belegt: [Date: Int] = [:]
        for einheit in verbleibend {
            let tag = kalender.startOfDay(for: einheit.tag)
            if (einheit.manuell && !einheit.erledigt && tag >= heute) || (einheit.erledigt && tag == heute) {
                belegt[tag, default: 0] += einheit.dauerMinuten
            }
        }

        // Während eines Blockpraktikums bleibt nur wenig Lernzeit
        let praktikumMinuten = Standardwerte.ganzzahl(EinstellungsSchluessel.praktikumMinuten, standard: Standardwerte.praktikumMinuten)
        var grenzen: [Date: Int] = [:]
        for tp in teilpruefungen where tp.typ == .praktischerTeil {
            guard let start = tp.datum, tp.lehrveranstaltung?.status.istAbgeschlossen == false else { continue }
            var tag = kalender.startOfDay(for: start)
            let ende = kalender.startOfDay(for: tp.ende ?? start)
            while tag <= ende {
                grenzen[tag] = praktikumMinuten
                guard let naechster = kalender.date(byAdding: .day, value: 1, to: tag) else { break }
                tag = naechster
            }
        }

        let optionen = Lernplaner.Optionen(
            vorlaufTage: Standardwerte.ganzzahl(EinstellungsSchluessel.vorlaufTage, standard: Standardwerte.vorlaufTage)
        )
        let plan = Lernplaner.planen(ziele: ziele, wochenplan: Standardwerte.wochenplan, ab: heute,
                                     belegteMinuten: belegt, kapazitaetsGrenzen: grenzen,
                                     optionen: optionen, kalender: kalender)

        for geplant in plan.einheiten {
            guard let tp = nachID[geplant.zielID] else { continue }
            let einheit = Lerneinheit(tag: geplant.tag, dauerMinuten: geplant.minuten, thema: tp.titelMitLfdNr)
            kontext.insert(einheit)
            einheit.teilpruefung = tp
            einheit.lehrveranstaltung = tp.lehrveranstaltung
        }

        let warnungen = plan.fehlendeMinuten
            .compactMap { id, minuten -> (Date, String)? in
                guard let tp = nachID[id], let datum = tp.datum else { return nil }
                return (datum, "\(tp.titelMitLfdNr): es fehlen etwa \(Dauer.text(minuten: minuten)) Lernzeit bis zur Prüfung.")
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        UserDefaults.standard.set(warnungen.joined(separator: "\n"), forKey: EinstellungsSchluessel.lernplanWarnungen)
        UserDefaults.standard.set(jetzt.timeIntervalSince1970, forKey: EinstellungsSchluessel.letzteLernplanAktualisierung)
        try? kontext.save()

        return Ergebnis(geplanteEinheiten: plan.einheiten.count, ziele: ziele.count, warnungen: warnungen)
    }

    /// Passt den Plan einmal pro Tag an verpasste Einheiten an.
    static func taeglichAktualisierenFallsNoetig(_ kontext: ModelContext, jetzt: Date = Date()) {
        let letzte = UserDefaults.standard.double(forKey: EinstellungsSchluessel.letzteLernplanAktualisierung)
        if letzte > 0, Calendar.current.isDate(Date(timeIntervalSince1970: letzte), inSameDayAs: jetzt) { return }
        aktualisieren(kontext, jetzt: jetzt)
    }
}
