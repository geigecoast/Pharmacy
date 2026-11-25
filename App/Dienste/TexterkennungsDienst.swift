import Foundation
import Vision
import PDFKit
import PencilKit

/// Texterkennung (OCR) für Scans, Seiten ohne Textebene und Handschrift.
@MainActor
enum TexterkennungsDienst {
    /// Seiten mit weniger Zeichen gelten als „ohne Text“ und werden erkannt.
    static let mindestZeichen = 20

    static func seitenErkennen(_ dokument: Dokument) async {
        guard dokument.istPDF, let daten = dokument.daten, let pdf = PDFDocument(data: daten) else { return }
        let offen = dokument.sortierteSeiten.filter {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count < mindestZeichen
        }
        guard !offen.isEmpty else { return }
        dokument.texterkennungLaeuft = true
        for seite in offen {
            guard let pdfSeite = pdf.page(at: seite.nummer), let bild = PDFWerkzeuge.bild(von: pdfSeite) else { continue }
            let text = await erkennen(bild)
            seite.text = text
            seite.ausTexterkennung = true
        }
        dokument.texterkennungLaeuft = false
    }

    static func handschriftErkennen(_ zeichnung: Zeichnung) async {
        guard let daten = zeichnung.daten, let pk = try? PKDrawing(data: daten),
              let bild = PDFWerkzeuge.bild(von: pk) else {
            zeichnung.text = ""
            return
        }
        zeichnung.text = await erkennen(bild)
    }

    /// Erkennt deutschen (und englischen) Text in einem Bild.
    nonisolated static func erkennen(_ bild: CGImage) async -> String {
        await Task.detached(priority: .utility) {
            let anfrage = VNRecognizeTextRequest()
            anfrage.recognitionLevel = .accurate
            anfrage.usesLanguageCorrection = true
            anfrage.recognitionLanguages = ["de-DE", "en-US"]
            let bearbeiter = VNImageRequestHandler(cgImage: bild, options: [:])
            do {
                try bearbeiter.perform([anfrage])
            } catch {
                return ""
            }
            let zeilen = (anfrage.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return zeilen.joined(separator: "\n")
        }.value
    }
}
