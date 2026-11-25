import XCTest
@testable import PharmaCore

final class PrognoseTests: XCTestCase {
    func testStufenUndBegruendung() {
        let klausuren = (2019...2024).map { (jahr: Int) in KlausurDaten(id: "k\(jahr)", jahr: jahr) }
        var fragen: [AltfrageDaten] = []
        // Identitätsreaktionen in 5 von 6, zuletzt 2024
        for jahr in [2019, 2020, 2022, 2023, 2024] {
            fragen.append(AltfrageDaten(klausurID: "k\(jahr)", themen: ["Identitätsreaktionen"], punkte: 8))
        }
        // Polarimetrie nur einmal, lange her
        fragen.append(AltfrageDaten(klausurID: "k2019", themen: ["Polarimetrie"], punkte: 2))
        // Schreibweisen vereinheitlichen
        fragen.append(AltfrageDaten(klausurID: "k2021", themen: ["identitätsreaktionen "], punkte: 8))

        let prognose = Prognoserechner.berechnen(fragen: fragen, klausuren: klausuren,
                                                 betonteThemen: ["Komplexometrie"], aktuellesJahr: 2025)
        XCTAssertEqual(prognose.first?.thema, "Identitätsreaktionen")
        XCTAssertEqual(prognose.first?.stufe, .sehrWahrscheinlich)
        XCTAssertEqual(prognose.first?.anzahlKlausuren, 6)
        XCTAssertEqual(prognose.first?.begruendung, "In 6 von 6 Altklausuren, zuletzt 2024, Ø 8 Punkte.")

        let polarimetrie = prognose.first { $0.thema == "Polarimetrie" }
        XCTAssertEqual(polarimetrie?.stufe, .moeglich)

        let komplexometrie = prognose.first { $0.thema == "Komplexometrie" }
        XCTAssertEqual(komplexometrie?.stufe, .wahrscheinlich)
        XCTAssertTrue(komplexometrie?.begruendung.contains("laut Notiz") ?? false)
    }

    func testLeer() {
        XCTAssertTrue(Prognoserechner.berechnen(fragen: [], klausuren: [], betonteThemen: [], aktuellesJahr: 2025).isEmpty)
    }

    func testBewertung() {
        XCTAssertTrue(Klausurbewertung.zahlRichtig(antwort: "100,4 %", loesung: 100.2))
        XCTAssertFalse(Klausurbewertung.zahlRichtig(antwort: "95", loesung: 100.2))
        XCTAssertFalse(Klausurbewertung.zahlRichtig(antwort: "abc", loesung: 1))
        XCTAssertEqual(Klausurbewertung.mcPunkte(auswahl: [1, 2], richtig: [1, 2], punkte: 2), 2)
        XCTAssertEqual(Klausurbewertung.mcPunkte(auswahl: [1], richtig: [1, 2], punkte: 2), 0)
        XCTAssertEqual(Klausurbewertung.note(prozent: 90), "1")
        XCTAssertEqual(Klausurbewertung.note(prozent: 49.9), "5")
    }
}
