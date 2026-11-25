import XCTest
@testable import PharmaCore

final class LernplanerTests: XCTestCase {
    var kalender: Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "Europe/Berlin")!
        k.firstWeekday = 2
        return k
    }

    /// Montag, 30.11.2026
    var montag: Date { kalender.startOfDay(for: Curriculum.datum(2026, 11, 30)) }

    func tag(_ offset: Int) -> Date {
        kalender.date(byAdding: .day, value: offset, to: montag)!
    }

    func minutenProTag(_ plan: Lernplan) -> [Date: Int] {
        plan.einheiten.reduce(into: [:]) { $0[$1.tag, default: 0] += $1.minuten }
    }

    func testWochenplanRawValue() {
        let plan = Wochenplan(minuten: [60, 60, 60, 60, 60, 30, 0])
        XCTAssertEqual(Wochenplan(rawValue: plan.rawValue), plan)
        XCTAssertNil(Wochenplan(rawValue: "1,2,3"))
        XCTAssertEqual(Wochenplan.index(fuer: montag, kalender: kalender), 0)
        XCTAssertEqual(Wochenplan.index(fuer: tag(6), kalender: kalender), 6)
    }

    func testKapazitaetWirdEingehalten() {
        let wochenplan = Wochenplan(minuten: [90, 90, 90, 90, 90, 60, 0])
        let ziele = [
            LernZiel(id: "a", pruefungstag: tag(10), bedarfMinuten: 2000),
            LernZiel(id: "b", pruefungstag: tag(12), bedarfMinuten: 2000),
        ]
        let plan = Lernplaner.planen(ziele: ziele, wochenplan: wochenplan, ab: montag, kalender: kalender)
        for (t, minuten) in minutenProTag(plan) {
            XCTAssertLessThanOrEqual(minuten, wochenplan.minuten(fuer: t, kalender: kalender))
        }
        XCTAssertNil(minutenProTag(plan)[tag(6)], "Sonntag hat keine Lernzeit")
        XCTAssertFalse(plan.fehlendeMinuten.isEmpty, "Zu viel Aufwand muss als fehlend gemeldet werden")
    }

    func testKeinePlanungAmOderNachDemPruefungstag() {
        let ziele = [LernZiel(id: "a", pruefungstag: tag(5), bedarfMinuten: 600)]
        let plan = Lernplaner.planen(ziele: ziele, wochenplan: .standard, ab: montag, kalender: kalender)
        XCTAssertFalse(plan.einheiten.isEmpty)
        XCTAssertTrue(plan.einheiten.allSatisfy { $0.tag < tag(5) })
        XCTAssertEqual(plan.einheiten.map(\.minuten).reduce(0, +), 600)
        XCTAssertTrue(plan.fehlendeMinuten.isEmpty)
    }

    func testEingangspruefungWirdPriorisiert() {
        let wochenplan = Wochenplan(minuten: Array(repeating: 90, count: 7))
        let ziele = [
            LernZiel(id: "abschluss", pruefungstag: tag(7), bedarfMinuten: 900),
            LernZiel(id: "eingang", pruefungstag: tag(7), bedarfMinuten: 900, istEingangspruefung: true),
        ]
        let plan = Lernplaner.planen(ziele: ziele, wochenplan: wochenplan, ab: montag, kalender: kalender)
        let summe = plan.einheiten.reduce(into: [String: Int]()) { $0[$1.zielID, default: 0] += $1.minuten }
        XCTAssertGreaterThan(summe["eingang"] ?? 0, summe["abschluss"] ?? 0)
    }

    func testVerpassteTageWerdenUmverteilt() {
        let ziele = [LernZiel(id: "a", pruefungstag: tag(10), bedarfMinuten: 600)]
        let normal = Lernplaner.planen(ziele: ziele, wochenplan: .standard, ab: montag, kalender: kalender)
        // Drei Tage verpasst, nichts erledigt: der gleiche Aufwand verteilt sich auf weniger Tage.
        let spaeter = Lernplaner.planen(ziele: ziele, wochenplan: .standard, ab: tag(3), kalender: kalender)
        XCTAssertEqual(spaeter.einheiten.map(\.minuten).reduce(0, +), 600)
        XCTAssertTrue(spaeter.einheiten.allSatisfy { $0.tag >= tag(3) })
        let tageNormal = Set(normal.einheiten.map(\.tag)).count
        let tageSpaeter = Set(spaeter.einheiten.map(\.tag)).count
        XCTAssertLessThanOrEqual(tageSpaeter, tageNormal)
    }

    func testBelegteZeitUndBlockpraktikum() {
        let wochenplan = Wochenplan(minuten: Array(repeating: 120, count: 7))
        let ziele = [LernZiel(id: "a", pruefungstag: tag(4), bedarfMinuten: 5000)]
        let plan = Lernplaner.planen(ziele: ziele, wochenplan: wochenplan, ab: montag,
                                     belegteMinuten: [montag: 90],
                                     kapazitaetsGrenzen: [tag(1): 30],
                                     kalender: kalender)
        let proTag = minutenProTag(plan)
        XCTAssertEqual(proTag[montag], 30)
        XCTAssertEqual(proTag[tag(1)], 30)
        XCTAssertEqual(proTag[tag(2)], 120)
    }

    func testErledigteMinutenReduzierenBedarf() {
        let ziele = [LernZiel(id: "a", pruefungstag: tag(10), bedarfMinuten: 600, erledigtMinuten: 450)]
        let plan = Lernplaner.planen(ziele: ziele, wochenplan: .standard, ab: montag, kalender: kalender)
        XCTAssertEqual(plan.einheiten.map(\.minuten).reduce(0, +), 150)
    }

    func testVergangenePruefungErgibtLeerenPlan() {
        let ziele = [LernZiel(id: "a", pruefungstag: tag(-2), bedarfMinuten: 600)]
        let plan = Lernplaner.planen(ziele: ziele, wochenplan: .standard, ab: montag, kalender: kalender)
        XCTAssertTrue(plan.einheiten.isEmpty)
    }

    func testDauerText() {
        XCTAssertEqual(Dauer.text(minuten: 45), "45 min")
        XCTAssertEqual(Dauer.text(minuten: 120), "2 h")
        XCTAssertEqual(Dauer.text(minuten: 150), "2 h 30 min")
    }
}
