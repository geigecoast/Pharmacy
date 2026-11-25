import XCTest
@testable import PharmaCore

final class AnalyseTests: XCTestCase {
    func testBereitschaft() {
        XCTAssertNil(Analyse.bereitschaft(lernanteil: nil, kartenLernstand: nil, probeklausur: nil))
        XCTAssertEqual(Analyse.bereitschaft(lernanteil: 0.5, kartenLernstand: nil, probeklausur: nil)!, 0.5, accuracy: 1e-9)
        let wert = Analyse.bereitschaft(lernanteil: 1, kartenLernstand: 0.5, probeklausur: 0)!
        XCTAssertEqual(wert, 0.4 + 0.175, accuracy: 1e-9)
        XCTAssertEqual(Analyse.bereitschaft(lernanteil: 2, kartenLernstand: nil, probeklausur: nil)!, 1, accuracy: 1e-9)
    }

    func testThemen() {
        let werte = Analyse.themen([
            ("Komplexometrie", 0.2, 1), ("komplexometrie", 0.6, 1), ("Spektroskopie", 0.9, 2), ("", 1, 1),
        ])
        XCTAssertEqual(werte.map(\.thema), ["Komplexometrie", "Spektroskopie"])
        XCTAssertEqual(werte[0].wert, 0.4, accuracy: 1e-9)
    }

    func testZeitprognose() {
        let gut = Analyse.zeitprognose(restMinuten: 600, tageBis: 10, tempoProTag: 120)
        XCTAssertTrue(gut.reicht)
        XCTAssertEqual(gut.benoetigtProTag, 60)
        XCTAssertEqual(gut.pufferTage, 5)
        let knapp = Analyse.zeitprognose(restMinuten: 3000, tageBis: 10, tempoProTag: 120)
        XCTAssertFalse(knapp.reicht)
        XCTAssertEqual(knapp.pufferTage, -15)
        XCTAssertTrue(Analyse.zeitprognose(restMinuten: 0, tageBis: 3, tempoProTag: 0).reicht)
    }

    func testLernminutenOhneDoppelzaehlung() {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let tag = Curriculum.datum(2026, 11, 25)
        let minuten = Analyse.lernminutenProTag(erfasst: [(tag, 30), (tag, 20)], lerneinheiten: [(tag, 45)], kalender: kalender)
        XCTAssertEqual(minuten[kalender.startOfDay(for: tag)], 50)
    }

    func testStundenText() {
        XCTAssertEqual(Analyse.stundenText(700), "11 h 40")
        XCTAssertEqual(Analyse.stundenText(45), "45 min")
        XCTAssertEqual(Analyse.stundenText(120), "2 h")
    }
}
