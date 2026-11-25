import Foundation
import SwiftData
import PharmaCore

/// Karteikarte mit FSRS-Lernstand.
@Model
final class Karteikarte {
    var kennung: UUID = UUID()
    var typRaw: String = KartenTyp.frageAntwort.rawValue
    /// Frage bzw. Lückentext mit {{…}} bzw. Bildunterschrift.
    var vorderseite: String = ""
    /// Antwort bzw. Zusatzinformation.
    var rueckseite: String = ""
    var optionen: [String] = []
    var richtigeOptionen: [Int] = []
    @Attribute(.externalStorage) var bildDaten: Data?
    /// Bild-Okklusion: Masken als relative Rechtecke (x, y, Breite, Höhe; 0…1).
    var maskenWerte: [Double] = []
    var thema: String = ""
    /// Prüfungsrelevant: wird beim Lernen und im Schnellquiz bevorzugt.
    var prioritaet: Bool = false
    var istIMPP: Bool = false
    var quelleRaw: String = KartenQuelle.manuell.rawValue
    var markierungKennung: UUID?
    var seitenIndex: Int?
    var erstelltAm: Date = Date()

    // FSRS
    var zustandRaw: Int = KartenZustand.neu.rawValue
    var stabilitaet: Double = 0
    var schwierigkeit: Double = 0
    var faellig: Date = Date()
    var letzteWiederholung: Date?
    var wiederholungen: Int = 0
    var fehlschlaege: Int = 0
    var intervallTage: Int = 0

    var lehrveranstaltung: Lehrveranstaltung?
    var dokument: Dokument?

    @Relationship(deleteRule: .cascade, inverse: \Wiederholung.karte)
    var protokoll: [Wiederholung]? = []

    @Relationship(deleteRule: .nullify, inverse: \Fehlereintrag.karte)
    var fehlereintraege: [Fehlereintrag]? = []

    init(typ: KartenTyp, vorderseite: String = "", rueckseite: String = "", thema: String = "") {
        self.typRaw = typ.rawValue
        self.vorderseite = vorderseite
        self.rueckseite = rueckseite
        self.thema = thema
    }

    var typ: KartenTyp {
        get { KartenTyp(rawValue: typRaw) ?? .frageAntwort }
        set { typRaw = newValue.rawValue }
    }

    var quelle: KartenQuelle {
        get { KartenQuelle(rawValue: quelleRaw) ?? .manuell }
        set { quelleRaw = newValue.rawValue }
    }

    var stand: KartenStand {
        get {
            KartenStand(zustand: KartenZustand(rawValue: zustandRaw) ?? .neu, stabilitaet: stabilitaet,
                        schwierigkeit: schwierigkeit, faellig: faellig, letzteWiederholung: letzteWiederholung,
                        wiederholungen: wiederholungen, fehlschlaege: fehlschlaege, intervallTage: intervallTage)
        }
        set {
            zustandRaw = newValue.zustand.rawValue
            stabilitaet = newValue.stabilitaet
            schwierigkeit = newValue.schwierigkeit
            faellig = newValue.faellig
            letzteWiederholung = newValue.letzteWiederholung
            wiederholungen = newValue.wiederholungen
            fehlschlaege = newValue.fehlschlaege
            intervallTage = newValue.intervallTage
        }
    }

    var masken: [CGRect] {
        get {
            stride(from: 0, to: maskenWerte.count - 3, by: 4).map {
                CGRect(x: maskenWerte[$0], y: maskenWerte[$0 + 1], width: maskenWerte[$0 + 2], height: maskenWerte[$0 + 3])
            }
        }
        set {
            maskenWerte = newValue.flatMap { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] }
        }
    }

    func istFaellig(_ jetzt: Date = Date()) -> Bool { faellig <= jetzt }

    /// Frage als Klartext (für Listen, Fehlerjournal, Export).
    var frageText: String {
        switch typ {
        case .lueckentext: Lueckentext.frage(vorderseite)
        case .bildOkklusion: vorderseite.isEmpty ? "Bild-Okklusion" : vorderseite
        default: vorderseite
        }
    }

    /// Antwort als Klartext.
    var antwortText: String {
        switch typ {
        case .lueckentext:
            let luecken = Lueckentext.luecken(vorderseite).joined(separator: ", ")
            return rueckseite.isEmpty ? luecken : "\(luecken) – \(rueckseite)"
        case .multipleChoice:
            let richtig = richtigeOptionen.sorted().compactMap { optionen.indices.contains($0) ? "\(Self.buchstabe($0)) \(optionen[$0])" : nil }
            return ([richtig.joined(separator: "; ")] + (rueckseite.isEmpty ? [] : [rueckseite])).joined(separator: " – ")
        default:
            return rueckseite
        }
    }

    static func buchstabe(_ index: Int) -> String {
        let buchstaben = Array("ABCDEFGHIJ")
        return index < buchstaben.count ? "\(buchstaben[index])" : "\(index + 1)"
    }

    /// Ist die Karte vollständig genug zum Lernen?
    var istGueltig: Bool {
        switch typ {
        case .frageAntwort: !vorderseite.trimmingCharacters(in: .whitespaces).isEmpty && !rueckseite.trimmingCharacters(in: .whitespaces).isEmpty
        case .lueckentext: Lueckentext.hatLuecke(vorderseite)
        case .multipleChoice: optionen.filter { !$0.isEmpty }.count >= 2 && !richtigeOptionen.isEmpty
        case .bildOkklusion: bildDaten != nil && !maskenWerte.isEmpty
        }
    }
}

/// Eine Bewertung einer Karte.
@Model
final class Wiederholung {
    var datum: Date = Date()
    var bewertungRaw: Int = Bewertung.gut.rawValue
    var dauerSekunden: Double = 0
    var intervallTage: Int = 0
    var karte: Karteikarte?

    init(datum: Date, bewertung: Bewertung, dauerSekunden: Double, intervallTage: Int) {
        self.datum = datum
        self.bewertungRaw = bewertung.rawValue
        self.dauerSekunden = dauerSekunden
        self.intervallTage = intervallTage
    }

    var bewertung: Bewertung { Bewertung(rawValue: bewertungRaw) ?? .gut }
}

/// Fehlerjournal: jede falsche Antwort landet hier.
@Model
final class Fehlereintrag {
    var datum: Date = Date()
    var frage: String = ""
    var deineAntwort: String = ""
    var richtigeAntwort: String = ""
    var thema: String = ""
    /// „Wiederholung“, „Schnellquiz“, …
    var herkunft: String = ""
    var verstanden: Bool = false
    var karte: Karteikarte?
    var lehrveranstaltung: Lehrveranstaltung?

    init(frage: String, deineAntwort: String, richtigeAntwort: String, thema: String, herkunft: String) {
        self.frage = frage
        self.deineAntwort = deineAntwort
        self.richtigeAntwort = richtigeAntwort
        self.thema = thema
        self.herkunft = herkunft
    }
}

/// Ergebnis eines Quiz (für Analysen und Gamification).
@Model
final class QuizErgebnis {
    var datum: Date = Date()
    var modusRaw: String = QuizModus.schnellquiz.rawValue
    var fragen: Int = 0
    var richtig: Int = 0
    var dauerSekunden: Double = 0
    var lehrveranstaltung: Lehrveranstaltung?

    init(modus: QuizModus, fragen: Int, richtig: Int, dauerSekunden: Double) {
        self.modusRaw = modus.rawValue
        self.fragen = fragen
        self.richtig = richtig
        self.dauerSekunden = dauerSekunden
    }

    var modus: QuizModus { QuizModus(rawValue: modusRaw) ?? .schnellquiz }
}
