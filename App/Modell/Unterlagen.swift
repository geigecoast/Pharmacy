import Foundation
import SwiftData
import PharmaCore

/// Vorlesungsunterlage: PDF, Scan, Präsentation oder Audioaufnahme.
@Model
final class Dokument {
    var kennung: UUID = UUID()
    var titel: String = ""
    var dateiname: String = ""
    var typRaw: String = DokumentTyp.pdf.rawValue
    @Attribute(.externalStorage) var daten: Data?
    /// Datum der Vorlesung.
    var datum: Date = Date()
    var importiertAm: Date = Date()
    var seitenzahl: Int = 0
    var texterkennungLaeuft: Bool = false
    var notizen: String = ""
    /// Audio: Transkript als JSON ([Transkriptabschnitt]) und als durchsuchbarer Text.
    var transkriptDaten: Data?
    var transkriptText: String = ""
    /// Audio: Zeitmarken zu Folien des verknüpften Dokuments.
    var folienmarkenDaten: Data?
    var verknuepftesDokumentKennung: UUID?

    var lehrveranstaltung: Lehrveranstaltung?

    @Relationship(deleteRule: .cascade, inverse: \Seite.dokument)
    var seiten: [Seite]? = []

    @Relationship(deleteRule: .cascade, inverse: \Markierung.dokument)
    var markierungen: [Markierung]? = []

    @Relationship(deleteRule: .cascade, inverse: \Zeichnung.dokument)
    var zeichnungen: [Zeichnung]? = []

    @Relationship(deleteRule: .nullify, inverse: \Karteikarte.dokument)
    var karteikarten: [Karteikarte]? = []

    init(titel: String, dateiname: String, typ: DokumentTyp, daten: Data?) {
        self.titel = titel
        self.dateiname = dateiname
        self.typRaw = typ.rawValue
        self.daten = daten
    }

    var typ: DokumentTyp {
        get { DokumentTyp(rawValue: typRaw) ?? .pdf }
        set { typRaw = newValue.rawValue }
    }

    var istPDF: Bool { typ == .pdf || typ == .scan }

    var sortierteSeiten: [Seite] { (seiten ?? []).sorted { $0.nummer < $1.nummer } }

    var sichtbareMarkierungen: [Markierung] {
        (markierungen ?? []).filter { $0.status != .abgelehnt }
            .sorted { ($0.seitenIndex, $0.erstelltAm) < ($1.seitenIndex, $1.erstelltAm) }
    }

    var transkript: [Transkriptabschnitt] {
        get { transkriptDaten.flatMap { try? JSONDecoder().decode([Transkriptabschnitt].self, from: $0) } ?? [] }
        set {
            transkriptDaten = try? JSONEncoder().encode(newValue)
            transkriptText = newValue.map(\.text).joined(separator: " ")
        }
    }

    var folienmarken: [Folienmarke] {
        get { folienmarkenDaten.flatMap { try? JSONDecoder().decode([Folienmarke].self, from: $0) } ?? [] }
        set { folienmarkenDaten = try? JSONEncoder().encode(newValue.sorted { $0.zeit < $1.zeit }) }
    }

    /// Dateiendung für temporäre Dateien (QuickLook, Audio).
    var endung: String {
        let teil = (dateiname as NSString).pathExtension
        return teil.isEmpty ? (typ == .audio ? "m4a" : "pdf") : teil
    }
}

/// Text einer Seite (aus dem PDF oder per Texterkennung) für die Volltextsuche.
@Model
final class Seite {
    var nummer: Int = 0
    var text: String = ""
    var ausTexterkennung: Bool = false
    var dokument: Dokument?

    init(nummer: Int, text: String) {
        self.nummer = nummer
        self.text = text
    }
}

/// Farbige Markierung auf einer Seite.
@Model
final class Markierung {
    var kennung: UUID = UUID()
    var seitenIndex: Int = 0
    /// Rechtecke in PDF-Koordinaten, je vier Werte (x, y, Breite, Höhe).
    var rechteckWerte: [Double] = []
    var farbeRaw: String = MarkierungsFarbe.gelb.rawValue
    var text: String = ""
    var quelleRaw: String = MarkierungsQuelle.nutzer.rawValue
    var statusRaw: String = MarkierungsStatus.angenommen.rawValue
    /// Begründung bei KI-Vorschlägen.
    var begruendung: String = ""
    var erstelltAm: Date = Date()
    var dokument: Dokument?

    init(seitenIndex: Int, rechtecke: [CGRect], farbe: MarkierungsFarbe, text: String) {
        self.seitenIndex = seitenIndex
        self.rechteckWerte = rechtecke.flatMap { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] }
        self.farbeRaw = farbe.rawValue
        self.text = text
    }

    var farbe: MarkierungsFarbe {
        get { MarkierungsFarbe(rawValue: farbeRaw) ?? .gelb }
        set { farbeRaw = newValue.rawValue }
    }

    var quelle: MarkierungsQuelle {
        get { MarkierungsQuelle(rawValue: quelleRaw) ?? .nutzer }
        set { quelleRaw = newValue.rawValue }
    }

    var status: MarkierungsStatus {
        get { MarkierungsStatus(rawValue: statusRaw) ?? .angenommen }
        set { statusRaw = newValue.rawValue }
    }

    var rechtecke: [CGRect] {
        stride(from: 0, to: rechteckWerte.count - 3, by: 4).map {
            CGRect(x: rechteckWerte[$0], y: rechteckWerte[$0 + 1], width: rechteckWerte[$0 + 2], height: rechteckWerte[$0 + 3])
        }
    }
}

/// Handschrift (Apple Pencil) auf einer Seite.
@Model
final class Zeichnung {
    var seitenIndex: Int = 0
    @Attribute(.externalStorage) var daten: Data?
    /// Per Texterkennung gelesene Handschrift.
    var text: String = ""
    var geaendertAm: Date = Date()
    var dokument: Dokument?

    init(seitenIndex: Int, daten: Data?) {
        self.seitenIndex = seitenIndex
        self.daten = daten
    }
}
