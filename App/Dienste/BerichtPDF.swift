import Foundation
import CoreText
import CoreGraphics

/// Erstellt formatierte PDFs aus Markdown-Text (Kopfzeile, Seitenzahlen, A4).
enum BerichtPDF {
    static let seite = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let rand: CGFloat = 60

    /// - Parameters:
    ///   - titel: großer Titel auf Seite 1, z. B. „Lernzusammenfassung“.
    ///   - kopfzeile: auf jeder Seite oben, z. B. „[43] Arzneistoffanalytik · Identitätsprüfung · 25.11.2026“.
    static func erstellen(titel: String, untertitel: String, kopfzeile: String, markdown: String) -> Data? {
        let inhalt = NSMutableAttributedString()
        inhalt.append(text(titel + "\n", schrift: "PTNewsreaderDisplay-Light", groesse: 28, farbe: 0.07, abstandDanach: 4))
        inhalt.append(text(untertitel + "\n\n", schrift: "PTGeist-Regular", groesse: 10, farbe: 0.45, abstandDanach: 10))
        for roheZeile in markdown.components(separatedBy: "\n") {
            let zeile = roheZeile.trimmingCharacters(in: .whitespaces)
            if zeile.isEmpty {
                inhalt.append(text("\n", schrift: "PTGeist-Regular", groesse: 6, farbe: 0.1, abstandDanach: 0))
            } else if zeile.hasPrefix("#") {
                let ohne = zeile.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                inhalt.append(inline(ohne + "\n", schrift: "PTNewsreaderText-Regular", fett: "PTNewsreaderText-Regular",
                                     groesse: 15, abstandDavor: 10, abstandDanach: 4))
            } else if zeile.hasPrefix("- ") || zeile.hasPrefix("* ") || zeile.hasPrefix("• ") {
                inhalt.append(inline("–\t" + zeile.dropFirst(2) + "\n", schrift: "PTGeist-Regular", fett: "PTGeist-Medium",
                                     groesse: 10.5, einzug: 14, abstandDanach: 3))
            } else {
                inhalt.append(inline(zeile + "\n", schrift: "PTGeist-Regular", fett: "PTGeist-Medium", groesse: 10.5, abstandDanach: 5))
            }
        }

        let satz = CTFramesetterCreateWithAttributedString(inhalt as CFAttributedString)
        let textRahmen = CGRect(x: rand, y: rand + 24, width: seite.width - 2 * rand, height: seite.height - 2 * rand - 48)
        var bereiche: [CFRange] = []
        var start = 0
        let laenge = inhalt.length
        while start < laenge {
            let pfad = CGPath(rect: textRahmen, transform: nil)
            let rahmen = CTFramesetterCreateFrame(satz, CFRange(location: start, length: 0), pfad, nil)
            let sichtbar = CTFrameGetVisibleStringRange(rahmen)
            guard sichtbar.length > 0 else { break }
            bereiche.append(CFRange(location: start, length: sichtbar.length))
            start += sichtbar.length
        }

        let ausgabe = NSMutableData()
        var kasten = seite
        guard let verbraucher = CGDataConsumer(data: ausgabe as CFMutableData),
              let kontext = CGContext(consumer: verbraucher, mediaBox: &kasten, nil) else { return nil }
        for (index, bereich) in bereiche.enumerated() {
            kontext.beginPDFPage(nil)
            zeile(kopfzeile, in: kontext, x: rand, y: seite.height - rand + 8, groesse: 8.5)
            kontext.setStrokeColor(gray: 0.85, alpha: 1)
            kontext.setLineWidth(0.5)
            kontext.move(to: CGPoint(x: rand, y: seite.height - rand))
            kontext.addLine(to: CGPoint(x: seite.width - rand, y: seite.height - rand))
            kontext.strokePath()
            let pfad = CGPath(rect: textRahmen, transform: nil)
            let rahmen = CTFramesetterCreateFrame(satz, bereich, pfad, nil)
            CTFrameDraw(rahmen, kontext)
            zeile("Seite \(index + 1) von \(bereiche.count)", in: kontext, x: seite.width - rand - 70, y: rand - 24, groesse: 8.5)
            zeile("PharmaTutor", in: kontext, x: rand, y: rand - 24, groesse: 8.5)
            kontext.endPDFPage()
        }
        kontext.closePDF()
        return ausgabe as Data
    }

    // MARK: Hilfen

    private static func schrift(_ name: String, _ groesse: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, groesse, nil)
    }

    private static func absatz(einzug: CGFloat, abstandDavor: CGFloat, abstandDanach: CGFloat) -> CTParagraphStyle {
        let zeilenhoehe: CGFloat = 1.25
        let tabs = [CTTextTabCreate(.left, Double(einzug), nil)] as CFArray
        return withUnsafeBytes(of: zeilenhoehe) { hoehe in
            withUnsafeBytes(of: abstandDavor) { vor in
                withUnsafeBytes(of: abstandDanach) { nach in
                    withUnsafeBytes(of: einzug) { einzugZeiger in
                        withUnsafePointer(to: tabs) { tabZeiger in
                            let einstellungen = [
                                CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: hoehe.baseAddress!),
                                CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: vor.baseAddress!),
                                CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: nach.baseAddress!),
                                CTParagraphStyleSetting(spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: einzugZeiger.baseAddress!),
                                CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: tabZeiger),
                            ]
                            return CTParagraphStyleCreate(einstellungen, einstellungen.count)
                        }
                    }
                }
            }
        }
    }

    private static func text(_ inhalt: String, schrift name: String, groesse: CGFloat, farbe grau: CGFloat,
                             abstandDanach: CGFloat) -> NSAttributedString {
        NSAttributedString(string: inhalt, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): schrift(name, groesse),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: grau, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): absatz(einzug: 0, abstandDavor: 0, abstandDanach: abstandDanach),
        ])
    }

    /// Text mit **fett** (wechselnde Schrift zwischen den Sternchen).
    private static func inline(_ inhalt: String, schrift name: String, fett: String, groesse: CGFloat,
                               einzug: CGFloat = 0, abstandDavor: CGFloat = 0, abstandDanach: CGFloat) -> NSAttributedString {
        let ergebnis = NSMutableAttributedString()
        let stil = absatz(einzug: einzug, abstandDavor: abstandDavor, abstandDanach: abstandDanach)
        for (index, teil) in inhalt.components(separatedBy: "**").enumerated() {
            let istFett = index % 2 == 1
            ergebnis.append(NSAttributedString(string: teil.replacingOccurrences(of: "*", with: ""), attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): schrift(istFett ? fett : name, groesse),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.07, alpha: 1),
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): stil,
            ]))
        }
        return ergebnis
    }

    private static func zeile(_ text: String, in kontext: CGContext, x: CGFloat, y: CGFloat, groesse: CGFloat) {
        let attribute: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): schrift("PTGeist-Regular", groesse),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.45, alpha: 1),
        ]
        let linie = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attribute))
        kontext.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(linie, kontext)
    }
}
