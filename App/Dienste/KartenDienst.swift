import Foundation
import SwiftUI
import SwiftData
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import PharmaCore

/// Lernen mit Karteikarten: Bewertung (FSRS), Fehlerjournal, Erzeugung aus Markierungen.
@MainActor
enum KartenDienst {
    static let fsrs = FSRS()
    /// Lernkarten, die in den nächsten Minuten fällig werden, dürfen vorgezogen werden.
    static let vorziehenSekunden: TimeInterval = 20 * 60

    /// Fällige Karten; Priorität zuerst, dann nach Fälligkeit.
    static func warteschlange(_ karten: [Karteikarte], jetzt: Date = Date()) -> [Karteikarte] {
        let gueltig = karten.filter(\.istGueltig)
        var faellig = gueltig.filter { $0.faellig <= jetzt }
        if faellig.isEmpty {
            faellig = gueltig.filter {
                $0.zustandRaw != KartenZustand.neu.rawValue && $0.zustandRaw != KartenZustand.wiederholen.rawValue
                    && $0.faellig <= jetzt.addingTimeInterval(vorziehenSekunden)
            }
        }
        return faellig.sorted {
            ($0.prioritaet ? 0 : 1, $0.faellig) < ($1.prioritaet ? 0 : 1, $1.faellig)
        }
    }

    static func anzahlFaellig(_ karten: [Karteikarte], jetzt: Date = Date()) -> Int {
        karten.filter { $0.istGueltig && $0.faellig <= jetzt }.count
    }

    /// Bewertet eine Karte, protokolliert die Wiederholung und trägt „Nochmal“ ins Fehlerjournal ein.
    static func bewerten(_ karte: Karteikarte, _ bewertung: Bewertung, dauer: TimeInterval, kontext: ModelContext, jetzt: Date = Date()) {
        let neu = fsrs.planen(karte.stand, bewertung, jetzt: jetzt)
        karte.stand = neu
        let eintrag = Wiederholung(datum: jetzt, bewertung: bewertung, dauerSekunden: dauer, intervallTage: neu.intervallTage)
        kontext.insert(eintrag)
        eintrag.karte = karte
        if bewertung == .nochmal {
            fehlerEintragen(karte, deineAntwort: "Nicht gewusst", herkunft: "Wiederholung", kontext: kontext)
        }
    }

    static func fehlerEintragen(_ karte: Karteikarte, deineAntwort: String, herkunft: String, kontext: ModelContext) {
        // Bereits offener Eintrag zur selben Karte wird nur aktualisiert.
        if let offen = (karte.fehlereintraege ?? []).first(where: { !$0.verstanden }) {
            offen.datum = Date()
            offen.deineAntwort = deineAntwort
            offen.herkunft = herkunft
            return
        }
        let eintrag = Fehlereintrag(frage: karte.frageText, deineAntwort: deineAntwort, richtigeAntwort: karte.antwortText,
                                    thema: karte.thema, herkunft: herkunft)
        kontext.insert(eintrag)
        eintrag.karte = karte
        eintrag.lehrveranstaltung = karte.lehrveranstaltung
    }

    /// Lernstand einer Kartenmenge: mittlere Abrufwahrscheinlichkeit (neue Karten zählen als 0).
    static func lernstand(_ karten: [Karteikarte], jetzt: Date = Date()) -> Double? {
        let gueltig = karten.filter(\.istGueltig)
        guard !gueltig.isEmpty, gueltig.contains(where: { $0.wiederholungen > 0 }) else { return nil }
        return gueltig.map { fsrs.abrufbarkeit($0.stand, jetzt: jetzt) }.reduce(0, +) / Double(gueltig.count)
    }

    // MARK: Karten aus Markierungen

    /// Markierungen, aus denen noch keine Karte erstellt wurde.
    static func offeneMarkierungen(_ lv: Lehrveranstaltung) -> [Markierung] {
        let vorhanden = Set((lv.karteikarten ?? []).compactMap(\.markierungKennung))
        return (lv.dokumente ?? []).flatMap { $0.sichtbareMarkierungen }
            .filter { $0.status == .angenommen && !$0.text.isEmpty && !vorhanden.contains($0.kennung) }
    }

    /// Erzeugt Lückentextkarten aus Markierungen: der markierte Begriff wird im Satz der Seite zur Lücke.
    /// Rote Markierungen (prüfungsrelevant) werden als prioritär markiert.
    @discardableResult
    static func ausMarkierungen(_ lv: Lehrveranstaltung, kontext: ModelContext) -> (erstellt: Int, uebersprungen: Int) {
        var erstellt = 0
        var uebersprungen = 0
        for markierung in offeneMarkierungen(lv) {
            guard let dokument = markierung.dokument else { continue }
            let seitentext = dokument.sortierteSeiten.first { $0.nummer == markierung.seitenIndex }?.text ?? ""
            guard let text = Kartenvorschlag.lueckentext(markiert: markierung.text, seitentext: seitentext) else {
                uebersprungen += 1
                continue
            }
            let karte = Karteikarte(typ: .lueckentext, vorderseite: text,
                                    rueckseite: "\(dokument.titel), Seite \(markierung.seitenIndex + 1)", thema: dokument.titel)
            karte.prioritaet = markierung.farbe == .rot
            karte.quelle = .markierung
            karte.markierungKennung = markierung.kennung
            karte.seitenIndex = markierung.seitenIndex
            kontext.insert(karte)
            karte.lehrveranstaltung = lv
            karte.dokument = dokument
            erstellt += 1
        }
        return (erstellt, uebersprungen)
    }
}

/// Export nach Anki (.apkg) und CSV.
@MainActor
enum KartenExport {
    static func anki(_ karten: [Karteikarte], stapel: String) throws -> Data {
        var notizen: [AnkiPaket.Notiz] = []
        var medien: [String: Data] = [:]
        for karte in karten where karte.istGueltig {
            let schlagwoerter = [karte.thema, karte.prioritaet ? "pruefungsrelevant" : ""].filter { !$0.isEmpty }
            switch karte.typ {
            case .frageAntwort:
                notizen.append(.init(art: .basis, felder: [html(karte.vorderseite), html(karte.rueckseite)], schlagwoerter: schlagwoerter))
            case .lueckentext:
                notizen.append(.init(art: .lueckentext, felder: [html(Lueckentext.alsAnki(karte.vorderseite)), html(karte.rueckseite)],
                                     schlagwoerter: schlagwoerter))
            case .multipleChoice:
                let liste = karte.optionen.enumerated().map { "<li>\(Karteikarte.buchstabe($0.offset)) \(html($0.element))</li>" }.joined()
                notizen.append(.init(art: .basis, felder: [html(karte.vorderseite) + "<ol type=\"A\" style=\"text-align:left\">\(liste)</ol>",
                                                            html(karte.antwortText)], schlagwoerter: schlagwoerter))
            case .bildOkklusion:
                guard let daten = karte.bildDaten,
                      let frage = BildOkklusion.png(daten, masken: karte.masken, verdeckt: true),
                      let antwort = BildOkklusion.png(daten, masken: karte.masken, verdeckt: false) else { continue }
                let name = karte.kennung.uuidString
                medien["\(name)-frage.png"] = frage
                medien["\(name)-antwort.png"] = antwort
                notizen.append(.init(art: .basis, felder: [
                    "\(html(karte.vorderseite))<br><img src=\"\(name)-frage.png\">",
                    "<img src=\"\(name)-antwort.png\"><br>\(html(karte.rueckseite))",
                ], schlagwoerter: schlagwoerter))
            }
        }
        return try AnkiPaket.erstellen(stapel: stapel, notizen: notizen, medien: medien)
    }

    static func csv(_ karten: [Karteikarte]) -> String {
        let zeilen = karten.filter(\.istGueltig).map { karte -> [String] in
            let vorne = karte.typ == .lueckentext ? Lueckentext.alsAnki(karte.vorderseite) : karte.frageText
            return [vorne, karte.antwortText, karte.thema.replacingOccurrences(of: " ", with: "_")]
        }
        return CSV.dokument(zeilen)
    }

    private static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

/// Zeichnet Bild-Okklusionsmasken in ein Bild (für den Anki-Export).
enum BildOkklusion {
    static func png(_ daten: Data, masken: [CGRect], verdeckt: Bool) -> Data? {
        guard let quelle = CGImageSourceCreateWithData(daten as CFData, nil),
              let bild = CGImageSourceCreateImageAtIndex(quelle, 0, nil) else { return nil }
        let breite = bild.width
        let hoehe = bild.height
        guard let kontext = CGContext(data: nil, width: breite, height: hoehe, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let flaeche = CGRect(x: 0, y: 0, width: breite, height: hoehe)
        kontext.draw(bild, in: flaeche)
        for maske in masken {
            // Masken sind relativ und oben links verankert; CoreGraphics zählt von unten.
            let rechteck = CGRect(x: maske.minX * CGFloat(breite), y: (1 - maske.maxY) * CGFloat(hoehe),
                                  width: maske.width * CGFloat(breite), height: maske.height * CGFloat(hoehe))
            if verdeckt {
                kontext.setFillColor(CGColor(red: 0.55, green: 0.42, blue: 0.62, alpha: 1))
                kontext.fill(rechteck)
            } else {
                kontext.setStrokeColor(CGColor(red: 0.55, green: 0.42, blue: 0.62, alpha: 1))
                kontext.setLineWidth(max(2, CGFloat(breite) / 300))
                kontext.stroke(rechteck)
            }
        }
        guard let ergebnis = kontext.makeImage() else { return nil }
        let ausgabe = NSMutableData()
        guard let ziel = CGImageDestinationCreateWithData(ausgabe as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(ziel, ergebnis, nil)
        guard CGImageDestinationFinalize(ziel) else { return nil }
        return ausgabe as Data
    }
}

/// Datei für den Export-Dialog (Anki-Paket oder CSV).
struct ExportDatei: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.ankiPaket, .commaSeparatedText, .pharmatutorSicherung, .data] }

    var daten: Data

    init(daten: Data) { self.daten = daten }

    init(configuration: ReadConfiguration) throws {
        daten = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: daten)
    }
}

extension UTType {
    /// Anki-Paket (.apkg).
    static var ankiPaket: UTType { UTType(filenameExtension: "apkg", conformingTo: .data) ?? .data }
}
