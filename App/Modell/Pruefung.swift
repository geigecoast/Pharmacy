import Foundation
import SwiftData
import PharmaCore

enum AltklausurArt: String, CaseIterable, Identifiable {
    case klausur, probeklausur, altfragen, notiz

    var id: String { rawValue }

    var name: String {
        switch self {
        case .klausur: "Altklausur"
        case .probeklausur: "Probeklausur"
        case .altfragen: "Altfragen"
        case .notiz: "Notiz zum Prüfer"
        }
    }
}

/// Importierte Altklausur, Probeklausur, Altfragen-Sammlung oder Notiz („Was hat der Prüfer betont?“).
@Model
final class Altklausur {
    var kennung: UUID = UUID()
    var titel: String = ""
    var artRaw: String = AltklausurArt.klausur.rawValue
    var jahr: Int?
    @Attribute(.externalStorage) var daten: Data?
    var dateiname: String = ""
    var text: String = ""
    var analysiert: Bool = false
    var analyseLaeuft: Bool = false
    /// Aus Notizen: Themen, die der Prüfer betont hat.
    var betonteThemen: [String] = []
    var importiertAm: Date = Date()
    var lehrveranstaltung: Lehrveranstaltung?

    @Relationship(deleteRule: .cascade, inverse: \AltklausurFrage.altklausur)
    var fragen: [AltklausurFrage]? = []

    init(titel: String, art: AltklausurArt) {
        self.titel = titel
        self.artRaw = art.rawValue
    }

    var art: AltklausurArt {
        get { AltklausurArt(rawValue: artRaw) ?? .klausur }
        set { artRaw = newValue.rawValue }
    }
}

/// Aus einer Altklausur extrahierte Frage.
@Model
final class AltklausurFrage {
    var nummer: Int = 0
    var text: String = ""
    var punkte: Double?
    var typ: String = ""
    var themen: [String] = []
    var altklausur: Altklausur?

    init(nummer: Int, text: String, punkte: Double?, typ: String, themen: [String]) {
        self.nummer = nummer
        self.text = text
        self.punkte = punkte
        self.typ = typ
        self.themen = themen
    }
}

/// Frage einer Probeklausur.
struct PKFrage: Codable, Identifiable, Hashable {
    enum Typ: String, Codable {
        case mc, freitext, struktur, rechnung, muendlich

        var name: String {
            switch self {
            case .mc: "Multiple Choice"
            case .freitext: "Freitext"
            case .struktur: "Strukturformel"
            case .rechnung: "Rechenaufgabe"
            case .muendlich: "Mündliche Prüfungsfrage"
            }
        }
    }

    var id: Int
    var typ: Typ
    var text: String
    var punkte: Double
    var optionen: [String]
    var richtige: [Int]
    var musterloesung: String
    var thema: String
    /// Rechenaufgaben: Zahlenergebnis als Text (z. B. „100,2“) und Einheit.
    var zahlLoesung: String
    var einheit: String
}

/// Bewertung einer Antwort.
struct PKBewertung: Codable, Hashable {
    var punkte: Double
    var rueckmeldung: String
}

/// Eine Probeklausur mit Antworten und Auswertung.
@Model
final class Probeklausur {
    var kennung: UUID = UUID()
    var titel: String = ""
    var erstelltAm: Date = Date()
    var dauerMinuten: Int = 60
    var fragenDaten: Data?
    var antwortenDaten: Data?
    var bewertungDaten: Data?
    var abgegebenAm: Date?
    var punkteErreicht: Double = 0
    var punkteGesamt: Double = 0
    var lehrveranstaltung: Lehrveranstaltung?

    init(titel: String, dauerMinuten: Int) {
        self.titel = titel
        self.dauerMinuten = dauerMinuten
    }

    var fragen: [PKFrage] {
        get { fragenDaten.flatMap { try? JSONDecoder().decode([PKFrage].self, from: $0) } ?? [] }
        set {
            fragenDaten = try? JSONEncoder().encode(newValue)
            punkteGesamt = newValue.reduce(0) { $0 + $1.punkte }
        }
    }

    /// Frage-ID → Antwort (MC: „0,2“; sonst Text).
    var antworten: [Int: String] {
        get { antwortenDaten.flatMap { try? JSONDecoder().decode([Int: String].self, from: $0) } ?? [:] }
        set { antwortenDaten = try? JSONEncoder().encode(newValue) }
    }

    var bewertungen: [Int: PKBewertung] {
        get { bewertungDaten.flatMap { try? JSONDecoder().decode([Int: PKBewertung].self, from: $0) } ?? [:] }
        set {
            bewertungDaten = try? JSONEncoder().encode(newValue)
            punkteErreicht = newValue.values.reduce(0) { $0 + $1.punkte }
        }
    }

    var prozent: Double { punkteGesamt > 0 ? punkteErreicht / punkteGesamt * 100 : 0 }
}

/// Mit dem Fokus-Timer erfasste Lernzeit.
@Model
final class Lernsitzung {
    var start: Date = Date()
    var dauerSekunden: Double = 0
    var lehrveranstaltung: Lehrveranstaltung?

    init(start: Date, dauerSekunden: Double) {
        self.start = start
        self.dauerSekunden = dauerSekunden
    }
}
