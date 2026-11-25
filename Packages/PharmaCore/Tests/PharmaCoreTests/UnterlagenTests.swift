import XCTest
#if canImport(Compression)
import Compression
#endif
@testable import PharmaCore

final class ZipTests: XCTestCase {
    func testArchivRundreise() throws {
        let archiv = Zip.archiv([
            ("hallo.txt", Data("Hallo Welt".utf8)),
            ("ordner/ä.txt", Data("Umlaute: äöüß".utf8)),
            ("leer.txt", Data()),
        ])
        let eintraege = try Zip.eintraege(archiv)
        XCTAssertEqual(eintraege.count, 3)
        XCTAssertEqual(String(decoding: eintraege["hallo.txt"]!, as: UTF8.self), "Hallo Welt")
        XCTAssertEqual(String(decoding: eintraege["ordner/ä.txt"]!, as: UTF8.self), "Umlaute: äöüß")
        XCTAssertEqual(eintraege["leer.txt"], Data())
    }

    func testCRC32() {
        XCTAssertEqual(Zip.crc32(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testUngueltigesArchiv() {
        XCTAssertThrowsError(try Zip.eintraege(Data("kein zip".utf8)))
    }

    #if canImport(Compression)
    /// Baut ein Archiv mit einem Deflate-Eintrag, wie ihn PowerPoint schreibt.
    func testDeflate() throws {
        let inhalt = Array(String(repeating: "Paracetamol hemmt die Cyclooxygenase. ", count: 40).utf8)
        var komprimiert = [UInt8](repeating: 0, count: inhalt.count + 64)
        let laenge = compression_encode_buffer(&komprimiert, komprimiert.count, inhalt, inhalt.count, nil, COMPRESSION_ZLIB)
        XCTAssertGreaterThan(laenge, 0)
        komprimiert = Array(komprimiert.prefix(laenge))

        // Archiv mit einem Deflate-Eintrag von Hand zusammensetzen
        let name = Array("x.txt".utf8)
        var bytes = [UInt8]()
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let crc = Int(Zip.crc32(inhalt))
        bytes += le32(0x0403_4B50) + le16(20) + le16(0) + le16(8) + le16(0) + le16(0)
        bytes += le32(crc) + le32(komprimiert.count) + le32(inhalt.count) + le16(name.count) + le16(0) + name + komprimiert
        let verzeichnisStart = bytes.count
        bytes += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(8) + le16(0) + le16(0)
        bytes += le32(crc) + le32(komprimiert.count) + le32(inhalt.count) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + name
        let verzeichnisLaenge = bytes.count - verzeichnisStart
        bytes += le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1) + le32(verzeichnisLaenge) + le32(verzeichnisStart) + le16(0)
        let eintraege = try Zip.eintraege(Data(bytes))
        XCTAssertEqual(eintraege["x.txt"], Data(inhalt))
    }
    #endif

    func testPptxText() throws {
        func folie(_ absaetze: [String]) -> Data {
            let p = absaetze.map { "<a:p><a:r><a:t>\($0)</a:t></a:r></a:p>" }.joined()
            return Data("<?xml version=\"1.0\"?><p:sld xmlns:p=\"p\" xmlns:a=\"a\"><p:cSld><p:spTree><p:sp><p:txBody>\(p)</p:txBody></p:sp></p:spTree></p:cSld></p:sld>".utf8)
        }
        let pptx = Zip.archiv([
            ("[Content_Types].xml", Data("<Types/>".utf8)),
            ("ppt/slides/slide10.xml", folie(["Folie zehn"])),
            ("ppt/slides/slide2.xml", folie(["Acetylsalicylsäure", "irreversible COX-Hemmung"])),
            ("ppt/slides/slide1.xml", folie(["Titel: NSAR"])),
            ("ppt/slides/_rels/slide1.xml.rels", Data("<Relationships/>".utf8)),
        ])
        let folien = try PptxText.folien(aus: pptx)
        XCTAssertEqual(folien, ["Titel: NSAR", "Acetylsalicylsäure\nirreversible COX-Hemmung", "Folie zehn"])
    }
}

final class UnterlagenTests: XCTestCase {
    func testDokumentTyp() {
        XCTAssertEqual(DokumentTyp.typ(fuerEndung: "PDF"), .pdf)
        XCTAssertEqual(DokumentTyp.typ(fuerEndung: "jpeg"), .scan)
        XCTAssertEqual(DokumentTyp.typ(fuerEndung: "pptx"), .praesentation)
        XCTAssertEqual(DokumentTyp.typ(fuerEndung: "m4a"), .audio)
        XCTAssertNil(DokumentTyp.typ(fuerEndung: "exe"))
    }

    func testTranskriptAbschnitte() {
        let woerter: [(zeit: Double, text: String)] = [
            (0, "Heute"), (0.5, "geht"), (1, "es"), (1.5, "um"), (2, "Opioide."),
            (3, "Morphin"), (10, "wirkt"), (25, "agonistisch"), (26, "am"), (27, "µ-Rezeptor"),
        ]
        let abschnitte = Transkript.abschnitte(woerter: woerter, maxDauer: 20)
        XCTAssertEqual(abschnitte.count, 3)
        XCTAssertEqual(abschnitte[0], Transkriptabschnitt(start: 0, text: "Heute geht es um Opioide."))
        XCTAssertEqual(abschnitte[1].start, 3)
        XCTAssertEqual(abschnitte[2].text, "am µ-Rezeptor")
    }

    func testFolieZuZeit() {
        let marken = [Folienmarke(zeit: 0, seitenIndex: 0), Folienmarke(zeit: 120, seitenIndex: 3), Folienmarke(zeit: 60, seitenIndex: 1)]
        XCTAssertEqual(Transkript.folie(zu: 30, marken: marken), 0)
        XCTAssertEqual(Transkript.folie(zu: 90, marken: marken), 1)
        XCTAssertEqual(Transkript.folie(zu: 500, marken: marken), 3)
        XCTAssertNil(Transkript.folie(zu: 10, marken: []))
    }

    func testZeitText() {
        XCTAssertEqual(Transkript.zeitText(754), "12:34")
        XCTAssertEqual(Transkript.zeitText(3909), "1:05:09")
    }

    func testTextausschnitt() {
        let text = "Die Gehaltsbestimmung erfolgt nach Ph. Eur. durch Titration mit Perchlorsäure in wasserfreier Essigsäure."
        let ausschnitt = Textausschnitt.um("titration", in: text, umfeld: 10)
        XCTAssertTrue(ausschnitt.contains("Titration"))
        XCTAssertTrue(ausschnitt.hasPrefix("…"))
        XCTAssertTrue(ausschnitt.hasSuffix("…"))
    }
}
