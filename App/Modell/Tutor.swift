import Foundation
import SwiftData
import PharmaCore

/// Erklärmodi des Tutors.
enum TutorModus: String, CaseIterable, Identifiable {
    case einfach, pruefungsniveau, schritte, sokratisch, muendlich

    var id: String { rawValue }

    var name: String {
        switch self {
        case .einfach: "Erklär’s mir einfach"
        case .pruefungsniveau: "Prüfungsniveau"
        case .schritte: "Schritt für Schritt"
        case .sokratisch: "Sokratisch"
        case .muendlich: "Mündliche Prüfung simulieren"
        }
    }

    var anweisung: String {
        switch self {
        case .einfach:
            "Erkläre einfach und anschaulich, mit Alltagsvergleichen und ohne unnötigen Fachjargon – aber fachlich korrekt. Fasse dich kurz."
        case .pruefungsniveau:
            "Antworte auf Klausur- und Staatsexamensniveau: präzise Fachsprache, vollständige Mechanismen, Strukturen, Ph.-Eur.-Bezüge und Zahlen, wo sie in der Prüfung erwartet werden."
        case .schritte:
            "Erkläre Schritt für Schritt mit nummerierten Schritten. Bei Mechanismen jeden Teilschritt einzeln; bei Rechnungen jeden Rechenschritt mit Einheiten und Plausibilitätsprüfung."
        case .sokratisch:
            "Arbeite sokratisch: Gib die Antwort nicht direkt. Stelle jeweils EINE gezielte Leitfrage, gib bei Bedarf einen kleinen Hinweis und warte auf die Antwort. Löse erst auf, wenn ausdrücklich darum gebeten wird."
        case .muendlich:
            "Du bist Prüfer:in in einer mündlichen Prüfung zu dieser Lehrveranstaltung. Stelle eine Prüfungsfrage, warte auf die Antwort und gib dann kurz Rückmeldung: was richtig war, was fehlte, eine Einschätzung als Note (1–5) und eine typische Nachfrage, wie sie ein echter Prüfer stellen würde. Beginne mit einer Einstiegsfrage, wenn noch nichts gefragt wurde."
        }
    }

    /// Modi mit den vier festen Abschnitten am Ende.
    var mitStruktur: Bool { self == .einfach || self == .pruefungsniveau || self == .schritte }
}

/// Ein Tutor-Gespräch zu einer Lehrveranstaltung.
@Model
final class TutorChat {
    var kennung: UUID = UUID()
    var titel: String = ""
    var erstelltAm: Date = Date()
    var lehrveranstaltung: Lehrveranstaltung?

    @Relationship(deleteRule: .cascade, inverse: \TutorNachricht.chat)
    var nachrichten: [TutorNachricht]? = []

    init(titel: String) {
        self.titel = titel
    }

    var sortierteNachrichten: [TutorNachricht] {
        (nachrichten ?? []).sorted { $0.datum < $1.datum }
    }
}

/// Quelle einer Antwort (Folie/Seite einer Unterlage).
struct TutorQuelle: Codable, Hashable {
    var titel: String
    var dokument: UUID?
    var seite: Int
}

@Model
final class TutorNachricht {
    var datum: Date = Date()
    var vonNutzer: Bool = true
    var text: String = ""
    var modusRaw: String = TutorModus.einfach.rawValue
    var quellenDaten: Data?
    var chat: TutorChat?

    init(vonNutzer: Bool, text: String, modus: TutorModus) {
        self.vonNutzer = vonNutzer
        self.text = text
        self.modusRaw = modus.rawValue
    }

    var modus: TutorModus { TutorModus(rawValue: modusRaw) ?? .einfach }

    var quellen: [TutorQuelle] {
        get { quellenDaten.flatMap { try? JSONDecoder().decode([TutorQuelle].self, from: $0) } ?? [] }
        set { quellenDaten = try? JSONEncoder().encode(newValue) }
    }
}

/// Stufen der KI-Zusammenfassung.
enum ZusammenfassungsStufe: Int, CaseIterable, Identifiable {
    case kurz = 0, lernen = 1, spickzettel = 2

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .kurz: "Kurzüberblick"
        case .lernen: "Lernzusammenfassung"
        case .spickzettel: "Last-Minute-Spickzettel"
        }
    }

    var segment: String {
        switch self {
        case .kurz: "Kurz"
        case .lernen: "Lernen"
        case .spickzettel: "Spickzettel"
        }
    }

    var anweisung: String {
        switch self {
        case .kurz:
            "Schreibe einen Kurzüberblick in 5–8 Sätzen: worum es in dieser Vorlesung geht und welches die wichtigsten Aussagen sind."
        case .lernen:
            "Schreibe eine vollständige Lernzusammenfassung für die Prüfungsvorbereitung, gegliedert mit Zwischenüberschriften (## …). Enthalten sein sollen Definitionen, Mechanismen, Strukturmerkmale, Arzneibuch-Methoden (Identität, Reinheit, Gehalt), Zahlen und kurze Merkhilfen."
        case .spickzettel:
            "Schreibe einen Last-Minute-Spickzettel: höchstens eine Seite, nur Stichpunkte, nur das Prüfungsrelevanteste – Formeln, Zahlen, Signalwörter, typische Fallen."
        }
    }
}

@Model
final class Zusammenfassung {
    var stufeRaw: Int = ZusammenfassungsStufe.lernen.rawValue
    var text: String = ""
    var erstelltAm: Date = Date()
    var dokument: Dokument?

    init(stufe: ZusammenfassungsStufe, text: String) {
        self.stufeRaw = stufe.rawValue
        self.text = text
    }

    var stufe: ZusammenfassungsStufe { ZusammenfassungsStufe(rawValue: stufeRaw) ?? .lernen }
}
