import XCTest
#if canImport(SQLite3)
import SQLite3
#endif
@testable import PharmaCore

final class FSRSTests: XCTestCase {
    let fsrs = FSRS()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testNeueKarteGutGehtInLernschritt() {
        let stand = fsrs.planen(.neu(start), .gut, jetzt: start)
        XCTAssertEqual(stand.zustand, .lernen)
        XCTAssertEqual(stand.faellig.timeIntervalSince(start), 600, accuracy: 1)
        XCTAssertEqual(stand.wiederholungen, 1)
    }

    func testNeueKarteEinfachGehtDirektInWiederholung() {
        let stand = fsrs.planen(.neu(start), .einfach, jetzt: start)
        XCTAssertEqual(stand.zustand, .wiederholen)
        XCTAssertGreaterThanOrEqual(stand.intervallTage, 10)
    }

    func testIntervalleSteigenBeiGut() {
        var stand = fsrs.planen(.neu(start), .gut, jetzt: start)
        var jetzt = stand.faellig
        stand = fsrs.planen(stand, .gut, jetzt: jetzt)
        XCTAssertEqual(stand.zustand, .wiederholen)
        var vorher = stand.intervallTage
        for _ in 0..<4 {
            jetzt = stand.faellig
            stand = fsrs.planen(stand, .gut, jetzt: jetzt)
            XCTAssertGreaterThan(stand.intervallTage, vorher)
            vorher = stand.intervallTage
        }
    }

    func testReihenfolgeDerVorschau() {
        var stand = fsrs.planen(.neu(start), .gut, jetzt: start)
        stand = fsrs.planen(stand, .gut, jetzt: stand.faellig)
        let jetzt = stand.faellig
        let vorschau = fsrs.vorschau(stand, jetzt: jetzt)
        let schwer = vorschau[.schwer]!.intervallTage
        let gut = vorschau[.gut]!.intervallTage
        let einfach = vorschau[.einfach]!.intervallTage
        XCTAssertLessThan(schwer, gut)
        XCTAssertLessThan(gut, einfach)
        XCTAssertEqual(vorschau[.nochmal]!.zustand, .neuLernen)
        XCTAssertEqual(vorschau[.nochmal]!.fehlschlaege, 1)
    }

    func testVergessenSenktStabilitaet() {
        var stand = fsrs.planen(.neu(start), .gut, jetzt: start)
        stand = fsrs.planen(stand, .gut, jetzt: stand.faellig)
        stand = fsrs.planen(stand, .gut, jetzt: stand.faellig)
        let vorher = stand.stabilitaet
        let nachher = fsrs.planen(stand, .nochmal, jetzt: stand.faellig)
        XCTAssertLessThan(nachher.stabilitaet, vorher)
        XCTAssertLessThanOrEqual(nachher.schwierigkeit, 10)
        XCTAssertGreaterThanOrEqual(nachher.schwierigkeit, 1)
    }

    func testAbrufbarkeitBeiStabilitaet() {
        XCTAssertEqual(FSRS.abrufbarkeit(tage: 10, stabilitaet: 10), 0.9, accuracy: 0.001)
        XCTAssertEqual(FSRS.abrufbarkeit(tage: 0, stabilitaet: 3), 1, accuracy: 0.0001)
    }

    func testAbstandText() {
        XCTAssertEqual(FSRS.abstandText(von: start, bis: start.addingTimeInterval(30)), "<1 min")
        XCTAssertEqual(FSRS.abstandText(von: start, bis: start.addingTimeInterval(600)), "10 min")
        XCTAssertEqual(FSRS.abstandText(von: start, bis: start.addingTimeInterval(3 * 86_400)), "3 T")
        XCTAssertEqual(FSRS.abstandText(von: start, bis: start.addingTimeInterval(90 * 86_400)), "3 Mon.")
    }
}

final class LueckentextTests: XCTestCase {
    func testTeile() {
        let text = "Paracetamol hemmt {{COX-2}} im {{c1::ZNS::Ort}}."
        XCTAssertEqual(Lueckentext.frage(text), "Paracetamol hemmt […] im […].")
        XCTAssertEqual(Lueckentext.antwort(text), "Paracetamol hemmt COX-2 im ZNS.")
        XCTAssertEqual(Lueckentext.luecken(text), ["COX-2", "ZNS"])
        XCTAssertEqual(Lueckentext.alsAnki(text), "Paracetamol hemmt {{c1::COX-2}} im {{c1::ZNS}}.")
        XCTAssertFalse(Lueckentext.hatLuecke("ohne"))
        XCTAssertEqual(Lueckentext.frage("offen {{ohne Ende"), "offen {{ohne Ende")
    }

    func testVorschlagAusMarkierung() {
        let seite = "Grundlagen der Identitätsprüfung. Die IR-Spektroskopie gegen CRS ist die Methode der ersten Wahl (2.2.24). Danach folgt die DC."
        let vorschlag = Kartenvorschlag.lueckentext(markiert: "IR-Spektroskopie", seitentext: seite)
        XCTAssertEqual(vorschlag, "Die {{IR-Spektroskopie}} gegen CRS ist die Methode der ersten Wahl (2.2.24).")
        XCTAssertNil(Kartenvorschlag.lueckentext(markiert: "nicht vorhanden", seitentext: seite))
    }

    func testCSV() {
        XCTAssertEqual(CSV.zeile(["a", "b;c", "d\"e"]), "a;\"b;c\";\"d\"\"e\"")
        XCTAssertTrue(CSV.dokument([["x", "y"]]).hasPrefix("#separator:Semicolon"))
    }
}

#if canImport(SQLite3)
final class AnkiTests: XCTestCase {
    func testPaketEnthaeltDatenbankUndNotizen() throws {
        let paket = try AnkiPaket.erstellen(
            stapel: "PharmaTutor::[43] Arzneistoffanalytik",
            notizen: [
                .init(art: .basis, felder: ["Was prüft eine Grenzprüfung?", "Ob eine Verunreinigung unter dem Grenzwert liegt."], schlagwoerter: ["H", "Analytik"]),
                .init(art: .lueckentext, felder: ["IR gegen {{c1::CRS}}", ""]),
            ],
            medien: ["bild.png": Data([1, 2, 3])]
        )
        let eintraege = try Zip.eintraege(paket)
        XCTAssertNotNil(eintraege["collection.anki2"])
        XCTAssertEqual(eintraege["0"], Data([1, 2, 3]))
        XCTAssertEqual(String(decoding: eintraege["media"]!, as: UTF8.self), "{\"0\":\"bild.png\"}")

        let pfad = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).anki2")
        try eintraege["collection.anki2"]!.write(to: pfad)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(pfad.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        func zaehlen(_ tabelle: String) -> Int {
            var anweisung: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT count(*) FROM \(tabelle)", -1, &anweisung, nil)
            defer { sqlite3_finalize(anweisung) }
            sqlite3_step(anweisung)
            return Int(sqlite3_column_int(anweisung, 0))
        }
        XCTAssertEqual(zaehlen("notes"), 2)
        XCTAssertEqual(zaehlen("cards"), 2)
        XCTAssertEqual(zaehlen("col"), 1)
    }

    func testPruefsumme() {
        // SHA-1("Hallo") = 59d9a6df…
        XCTAssertEqual(AnkiPaket.pruefsumme("Hallo"), 0x59D9_A6DF)
    }
}
#endif
