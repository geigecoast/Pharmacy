import Foundation

// MARK: - Datentypen für das vorgeladene Curriculum

public struct CurriculumTeilpruefung: Sendable, Hashable {
    public var typ: TeilpruefungTyp
    public var bezeichnung: String
    public var anmeldepflichtig: Bool
    public var hinweis: String

    public init(_ typ: TeilpruefungTyp, _ bezeichnung: String = "", anmeldepflichtig: Bool = false, hinweis: String = "") {
        self.typ = typ
        self.bezeichnung = bezeichnung
        self.anmeldepflichtig = anmeldepflichtig
        self.hinweis = hinweis
    }
}

public struct CurriculumKurs: Sendable, Hashable {
    public var lfdNr: String
    public var bezeichnung: String
    public var lehrform: Lehrform
    public var sws: String
    public var stoffgebiete: [Stoffgebiet]
    public var leistungsnachweis: String
    public var dozenten: [String]
    public var voraussetzungen: VoraussetzungsRegel
    public var anmeldepflicht: Bool
    public var status: LVStatus
    public var hinweis: String
    public var teilpruefungen: [CurriculumTeilpruefung]
    public var lernpfad: String?
    public var lernpfadTeil: Int

    public init(
        _ lfdNr: String,
        _ bezeichnung: String,
        lehrform: Lehrform,
        sws: String,
        stoffgebiete: [Stoffgebiet],
        ln: String = "",
        dozenten: [String] = [],
        voraussetzungen: VoraussetzungsRegel = .keine,
        anmeldepflicht: Bool = false,
        status: LVStatus = .offen,
        hinweis: String = "",
        teilpruefungen: [CurriculumTeilpruefung] = [],
        lernpfad: String? = nil,
        lernpfadTeil: Int = 0
    ) {
        self.lfdNr = lfdNr
        self.bezeichnung = bezeichnung
        self.lehrform = lehrform
        self.sws = sws
        self.stoffgebiete = stoffgebiete
        self.leistungsnachweis = ln
        self.dozenten = dozenten
        self.voraussetzungen = voraussetzungen
        self.anmeldepflicht = anmeldepflicht
        self.status = status
        self.hinweis = hinweis
        self.teilpruefungen = teilpruefungen
        self.lernpfad = lernpfad
        self.lernpfadTeil = lernpfadTeil
    }
}

public struct CurriculumFrist: Sendable, Hashable {
    public var titel: String
    public var art: Fristart
    public var datum: Date?
    public var hinweis: String
    public var lfdNr: String?

    public init(_ titel: String, art: Fristart, datum: Date?, hinweis: String = "", lfdNr: String? = nil) {
        self.titel = titel
        self.art = art
        self.datum = datum
        self.hinweis = hinweis
        self.lfdNr = lfdNr
    }
}

public struct CurriculumSemester: Sendable, Hashable {
    public var nummer: Int
    public var titel: String
    public var typ: SemesterTyp
    public var istAktuell: Bool
    public var vorlesungsbeginn: Date?
    public var vorlesungsende: Date?
    public var kurse: [CurriculumKurs]
    public var fristen: [CurriculumFrist]

    public init(
        nummer: Int,
        titel: String,
        typ: SemesterTyp = .regulaer,
        istAktuell: Bool = false,
        vorlesungsbeginn: Date? = nil,
        vorlesungsende: Date? = nil,
        kurse: [CurriculumKurs] = [],
        fristen: [CurriculumFrist] = []
    ) {
        self.nummer = nummer
        self.titel = titel
        self.typ = typ
        self.istAktuell = istAktuell
        self.vorlesungsbeginn = vorlesungsbeginn
        self.vorlesungsende = vorlesungsende
        self.kurse = kurse
        self.fristen = fristen
    }
}

public struct CurriculumLernpfad: Sendable, Hashable {
    public var schluessel: String
    public var titel: String
}

// MARK: - Studienverlaufsplan Pharmazie, Goethe-Universität Frankfurt (FB 14)

public enum Curriculum {
    /// Wird erhöht, wenn sich die vorgeladenen Daten ändern.
    public static let version = 1

    public static let nummerStaatsexamen = 100

    /// Datum in deutscher Zeitzone.
    public static func datum(_ jahr: Int, _ monat: Int, _ tag: Int) -> Date {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return kalender.date(from: DateComponents(year: jahr, month: monat, day: tag, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    public static let lernpfade: [CurriculumLernpfad] = [
        CurriculumLernpfad(schluessel: "medchem", titel: "Pharmazeutische/Medizinische Chemie III"),
        CurriculumLernpfad(schluessel: "pharmakologie", titel: "Pharmakologie und Toxikologie"),
        CurriculumLernpfad(schluessel: "pharmtech", titel: "Pharmazeutische Technologie"),
        CurriculumLernpfad(schluessel: "pharmbio", titel: "Pharmazeutische Biologie"),
        CurriculumLernpfad(schluessel: "krankheitslehre", titel: "Krankheitslehre und Pharmakotherapie"),
        CurriculumLernpfad(schluessel: "biochemie", titel: "Biochemie und Molekularbiologie"),
    ]

    // Häufig verwendete Regeln
    static let ph1: VoraussetzungsRegel = .zulassung("Ph1")
    static let ph1Und43oder44: VoraussetzungsRegel = .alle([ph1, .eine([.kurs("43"), .kurs("44")])])

    // Vorlesungszeiten: Näherungswerte, bitte in der App prüfen und anpassen.
    static let semester5 = (datum(2026, 10, 19), datum(2027, 2, 12))
    static let semester6 = (datum(2027, 4, 19), datum(2027, 7, 23))
    static let semester7 = (datum(2027, 10, 18), datum(2028, 2, 11))
    static let semester8 = (datum(2028, 4, 18), datum(2028, 7, 21))

    public static let semester: [CurriculumSemester] = [
        // MARK: 5. Semester
        CurriculumSemester(
            nummer: 5, titel: "5. Semester", istAktuell: true,
            vorlesungsbeginn: semester5.0, vorlesungsende: semester5.1,
            kurse: [
                CurriculumKurs("38", "Pharmazeutische/Medizinische Chemie III Teil 1",
                               lehrform: .v, sws: "2", stoffgebiete: [.h],
                               dozenten: ["Prof. Knapp", "Prof. Kaiser", "Prof. Proschak"],
                               lernpfad: "medchem", lernpfadTeil: 1),
                CurriculumKurs("39+42", "Pharmakologie und Toxikologie inkl. Pathophysiologie/Pathobiochemie Teil 1",
                               lehrform: .v, sws: "2+1", stoffgebiete: [.i, .e],
                               dozenten: ["Prof. Schmidtko"],
                               lernpfad: "pharmakologie", lernpfadTeil: 1),
                CurriculumKurs("40", "Biochemie und Molekularbiologie Teil 1",
                               lehrform: .v, sws: "1,5", stoffgebiete: [.e],
                               dozenten: ["Dr. Sorg"],
                               hinweis: "2. Semesterhälfte. Die Eingangsprüfung ist Voraussetzung für [53].",
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.schriftlicheEingangspruefung, "Biochemie (Klausur)",
                                                          anmeldepflichtig: true,
                                                          hinweis: "Voraussetzung für [53]")
                               ],
                               lernpfad: "biochemie", lernpfadTeil: 1),
                CurriculumKurs("41", "Immunologie, Impfstoffe und Sera",
                               lehrform: .v, sws: "1", stoffgebiete: [.g],
                               dozenten: ["Prof. Marschalek"]),
                CurriculumKurs("43", "Arzneistoffanalytik (Arzneibücher, Qualitätskontrolle/-sicherung, Normen Medizinprodukte)",
                               lehrform: .ps, sws: "8", stoffgebiete: [.h], ln: "H1",
                               dozenten: ["Prof. Kaiser", "Dr. Kahnt"],
                               voraussetzungen: ph1, anmeldepflicht: true, status: .offen,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.muendlicheEingangspruefung, "Arzneibuchanalytik", anmeldepflichtig: true,
                                                          hinweis: "Voraussetzung für den Praktischen Teil"),
                                   CurriculumTeilpruefung(.praktischerTeil, "Blockpraktikum (1. Semesterhälfte)"),
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, anmeldepflichtig: true),
                               ]),
                CurriculumKurs("44", "Arzneimittelanalytik, Drug-Monitoring, toxikologische und umweltrelevante Untersuchungen Teil 1",
                               lehrform: .ps, sws: "10", stoffgebiete: [.h], ln: "H2a",
                               dozenten: ["Prof. Proschak", "Dr. Hofmann"],
                               voraussetzungen: ph1, anmeldepflicht: true, status: .bestanden,
                               hinweis: "Bestanden – Unterlagen bleiben als Archiv und Staatsexamen-Material erhalten."),
                CurriculumKurs("62", "Qualitätssicherung bei der Herstellung und Prüfung von Arzneimitteln",
                               lehrform: .s, sws: "1", stoffgebiete: [.f], ln: "F1b",
                               dozenten: ["Prof. Schiller"],
                               anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, anmeldepflichtig: true)
                               ]),
            ]
        ),

        // MARK: 6. Semester
        CurriculumSemester(
            nummer: 6, titel: "6. Semester",
            vorlesungsbeginn: semester6.0, vorlesungsende: semester6.1,
            kurse: [
                CurriculumKurs("45", "Grundlagen der Klinischen Chemie und der Pathobiochemie",
                               lehrform: .blockV, sws: "1", stoffgebiete: [.e],
                               dozenten: ["Dr. Dr. Klosson"]),
                CurriculumKurs("46", "Biochemie und Molekularbiologie Teil 2",
                               lehrform: .v, sws: "1,5", stoffgebiete: [.e],
                               dozenten: ["Prof. Knapp"],
                               hinweis: "1. Semesterhälfte",
                               lernpfad: "biochemie", lernpfadTeil: 2),
                CurriculumKurs("47", "Pharmazeutische Biologie Teil 1: Biogene Arzneistoffe, Rekombinante Wirkstoffe, Biotechnologie",
                               lehrform: .v, sws: "2+1+1", stoffgebiete: [.g],
                               dozenten: ["Prof. Marschalek", "Prof. Crüsemann"],
                               lernpfad: "pharmbio", lernpfadTeil: 1),
                CurriculumKurs("48", "Pharmazeutische/Medizinische Chemie III Teil 2",
                               lehrform: .v, sws: "2", stoffgebiete: [.h],
                               lernpfad: "medchem", lernpfadTeil: 2),
                CurriculumKurs("49", "Pharmazeutische Technologie Teil 1 (Halbfeste Arzneiformen, Medizinprodukte)",
                               lehrform: .v, sws: "3", stoffgebiete: [.f],
                               dozenten: ["Prof. Windbergs"],
                               lernpfad: "pharmtech", lernpfadTeil: 1),
                CurriculumKurs("50+51", "Pharmakologie und Toxikologie Teil 2",
                               lehrform: .v, sws: "2+1", stoffgebiete: [.i, .e],
                               dozenten: ["Prof. Schmidtko"],
                               lernpfad: "pharmakologie", lernpfadTeil: 2),
                CurriculumKurs("61", "Biopharmazie inkl. arzneiformenbezogener Pharmakokinetik",
                               lehrform: .v, sws: "2", stoffgebiete: [.f],
                               dozenten: ["Prof. Windbergs"]),
                CurriculumKurs("63", "Biopharmazie (Seminar + Übungen)",
                               lehrform: .su, sws: "2", stoffgebiete: [.f], ln: "F2",
                               dozenten: ["Prof. Windbergs", "Dr. Vogel-Kindgen", "Dr. Gier"],
                               voraussetzungen: ph1Und43oder44, anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, anmeldepflichtig: true)
                               ]),
                CurriculumKurs("52", "Pharmakologisch-toxikologischer Demonstrationskurs",
                               lehrform: .s, sws: "6", stoffgebiete: [.i], ln: "I3",
                               dozenten: ["Prof. Schmidtko", "Dr. Metzner"],
                               voraussetzungen: ph1Und43oder44, anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.praktischerTeil),
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, anmeldepflichtig: true),
                               ]),
                CurriculumKurs("53", "Biochemische Untersuchungsmethoden inkl. Klinische Chemie",
                               lehrform: .ps, sws: "7+1", stoffgebiete: [.e], ln: "E",
                               dozenten: ["Prof. Knapp", "Dr. Sorg", "Dr. Dr. Klosson"],
                               voraussetzungen: .alle([
                                   ph1,
                                   .eine([.kurs("43"), .kurs("44")]),
                                   .teilpruefung(lfdNr: "40", typ: .schriftlicheEingangspruefung),
                               ]),
                               anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.praktischerTeil, "Biochemie"),
                                   CurriculumTeilpruefung(.abschlusskolloquium, "Biochemie"),
                                   CurriculumTeilpruefung(.praktischerTeil, "Klinische Chemie"),
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, "Biochemie", anmeldepflichtig: true),
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, "Klinische Chemie", anmeldepflichtig: true),
                               ]),
            ],
            fristen: [
                CurriculumFrist("Wahlpflichtfach [76]: Platzvergabe", art: .platzvergabe,
                                datum: datum(2027, 6, 1),
                                hinweis: "Mitte des 6. Semesters: „Vorstellung der Arbeitskreise“ und Prioritätenliste. Externe Plätze müssen bis dahin organisiert sein. Datum ist ein Näherungswert – bitte prüfen.",
                                lfdNr: "76")
            ]
        ),

        // MARK: 7. Semester
        CurriculumSemester(
            nummer: 7, titel: "7. Semester",
            vorlesungsbeginn: semester7.0, vorlesungsende: semester7.1,
            kurse: [
                CurriculumKurs("54+55", "Pharmakologie und Toxikologie Teil 3",
                               lehrform: .v, sws: "2+1", stoffgebiete: [.i, .e],
                               dozenten: ["Prof. Schmidtko"],
                               lernpfad: "pharmakologie", lernpfadTeil: 3),
                CurriculumKurs("56+57", "Krankheitslehre Teil 1 + Pharmakotherapie Teil 1",
                               lehrform: .vu, sws: "3+1", stoffgebiete: [.i], ln: "I1",
                               dozenten: ["Prof. Oppermann"],
                               hinweis: "Regelmäßige und aktive Teilnahme erforderlich.",
                               lernpfad: "krankheitslehre", lernpfadTeil: 1),
                CurriculumKurs("58", "Pharmazeutische Technologie Teil 2 (Flüssige Arzneiformen)",
                               lehrform: .v, sws: "2", stoffgebiete: [.f],
                               dozenten: ["Prof. Windbergs"],
                               lernpfad: "pharmtech", lernpfadTeil: 2),
                CurriculumKurs("59", "Pharmazeutische Biologie Teil 2",
                               lehrform: .v, sws: "2+1+1", stoffgebiete: [.g],
                               lernpfad: "pharmbio", lernpfadTeil: 2),
                CurriculumKurs("60", "Pharmazeutische/Medizinische Chemie III Teil 3",
                               lehrform: .v, sws: "2", stoffgebiete: [.h],
                               lernpfad: "medchem", lernpfadTeil: 3),
                CurriculumKurs("64", "Pharmazeutische Technologie inkl. Medizinprodukte",
                               lehrform: .ps, sws: "14", stoffgebiete: [.f], ln: "F1a",
                               dozenten: ["Prof. Windbergs", "Dr. Planz"],
                               voraussetzungen: .alle([.kurs("43"), .kurs("44"), .kurs("53"), .teilnahme("52")]),
                               anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.praktischerTeil),
                                   CurriculumTeilpruefung(.muendlicheAbschlusspruefung, anmeldepflichtig: true),
                               ]),
                CurriculumKurs("65", "Pharmazeutische Biologie III (Biologische/phytochemische Untersuchungen)",
                               lehrform: .ps, sws: "6", stoffgebiete: [.g], ln: "G1",
                               dozenten: ["Prof. Bachmeier", "Dr. Meyer"],
                               anmeldepflicht: true,
                               hinweis: "Blockkurs in den ersten 2 Wochen der vorlesungsfreien Zeit.",
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.praktischerTeil, "Blockkurs"),
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, anmeldepflichtig: true),
                               ]),
            ]
        ),

        // MARK: 8. Semester
        CurriculumSemester(
            nummer: 8, titel: "8. Semester",
            vorlesungsbeginn: semester8.0, vorlesungsende: semester8.1,
            kurse: [
                CurriculumKurs("67a+66", "Klinische Pharmazie I (Pharmakokinetik, Dosisoptimierung) + Pharmakoepidemiologie/-ökonomie",
                               lehrform: .su, sws: "2+0,5", stoffgebiete: [.i], ln: "I2 (gemeinsam mit [67b], [67c])",
                               dozenten: ["Prof. Oppermann"]),
                CurriculumKurs("67b", "Klinische Pharmazie II (Pharmazeutische Betreuung, MyDispense, Trainingsapotheke)",
                               lehrform: .ps, sws: "3,5", stoffgebiete: [.i], ln: "I2 (gemeinsam mit [67a+66], [67c])",
                               anmeldepflicht: true,
                               hinweis: "Mindestens 5 MyDispense-Fälle vor der Elektronischen Abschlussprüfung.",
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.elektronischeAbschlusspruefung, anmeldepflichtig: true,
                                                          hinweis: "Mindestens 5 MyDispense-Fälle bearbeiten")
                               ]),
                CurriculumKurs("67c", "Klinische Pharmazie III – Wissenschaftliche Arzneimittelbewertung (FAS)",
                               lehrform: .us, sws: "2", stoffgebiete: [.i], ln: "I2 (gemeinsam mit [67a+66], [67b])",
                               voraussetzungen: .hoechstensFehlend(1, ["43", "44", "52", "53", "62", "63", "64", "65"].map { VoraussetzungsRegel.kurs($0) }),
                               anmeldepflicht: true),
                CurriculumKurs("68+69", "Krankheitslehre Teil 2 + Pharmakotherapie Teil 2",
                               lehrform: .vu, sws: "3+1", stoffgebiete: [.i], ln: "I1",
                               dozenten: ["Prof. Oppermann"],
                               anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, "ggf. mündlich", anmeldepflichtig: true)
                               ],
                               lernpfad: "krankheitslehre", lernpfadTeil: 2),
                CurriculumKurs("70", "Pharmazeutische Technologie Teil 3 (Feste Arzneiformen)",
                               lehrform: .v, sws: "2", stoffgebiete: [.f],
                               lernpfad: "pharmtech", lernpfadTeil: 3),
                CurriculumKurs("71", "Pharmazeutische Biologie Teil 3",
                               lehrform: .v, sws: "2+1", stoffgebiete: [.g],
                               lernpfad: "pharmbio", lernpfadTeil: 3),
                CurriculumKurs("72", "Pharmazeutische/Medizinische Chemie III Teil 4",
                               lehrform: .v, sws: "2", stoffgebiete: [.h],
                               lernpfad: "medchem", lernpfadTeil: 4),
                CurriculumKurs("73", "Spezielle Rechtsgebiete für Apotheker",
                               lehrform: .v, sws: "1", stoffgebiete: [.i],
                               dozenten: ["Dr. Binger"]),
                CurriculumKurs("74", "Arzneimittelanalytik Teil 2",
                               lehrform: .s, sws: "1+1", stoffgebiete: [.h], ln: "H2b",
                               voraussetzungen: .alle([.kurs("43"), .kurs("44"), .kurs("53")]),
                               anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.praesentation),
                                   CurriculumTeilpruefung(.schriftlicheAbschlusspruefung, "SAR", anmeldepflichtig: true),
                               ]),
                CurriculumKurs("75", "Biogene Arzneimittel (Phytopharmaka, Antibiotika, gentechnisch hergestellte Arzneimittel)",
                               lehrform: .s, sws: "2", stoffgebiete: [.g], ln: "G2",
                               dozenten: ["Prof. Crüsemann", "Dr. Zündorf"],
                               voraussetzungen: .hoechstensFehlend(1, ["62", "63", "64", "65"].map { VoraussetzungsRegel.kurs($0) }),
                               anmeldepflicht: true,
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.seminararbeit)
                               ]),
                CurriculumKurs("76", "Wahlpflichtfach",
                               lehrform: .ps, sws: "84 Zeitstunden (2–4 Wochen)", stoffgebiete: [.k],
                               anmeldepflicht: true,
                               hinweis: "Platzvergabe Mitte des 6. Semesters (Prioritätenliste).",
                               teilpruefungen: [
                                   CurriculumTeilpruefung(.praktischerTeil, "84 Zeitstunden")
                               ]),
            ]
        ),

        // MARK: Staatsexamen
        CurriculumSemester(nummer: nummerStaatsexamen, titel: "Staatsexamen", typ: .staatsexamen),

        // MARK: Grundstudium-Archiv
        CurriculumSemester(nummer: 1, titel: "1. Semester", typ: .archiv),
        CurriculumSemester(nummer: 2, titel: "2. Semester", typ: .archiv),
        CurriculumSemester(nummer: 3, titel: "3. Semester", typ: .archiv),
        CurriculumSemester(nummer: 4, titel: "4. Semester", typ: .archiv),
    ]

    /// Alle Kurse über alle Semester.
    public static var alleKurse: [CurriculumKurs] { semester.flatMap(\.kurse) }
}
