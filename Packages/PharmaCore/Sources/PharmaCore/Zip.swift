import Foundation
#if canImport(Compression)
import Compression
#endif

/// Minimaler ZIP-Leser (gespeichert und Deflate) und -Schreiber (gespeichert), z. B. für PPTX und Anki.
public enum Zip {
    public enum Fehler: Error, Equatable {
        case ungueltigesArchiv
        case nichtUnterstuetzteKompression(UInt16)
        case entpackenFehlgeschlagen(String)
    }

    // MARK: Lesen

    /// Liest alle Einträge eines ZIP-Archivs.
    public static func eintraege(_ daten: Data) throws -> [String: Data] {
        let bytes = [UInt8](daten)
        guard bytes.count >= 22 else { throw Fehler.ungueltigesArchiv }

        // Ende des zentralen Verzeichnisses suchen
        var eocd: Int?
        let untergrenze = max(0, bytes.count - 22 - 65_535)
        var i = bytes.count - 22
        while i >= untergrenze {
            if lese32(bytes, i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard let ende = eocd else { throw Fehler.ungueltigesArchiv }
        let anzahl = Int(lese16(bytes, ende + 10))
        var position = Int(lese32(bytes, ende + 16))

        var ergebnis: [String: Data] = [:]
        for _ in 0..<anzahl {
            guard position + 46 <= bytes.count, lese32(bytes, position) == 0x0201_4B50 else { throw Fehler.ungueltigesArchiv }
            let methode = lese16(bytes, position + 10)
            let komprimiert = Int(lese32(bytes, position + 20))
            let unkomprimiert = Int(lese32(bytes, position + 24))
            let namenslaenge = Int(lese16(bytes, position + 28))
            let extralaenge = Int(lese16(bytes, position + 30))
            let kommentarlaenge = Int(lese16(bytes, position + 32))
            let lokal = Int(lese32(bytes, position + 42))
            guard position + 46 + namenslaenge <= bytes.count else { throw Fehler.ungueltigesArchiv }
            let name = String(decoding: bytes[(position + 46)..<(position + 46 + namenslaenge)], as: UTF8.self)
            position += 46 + namenslaenge + extralaenge + kommentarlaenge

            guard lokal + 30 <= bytes.count, lese32(bytes, lokal) == 0x0403_4B50 else { throw Fehler.ungueltigesArchiv }
            let start = lokal + 30 + Int(lese16(bytes, lokal + 26)) + Int(lese16(bytes, lokal + 28))
            guard start + komprimiert <= bytes.count else { throw Fehler.ungueltigesArchiv }
            let roh = Array(bytes[start..<(start + komprimiert)])

            if name.hasSuffix("/") { continue }
            switch methode {
            case 0:
                ergebnis[name] = Data(roh)
            case 8:
                ergebnis[name] = try entpacken(roh, groesse: unkomprimiert, name: name)
            default:
                throw Fehler.nichtUnterstuetzteKompression(methode)
            }
        }
        return ergebnis
    }

    private static func entpacken(_ roh: [UInt8], groesse: Int, name: String) throws -> Data {
        #if canImport(Compression)
        if groesse == 0 { return Data() }
        guard !roh.isEmpty else { throw Fehler.entpackenFehlgeschlagen(name) }
        var ziel = [UInt8](repeating: 0, count: groesse)
        let geschrieben = roh.withUnsafeBufferPointer { quelle in
            ziel.withUnsafeMutableBufferPointer { zielPuffer in
                compression_decode_buffer(zielPuffer.baseAddress!, groesse, quelle.baseAddress!, roh.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard geschrieben == groesse else { throw Fehler.entpackenFehlgeschlagen(name) }
        return Data(ziel)
        #else
        throw Fehler.nichtUnterstuetzteKompression(8)
        #endif
    }

    // MARK: Schreiben

    /// Erstellt ein ZIP-Archiv mit unkomprimierten Einträgen.
    public static func archiv(_ eintraege: [(name: String, daten: Data)]) -> Data {
        var ausgabe = [UInt8]()
        var verzeichnis = [UInt8]()
        for eintrag in eintraege {
            let name = Array(eintrag.name.utf8)
            let inhalt = [UInt8](eintrag.daten)
            let pruefsumme = crc32(inhalt)
            let offset = UInt32(ausgabe.count)

            ausgabe += le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            ausgabe += le32(pruefsumme) + le32(UInt32(inhalt.count)) + le32(UInt32(inhalt.count))
            ausgabe += le16(UInt16(name.count)) + le16(0) + name + inhalt

            verzeichnis += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            verzeichnis += le32(pruefsumme) + le32(UInt32(inhalt.count)) + le32(UInt32(inhalt.count))
            verzeichnis += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let verzeichnisOffset = UInt32(ausgabe.count)
        ausgabe += verzeichnis
        ausgabe += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(eintraege.count)) + le16(UInt16(eintraege.count))
        ausgabe += le32(UInt32(verzeichnis.count)) + le32(verzeichnisOffset) + le16(0)
        return Data(ausgabe)
    }

    // MARK: Hilfen

    private static let crcTabelle: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = crcTabelle[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func lese16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i + 1 < b.count else { return 0 }
        return UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func lese32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
}

/// Liest den Text aus PowerPoint-Dateien (.pptx), Folie für Folie.
public enum PptxText {
    public static func folien(aus daten: Data) throws -> [String] {
        let eintraege = try Zip.eintraege(daten)
        let folien = eintraege.keys.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("ppt/slides/slide"), name.hasSuffix(".xml") else { return nil }
            let nummer = name.dropFirst("ppt/slides/slide".count).dropLast(".xml".count)
            guard let n = Int(nummer) else { return nil }
            return (n, name)
        }
        .sorted { $0.0 < $1.0 }
        return folien.map { _, name in text(ausXML: eintraege[name] ?? Data()) }
    }

    static func text(ausXML daten: Data) -> String {
        let leser = FolienLeser()
        let parser = XMLParser(data: daten)
        parser.delegate = leser
        parser.parse()
        return leser.absaetze.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private final class FolienLeser: NSObject, XMLParserDelegate {
        var absaetze: [String] = []
        private var aktuell = ""
        private var imText = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "a:t" { imText = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if imText { aktuell += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "a:t" { imText = false }
            if elementName == "a:p" {
                absaetze.append(aktuell.trimmingCharacters(in: .whitespaces))
                aktuell = ""
            }
        }
    }
}
