import XCTest
@testable import PharmaCore

final class LfdNrTests: XCTestCase {
    func testTeile() {
        XCTAssertEqual(LfdNr.teile("[39+42]"), ["39", "42"])
        XCTAssertEqual(LfdNr.teile("67a+66"), ["67a", "66"])
        XCTAssertEqual(LfdNr.teile("43"), ["43"])
    }

    func testAnzeige() {
        XCTAssertEqual(LfdNr.anzeige("43"), "[43]")
        XCTAssertEqual(LfdNr.anzeige("[39+42]"), "[39+42]")
    }

    func testSuche() {
        XCTAssertTrue(LfdNr.passt(lfdNr: "43", bezeichnung: "Arzneistoffanalytik", suchbegriff: "[43]"))
        XCTAssertTrue(LfdNr.passt(lfdNr: "39+42", bezeichnung: "Pharmakologie", suchbegriff: "[42]"))
        XCTAssertFalse(LfdNr.passt(lfdNr: "44", bezeichnung: "Arzneimittelanalytik", suchbegriff: "[43]"))
        XCTAssertTrue(LfdNr.passt(lfdNr: "67b", bezeichnung: "Klinische Pharmazie II", suchbegriff: "67b"))
        XCTAssertTrue(LfdNr.passt(lfdNr: "41", bezeichnung: "Immunologie, Impfstoffe und Sera", suchbegriff: "impfstoffe"))
        XCTAssertTrue(LfdNr.passt(lfdNr: "41", bezeichnung: "Immunologie", suchbegriff: ""))
    }
}

final class VoraussetzungsTests: XCTestCase {
    /// Stand laut Curriculum: [44] bestanden, Ph1 vorhanden.
    let aktuellerStand = StudienStand(bestandeneKurse: ["44"], zulassungen: ["Ph1"])

    func kurs(_ nr: String) throws -> CurriculumKurs {
        try XCTUnwrap(Curriculum.alleKurse.first { LfdNr.teile($0.lfdNr).contains(nr) }, "Kurs \(nr) fehlt")
    }

    func testFreigeschaltetDurch44() throws {
        for nr in ["52", "63"] {
            let k = try kurs(nr)
            let freigabe = Freigabe.ermitteln(status: k.status, regel: k.voraussetzungen, stand: aktuellerStand)
            XCTAssertEqual(freigabe, .freigeschaltet(hinweise: []), "[\(nr)] sollte freigeschaltet sein")
        }
    }

    func test53BrauchtEingangspruefung40() throws {
        let k = try kurs("53")
        let freigabe = Freigabe.ermitteln(status: k.status, regel: k.voraussetzungen, stand: aktuellerStand)
        guard case .blockiert(let fehlend) = freigabe else { return XCTFail("[53] sollte blockiert sein") }
        XCTAssertEqual(fehlend.count, 1)
        XCTAssertTrue(fehlend[0].contains("[40]"))

        var stand = aktuellerStand
        stand.bestandeneTeilpruefungen.insert(TeilpruefungSchluessel(lfdNr: "40", typ: .schriftlicheEingangspruefung))
        XCTAssertEqual(Freigabe.ermitteln(status: k.status, regel: k.voraussetzungen, stand: stand), .freigeschaltet(hinweise: []))
    }

    func test64Blockiert() throws {
        let k = try kurs("64")
        guard case .blockiert(let fehlend) = Freigabe.ermitteln(status: k.status, regel: k.voraussetzungen, stand: aktuellerStand) else {
            return XCTFail("[64] sollte blockiert sein")
        }
        XCTAssertEqual(fehlend.count, 3) // [43], [53], Teilnahme [52]
    }

    func testEineDarfFehlen() throws {
        let k = try kurs("75")
        let stand = StudienStand(bestandeneKurse: ["62", "63", "64"])
        guard case .freigeschaltet(let hinweise) = Freigabe.ermitteln(status: k.status, regel: k.voraussetzungen, stand: stand) else {
            return XCTFail("[75] sollte mit einer fehlenden Veranstaltung freigeschaltet sein")
        }
        XCTAssertEqual(hinweise.count, 1)

        let zuWenig = StudienStand(bestandeneKurse: ["62", "63"])
        if case .freigeschaltet = Freigabe.ermitteln(status: k.status, regel: k.voraussetzungen, stand: zuWenig) {
            XCTFail("[75] darf mit zwei fehlenden Veranstaltungen nicht freigeschaltet sein")
        }
    }

    func testBestandenBleibtBestanden() throws {
        let k = try kurs("44")
        XCTAssertEqual(Freigabe.ermitteln(status: k.status, regel: k.voraussetzungen, stand: StudienStand()), .bestanden)
    }

    func testTeilnahmeGenuegt() {
        let regel = VoraussetzungsRegel.teilnahme("52")
        XCTAssertTrue(regel.pruefe(StudienStand(teilgenommeneKurse: ["52"])).erfuellt)
        XCTAssertFalse(regel.pruefe(StudienStand()).erfuellt)
    }

    func testCodableRoundtrip() throws {
        for k in Curriculum.alleKurse {
            let daten = try XCTUnwrap(k.voraussetzungen.alsDaten())
            XCTAssertEqual(VoraussetzungsRegel.aus(daten), k.voraussetzungen)
        }
    }

    func testBeschreibung() throws {
        XCTAssertEqual(try kurs("63").voraussetzungen.beschreibung, "Zulassung Ph1 + ([43] oder [44])")
        XCTAssertEqual(VoraussetzungsRegel.keine.beschreibung, "Keine Voraussetzungen")
    }
}

final class CurriculumTests: XCTestCase {
    func testSemesterVorhanden() {
        let nummern = Curriculum.semester.map(\.nummer)
        for n in [1, 2, 3, 4, 5, 6, 7, 8, Curriculum.nummerStaatsexamen] {
            XCTAssertTrue(nummern.contains(n), "Semester \(n) fehlt")
        }
        XCTAssertEqual(Set(nummern).count, nummern.count, "Semesternummern müssen eindeutig sein")
        XCTAssertEqual(Curriculum.semester.filter(\.istAktuell).map(\.nummer), [5])
    }

    func testLfdNrEindeutig() {
        let teile = Curriculum.alleKurse.flatMap { LfdNr.teile($0.lfdNr) }
        XCTAssertEqual(Set(teile).count, teile.count, "Lfd. Nr. doppelt vergeben")
    }

    func testVoraussetzungenVerweisenAufVorhandeneKurse() {
        let alle = Set(Curriculum.alleKurse.flatMap { LfdNr.teile($0.lfdNr) })
        for k in Curriculum.alleKurse {
            for ref in k.voraussetzungen.referenzierteKurse {
                XCTAssertTrue(alle.contains(ref), "[\(k.lfdNr)] verweist auf unbekannte [\(ref)]")
            }
        }
    }

    func testStatus() {
        XCTAssertEqual(Curriculum.alleKurse.filter { $0.status == .bestanden }.map(\.lfdNr), ["44"])
        XCTAssertEqual(Curriculum.alleKurse.first { $0.lfdNr == "43" }?.status, .offen)
    }

    func testLernpfadeVollstaendig() {
        let schluessel = Set(Curriculum.lernpfade.map(\.schluessel))
        for k in Curriculum.alleKurse {
            if let pfad = k.lernpfad { XCTAssertTrue(schluessel.contains(pfad), "Unbekannter Lernpfad \(pfad)") }
        }
        let medchem = Curriculum.alleKurse.filter { $0.lernpfad == "medchem" }.map(\.lernpfadTeil).sorted()
        XCTAssertEqual(medchem, [1, 2, 3, 4])
        let pharmakologie = Curriculum.alleKurse.filter { $0.lernpfad == "pharmakologie" }.map(\.lernpfadTeil).sorted()
        XCTAssertEqual(pharmakologie, [1, 2, 3])
    }

    func testAnmeldepflichtigeTeilpruefungenNurBeiAnmeldepflichtigenKursen() {
        for k in Curriculum.alleKurse where k.teilpruefungen.contains(where: \.anmeldepflichtig) {
            XCTAssertTrue(k.anmeldepflicht || k.lfdNr == "40", "[\(k.lfdNr)] hat anmeldepflichtige Prüfungen, ist aber nicht mit * markiert")
        }
    }
}

final class ZeitTests: XCTestCase {
    func testCountdownText() {
        XCTAssertEqual(Countdown.text(tage: 0), "heute")
        XCTAssertEqual(Countdown.text(tage: 1), "morgen")
        XCTAssertEqual(Countdown.text(tage: 12), "in 12 Tagen")
        XCTAssertEqual(Countdown.text(tage: -3), "vor 3 Tagen")
    }

    func testTage() {
        let a = Curriculum.datum(2026, 11, 25)
        let b = Curriculum.datum(2026, 12, 5)
        XCTAssertEqual(Countdown.tage(von: a, bis: b), 10)
    }
}
