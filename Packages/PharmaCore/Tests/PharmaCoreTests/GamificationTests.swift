import XCTest
@testable import PharmaCore

final class GamificationTests: XCTestCase {
    private var kalender: Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "Europe/Berlin")!
        k.firstWeekday = 2
        k.minimumDaysInFirstWeek = 4
        return k
    }

    /// Mittwoch, 25.11.2026.
    private var heute: Date { kalender.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 15))! }

    private func tag(_ versatz: Int) -> Date {
        kalender.date(byAdding: .day, value: versatz, to: kalender.startOfDay(for: heute))!
    }

    private func minuten(_ versaetze: [Int], je: Double = 30) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: versaetze.map { (tag($0), je) })
    }

    func testLeer() {
        let s = Gamification.serie(minutenProTag: [:], tagesziel: 20, ruhetagErlaubt: true, heute: heute, kalender: kalender)
        XCTAssertEqual(s.aktuell, 0)
        XCTAssertEqual(s.laengste, 0)
        XCTAssertFalse(s.heuteErreicht)
    }

    func testHeuteNochOffenReisstNicht() {
        let s = Gamification.serie(minutenProTag: minuten([-3, -2, -1]), tagesziel: 20, ruhetagErlaubt: false, heute: heute, kalender: kalender)
        XCTAssertEqual(s.aktuell, 3)
        XCTAssertFalse(s.heuteErreicht)
        let mitHeute = Gamification.serie(minutenProTag: minuten([-3, -2, -1, 0]), tagesziel: 20, ruhetagErlaubt: false, heute: heute, kalender: kalender)
        XCTAssertEqual(mitHeute.aktuell, 4)
        XCTAssertTrue(mitHeute.heuteErreicht)
    }

    func testTageszielMussErreichtSein() {
        var daten = minuten([-2, -1])
        daten[tag(-1)] = 5
        let s = Gamification.serie(minutenProTag: daten, tagesziel: 20, ruhetagErlaubt: false, heute: heute, kalender: kalender)
        XCTAssertEqual(s.aktuell, 0)
        XCTAssertEqual(s.laengste, 1)
    }

    func testRuhetag() {
        // Mo 23.11. fehlt, sonst gelernt (Do 19.11. bis Mi 25.11.)
        let daten = minuten([-6, -5, -4, -3, -1, 0])
        let ohne = Gamification.serie(minutenProTag: daten, tagesziel: 20, ruhetagErlaubt: false, heute: heute, kalender: kalender)
        XCTAssertEqual(ohne.aktuell, 2)
        XCTAssertEqual(ohne.laengste, 4)
        let mit = Gamification.serie(minutenProTag: daten, tagesziel: 20, ruhetagErlaubt: true, heute: heute, kalender: kalender)
        XCTAssertEqual(mit.aktuell, 6)
        XCTAssertTrue(mit.ruhetagDieseWocheGenutzt)
    }

    func testZweiFehltageBeendenSerie() {
        let daten = minuten([-6, -5, -4, -1, 0])
        let s = Gamification.serie(minutenProTag: daten, tagesziel: 20, ruhetagErlaubt: true, heute: heute, kalender: kalender)
        XCTAssertEqual(s.aktuell, 2)
        XCTAssertEqual(s.laengste, 3)
    }

    func testNurEinRuhetagProWoche() {
        // Woche Mo 16. bis So 22.11.: Di 17. und Do 19. fehlen → der zweite Fehltag derselben Woche beendet die Serie.
        let daten = minuten([-9, -7, -5, -4, -3, -2, -1, 0])
        let s = Gamification.serie(minutenProTag: daten, tagesziel: 20, ruhetagErlaubt: true, heute: heute, kalender: kalender)
        XCTAssertEqual(s.aktuell, 6)
    }

    func testWochenMitZiel() {
        let daten = minuten([-9, -8, -2, -1], je: 200)
        XCTAssertEqual(Gamification.wochenMitZiel(minutenProTag: daten, wochenziel: 300, kalender: kalender), 2)
        XCTAssertEqual(Gamification.wochenMitZiel(minutenProTag: daten, wochenziel: 500, kalender: kalender), 0)
    }

    func testPunkteUndStufen() {
        let a = Gamification.Aktivitaet(lernminuten: 100, wiederholungen: 50, quizRunden: 2, probeklausuren: 1,
                                        fehlerVerstanden: 3, teilpruefungenBestanden: 1)
        XCTAssertEqual(Gamification.punkte(a), 100 + 100 + 30 + 60 + 30 + 250)

        XCTAssertEqual(Gamification.stufe(punkte: 0).nummer, 1)
        XCTAssertEqual(Gamification.stufe(punkte: 249).nummer, 1)
        let zwei = Gamification.stufe(punkte: 500)
        XCTAssertEqual(zwei.nummer, 2)
        XCTAssertEqual(zwei.titel, "Rezeptur")
        XCTAssertEqual(zwei.naechsteAb, 750)
        XCTAssertEqual(zwei.fortschritt, 0.5, accuracy: 0.001)
        let oben = Gamification.stufe(punkte: 1_000_000)
        XCTAssertEqual(oben.nummer, Gamification.stufentitel.count)
        XCTAssertNil(oben.naechsteAb)
        XCTAssertEqual(oben.fortschritt, 1)
    }

    func testAbzeichen() {
        var s = Gamification.Statistik()
        XCTAssertTrue(Gamification.erreichteAbzeichen(s).isEmpty)
        s.aktivitaet.wiederholungen = 1
        s.laengsteSerie = 8
        s.aktivitaet.lernminuten = 600
        s.besteProbeklausurProzent = 92
        XCTAssertEqual(Set(Gamification.erreichteAbzeichen(s)), [.ersteWiederholung, .serie7, .stunden10, .probeklausur90])
        XCTAssertEqual(Gamification.Abzeichen.serie30.fortschritt(s).wert, 8)
        XCTAssertEqual(Gamification.Abzeichen.serie30.fortschritt(s).ziel, 30)
    }
}
