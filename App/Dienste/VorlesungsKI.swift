import Foundation
import SwiftData
import PDFKit
import PharmaCore

/// KI-Funktionen für Vorlesungsunterlagen: Kernaussagen markieren, Zusammenfassungen, Karteikarten.
@MainActor
enum VorlesungsKI {
    static let maxZeichen = 120_000

    /// Seitentexte als ein Dokument („=== Seite n ===“).
    static func volltext(_ dokument: Dokument) -> String {
        var text = ""
        for seite in dokument.sortierteSeiten {
            let teil = "=== Seite \(seite.nummer + 1) ===\n\(seite.text.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            if text.count + teil.count > maxZeichen { break }
            text += teil
        }
        if dokument.typ == .audio { text = String(dokument.transkriptText.prefix(maxZeichen)) }
        return text
    }

    static func hatText(_ dokument: Dokument) -> Bool {
        !volltext(dokument).replacingOccurrences(of: "=== Seite", with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func system(_ dokument: Dokument) -> String {
        KIAnweisungen.basis + KIAnweisungen.kontext(dokument.lehrveranstaltung)
    }

    // MARK: Zusammenfassung

    static func zusammenfassen(_ dokument: Dokument, stufe: ZusammenfassungsStufe, kontext: ModelContext,
                               fortschritt: @escaping (String) -> Void) async throws {
        let anfrage = KIAnfrage(
            modell: KI.modell,
            system: system(dokument),
            nachrichten: [KINachricht(rolle: .nutzer,
                                      text: "\(stufe.anweisung)\nGrundlage ist ausschließlich die beigefügte Vorlesung „\(dokument.titel)“.",
                                      dokumente: [KIDokument(titel: dokument.titel, text: volltext(dokument))])],
            maxTokens: stufe == .lernen ? 16_000 : 6_000,
            aufwand: stufe == .lernen ? .hoch : .mittel
        )
        let (text, _) = try await KI.vollstaendig(anfrage, fortschritt: fortschritt)
        for alt in (dokument.zusammenfassungen ?? []) where alt.stufe == stufe {
            kontext.delete(alt)
        }
        let neu = Zusammenfassung(stufe: stufe, text: text)
        kontext.insert(neu)
        neu.dokument = dokument
    }

    // MARK: Kernaussagen

    private struct Kernaussagen: Decodable {
        struct Aussage: Decodable {
            let seite: Int
            let zitat: String
            let farbe: String
            let begruendung: String
        }
        let kernaussagen: [Aussage]
    }

    static let kernaussagenSchema = Data("""
    {"type":"object","additionalProperties":false,"required":["kernaussagen"],
     "properties":{"kernaussagen":{"type":"array","items":{"type":"object","additionalProperties":false,
       "required":["seite","zitat","farbe","begruendung"],
       "properties":{"seite":{"type":"integer"},"zitat":{"type":"string"},
         "farbe":{"type":"string","enum":["gelb","rot","gruen","blau","lila"]},"begruendung":{"type":"string"}}}}}}
    """.utf8)

    /// Schlägt Kernaussagen als Markierungen vor (Status „vorgeschlagen“, zum Annehmen oder Ablehnen).
    @discardableResult
    static func kernaussagenMarkieren(_ dokument: Dokument, kontext: ModelContext) async throws -> (vorgeschlagen: Int, nichtGefunden: Int) {
        guard let daten = dokument.daten, let pdf = PDFDocument(data: daten) else { return (0, 0) }
        let anfrage = KIAnfrage(
            modell: KI.modell,
            system: system(dokument),
            nachrichten: [KINachricht(rolle: .nutzer, text: """
            Markiere in dieser Vorlesung die 8 bis 15 wichtigsten Kernaussagen und wahrscheinlichen Prüfungsthemen.
            Gib für jede an: die Seitenzahl, ein WÖRTLICHES Zitat von 4 bis 25 Wörtern exakt so, wie es im Text der Seite steht \
            (gleiche Schreibweise, keine Auslassungen), die Farbe und eine kurze Begründung (ein Satz).
            Farben: rot = prüfungsrelevant, gelb = wichtig, gruen = Definition, blau = Strukturformel/Mechanismus, \
            lila = Arzneibuch-Methode/Analytik (Identität, Reinheit, Gehalt).

            \(volltext(dokument))
            """)],
            maxTokens: 8_000,
            aufwand: .hoch,
            schema: kernaussagenSchema
        )
        let ergebnis = try await KI.json(Kernaussagen.self, anfrage)
        var vorgeschlagen = 0
        var nichtGefunden = 0
        for aussage in ergebnis.kernaussagen {
            let index = aussage.seite - 1
            guard let rechtecke = fundstelle(aussage.zitat, seite: index, in: pdf) else {
                nichtGefunden += 1
                continue
            }
            let markierung = Markierung(seitenIndex: index, rechtecke: rechtecke,
                                        farbe: MarkierungsFarbe(rawValue: aussage.farbe) ?? .gelb, text: aussage.zitat)
            markierung.quelle = .ki
            markierung.status = .vorgeschlagen
            markierung.begruendung = aussage.begruendung
            kontext.insert(markierung)
            markierung.dokument = dokument
            vorgeschlagen += 1
        }
        return (vorgeschlagen, nichtGefunden)
    }

    /// Sucht ein Zitat auf einer Seite (bei Bedarf gekürzt) und liefert die Zeilenrechtecke.
    static func fundstelle(_ zitat: String, seite index: Int, in pdf: PDFDocument) -> [CGRect]? {
        guard let seite = pdf.page(at: index) else { return nil }
        let woerter = zitat.split(whereSeparator: \.isWhitespace)
        let versuche = [zitat, woerter.prefix(8).joined(separator: " "), woerter.prefix(5).joined(separator: " ")]
        for versuch in versuche where versuch.count >= 8 {
            let treffer = pdf.findString(versuch, withOptions: [.caseInsensitive, .diacriticInsensitive])
            if let fund = treffer.first(where: { $0.pages.contains(seite) }) {
                let rechtecke = fund.selectionsByLine().map { $0.bounds(for: seite) }.filter { $0.width > 1 }
                if !rechtecke.isEmpty { return rechtecke }
            }
        }
        return nil
    }

    // MARK: Karteikarten

    private struct KartenAntwort: Decodable {
        struct Karte: Decodable {
            let typ: String
            let vorderseite: String
            let rueckseite: String
            let optionen: [String]
            let richtige: [Int]
            let thema: String
            let seite: Int
            let pruefungsrelevant: Bool
        }
        let karten: [Karte]
    }

    static let kartenSchema = Data("""
    {"type":"object","additionalProperties":false,"required":["karten"],
     "properties":{"karten":{"type":"array","items":{"type":"object","additionalProperties":false,
       "required":["typ","vorderseite","rueckseite","optionen","richtige","thema","seite","pruefungsrelevant"],
       "properties":{"typ":{"type":"string","enum":["frageAntwort","lueckentext","multipleChoice"]},
         "vorderseite":{"type":"string"},"rueckseite":{"type":"string"},
         "optionen":{"type":"array","items":{"type":"string"}},"richtige":{"type":"array","items":{"type":"integer"}},
         "thema":{"type":"string"},"seite":{"type":"integer"},"pruefungsrelevant":{"type":"boolean"}}}}}}
    """.utf8)

    /// Erzeugt Karteikarten aus einer Vorlesung (oder ihrer Lernzusammenfassung).
    @discardableResult
    static func kartenErzeugen(_ dokument: Dokument, anzahl: Int = 15, kontext: ModelContext) async throws -> Int {
        guard let lv = dokument.lehrveranstaltung else { return 0 }
        let zusammenfassung = (dokument.zusammenfassungen ?? []).first { $0.stufe == .lernen }?.text ?? ""
        let anfrage = KIAnfrage(
            modell: KI.modell,
            system: system(dokument),
            nachrichten: [KINachricht(rolle: .nutzer, text: """
            Erstelle \(anzahl) hochwertige Karteikarten zu dieser Vorlesung für die Prüfungsvorbereitung. Mische die Typen:
            - frageAntwort: präzise Frage, knappe vollständige Antwort,
            - lueckentext: ein Satz aus dem Stoff, die Lücke(n) in doppelten geschweiften Klammern, z. B. „Paracetamol hemmt {{COX-2}}“ \
            (bei diesem Typ rueckseite leer oder mit kurzer Ergänzung, optionen und richtige leer),
            - multipleChoice: Frage im IMPP-Stil mit 4–5 Antworten in optionen und den 0-basierten Indizes der richtigen in richtige.
            Bei frageAntwort sind optionen und richtige leer. Gib je Karte ein kurzes Thema, die Seitenzahl und an, ob sie \
            besonders prüfungsrelevant ist. Keine doppelten Karten, keine trivialen Fragen.

            Vorlesung:
            \(volltext(dokument))
            \(zusammenfassung.isEmpty ? "" : "\nLernzusammenfassung:\n" + zusammenfassung)
            """)],
            maxTokens: 12_000,
            aufwand: .hoch,
            schema: kartenSchema
        )
        let antwort = try await KI.json(KartenAntwort.self, anfrage)
        var erstellt = 0
        for vorschlag in antwort.karten {
            let typ = KartenTyp(rawValue: vorschlag.typ) ?? .frageAntwort
            let karte = Karteikarte(typ: typ, vorderseite: vorschlag.vorderseite, rueckseite: vorschlag.rueckseite, thema: vorschlag.thema)
            if typ == .multipleChoice {
                karte.optionen = vorschlag.optionen
                karte.richtigeOptionen = vorschlag.richtige.filter { vorschlag.optionen.indices.contains($0) }
            }
            karte.prioritaet = vorschlag.pruefungsrelevant
            karte.quelle = .ki
            karte.seitenIndex = max(0, vorschlag.seite - 1)
            guard karte.istGueltig else { continue }
            kontext.insert(karte)
            karte.lehrveranstaltung = lv
            karte.dokument = dokument
            erstellt += 1
        }
        return erstellt
    }

    // MARK: Fehler erklären

    static func fehlerErklaerung(_ eintrag: Fehlereintrag) -> KIAnfrage {
        KIAnfrage(
            modell: KI.modell,
            system: KIAnweisungen.basis + KIAnweisungen.kontext(eintrag.lehrveranstaltung) + KIAnweisungen.struktur,
            nachrichten: [KINachricht(rolle: .nutzer, text: """
            Ich habe diese Frage falsch beantwortet. Erkläre mir freundlich und konkret, warum meine Antwort falsch ist, \
            was richtig ist und warum – und wie ich den Fehler künftig vermeide.

            Frage: \(eintrag.frage)
            Meine Antwort: \(eintrag.deineAntwort)
            Richtige Antwort: \(eintrag.richtigeAntwort)
            \(eintrag.thema.isEmpty ? "" : "Thema: \(eintrag.thema)")
            """)],
            maxTokens: 6_000,
            aufwand: .mittel
        )
    }
}
