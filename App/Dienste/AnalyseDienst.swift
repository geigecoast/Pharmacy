import Foundation
import SwiftData
import PharmaCore

/// Analysen: Lernzeit, Themenbeherrschung, Prüfungsbereitschaft.
@MainActor
enum AnalyseDienst {
    static var kalender: Calendar { Calendar.deutsch }

    /// Lernminuten je Tag (gesamt oder für eine Lehrveranstaltung), ohne Doppelzählung.
    static func lernminuten(lv: Lehrveranstaltung?, kontext: ModelContext) -> [Date: Double] {
        func passt(_ andere: Lehrveranstaltung?) -> Bool { lv == nil || andere == lv }
        var erfasst: [(Date, Double)] = []
        for sitzung in (try? kontext.fetch(FetchDescriptor<Lernsitzung>())) ?? [] where passt(sitzung.lehrveranstaltung) {
            erfasst.append((sitzung.start, sitzung.dauerSekunden / 60))
        }
        for wiederholung in (try? kontext.fetch(FetchDescriptor<Wiederholung>())) ?? [] where passt(wiederholung.karte?.lehrveranstaltung) {
            erfasst.append((wiederholung.datum, min(wiederholung.dauerSekunden, 300) / 60))
        }
        for quiz in (try? kontext.fetch(FetchDescriptor<QuizErgebnis>())) ?? [] where passt(quiz.lehrveranstaltung) {
            erfasst.append((quiz.datum, quiz.dauerSekunden / 60))
        }
        for klausur in (try? kontext.fetch(FetchDescriptor<Probeklausur>())) ?? [] where passt(klausur.lehrveranstaltung) {
            guard let abgabe = klausur.abgegebenAm else { continue }
            erfasst.append((abgabe, min(abgabe.timeIntervalSince(klausur.erstelltAm) / 60, Double(klausur.dauerMinuten))))
        }
        let einheiten = ((try? kontext.fetch(FetchDescriptor<Lerneinheit>())) ?? [])
            .filter { $0.erledigt && passt($0.lehrveranstaltung) }
            .map { ($0.erledigtAm ?? $0.tag, Double($0.dauerMinuten)) }
        return Analyse.lernminutenProTag(erfasst: erfasst, lerneinheiten: einheiten, kalender: kalender)
    }

    /// Minuten Mo–So einer Woche.
    static func woche(_ minuten: [Date: Double], um datum: Date = Date()) -> [Int] {
        let start = kalender.dateInterval(of: .weekOfYear, for: datum)?.start ?? datum
        return (0..<7).map { offset in
            guard let tag = kalender.date(byAdding: .day, value: offset, to: start) else { return 0 }
            return Int((minuten[kalender.startOfDay(for: tag)] ?? 0).rounded())
        }
    }

    /// Summen der letzten `anzahl` Wochen (älteste zuerst).
    static func wochensummen(_ minuten: [Date: Double], anzahl: Int = 8) -> [(beginn: Date, minuten: Int)] {
        let diese = kalender.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<anzahl).reversed().compactMap { zurueck in
            guard let beginn = kalender.date(byAdding: .weekOfYear, value: -zurueck, to: diese),
                  let ende = kalender.date(byAdding: .day, value: 7, to: beginn) else { return nil }
            let summe = minuten.filter { $0.key >= beginn && $0.key < ende }.values.reduce(0, +)
            return (beginn, Int(summe.rounded()))
        }
    }

    /// Mittlere Lernminuten pro Tag der letzten 14 Tage.
    static func tempo(_ minuten: [Date: Double]) -> Double {
        let heute = kalender.startOfDay(for: Date())
        guard let grenze = kalender.date(byAdding: .day, value: -14, to: heute) else { return 0 }
        return minuten.filter { $0.key >= grenze && $0.key <= heute }.values.reduce(0, +) / 14
    }

    /// Themenbeherrschung aus Karteikarten, Probeklausuren und offenen Fehlern.
    static func themen(_ lv: Lehrveranstaltung) -> [Analyse.ThemenWert] {
        var werte: [(thema: String, wert: Double, gewicht: Double)] = []
        let jetzt = Date()
        for karte in (lv.karteikarten ?? []) where karte.istGueltig && !karte.thema.isEmpty {
            werte.append((karte.thema, KartenDienst.fsrs.abrufbarkeit(karte.stand, jetzt: jetzt), 1))
        }
        for klausur in (lv.probeklausuren ?? []) where klausur.abgegebenAm != nil {
            let bewertungen = klausur.bewertungen
            for frage in klausur.fragen where !frage.thema.isEmpty {
                werte.append((frage.thema, (bewertungen[frage.id]?.punkte ?? 0) / max(frage.punkte, 1), 2))
            }
        }
        for fehler in (lv.fehlereintraege ?? []) where !fehler.verstanden && !fehler.thema.isEmpty {
            werte.append((fehler.thema, 0, 0.5))
        }
        return Analyse.themen(werte)
    }

    struct Bereitschaft {
        var gesamt: Double?
        var lernanteil: Double?
        var karten: Double?
        var probeklausur: Double?
    }

    static func bereitschaft(_ tp: Teilpruefung) -> Bereitschaft {
        let lv = tp.lehrveranstaltung
        let lernanteil: Double? = tp.lernaufwandMinuten > 0
            ? Double((tp.lerneinheiten ?? []).filter(\.erledigt).reduce(0) { $0 + $1.dauerMinuten }) / Double(tp.lernaufwandMinuten)
            : nil
        let karten = KartenDienst.lernstand(lv?.karteikarten ?? [])
        let letzte = (lv?.probeklausuren ?? []).filter { $0.abgegebenAm != nil }.max { ($0.abgegebenAm ?? .distantPast) < ($1.abgegebenAm ?? .distantPast) }
        let probe = letzte.map { $0.prozent / 100 }
        return Bereitschaft(gesamt: Analyse.bereitschaft(lernanteil: lernanteil, kartenLernstand: karten, probeklausur: probe),
                            lernanteil: lernanteil.map { min($0, 1) }, karten: karten, probeklausur: probe)
    }
}
