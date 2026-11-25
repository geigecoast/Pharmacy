import Foundation
import SwiftData
import PDFKit
import PharmaCore

/// Altklausuren-Analyse, Prüfungsprognose und Probeklausuren.
@MainActor
enum PruefungsKI {
    // MARK: Import

    /// Importiert eine Altklausur (PDF oder Bild); Text kommt aus dem PDF oder per Texterkennung.
    @discardableResult
    static func importieren(url: URL, art: AltklausurArt, in lv: Lehrveranstaltung, kontext: ModelContext) async throws -> Altklausur {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        var daten: Data
        do { daten = try Data(contentsOf: url) } catch { throw DokumentImport.Fehler.nichtLesbar(name) }
        let typ = DokumentTyp.typ(fuerEndung: url.pathExtension)
        if typ == .scan {
            guard let bild = PlattformBild(data: daten), let pdf = PDFWerkzeuge.pdf(ausBildern: [bild]) else {
                throw DokumentImport.Fehler.beschaedigt(name)
            }
            daten = pdf
        } else if typ != .pdf {
            throw DokumentImport.Fehler.nichtUnterstuetzt(name)
        }
        guard let pdf = PDFDocument(data: daten) else { throw DokumentImport.Fehler.beschaedigt(name) }

        let titel = url.deletingPathExtension().lastPathComponent
        let klausur = Altklausur(titel: titel, art: art)
        klausur.daten = daten
        klausur.dateiname = name
        klausur.jahr = jahr(in: titel)
        kontext.insert(klausur)
        klausur.lehrveranstaltung = lv

        klausur.analyseLaeuft = true
        var text = ""
        for index in 0..<pdf.pageCount {
            guard let seite = pdf.page(at: index) else { continue }
            var seitentext = seite.string ?? ""
            if seitentext.trimmingCharacters(in: .whitespacesAndNewlines).count < TexterkennungsDienst.mindestZeichen,
               let bild = PDFWerkzeuge.bild(von: seite) {
                seitentext = await TexterkennungsDienst.erkennen(bild)
            }
            text += "=== Seite \(index + 1) ===\n\(seitentext)\n\n"
        }
        klausur.text = text
        klausur.analyseLaeuft = false
        return klausur
    }

    static func notizAnlegen(_ text: String, in lv: Lehrveranstaltung, kontext: ModelContext) -> Altklausur {
        let notiz = Altklausur(titel: String(text.prefix(60)), art: .notiz)
        notiz.text = text
        kontext.insert(notiz)
        notiz.lehrveranstaltung = lv
        return notiz
    }

    /// Jahreszahl aus einem Dateinamen wie „Klausur_WS2023.pdf“.
    static func jahr(in text: String) -> Int? {
        let ziffern = text.split { !$0.isNumber }.compactMap { Int($0) }
        return ziffern.first { (2000...2100).contains($0) }
    }

    // MARK: Analyse

    private struct Analyse: Decodable {
        struct Frage: Decodable {
            let nummer: Int
            let text: String
            let punkte: Double
            let typ: String
            let themen: [String]
        }
        let jahr: Int
        let fragen: [Frage]
        let betonteThemen: [String]
    }

    static let analyseSchema = Data("""
    {"type":"object","additionalProperties":false,"required":["jahr","fragen","betonteThemen"],
     "properties":{"jahr":{"type":"integer"},"betonteThemen":{"type":"array","items":{"type":"string"}},
       "fragen":{"type":"array","items":{"type":"object","additionalProperties":false,
         "required":["nummer","text","punkte","typ","themen"],
         "properties":{"nummer":{"type":"integer"},"text":{"type":"string"},"punkte":{"type":"number"},
           "typ":{"type":"string","enum":["mc","freitext","struktur","rechnung","muendlich"]},
           "themen":{"type":"array","items":{"type":"string"}}}}}}}
    """.utf8)

    /// Bisher verwendete Themen der Lehrveranstaltung (für einheitliche Bezeichnungen).
    static func bekannteThemen(_ lv: Lehrveranstaltung) -> [String] {
        let ausFragen = (lv.altklausuren ?? []).flatMap { ($0.fragen ?? []).flatMap(\.themen) + $0.betonteThemen }
        var gesehen = Set<String>()
        return ausFragen.filter { gesehen.insert(Prognoserechner.schluessel($0)).inserted }.sorted()
    }

    static func analysieren(_ klausur: Altklausur, kontext: ModelContext) async throws {
        guard let lv = klausur.lehrveranstaltung else { return }
        klausur.analyseLaeuft = true
        defer { klausur.analyseLaeuft = false }
        let themen = bekannteThemen(lv)
        let auftrag: String
        if klausur.art == .notiz {
            auftrag = """
            Das ist eine Notiz von Studierenden dazu, was der Prüfer betont hat oder was als prüfungsrelevant gilt. \
            Gib die genannten Themen in betonteThemen zurück (kurze Fachbegriffe). fragen ist leer, jahr ist 0.
            """
        } else {
            auftrag = """
            Das ist eine \(klausur.art.name). Extrahiere alle Fragen (bei Teilaufgaben jede einzeln) mit Nummer, vollständigem \
            Fragetext, Punktzahl (0, wenn nicht angegeben), Fragetyp und 1–3 Themen als kurze Fachbegriffe \
            (z. B. „Komplexometrische Titration“, „Identitätsreaktionen“). Gib das Jahr der Klausur an (0, wenn unbekannt). \
            betonteThemen bleibt leer, außer im Dokument steht ausdrücklich, was besonders wichtig ist.
            """
        }
        let anfrage = KIAnfrage(
            modell: KI.modell,
            system: KIAnweisungen.basis + KIAnweisungen.kontext(lv),
            nachrichten: [KINachricht(rolle: .nutzer, text: """
            \(auftrag)
            \(themen.isEmpty ? "" : "Verwende nach Möglichkeit diese bereits benutzten Themenbezeichnungen: " + themen.joined(separator: "; "))

            Titel: \(klausur.titel)
            \(String(klausur.text.prefix(80_000)))
            """)],
            maxTokens: 16_000,
            aufwand: .mittel,
            schema: analyseSchema
        )
        let analyse = try await KI.json(Analyse.self, anfrage)
        for alt in klausur.fragen ?? [] { kontext.delete(alt) }
        for frage in analyse.fragen {
            let neu = AltklausurFrage(nummer: frage.nummer, text: frage.text, punkte: frage.punkte > 0 ? frage.punkte : nil,
                                      typ: frage.typ, themen: frage.themen)
            kontext.insert(neu)
            neu.altklausur = klausur
        }
        if klausur.jahr == nil, analyse.jahr >= 2000 { klausur.jahr = analyse.jahr }
        klausur.betonteThemen = analyse.betonteThemen
        klausur.analysiert = true
    }

    // MARK: Prognose

    static func prognose(_ lv: Lehrveranstaltung) -> [PrognoseEintrag] {
        let alle = (lv.altklausuren ?? []).filter(\.analysiert)
        let klausuren = alle.filter { $0.art != .notiz }
        let fragen = klausuren.flatMap { klausur in
            (klausur.fragen ?? []).map { AltfrageDaten(klausurID: klausur.kennung.uuidString, themen: $0.themen, punkte: $0.punkte) }
        }
        return Prognoserechner.berechnen(
            fragen: fragen,
            klausuren: klausuren.map { KlausurDaten(id: $0.kennung.uuidString, jahr: $0.jahr) },
            betonteThemen: alle.flatMap(\.betonteThemen),
            aktuellesJahr: Calendar.current.component(.year, from: Date())
        )
    }

    /// Passende Folie/Seite zu einem Thema in den Unterlagen.
    static func folie(zu thema: String, in lv: Lehrveranstaltung) -> (dokument: Dokument, seite: Int, titel: String)? {
        var seiten: [String: (Dokument, Int)] = [:]
        var eintraege: [Suchindex.Eintrag] = []
        for dokument in lv.dokumente ?? [] {
            for seite in dokument.sortierteSeiten where !seite.text.isEmpty {
                let id = "\(dokument.kennung)|\(seite.nummer)"
                seiten[id] = (dokument, seite.nummer)
                eintraege.append(.init(id: id, text: dokument.titel + "\n" + seite.text))
            }
        }
        guard let treffer = Suchindex(eintraege).suchen(thema, anzahl: 1).first, let fund = seiten[treffer.id] else { return nil }
        let nummer = (lv.dokumente ?? []).filter { $0.typ != .audio }.sorted { $0.datum < $1.datum }
            .firstIndex(where: { $0 === fund.0 }).map { "VL \($0 + 1)" } ?? fund.0.titel
        return (fund.0, fund.1, "\(nummer), S. \(fund.1 + 1)")
    }

    // MARK: Probeklausur

    private struct Entwurf: Decodable {
        struct Frage: Decodable {
            let typ: String
            let text: String
            let punkte: Double
            let optionen: [String]
            let richtige: [Int]
            let musterloesung: String
            let thema: String
            let zahlLoesung: String
            let einheit: String
        }
        let titel: String
        let fragen: [Frage]
    }

    static let entwurfSchema = Data("""
    {"type":"object","additionalProperties":false,"required":["titel","fragen"],
     "properties":{"titel":{"type":"string"},"fragen":{"type":"array","items":{"type":"object","additionalProperties":false,
       "required":["typ","text","punkte","optionen","richtige","musterloesung","thema","zahlLoesung","einheit"],
       "properties":{"typ":{"type":"string","enum":["mc","freitext","struktur","rechnung","muendlich"]},
         "text":{"type":"string"},"punkte":{"type":"number"},"optionen":{"type":"array","items":{"type":"string"}},
         "richtige":{"type":"array","items":{"type":"integer"}},"musterloesung":{"type":"string"},"thema":{"type":"string"},
         "zahlLoesung":{"type":"string"},"einheit":{"type":"string"}}}}}}
    """.utf8)

    static func probeklausurErstellen(_ lv: Lehrveranstaltung, teilpruefung: Teilpruefung?, dauer: Int, anzahl: Int,
                                      kontext: ModelContext) async throws -> Probeklausur {
        let vorhersage = prognose(lv).prefix(15)
        let altfragen = (lv.altklausuren ?? []).filter { $0.art != .notiz }.flatMap { $0.fragen ?? [] }.shuffled().prefix(25)
        let muendlicheTypen: [TeilpruefungTyp] = [.muendlicheEingangspruefung, .muendlicheAbschlusspruefung, .abschlusskolloquium]
        let muendlich = teilpruefung.map { muendlicheTypen.contains($0.typ) } ?? false
        let elektronisch = teilpruefung?.typ == .elektronischeAbschlusspruefung
        let stil: String
        if muendlich {
            stil = "Nur mündliche Prüfungsfragen (typ „muendlich“), wie sie ein Prüfer stellt – mit Nachfrage-Potenzial."
        } else if elektronisch {
            stil = "Überwiegend Multiple Choice (typ „mc“) im IMPP-Stil."
        } else {
            stil = "Mische Multiple Choice im IMPP-Stil (mc), Freitext (freitext), Strukturformeln/Mechanismen in Worten (struktur) und Rechenaufgaben (rechnung) – so wie in der echten schriftlichen Prüfung."
        }

        // Auszüge aus den Unterlagen zu den wahrscheinlichsten Themen
        var auszuege: [KIDokument] = []
        var gesehen = Set<String>()
        for eintrag in vorhersage.prefix(8) {
            for auszug in TutorSuche.auszuege(fuer: eintrag.thema, in: lv, anzahl: 2) where gesehen.insert(auszug.dokument.titel).inserted {
                auszuege.append(auszug.dokument)
            }
        }
        if auszuege.isEmpty {
            auszuege = TutorSuche.auszuege(fuer: lv.bezeichnung, in: lv, anzahl: 8).map(\.dokument)
        }

        let anfrage = KIAnfrage(
            modell: KI.modell,
            system: KIAnweisungen.basis + KIAnweisungen.kontext(lv),
            nachrichten: [KINachricht(rolle: .nutzer, text: """
            Erstelle eine Probeklausur mit \(anzahl) Fragen für \(teilpruefung?.titelMitLfdNr ?? "diese Lehrveranstaltung"), \
            Bearbeitungszeit \(dauer) Minuten. \(stil)
            Punkte je Frage passend zum Aufwand. Für mc: 4–5 optionen, richtige = 0-basierte Indizes. Für rechnung: zahlLoesung \
            als Zahl mit Komma (z. B. „100,2“) und einheit. Für alle anderen Typen zahlLoesung und einheit leer, optionen und \
            richtige leer. musterloesung: vollständige Erwartung mit Bewertungspunkten. thema: kurzer Fachbegriff.
            Gewichte die Themen nach dieser Prognose (wahrscheinlichste zuerst):
            \(vorhersage.map { "- \($0.thema): \($0.stufe.name)" }.joined(separator: "\n"))
            \(altfragen.isEmpty ? "" : "Orientiere dich am Stil dieser Altfragen:\n" + altfragen.map { "- " + $0.text.prefix(300) }.joined(separator: "\n"))
            Stütze dich auf die beigefügten Auszüge aus den Unterlagen.
            """, dokumente: auszuege)],
            maxTokens: 16_000,
            aufwand: .hoch,
            schema: entwurfSchema
        )
        let entwurf = try await KI.json(Entwurf.self, anfrage)
        let fragen = entwurf.fragen.enumerated().map { index, frage in
            PKFrage(id: index, typ: PKFrage.Typ(rawValue: frage.typ) ?? .freitext, text: frage.text, punkte: max(1, frage.punkte),
                    optionen: frage.optionen, richtige: frage.richtige.filter { frage.optionen.indices.contains($0) },
                    musterloesung: frage.musterloesung, thema: frage.thema, zahlLoesung: frage.zahlLoesung, einheit: frage.einheit)
        }
        let klausur = Probeklausur(titel: entwurf.titel.isEmpty ? "Probeklausur" : entwurf.titel, dauerMinuten: dauer)
        klausur.fragen = fragen
        kontext.insert(klausur)
        klausur.lehrveranstaltung = lv
        return klausur
    }

    // MARK: Bewertung

    private struct KIBewertung: Decodable {
        struct Eintrag: Decodable {
            let id: Int
            let punkte: Double
            let rueckmeldung: String
        }
        let bewertungen: [Eintrag]
    }

    static let bewertungSchema = Data("""
    {"type":"object","additionalProperties":false,"required":["bewertungen"],
     "properties":{"bewertungen":{"type":"array","items":{"type":"object","additionalProperties":false,
       "required":["id","punkte","rueckmeldung"],
       "properties":{"id":{"type":"integer"},"punkte":{"type":"number"},"rueckmeldung":{"type":"string"}}}}}}
    """.utf8)

    /// Bewertet eine abgegebene Probeklausur: MC und Rechenaufgaben lokal, offene Antworten per KI.
    static func bewerten(_ klausur: Probeklausur, kontext: ModelContext) async throws {
        let fragen = klausur.fragen
        let antworten = klausur.antworten
        var bewertungen: [Int: PKBewertung] = [:]
        var offen: [PKFrage] = []
        for frage in fragen {
            let antwort = antworten[frage.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch frage.typ {
            case .mc:
                let auswahl = Set(antwort.split(separator: ",").compactMap { Int($0) })
                let punkte = Klausurbewertung.mcPunkte(auswahl: auswahl, richtig: Set(frage.richtige), punkte: frage.punkte)
                let loesung = frage.richtige.map { Karteikarte.buchstabe($0) }.joined(separator: ", ")
                bewertungen[frage.id] = PKBewertung(punkte: punkte, rueckmeldung: punkte > 0 ? "Richtig." : "Richtig wäre: \(loesung).")
            case .rechnung:
                if let loesung = Dezimal.lesen(frage.zahlLoesung) {
                    let richtig = Klausurbewertung.zahlRichtig(antwort: antwort, loesung: loesung)
                    bewertungen[frage.id] = PKBewertung(punkte: richtig ? frage.punkte : 0,
                                                       rueckmeldung: richtig ? "Ergebnis stimmt." : "Erwartet: \(frage.zahlLoesung) \(frage.einheit). \(frage.musterloesung)")
                } else {
                    offen.append(frage)
                }
            default:
                if antwort.isEmpty {
                    bewertungen[frage.id] = PKBewertung(punkte: 0, rueckmeldung: "Nicht beantwortet.")
                } else {
                    offen.append(frage)
                }
            }
        }

        if !offen.isEmpty {
            let liste = offen.map { frage in
                """
                [id \(frage.id)] (\(frage.punkte.formatted()) Punkte, \(frage.typ.name))
                Frage: \(frage.text)
                Musterlösung: \(frage.musterloesung)
                Antwort der Studentin/des Studenten: \(antworten[frage.id] ?? "")
                """
            }.joined(separator: "\n\n")
            let anfrage = KIAnfrage(
                modell: KI.modell,
                system: KIAnweisungen.basis + KIAnweisungen.kontext(klausur.lehrveranstaltung),
                nachrichten: [KINachricht(rolle: .nutzer, text: """
                Bewerte diese Antworten wie ein fairer, aber genauer Prüfer anhand der Musterlösung. Vergib Teilpunkte \
                (in halben Punkten, höchstens die angegebene Punktzahl). Rückmeldung je Antwort in 1–3 Sätzen: \
                was richtig war und was fehlte.

                \(liste)
                """)],
                maxTokens: 8_000,
                aufwand: .mittel,
                schema: bewertungSchema
            )
            let ergebnis = try await KI.json(KIBewertung.self, anfrage)
            for eintrag in ergebnis.bewertungen {
                guard let frage = offen.first(where: { $0.id == eintrag.id }) else { continue }
                bewertungen[frage.id] = PKBewertung(punkte: min(max(0, eintrag.punkte), frage.punkte), rueckmeldung: eintrag.rueckmeldung)
            }
            for frage in offen where bewertungen[frage.id] == nil {
                bewertungen[frage.id] = PKBewertung(punkte: 0, rueckmeldung: "Konnte nicht bewertet werden.")
            }
        }

        klausur.bewertungen = bewertungen
        klausur.abgegebenAm = Date()

        // Schwache Antworten ins Fehlerjournal
        for frage in fragen {
            guard let bewertung = bewertungen[frage.id], bewertung.punkte < frage.punkte * 0.5 else { continue }
            let eintrag = Fehlereintrag(frage: frage.text, deineAntwort: antwortText(frage, antworten[frage.id] ?? ""),
                                        richtigeAntwort: frage.typ == .mc
                                            ? frage.richtige.compactMap { frage.optionen.indices.contains($0) ? "\(Karteikarte.buchstabe($0)) \(frage.optionen[$0])" : nil }.joined(separator: "; ")
                                            : frage.musterloesung,
                                        thema: frage.thema, herkunft: "Probeklausur")
            kontext.insert(eintrag)
            eintrag.lehrveranstaltung = klausur.lehrveranstaltung
        }
    }

    static func antwortText(_ frage: PKFrage, _ antwort: String) -> String {
        guard frage.typ == .mc else { return antwort.isEmpty ? "–" : antwort }
        let auswahl = antwort.split(separator: ",").compactMap { Int($0) }
        guard !auswahl.isEmpty else { return "–" }
        return auswahl.compactMap { frage.optionen.indices.contains($0) ? "\(Karteikarte.buchstabe($0)) \(frage.optionen[$0])" : nil }
            .joined(separator: "; ")
    }
}
