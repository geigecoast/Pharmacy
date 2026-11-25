import Foundation

/// Lernserie, Punkte, Stufen und Abzeichen.
public enum Gamification {

    // MARK: Lernserie

    public struct Serie: Equatable, Sendable {
        /// Aufeinanderfolgende Tage mit erreichtem Tagesziel (heute zählt erst, wenn erreicht).
        public var aktuell: Int
        public var laengste: Int
        public var heuteErreicht: Bool
        /// Ruhetag in der laufenden Serie in dieser Woche bereits verbraucht.
        public var ruhetagDieseWocheGenutzt: Bool

        public init(aktuell: Int, laengste: Int, heuteErreicht: Bool, ruhetagDieseWocheGenutzt: Bool) {
            self.aktuell = aktuell
            self.laengste = laengste
            self.heuteErreicht = heuteErreicht
            self.ruhetagDieseWocheGenutzt = ruhetagDieseWocheGenutzt
        }
    }

    /// Berechnet die Lernserie.
    /// - Ein Tag zählt, wenn mindestens `tagesziel` Minuten gelernt wurden.
    /// - Mit `ruhetagErlaubt` darf pro Kalenderwoche ein einzelner Tag fehlen, ohne dass die Serie reißt
    ///   (er zählt nicht mit; zwei Fehltage hintereinander beenden die Serie).
    /// - Heute ist noch offen: Ist das Ziel heute nicht erreicht, reißt die Serie nicht.
    public static func serie(minutenProTag: [Date: Double], tagesziel: Int, ruhetagErlaubt: Bool,
                             heute: Date, kalender: Calendar) -> Serie {
        let ziel = Double(max(tagesziel, 1))
        let heuteStart = kalender.startOfDay(for: heute)
        var erreicht: Set<Date> = []
        for (tag, minuten) in minutenProTag where minuten >= ziel {
            erreicht.insert(kalender.startOfDay(for: tag))
        }
        let heuteErreicht = erreicht.contains(heuteStart)
        guard let erster = erreicht.filter({ $0 <= heuteStart }).min() else {
            return Serie(aktuell: 0, laengste: 0, heuteErreicht: false, ruhetagDieseWocheGenutzt: false)
        }

        func woche(_ tag: Date) -> Date { kalender.dateInterval(of: .weekOfYear, for: tag)?.start ?? tag }

        var lauf = 0
        var laengste = 0
        var genutzteWochen: Set<Date> = []
        var vorherFehltag = false
        var tag = erster
        while tag <= heuteStart {
            if erreicht.contains(tag) {
                lauf += 1
                vorherFehltag = false
            } else if tag == heuteStart {
                // Heute ist noch nicht vorbei.
                break
            } else if ruhetagErlaubt, lauf > 0, !vorherFehltag, !genutzteWochen.contains(woche(tag)) {
                genutzteWochen.insert(woche(tag))
                vorherFehltag = true
            } else {
                lauf = 0
                genutzteWochen = []
                vorherFehltag = false
            }
            laengste = max(laengste, lauf)
            guard let naechster = kalender.date(byAdding: .day, value: 1, to: tag) else { break }
            tag = naechster
        }
        return Serie(aktuell: lauf, laengste: laengste, heuteErreicht: heuteErreicht,
                     ruhetagDieseWocheGenutzt: lauf > 0 && genutzteWochen.contains(woche(heuteStart)))
    }

    /// Anzahl der Kalenderwochen (bis einschließlich der laufenden), in denen das Wochenziel erreicht wurde.
    public static func wochenMitZiel(minutenProTag: [Date: Double], wochenziel: Int, kalender: Calendar) -> Int {
        guard wochenziel > 0 else { return 0 }
        var summen: [Date: Double] = [:]
        for (tag, minuten) in minutenProTag {
            let start = kalender.dateInterval(of: .weekOfYear, for: tag)?.start ?? tag
            summen[start, default: 0] += minuten
        }
        return summen.values.filter { $0 >= Double(wochenziel) }.count
    }

    // MARK: Punkte und Stufen

    public struct Aktivitaet: Equatable, Sendable {
        public var lernminuten: Int
        public var wiederholungen: Int
        public var quizRunden: Int
        public var probeklausuren: Int
        public var fehlerVerstanden: Int
        public var teilpruefungenBestanden: Int

        public init(lernminuten: Int = 0, wiederholungen: Int = 0, quizRunden: Int = 0, probeklausuren: Int = 0,
                    fehlerVerstanden: Int = 0, teilpruefungenBestanden: Int = 0) {
            self.lernminuten = lernminuten
            self.wiederholungen = wiederholungen
            self.quizRunden = quizRunden
            self.probeklausuren = probeklausuren
            self.fehlerVerstanden = fehlerVerstanden
            self.teilpruefungenBestanden = teilpruefungenBestanden
        }
    }

    /// Wie Punkte entstehen (für die Erklärung in der App).
    public static let punkteRegeln: [(String, Int)] = [
        ("Je Lernminute", 1),
        ("Je Kartenwiederholung", 2),
        ("Je Quizrunde", 15),
        ("Je abgegebener Probeklausur", 60),
        ("Je verstandenem Fehler", 10),
        ("Je bestandener Teilprüfung", 250),
    ]

    public static func punkte(_ a: Aktivitaet) -> Int {
        a.lernminuten + 2 * a.wiederholungen + 15 * a.quizRunden + 60 * a.probeklausuren
            + 10 * a.fehlerVerstanden + 250 * a.teilpruefungenBestanden
    }

    public static let stufentitel = [
        "Einsteiger", "Rezeptur", "Defektur", "Analytik", "Galenik",
        "Drogenkunde", "Pharmakologie", "Klinische Pharmazie", "Examensreif", "Approbationsreif",
    ]

    public struct Stufe: Equatable, Sendable {
        public var nummer: Int
        public var titel: String
        public var punkteAb: Int
        /// nil auf der höchsten Stufe.
        public var naechsteAb: Int?
        /// Fortschritt zur nächsten Stufe 0…1.
        public var fortschritt: Double
    }

    /// Schwelle der Stufe n (1-basiert): 250 · (n−1) · n / 2 → 0, 250, 750, 1500, 2500, …
    public static func schwelle(_ stufe: Int) -> Int { 250 * (stufe - 1) * stufe / 2 }

    public static func stufe(punkte: Int) -> Stufe {
        var nummer = 1
        while nummer < stufentitel.count, punkte >= schwelle(nummer + 1) { nummer += 1 }
        let ab = schwelle(nummer)
        guard nummer < stufentitel.count else {
            return Stufe(nummer: nummer, titel: stufentitel[nummer - 1], punkteAb: ab, naechsteAb: nil, fortschritt: 1)
        }
        let naechste = schwelle(nummer + 1)
        let fortschritt = Double(max(0, punkte - ab)) / Double(naechste - ab)
        return Stufe(nummer: nummer, titel: stufentitel[nummer - 1], punkteAb: ab, naechsteAb: naechste, fortschritt: min(fortschritt, 1))
    }

    // MARK: Abzeichen

    public struct Statistik: Equatable, Sendable {
        public var aktivitaet = Aktivitaet()
        public var laengsteSerie = 0
        public var kartenErstellt = 0
        public var tutorFragen = 0
        public var besteProbeklausurProzent: Double?
        public var perfektesQuiz = false
        public var fruehSitzung = false
        public var spaetSitzung = false
        public var semesterKomplett = false
        public var wochenMitZiel = 0

        public init() {}
    }

    public enum Abzeichen: String, CaseIterable, Identifiable, Sendable {
        case ersteWiederholung, wiederholungen500, wiederholungen2500
        case serie7, serie30, serie100
        case stunden10, stunden100
        case wochenziel4
        case ersteProbeklausur, probeklausur90, quizPerfekt
        case fehler25, karten100, tutor50
        case fruehaufsteher, nachteule
        case teilpruefung, semester

        public var id: String { rawValue }

        public var titel: String {
            switch self {
            case .ersteWiederholung: "Erste Karte"
            case .wiederholungen500: "Karteikasten"
            case .wiederholungen2500: "Gedächtnisprofi"
            case .serie7: "Eine Woche dran"
            case .serie30: "Monatsserie"
            case .serie100: "Hundert Tage"
            case .stunden10: "Zehn Stunden"
            case .stunden100: "Hundert Stunden"
            case .wochenziel4: "Im Plan"
            case .ersteProbeklausur: "Generalprobe"
            case .probeklausur90: "Bestnote"
            case .quizPerfekt: "Fehlerfrei"
            case .fehler25: "Aus Fehlern gelernt"
            case .karten100: "Kartenschmiede"
            case .tutor50: "Neugierig"
            case .fruehaufsteher: "Frühaufsteher"
            case .nachteule: "Nachteule"
            case .teilpruefung: "Bestanden"
            case .semester: "Semester geschafft"
            }
        }

        public var beschreibung: String {
            switch self {
            case .ersteWiederholung: "Die erste Karteikarte wiederholt."
            case .wiederholungen500: "500 Kartenwiederholungen."
            case .wiederholungen2500: "2.500 Kartenwiederholungen."
            case .serie7: "Sieben Tage Lernserie."
            case .serie30: "30 Tage Lernserie."
            case .serie100: "100 Tage Lernserie."
            case .stunden10: "Zehn Stunden Lernzeit insgesamt."
            case .stunden100: "Hundert Stunden Lernzeit insgesamt."
            case .wochenziel4: "In vier Wochen das Wochenziel erreicht."
            case .ersteProbeklausur: "Die erste Probeklausur abgegeben."
            case .probeklausur90: "Eine Probeklausur mit mindestens 90 % der Punkte."
            case .quizPerfekt: "Ein Quiz mit mindestens zehn Fragen ohne Fehler."
            case .fehler25: "25 Einträge im Fehlerjournal als verstanden markiert."
            case .karten100: "100 eigene Karteikarten erstellt."
            case .tutor50: "50 Fragen an den Tutor gestellt."
            case .fruehaufsteher: "Eine Fokus-Sitzung vor 7 Uhr begonnen."
            case .nachteule: "Eine Fokus-Sitzung nach 23 Uhr begonnen."
            case .teilpruefung: "Die erste Teilprüfung bestanden."
            case .semester: "Alle Lehrveranstaltungen eines Semesters bestanden."
            }
        }

        /// SF-Symbol.
        public var symbol: String {
            switch self {
            case .ersteWiederholung, .wiederholungen500, .wiederholungen2500: "rectangle.stack"
            case .serie7, .serie30, .serie100: "flame"
            case .stunden10, .stunden100: "clock"
            case .wochenziel4: "calendar"
            case .ersteProbeklausur, .probeklausur90: "doc.text"
            case .quizPerfekt: "checkmark.seal"
            case .fehler25: "exclamationmark.bubble"
            case .karten100: "square.and.pencil"
            case .tutor50: "bubble.left.and.text.bubble.right"
            case .fruehaufsteher: "sunrise"
            case .nachteule: "moon.stars"
            case .teilpruefung: "graduationcap"
            case .semester: "laurel.leading"
            }
        }

        /// Fortschritt als (erreicht, Ziel).
        public func fortschritt(_ s: Statistik) -> (wert: Int, ziel: Int) {
            func ja(_ b: Bool) -> (Int, Int) { (b ? 1 : 0, 1) }
            switch self {
            case .ersteWiederholung: return (min(s.aktivitaet.wiederholungen, 1), 1)
            case .wiederholungen500: return (s.aktivitaet.wiederholungen, 500)
            case .wiederholungen2500: return (s.aktivitaet.wiederholungen, 2500)
            case .serie7: return (s.laengsteSerie, 7)
            case .serie30: return (s.laengsteSerie, 30)
            case .serie100: return (s.laengsteSerie, 100)
            case .stunden10: return (s.aktivitaet.lernminuten / 60, 10)
            case .stunden100: return (s.aktivitaet.lernminuten / 60, 100)
            case .wochenziel4: return (s.wochenMitZiel, 4)
            case .ersteProbeklausur: return (min(s.aktivitaet.probeklausuren, 1), 1)
            case .probeklausur90: return ja((s.besteProbeklausurProzent ?? 0) >= 90)
            case .quizPerfekt: return ja(s.perfektesQuiz)
            case .fehler25: return (s.aktivitaet.fehlerVerstanden, 25)
            case .karten100: return (s.kartenErstellt, 100)
            case .tutor50: return (s.tutorFragen, 50)
            case .fruehaufsteher: return ja(s.fruehSitzung)
            case .nachteule: return ja(s.spaetSitzung)
            case .teilpruefung: return (min(s.aktivitaet.teilpruefungenBestanden, 1), 1)
            case .semester: return ja(s.semesterKomplett)
            }
        }

        public func erreicht(_ s: Statistik) -> Bool {
            let f = fortschritt(s)
            return f.wert >= f.ziel
        }
    }

    public static func erreichteAbzeichen(_ s: Statistik) -> [Abzeichen] {
        Abzeichen.allCases.filter { $0.erreicht(s) }
    }
}
