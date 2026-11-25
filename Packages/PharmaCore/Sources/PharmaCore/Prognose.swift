import Foundation

public enum PrognoseStufe: Int, Codable, CaseIterable, Comparable, Sendable {
    case moeglich = 1
    case wahrscheinlich = 2
    case sehrWahrscheinlich = 3

    public var name: String {
        switch self {
        case .sehrWahrscheinlich: "Sehr wahrscheinlich"
        case .wahrscheinlich: "Wahrscheinlich"
        case .moeglich: "Möglich"
        }
    }

    public static func < (a: PrognoseStufe, b: PrognoseStufe) -> Bool { a.rawValue < b.rawValue }
}

/// Eine Frage aus einer Altklausur mit ihren Themen.
public struct AltfrageDaten: Sendable {
    public var klausurID: String
    public var themen: [String]
    public var punkte: Double?

    public init(klausurID: String, themen: [String], punkte: Double? = nil) {
        self.klausurID = klausurID
        self.themen = themen
        self.punkte = punkte
    }
}

public struct KlausurDaten: Sendable {
    public var id: String
    public var jahr: Int?

    public init(id: String, jahr: Int?) {
        self.id = id
        self.jahr = jahr
    }
}

public struct PrognoseEintrag: Sendable, Equatable, Identifiable {
    public var thema: String
    public var stufe: PrognoseStufe
    public var wert: Double
    public var anzahlKlausuren: Int
    public var gesamtKlausuren: Int
    public var zuletzt: Int?
    public var mittlerePunkte: Double?
    public var betont: Bool
    public var begruendung: String

    public var id: String { thema }
}

/// Prüfungsprognose aus Häufigkeit, Aktualität und Punktgewichtung – ausdrücklich ohne Garantie.
public enum Prognoserechner {
    /// Vergleichsschlüssel für Themen (Groß-/Kleinschreibung, Akzente, Leerzeichen egal).
    public static func schluessel(_ thema: String) -> String {
        thema.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    public static func berechnen(fragen: [AltfrageDaten], klausuren: [KlausurDaten], betonteThemen: [String],
                                 aktuellesJahr: Int) -> [PrognoseEintrag] {
        let jahrNachKlausur = Dictionary(klausuren.map { ($0.id, $0.jahr) }, uniquingKeysWith: { a, _ in a })
        let gesamt = max(klausuren.count, 1)

        struct Sammlung {
            var schreibweisen: [String: Int] = [:]
            var klausuren: Set<String> = []
            var punkte: [Double] = []
        }
        var themen: [String: Sammlung] = [:]
        for frage in fragen {
            for thema in Set(frage.themen.map { $0.trimmingCharacters(in: .whitespaces) }) where !thema.isEmpty {
                let s = schluessel(thema)
                guard !s.isEmpty else { continue }
                themen[s, default: Sammlung()].schreibweisen[thema, default: 0] += 1
                themen[s, default: Sammlung()].klausuren.insert(frage.klausurID)
                if let punkte = frage.punkte { themen[s, default: Sammlung()].punkte.append(punkte) }
            }
        }
        let betont = Dictionary(betonteThemen.map { (schluessel($0), $0) }, uniquingKeysWith: { a, _ in a })
        for (s, original) in betont where themen[s] == nil {
            themen[s] = Sammlung(schreibweisen: [original: 1])
        }

        let maxPunkte = themen.values.compactMap { $0.punkte.isEmpty ? nil : $0.punkte.reduce(0, +) / Double($0.punkte.count) }.max() ?? 0

        let ergebnis: [PrognoseEintrag] = themen.map { s, sammlung in
            let anzahl = sammlung.klausuren.count
            let haeufigkeit = Double(anzahl) / Double(gesamt)
            let jahre = sammlung.klausuren.compactMap { jahrNachKlausur[$0] ?? nil }
            let zuletzt = jahre.max()
            let aktualitaet: Double = {
                guard anzahl > 0 else { return 0 }
                guard let zuletzt else { return 0.5 }
                return exp(-Double(max(0, aktuellesJahr - zuletzt)) / 3)
            }()
            let mittel = sammlung.punkte.isEmpty ? nil : sammlung.punkte.reduce(0, +) / Double(sammlung.punkte.count)
            let punkteAnteil = (mittel != nil && maxPunkte > 0) ? mittel! / maxPunkte : 0
            let istBetont = betont[s] != nil
            let wert = min(1, 0.5 * haeufigkeit + 0.25 * aktualitaet + 0.15 * punkteAnteil + (istBetont ? 0.25 : 0))

            let stufe: PrognoseStufe
            if wert >= 0.6 && (anzahl >= 2 || (anzahl >= 1 && istBetont)) {
                stufe = .sehrWahrscheinlich
            } else if wert >= 0.35 || istBetont {
                stufe = .wahrscheinlich
            } else {
                stufe = .moeglich
            }

            var teile: [String] = []
            if anzahl > 0 {
                var satz = "In \(anzahl) von \(klausuren.count) Altklausuren"
                if let zuletzt { satz += ", zuletzt \(zuletzt)" }
                if let mittel { satz += ", Ø \(formatiert(mittel)) Punkte" }
                teile.append(satz)
            } else {
                teile.append("Bisher in keiner Altklausur")
            }
            if istBetont { teile.append("laut Notiz vom Prüfer betont") }
            let name = sammlung.schreibweisen.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? s

            return PrognoseEintrag(thema: name, stufe: stufe, wert: wert, anzahlKlausuren: anzahl, gesamtKlausuren: klausuren.count,
                                   zuletzt: zuletzt, mittlerePunkte: mittel, betont: istBetont,
                                   begruendung: teile.joined(separator: "; ") + ".")
        }
        return ergebnis.sorted { ($0.stufe, $0.wert, $1.thema) > ($1.stufe, $1.wert, $0.thema) }
    }

    static func formatiert(_ wert: Double) -> String {
        let gerundet = (wert * 10).rounded() / 10
        return gerundet == gerundet.rounded() ? "\(Int(gerundet))" : String(gerundet).replacingOccurrences(of: ".", with: ",")
    }
}

/// Bewertung von Probeklausuren.
public enum Klausurbewertung {
    /// Rechenaufgabe: richtig, wenn die Zahl innerhalb der Toleranz liegt (z. B. 2 %).
    public static func zahlRichtig(antwort: String, loesung: Double, toleranzProzent: Double = 2) -> Bool {
        let bereinigt = antwort.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
        guard let wert = Dezimal.lesen(bereinigt) else { return false }
        if loesung == 0 { return abs(wert) < 1e-9 }
        return abs(wert - loesung) / abs(loesung) * 100 <= toleranzProzent
    }

    /// Multiple Choice: volle Punkte nur bei exakt richtiger Auswahl.
    public static func mcPunkte(auswahl: Set<Int>, richtig: Set<Int>, punkte: Double) -> Double {
        auswahl == richtig ? punkte : 0
    }

    /// Orientierungsnote nach Prozent (übliche Staffel; die tatsächliche Notengebung legt die Prüfung fest).
    public static func note(prozent: Double) -> String {
        switch prozent {
        case 87.5...: "1"
        case 75..<87.5: "2"
        case 62.5..<75: "3"
        case 50..<62.5: "4"
        default: "5"
        }
    }
}
