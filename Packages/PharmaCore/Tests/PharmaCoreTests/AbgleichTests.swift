import XCTest
@testable import PharmaCore

final class AbgleichTests: XCTestCase {
    private let mac = UUID()
    private let ipad = UUID()

    private func stand(_ geraet: UUID, basis: UUID?, minute: Int, schema: Int = Abgleich.schemaVersion) -> Abgleich.Stand {
        Abgleich.Stand(basisID: basis, geraetID: geraet, geraetName: geraet == mac ? "Mac" : "iPad",
                       erstelltAm: Date(timeIntervalSince1970: TimeInterval(minute * 60)), appVersion: "1.0", schemaVersion: schema)
    }

    func testNichtsOhneFremde() {
        let eigener = stand(mac, basis: nil, minute: 1)
        XCTAssertEqual(Abgleich.entscheiden(fremde: [eigener], eigeneGeraetID: mac, meinStandID: eigener.id,
                                            lokalGeaendert: false, erledigt: []), .nichts)
    }

    func testVorspulen() {
        // Mac exportiert a1, iPad übernimmt a1, lernt und exportiert b1 (Basis a1).
        let a1 = stand(mac, basis: nil, minute: 1)
        let b1 = stand(ipad, basis: a1.id, minute: 5)
        XCTAssertEqual(Abgleich.entscheiden(fremde: [a1, b1], eigeneGeraetID: mac, meinStandID: a1.id,
                                            lokalGeaendert: false, erledigt: []), .uebernehmen(b1))
    }

    func testLokaleAenderungFuehrtZuKonflikt() {
        let a1 = stand(mac, basis: nil, minute: 1)
        let b1 = stand(ipad, basis: a1.id, minute: 5)
        XCTAssertEqual(Abgleich.entscheiden(fremde: [b1], eigeneGeraetID: mac, meinStandID: a1.id,
                                            lokalGeaendert: true, erledigt: []), .konflikt(b1))
    }

    func testFremderStandOhneEigeneBasisIstKonflikt() {
        // Mac hat a2 exportiert, das iPad kennt nur a1 und exportiert b2 auf Basis a1.
        let a1 = stand(mac, basis: nil, minute: 1)
        let a2 = stand(mac, basis: a1.id, minute: 3)
        let b2 = stand(ipad, basis: a1.id, minute: 6)
        XCTAssertEqual(Abgleich.entscheiden(fremde: [a2, b2], eigeneGeraetID: mac, meinStandID: a2.id,
                                            lokalGeaendert: false, erledigt: []), .konflikt(b2))
    }

    func testNeuesGeraetUebernimmt() {
        let a1 = stand(mac, basis: nil, minute: 1)
        XCTAssertEqual(Abgleich.entscheiden(fremde: [a1], eigeneGeraetID: ipad, meinStandID: nil,
                                            lokalGeaendert: false, erledigt: []), .uebernehmen(a1))
        XCTAssertEqual(Abgleich.entscheiden(fremde: [a1], eigeneGeraetID: ipad, meinStandID: nil,
                                            lokalGeaendert: true, erledigt: []), .konflikt(a1))
    }

    func testErledigteUndNeuereVersion() {
        let b1 = stand(ipad, basis: nil, minute: 5)
        XCTAssertEqual(Abgleich.entscheiden(fremde: [b1], eigeneGeraetID: mac, meinStandID: nil,
                                            lokalGeaendert: false, erledigt: [b1.id]), .nichts)
        let zukunft = stand(ipad, basis: nil, minute: 7, schema: Abgleich.schemaVersion + 1)
        XCTAssertEqual(Abgleich.entscheiden(fremde: [zukunft], eigeneGeraetID: mac, meinStandID: nil,
                                            lokalGeaendert: false, erledigt: []), .neuereVersion(zukunft))
    }

    func testJSONRundreise() throws {
        let a = stand(mac, basis: UUID(), minute: 42)
        XCTAssertEqual(try Abgleich.Stand.aus(json: a.json()), a)
    }

    func testDateiname() {
        let id = UUID(uuidString: "1A2B3C4D-0000-0000-0000-000000000000")!
        XCTAssertEqual(Abgleich.dateiname(geraetName: "Mein MacBook Air", geraetID: id), "PharmaTutor-Mein-MacBook-Air-1A2B3C4D")
        XCTAssertEqual(Abgleich.dateiname(geraetName: "  ", geraetID: id), "PharmaTutor-Geraet-1A2B3C4D")
        XCTAssertEqual(Abgleich.icloudPlatzhalterZiel(".PharmaTutor-iPad-1.json.icloud"), "PharmaTutor-iPad-1.json")
        XCTAssertNil(Abgleich.icloudPlatzhalterZiel("PharmaTutor-iPad-1.json"))
    }
}
