import Foundation
import PDFKit
import PencilKit
import CoreGraphics
import PharmaCore

/// Hilfsfunktionen rund um PDFKit: Seiten rendern, Markierungen und Zeichnungen anzeigen, exportieren.
enum PDFWerkzeuge {
    static let markierungsKennung = "pharmatutor.markierung"
    static let zeichnungsKennung = "pharmatutor.zeichnung"

    /// Unveränderliche Kopie einer Markierung für die Anzeige.
    struct MarkierungsDaten: Hashable {
        let kennung: UUID
        let seitenIndex: Int
        let rechtecke: [CGRect]
        let farbe: MarkierungsFarbe
        let vorgeschlagen: Bool

        func hash(into hasher: inout Hasher) {
            hasher.combine(kennung)
            hasher.combine(farbe)
            hasher.combine(vorgeschlagen)
        }
    }

    struct ZeichnungsDaten: Hashable {
        let seitenIndex: Int
        let daten: Data
        let geaendertAm: Date
    }

    /// Rendert eine PDF-Seite als Bild (weißer Hintergrund), z. B. für die Texterkennung.
    static func bild(von seite: PDFPage, breite: CGFloat = 1800) -> CGImage? {
        let box = seite.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let skalierung = breite / box.width
        let pixelBreite = Int(box.width * skalierung)
        let pixelHoehe = Int(box.height * skalierung)
        guard let kontext = CGContext(data: nil, width: pixelBreite, height: pixelHoehe, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        kontext.setFillColor(CGColor(gray: 1, alpha: 1))
        kontext.fill(CGRect(x: 0, y: 0, width: pixelBreite, height: pixelHoehe))
        kontext.scaleBy(x: skalierung, y: skalierung)
        kontext.translateBy(x: -box.minX, y: -box.minY)
        seite.draw(with: .mediaBox, to: kontext)
        return kontext.makeImage()
    }

    /// Bild einer Zeichnung auf weißem Grund (für die Texterkennung der Handschrift).
    static func bild(von zeichnung: PKDrawing) -> CGImage? {
        let rahmen = zeichnung.bounds.insetBy(dx: -20, dy: -20)
        guard !rahmen.isEmpty, let strich = zeichnung.image(from: rahmen, scale: 2).cgBild else { return nil }
        guard let kontext = CGContext(data: nil, width: strich.width, height: strich.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let flaeche = CGRect(x: 0, y: 0, width: strich.width, height: strich.height)
        kontext.setFillColor(CGColor(gray: 1, alpha: 1))
        kontext.fill(flaeche)
        kontext.draw(strich, in: flaeche)
        return kontext.makeImage()
    }

    /// Ersetzt die Markierungs- und Zeichnungsannotationen der App im Dokument.
    static func annotationenSetzen(in dokument: PDFDocument, markierungen: [MarkierungsDaten], zeichnungen: [ZeichnungsDaten]) {
        for index in 0..<dokument.pageCount {
            guard let seite = dokument.page(at: index) else { continue }
            for annotation in seite.annotations where annotation.userName?.hasPrefix("pharmatutor.") == true {
                seite.removeAnnotation(annotation)
            }
        }
        for markierung in markierungen {
            guard let seite = dokument.page(at: markierung.seitenIndex) else { continue }
            for rechteck in markierung.rechtecke {
                let annotation = PDFAnnotation(bounds: rechteck, forType: .highlight, withProperties: nil)
                annotation.color = markierung.farbe.plattformFarbe.withAlphaComponent(markierung.vorgeschlagen ? 0.2 : 0.45)
                annotation.userName = markierungsKennung
                seite.addAnnotation(annotation)
            }
        }
        for zeichnung in zeichnungen {
            guard let seite = dokument.page(at: zeichnung.seitenIndex),
                  let annotation = ZeichnungsAnnotation(daten: zeichnung.daten, seite: seite) else { continue }
            seite.addAnnotation(annotation)
        }
    }

    /// Erstellt ein PDF, in das Markierungen und Handschrift fest eingezeichnet sind.
    static func exportieren(daten: Data, markierungen: [MarkierungsDaten], zeichnungen: [ZeichnungsDaten]) -> Data? {
        guard let dokument = PDFDocument(data: daten) else { return nil }
        annotationenSetzen(in: dokument, markierungen: markierungen, zeichnungen: zeichnungen)
        let ausgabe = NSMutableData()
        guard let verbraucher = CGDataConsumer(data: ausgabe as CFMutableData),
              let kontext = CGContext(consumer: verbraucher, mediaBox: nil, nil) else { return nil }
        for index in 0..<dokument.pageCount {
            guard let seite = dokument.page(at: index) else { continue }
            var box = seite.bounds(for: .mediaBox)
            kontext.beginPage(mediaBox: &box)
            seite.draw(with: .mediaBox, to: kontext)
            kontext.endPage()
        }
        kontext.closePDF()
        return ausgabe as Data
    }

    /// Erstellt aus Bildern ein PDF (eine Seite pro Bild).
    static func pdf(ausBildern bilder: [PlattformBild]) -> Data? {
        let dokument = PDFDocument()
        for (index, bild) in bilder.enumerated() {
            if let seite = PDFPage(image: bild) {
                dokument.insert(seite, at: index)
            }
        }
        return dokument.pageCount > 0 ? dokument.dataRepresentation() : nil
    }
}

/// Zeigt eine PencilKit-Zeichnung auf einer PDF-Seite an.
final class ZeichnungsAnnotation: PDFAnnotation {
    private var bild: CGImage?

    /// Die Zeichnung liegt in Seitenkoordinaten mit Ursprung oben links (wie die Überlagerung auf dem iPad).
    init?(daten: Data, seite: PDFPage) {
        guard let zeichnung = try? PKDrawing(data: daten), !zeichnung.bounds.isEmpty,
              let bild = zeichnung.image(from: zeichnung.bounds, scale: 2).cgBild else { return nil }
        let box = seite.bounds(for: .mediaBox)
        let r = zeichnung.bounds
        let rahmen = CGRect(x: box.minX + r.minX, y: box.maxY - r.maxY, width: r.width, height: r.height)
        self.bild = bild
        super.init(bounds: rahmen, forType: .stamp, withProperties: nil)
        userName = PDFWerkzeuge.zeichnungsKennung
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let bild else { return }
        context.saveGState()
        context.draw(bild, in: bounds)
        context.restoreGState()
    }
}
