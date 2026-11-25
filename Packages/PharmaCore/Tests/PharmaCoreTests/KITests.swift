import XCTest
@testable import PharmaCore

final class ClaudeAPITests: XCTestCase {
    func testKoerperMitDokumentenUndZitaten() throws {
        let anfrage = KIAnfrage(
            modell: "claude-opus-5-5",
            system: "Du bist ein Tutor.",
            nachrichten: [
                KINachricht(rolle: .nutzer, text: "Was ist Identität?"),
                KINachricht(rolle: .assistent, text: "Antwort"),
                KINachricht(rolle: .nutzer, text: "Und Reinheit?", dokumente: [KIDokument(titel: "VL 6, Seite 12", text: "Reinheit …")]),
            ]
        )
        let objekt = try XCTUnwrap(JSONSerialization.jsonObject(with: ClaudeAPI.koerper(anfrage)) as? [String: Any])
        XCTAssertEqual(objekt["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(objekt["stream"] as? Bool, true)
        XCTAssertEqual(objekt["fallbacks"] as? String, "default")
        XCTAssertNil(objekt["temperature"])
        let nachrichten = try XCTUnwrap(objekt["messages"] as? [[String: Any]])
        XCTAssertEqual(nachrichten.count, 3)
        XCTAssertEqual(nachrichten[1]["content"] as? String, "Antwort")
        let inhalt = try XCTUnwrap(nachrichten[2]["content"] as? [[String: Any]])
        XCTAssertEqual(inhalt.first?["type"] as? String, "document")
        XCTAssertEqual((inhalt.first?["citations"] as? [String: Bool])?["enabled"], true)
        XCTAssertEqual(inhalt.last?["text"] as? String, "Und Reinheit?")
        let ausgabe = try XCTUnwrap(objekt["output_config"] as? [String: Any])
        XCTAssertEqual(ausgabe["effort"] as? String, "medium")
    }

    func testSchemaOhneZitateUndHaikuOhneFallback() throws {
        let schema = Data(#"{"type":"object","properties":{"a":{"type":"string"}},"required":["a"],"additionalProperties":false}"#.utf8)
        let anfrage = KIAnfrage(modell: "claude-haiku-5-5", system: "x",
                                nachrichten: [KINachricht(rolle: .nutzer, text: "y", dokumente: [KIDokument(titel: "t", text: "z")])],
                                schema: schema)
        let objekt = try XCTUnwrap(JSONSerialization.jsonObject(with: ClaudeAPI.koerper(anfrage)) as? [String: Any])
        XCTAssertNil(objekt["fallbacks"])
        let format = ((objekt["output_config"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format?["type"] as? String, "json_schema")
        let inhalt = (objekt["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
        XCTAssertNil(inhalt?.first?["citations"])
        XCTAssertNil(ClaudeAPI.kopfzeilen(schluessel: "k", modell: "claude-haiku-5-5")["anthropic-beta"])
        XCTAssertEqual(ClaudeAPI.kopfzeilen(schluessel: "k", modell: "claude-opus-5-5")["anthropic-version"], "2026-10-21")
    }

    func testFehlermeldung() {
        let daten = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        XCTAssertEqual(ClaudeAPI.fehlermeldung(aus: daten)?.typ, "authentication_error")
    }
}

final class SSETests: XCTestCase {
    func testStream() {
        var zerleger = SSEZerleger()
        let zeilen = [
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hallo"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"citations_delta","citation":{"type":"char_location","cited_text":"Reinheit …","document_index":0,"document_title":"VL 6, Seite 12"}}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        let ereignisse = zeilen.flatMap { zerleger.zeile($0) }
        XCTAssertEqual(ereignisse, [
            .text("Hallo"),
            .zitat(KIZitat(dokumentIndex: 0, dokumentTitel: "VL 6, Seite 12", zitierterText: "Reinheit …")),
            .ende(stopGrund: "end_turn"),
        ])
    }

    func testFehlerImStream() {
        var zerleger = SSEZerleger()
        XCTAssertEqual(zerleger.zeile(#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#),
                       [.fehler(typ: "overloaded_error", meldung: "Overloaded")])
    }
}

final class AntwortstrukturTests: XCTestCase {
    func testZerlegen() {
        let text = """
        Eine Monographie beantwortet drei Fragen.

        ### Merksatz
        „Wer – wie sauber – wie viel.“
        ### Signalwörter
        „prüfen auf“ → Reinheit
        **Typische Falle:** IR sagt nichts über Reinheit.
        ## In der Klausur
        Ziel, Methode, Kapitel nennen.
        """
        let zerlegt = Antwortstruktur.zerlegen(text)
        XCTAssertEqual(zerlegt.haupttext, "Eine Monographie beantwortet drei Fragen.")
        XCTAssertEqual(zerlegt.abschnitte.map { $0.titel }, ["Merksatz", "Signalwörter", "Typische Falle", "In der Klausur"])
        XCTAssertEqual(zerlegt.abschnitte[2].text, "IR sagt nichts über Reinheit.")
        XCTAssertEqual(zerlegt.abschnitte[3].text, "Ziel, Methode, Kapitel nennen.")
    }

    func testKeineFalschenTreffer() {
        let zerlegt = Antwortstruktur.zerlegen("Merksätze helfen beim Lernen.")
        XCTAssertTrue(zerlegt.abschnitte.isEmpty)
    }
}

final class SuchindexTests: XCTestCase {
    func testBM25() {
        let index = Suchindex([
            .init(id: "1", text: "Komplexometrische Titration mit Natriumedetat und Eriochromschwarz T als Indikator."),
            .init(id: "2", text: "Die IR-Spektroskopie dient der Identitätsprüfung im Vergleich mit einer CRS."),
            .init(id: "3", text: "Grenzprüfung auf Schwermetalle nach Ph. Eur."),
        ])
        XCTAssertEqual(index.suchen("Wie funktioniert die Identitätsprüfung mit IR?").first?.id, "2")
        XCTAssertEqual(index.suchen("Titrationen komplexometrisch").first?.id, "1")
        XCTAssertTrue(index.suchen("und oder der").isEmpty)
    }
}

final class RechnerTests: XCTestCase {
    func testGehalt() {
        // 1 ml 0,1 M Perchlorsäure entspricht 18,02 mg; Verbrauch 8,30 ml, f = 1,005, Einwaage 150 mg
        let gehalt = Analytikrechner.gehaltProzent(verbrauchML: 8.30, faktor: 1.005, aequivalentMG: 18.02, einwaageMG: 150)!
        XCTAssertEqual(gehalt, 100.21, accuracy: 0.01)
        XCTAssertEqual(Analytikrechner.sollverbrauchML(einwaageMG: 150, sollProzent: 100, faktor: 1, aequivalentMG: 18.02)!, 8.324, accuracy: 0.001)
        XCTAssertEqual(Analytikrechner.aequivalentMG(molaritaet: 0.1, molareMasse: 180.16)!, 18.016, accuracy: 0.0001)
        XCTAssertNil(Analytikrechner.gehaltProzent(verbrauchML: 1, faktor: 1, aequivalentMG: 1, einwaageMG: 0))
    }

    func testVerduennung() {
        XCTAssertEqual(Konzentrationsrechner.verduennung(c1: 1, v1: nil, c2: 0.1, v2: 100)!, 10, accuracy: 1e-9)
        XCTAssertNil(Konzentrationsrechner.verduennung(c1: nil, v1: nil, c2: 1, v2: 1))
        XCTAssertEqual(Konzentrationsrechner.molaritaet(masseMG: 1801.6, volumenML: 100, molareMasse: 180.16)!, 0.1, accuracy: 1e-9)
    }

    func testDezimal() {
        XCTAssertEqual(Dezimal.lesen("1,5"), 1.5)
        XCTAssertEqual(Dezimal.lesen("1.234,5"), 1234.5)
        XCTAssertEqual(Dezimal.text(100.214, stellen: 2), "100,21")
    }
}
