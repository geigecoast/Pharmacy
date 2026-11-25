import Foundation

/// Kennzahlen für Analysen und Dashboard.
public enum Analyse {
    /// Prüfungsbereitschaft 0…1 aus den verfügbaren Bestandteilen (fehlende werden ausgelassen und neu gewichtet).
    /// - lernanteil: erledigte Lernzeit ÷ Lernaufwand
    /// - kartenLernstand: mittlere Erinnerungswahrscheinlichkeit der Karteikarten
    /// - probeklausur: Anteil erreichter Punkte der letzten Probeklausur(en)
    public static func bereitschaft(lernanteil: Double?, kartenLernstand: Double?, probeklausur: Double?) -> Double? {
        let teile: [(Double?, Double)] = [(lernanteil, 0.4), (kartenLernstand, 0.35), (probeklausur, 0.25)]
        let vorhanden = teile.compactMap { wert, gewicht in wert.map { (min(max($0, 0), 1), gewicht) } }
        guard !vorhanden.isEmpty else { return nil }
        let summe = vorhanden.reduce(0) { $0 + $1.1 }
        return vorhanden.reduce(0) { $0 + $1.0 * $1.1 } / summe
    }

    public struct ThemenWert: Equatable, Sendable, Identifiable {
        public var thema: String
        public var wert: Double
        public var gewicht: Double
        public var id: String { thema }
    }

    /// Fasst Einzelwerte je Thema zusammen (gewichteter Mittelwert), schwächste zuerst.
    public static func themen(_ eintraege: [(thema: String, wert: Double, gewicht: Double)]) -> [ThemenWert] {
        var summe: [String: (wert: Double, gewicht: Double, name: String)] = [:]
        for eintrag in eintraege where !eintrag.thema.trimmingCharacters(in: .whitespaces).isEmpty && eintrag.gewicht > 0 {
            let schluessel = Prognoserechner.schluessel(eintrag.thema)
            let bisher = summe[schluessel] ?? (0, 0, eintrag.thema)
            summe[schluessel] = (bisher.wert + eintrag.wert * eintrag.gewicht, bisher.gewicht + eintrag.gewicht, bisher.name)
        }
        return summe.values
            .map { ThemenWert(thema: $0.name, wert: $0.wert / $0.gewicht, gewicht: $0.gewicht) }
            .sorted { ($0.wert, $0.thema) < ($1.wert, $1.thema) }
    }

    public struct Zeitprognose: Equatable, Sendable {
        public var reicht: Bool
        /// Benötigte Minuten pro Tag bis zur Prüfung.
        public var benoetigtProTag: Int
        /// Tage Puffer beim tatsächlichen Tempo (negativ = Rückstand).
        public var pufferTage: Int
    }

    /// „Bist du rechtzeitig fertig?“ – Restaufwand gegen Tempo (tatsächlich oder geplant).
    public static func zeitprognose(restMinuten: Int, tageBis: Int, tempoProTag: Double) -> Zeitprognose {
        let tage = max(tageBis, 1)
        let benoetigt = Int((Double(restMinuten) / Double(tage)).rounded(.up))
        guard restMinuten > 0 else { return Zeitprognose(reicht: true, benoetigtProTag: 0, pufferTage: tage) }
        guard tempoProTag > 0 else { return Zeitprognose(reicht: false, benoetigtProTag: benoetigt, pufferTage: -tage) }
        let tageNoetig = Int((Double(restMinuten) / tempoProTag).rounded(.up))
        return Zeitprognose(reicht: tageNoetig <= tage, benoetigtProTag: benoetigt, pufferTage: tage - tageNoetig)
    }

    /// Lernminuten je Tag ohne Doppelzählung: je Tag das Maximum aus
    /// (Fokus-Timer + Karten + Quiz) und erledigten Lerneinheiten.
    public static func lernminutenProTag(erfasst: [(Date, Double)], lerneinheiten: [(Date, Double)], kalender: Calendar) -> [Date: Double] {
        var a: [Date: Double] = [:]
        var b: [Date: Double] = [:]
        for (datum, minuten) in erfasst { a[kalender.startOfDay(for: datum), default: 0] += minuten }
        for (datum, minuten) in lerneinheiten { b[kalender.startOfDay(for: datum), default: 0] += minuten }
        var ergebnis: [Date: Double] = [:]
        for tag in Set(a.keys).union(b.keys) {
            ergebnis[tag] = max(a[tag] ?? 0, b[tag] ?? 0)
        }
        return ergebnis
    }

    /// Kurzform „11 h 40“ wie im Design.
    public static func stundenText(_ minuten: Int) -> String {
        let h = minuten / 60
        let m = minuten % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : String(format: "%d h %02d", h, m)
    }
}
