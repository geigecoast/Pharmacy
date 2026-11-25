import Foundation
import SwiftData
import SwiftUI
import PharmaCore

// Hinweis zum Schema: Alle Eigenschaften haben Standardwerte oder sind optional, Beziehungen sind
// optional und haben eine Inverse, und es gibt keine Unique-Constraints. So bleibt das Modell
// kompatibel mit späterer Synchronisierung (CloudKit oder eigener Sync).

@Model
final class Semester {
    var nummer: Int = 0
    var titel: String = ""
    var typRaw: String = SemesterTyp.regulaer.rawValue
    var istAktuell: Bool = false
    var vorlesungsbeginn: Date?
    var vorlesungsende: Date?
    var sortierung: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Lehrveranstaltung.semester)
    var lehrveranstaltungen: [Lehrveranstaltung]? = []

    @Relationship(deleteRule: .cascade, inverse: \Frist.semester)
    var fristen: [Frist]? = []

    init(nummer: Int, titel: String, typ: SemesterTyp = .regulaer, istAktuell: Bool = false, sortierung: Int = 0) {
        self.nummer = nummer
        self.titel = titel
        self.typRaw = typ.rawValue
        self.istAktuell = istAktuell
        self.sortierung = sortierung
    }

    var typ: SemesterTyp {
        get { SemesterTyp(rawValue: typRaw) ?? .regulaer }
        set { typRaw = newValue.rawValue }
    }

    var sortierteLehrveranstaltungen: [Lehrveranstaltung] {
        (lehrveranstaltungen ?? []).sorted { ($0.sortierung, $0.lfdNr) < ($1.sortierung, $1.lfdNr) }
    }

    var sortierteFristen: [Frist] {
        (fristen ?? []).sorted { ($0.datum ?? .distantFuture) < ($1.datum ?? .distantFuture) }
    }
}

@Model
final class Lehrveranstaltung {
    var lfdNr: String = ""
    var bezeichnung: String = ""
    var kurzname: String = ""
    var lehrformRaw: String = Lehrform.v.rawValue
    var sws: String = ""
    var stoffgebieteRaw: [String] = []
    var leistungsnachweis: String = ""
    var dozenten: [String] = []
    var voraussetzungenDaten: Data?
    var anmeldepflicht: Bool = false
    var statusRaw: String = LVStatus.offen.rawValue
    /// Verbindliche Anmeldung im QIS/LSF (Beginn der 3-Semester-Frist).
    var anmeldedatum: Date?
    var hinweis: String = ""
    var notizen: String = ""
    var sortierung: Int = 0
    var lernpfadTeil: Int = 0
    var erstelltAm: Date = Date()

    var semester: Semester?
    var lernpfad: Lernpfad?

    @Relationship(deleteRule: .cascade, inverse: \Teilpruefung.lehrveranstaltung)
    var teilpruefungen: [Teilpruefung]? = []

    @Relationship(deleteRule: .nullify, inverse: \Frist.lehrveranstaltung)
    var fristen: [Frist]? = []

    @Relationship(deleteRule: .cascade, inverse: \Lerneinheit.lehrveranstaltung)
    var lerneinheiten: [Lerneinheit]? = []

    @Relationship(deleteRule: .cascade, inverse: \Dokument.lehrveranstaltung)
    var dokumente: [Dokument]? = []

    @Relationship(deleteRule: .cascade, inverse: \Karteikarte.lehrveranstaltung)
    var karteikarten: [Karteikarte]? = []

    @Relationship(deleteRule: .cascade, inverse: \Fehlereintrag.lehrveranstaltung)
    var fehlereintraege: [Fehlereintrag]? = []

    @Relationship(deleteRule: .cascade, inverse: \QuizErgebnis.lehrveranstaltung)
    var quizErgebnisse: [QuizErgebnis]? = []

    @Relationship(deleteRule: .cascade, inverse: \TutorChat.lehrveranstaltung)
    var tutorChats: [TutorChat]? = []

    init(lfdNr: String, bezeichnung: String, lehrform: Lehrform = .v, sws: String = "", sortierung: Int = 0) {
        self.lfdNr = lfdNr
        self.bezeichnung = bezeichnung
        self.lehrformRaw = lehrform.rawValue
        self.sws = sws
        self.sortierung = sortierung
    }

    var lehrform: Lehrform {
        get { Lehrform(rawValue: lehrformRaw) ?? .v }
        set { lehrformRaw = newValue.rawValue }
    }

    var status: LVStatus {
        get { LVStatus(rawValue: statusRaw) ?? .offen }
        set { statusRaw = newValue.rawValue }
    }

    var stoffgebiete: [Stoffgebiet] {
        get { stoffgebieteRaw.compactMap(Stoffgebiet.init(rawValue:)) }
        set { stoffgebieteRaw = newValue.sorted().map(\.rawValue) }
    }

    var voraussetzungen: VoraussetzungsRegel {
        get { VoraussetzungsRegel.aus(voraussetzungenDaten) }
        set { voraussetzungenDaten = newValue.alsDaten() }
    }

    var lfdNrTeile: [String] { LfdNr.teile(lfdNr) }

    /// Kurzname, falls vorhanden, sonst die volle Bezeichnung.
    var anzeigename: String { kurzname.isEmpty ? bezeichnung : kurzname }

    /// "[43]" bzw. "[43]*" bei Anmeldepflicht.
    var lfdNrAnzeige: String { LfdNr.anzeige(lfdNr) + (anmeldepflicht ? "*" : "") }

    var hauptStoffgebiet: Stoffgebiet? { stoffgebiete.first }

    var sortierteTeilpruefungen: [Teilpruefung] {
        (teilpruefungen ?? []).sorted {
            ($0.datum ?? .distantFuture, $0.sortierung) < ($1.datum ?? .distantFuture, $1.sortierung)
        }
    }

    /// Nächste noch offene Teilprüfung mit Datum ab heute.
    var naechsteTeilpruefung: Teilpruefung? {
        guard !status.istAbgeschlossen else { return nil }
        let heute = Calendar.current.startOfDay(for: Date())
        return sortierteTeilpruefungen.first { tp in
            guard let datum = tp.datum else { return false }
            return tp.ergebnis == .offen && datum >= heute
        }
    }
}

@Model
final class Teilpruefung {
    var typRaw: String = TeilpruefungTyp.schriftlicheAbschlusspruefung.rawValue
    var bezeichnung: String = ""
    var datum: Date?
    /// Ende bei mehrtägigen Terminen (z. B. Blockpraktikum).
    var ende: Date?
    var ort: String = ""
    var anmeldepflichtig: Bool = false
    var angemeldet: Bool = false
    var anmeldeschluss: Date?
    var ergebnisRaw: String = PruefungsErgebnis.offen.rawValue
    var note: String = ""
    var hinweis: String = ""
    var sortierung: Int = 0
    /// Eigener Lernaufwand in Stunden; `nil` = Standardwert der Prüfungsart.
    var lernaufwandStunden: Double?

    var lehrveranstaltung: Lehrveranstaltung?

    @Relationship(deleteRule: .cascade, inverse: \Lerneinheit.teilpruefung)
    var lerneinheiten: [Lerneinheit]? = []

    init(typ: TeilpruefungTyp, bezeichnung: String = "", anmeldepflichtig: Bool = false, hinweis: String = "", sortierung: Int = 0) {
        self.typRaw = typ.rawValue
        self.bezeichnung = bezeichnung
        self.anmeldepflichtig = anmeldepflichtig
        self.hinweis = hinweis
        self.sortierung = sortierung
    }

    var typ: TeilpruefungTyp {
        get { TeilpruefungTyp(rawValue: typRaw) ?? .schriftlicheAbschlusspruefung }
        set { typRaw = newValue.rawValue }
    }

    var ergebnis: PruefungsErgebnis {
        get { PruefungsErgebnis(rawValue: ergebnisRaw) ?? .offen }
        set { ergebnisRaw = newValue.rawValue }
    }

    var titel: String {
        bezeichnung.isEmpty ? typ.name : "\(typ.name) – \(bezeichnung)"
    }

    /// "[43] Schriftliche Abschlussprüfung"
    var titelMitLfdNr: String {
        guard let lv = lehrveranstaltung else { return titel }
        return "\(LfdNr.anzeige(lv.lfdNr)) \(titel)"
    }

    var effektiverLernaufwandStunden: Double {
        lernaufwandStunden ?? typ.standardLernaufwandStunden
    }

    var lernaufwandMinuten: Int { Int((effektiverLernaufwandStunden * 60).rounded()) }
}

/// Ein Block im Lernplan (automatisch geplant oder selbst angelegt).
@Model
final class Lerneinheit {
    var kennung: UUID = UUID()
    /// Tagesbeginn des geplanten Tages.
    var tag: Date = Date()
    var dauerMinuten: Int = 45
    var thema: String = ""
    var erledigt: Bool = false
    var erledigtAm: Date?
    /// Selbst angelegt oder verschoben – wird beim Neuplanen nicht überschrieben.
    var manuell: Bool = false

    var teilpruefung: Teilpruefung?
    var lehrveranstaltung: Lehrveranstaltung?

    init(tag: Date, dauerMinuten: Int, thema: String, manuell: Bool = false) {
        self.tag = Calendar.current.startOfDay(for: tag)
        self.dauerMinuten = dauerMinuten
        self.thema = thema
        self.manuell = manuell
    }

    var farbe: Color { lehrveranstaltung?.farbe ?? .accentColor }

    /// Liegt in der Vergangenheit und wurde nicht erledigt.
    var verpasst: Bool {
        !erledigt && tag < Calendar.current.startOfDay(for: Date())
    }

    func umschalten() {
        erledigt.toggle()
        erledigtAm = erledigt ? Date() : nil
    }
}

@Model
final class Frist {
    var titel: String = ""
    var artRaw: String = Fristart.sonstiges.rawValue
    var datum: Date?
    var hinweis: String = ""
    var erledigt: Bool = false

    var semester: Semester?
    var lehrveranstaltung: Lehrveranstaltung?

    init(titel: String, art: Fristart, datum: Date?, hinweis: String = "") {
        self.titel = titel
        self.artRaw = art.rawValue
        self.datum = datum
        self.hinweis = hinweis
    }

    var art: Fristart {
        get { Fristart(rawValue: artRaw) ?? .sonstiges }
        set { artRaw = newValue.rawValue }
    }
}

/// Verknüpft Vorlesungen, die über mehrere Semester laufen (z. B. Pharmakologie Teil 1–3).
@Model
final class Lernpfad {
    var schluessel: String = ""
    var titel: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Lehrveranstaltung.lernpfad)
    var lehrveranstaltungen: [Lehrveranstaltung]? = []

    init(schluessel: String, titel: String) {
        self.schluessel = schluessel
        self.titel = titel
    }

    var sortierteTeile: [Lehrveranstaltung] {
        (lehrveranstaltungen ?? []).sorted { $0.lernpfadTeil < $1.lernpfadTeil }
    }
}

/// Vom Nutzer änderbare Zuordnung Stoffgebiet → Staatsexamen-Fächer.
@Model
final class StoffgebietZuordnung {
    var code: String = ""
    var faecherRaw: [String] = []

    init(stoffgebiet: Stoffgebiet) {
        self.code = stoffgebiet.rawValue
        self.faecherRaw = stoffgebiet.standardStaatsexamenFaecher.map(\.rawValue)
    }

    var stoffgebiet: Stoffgebiet? { Stoffgebiet(rawValue: code) }

    var faecher: [StaatsexamenFach] {
        get { faecherRaw.compactMap(StaatsexamenFach.init(rawValue:)) }
        set { faecherRaw = newValue.map(\.rawValue) }
    }
}

enum Datenschema {
    static let modelle: [any PersistentModel.Type] = [
        Semester.self,
        Lehrveranstaltung.self,
        Teilpruefung.self,
        Frist.self,
        Lernpfad.self,
        StoffgebietZuordnung.self,
        Lerneinheit.self,
        Dokument.self,
        Seite.self,
        Markierung.self,
        Zeichnung.self,
        Karteikarte.self,
        Wiederholung.self,
        Fehlereintrag.self,
        QuizErgebnis.self,
        TutorChat.self,
        TutorNachricht.self,
        Zusammenfassung.self,
    ]
}
