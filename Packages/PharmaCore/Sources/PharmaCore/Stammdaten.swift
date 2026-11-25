import Foundation

// MARK: - Stoffgebiete

/// Stoffgebiete des 2. Ausbildungsabschnitts (AAppO).
public enum Stoffgebiet: String, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case e = "E"
    case f = "F"
    case g = "G"
    case h = "H"
    case i = "I"
    case k = "K"

    public var id: String { rawValue }
    public var code: String { rawValue }

    public var name: String {
        switch self {
        case .e: "Biochemie und Pathobiochemie"
        case .f: "Pharmazeutische Technologie/Biopharmazie"
        case .g: "Biogene Arzneistoffe"
        case .h: "Pharmazeutische/Medizinische Chemie"
        case .i: "Pharmakologie, Toxikologie und Klinische Pharmazie"
        case .k: "Wahlpflichtfach"
        }
    }

    /// Standard-Zuordnung zu den Prüfungsfächern des 2. Staatsexamens (vom Nutzer änderbar).
    public var standardStaatsexamenFaecher: [StaatsexamenFach] {
        switch self {
        case .e: [.pharmakologie]
        case .f: [.technologie]
        case .g: [.biologie]
        case .h: [.chemie]
        case .i: [.pharmakologie, .klinischePharmazie]
        case .k: []
        }
    }

    public static func < (lhs: Stoffgebiet, rhs: Stoffgebiet) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Prüfungsfächer des 2. Abschnitts der Pharmazeutischen Prüfung.
public enum StaatsexamenFach: String, Codable, CaseIterable, Identifiable, Sendable {
    case chemie
    case biologie
    case technologie
    case pharmakologie
    case klinischePharmazie

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .chemie: "Pharmazeutische/Medizinische Chemie"
        case .biologie: "Pharmazeutische Biologie"
        case .technologie: "Pharmazeutische Technologie/Biopharmazie"
        case .pharmakologie: "Pharmakologie und Toxikologie"
        case .klinischePharmazie: "Klinische Pharmazie"
        }
    }
}

// MARK: - Lehrveranstaltung

public enum Lehrform: String, Codable, CaseIterable, Identifiable, Sendable {
    case v = "V"
    case blockV = "Block-V"
    case ps = "P+S"
    case s = "S"
    case su = "S+Ü"
    case vu = "V+Ü"
    case us = "Ü/S"

    public var id: String { rawValue }
    public var kuerzel: String { rawValue }

    public var name: String {
        switch self {
        case .v: "Vorlesung"
        case .blockV: "Blockvorlesung"
        case .ps: "Praktikum mit Seminar"
        case .s: "Seminar"
        case .su: "Seminar mit Übung"
        case .vu: "Vorlesung mit Übung"
        case .us: "Übung/Seminar"
        }
    }
}

public enum LVStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case offen
    case angemeldet
    case laeuft
    case bestanden
    case nichtBestanden
    case wiederholung

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .offen: "Offen"
        case .angemeldet: "Angemeldet"
        case .laeuft: "Läuft"
        case .bestanden: "Bestanden"
        case .nichtBestanden: "Nicht bestanden"
        case .wiederholung: "Wiederholung"
        }
    }

    /// Bestandene Veranstaltungen bekommen keine Prüfungserinnerungen mehr.
    public var istAbgeschlossen: Bool { self == .bestanden }
}

public enum TeilpruefungTyp: String, Codable, CaseIterable, Identifiable, Sendable {
    case muendlicheEingangspruefung
    case schriftlicheEingangspruefung
    case praktischerTeil
    case schriftlicheAbschlusspruefung
    case muendlicheAbschlusspruefung
    case abschlusskolloquium
    case praesentation
    case seminararbeit
    case elektronischeAbschlusspruefung

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .muendlicheEingangspruefung: "Mündliche Eingangsprüfung"
        case .schriftlicheEingangspruefung: "Schriftliche Eingangsprüfung"
        case .praktischerTeil: "Praktischer Teil"
        case .schriftlicheAbschlusspruefung: "Schriftliche Abschlussprüfung"
        case .muendlicheAbschlusspruefung: "Mündliche Abschlussprüfung"
        case .abschlusskolloquium: "Abschlusskolloquium"
        case .praesentation: "Präsentation"
        case .seminararbeit: "Seminararbeit"
        case .elektronischeAbschlusspruefung: "Elektronische Abschlussprüfung (MyDispense)"
        }
    }

    public var symbol: String {
        switch self {
        case .muendlicheEingangspruefung, .muendlicheAbschlusspruefung, .abschlusskolloquium: "person.wave.2"
        case .schriftlicheEingangspruefung, .schriftlicheAbschlusspruefung: "pencil.and.list.clipboard"
        case .praktischerTeil: "flask"
        case .praesentation: "person.and.background.dotted"
        case .seminararbeit: "doc.text"
        case .elektronischeAbschlusspruefung: "desktopcomputer"
        }
    }

    /// Geschätzter Lernaufwand in Stunden (Standardwert, pro Teilprüfung änderbar).
    public var standardLernaufwandStunden: Double {
        switch self {
        case .muendlicheEingangspruefung, .schriftlicheEingangspruefung: 15
        case .praktischerTeil: 0
        case .schriftlicheAbschlusspruefung: 25
        case .muendlicheAbschlusspruefung: 20
        case .abschlusskolloquium: 8
        case .praesentation: 10
        case .seminararbeit: 15
        case .elektronischeAbschlusspruefung: 8
        }
    }

    /// Eingangsprüfungen schalten einen Praktischen Teil frei und werden im Lernplan priorisiert.
    public var istEingangspruefung: Bool {
        self == .muendlicheEingangspruefung || self == .schriftlicheEingangspruefung
    }
}

public enum PruefungsErgebnis: String, Codable, CaseIterable, Identifiable, Sendable {
    case offen
    case bestanden
    case nichtBestanden

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .offen: "Offen"
        case .bestanden: "Bestanden"
        case .nichtBestanden: "Nicht bestanden"
        }
    }
}

public enum SemesterTyp: String, Codable, CaseIterable, Sendable {
    case regulaer
    case staatsexamen
    case archiv
}

public enum Fristart: String, Codable, CaseIterable, Identifiable, Sendable {
    case qisAnmeldung
    case platzvergabe
    case sonstiges

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .qisAnmeldung: "QIS/LSF-Anmeldung"
        case .platzvergabe: "Platzvergabe"
        case .sonstiges: "Frist"
        }
    }
}
