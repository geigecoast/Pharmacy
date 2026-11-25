import SwiftUI
import SwiftData
import PDFKit
import PencilKit
import PharmaCore

/// Steuert die PDF-Ansicht von SwiftUI aus (Seite, Auswahl, Suche, Markieren).
@Observable
final class PDFSteuerung {
    @ObservationIgnored weak var ansicht: PDFView?
    @ObservationIgnored private var treffer: [PDFSelection] = []

    var aktuelleSeite = 0
    var seitenzahl = 0
    var hatAuswahl = false
    var trefferAnzahl = 0
    var trefferIndex = 0

    func gehe(zu index: Int) {
        guard let ansicht, let seite = ansicht.document?.page(at: index) else { return }
        ansicht.go(to: seite)
    }

    func suchen(_ text: String) {
        guard let ansicht, let dokument = ansicht.document else { return }
        let begriff = text.trimmingCharacters(in: .whitespaces)
        treffer = begriff.count < 2 ? [] : dokument.findString(begriff, withOptions: [.caseInsensitive, .diacriticInsensitive])
        trefferAnzahl = treffer.count
        trefferIndex = 0
        ansicht.highlightedSelections = treffer.isEmpty ? nil : treffer
        zeigeTreffer()
    }

    func naechsterTreffer(_ schritt: Int) {
        guard !treffer.isEmpty else { return }
        trefferIndex = (trefferIndex + schritt + treffer.count) % treffer.count
        zeigeTreffer()
    }

    private func zeigeTreffer() {
        guard trefferIndex < treffer.count, let ansicht else { return }
        ansicht.go(to: treffer[trefferIndex])
    }

    /// Markiert die aktuelle Textauswahl in der gewählten Farbe.
    func markieren(_ farbe: MarkierungsFarbe, dokument: Dokument, kontext: ModelContext) {
        guard let ansicht, let auswahl = ansicht.currentSelection, let pdf = ansicht.document else { return }
        var proSeite: [Int: [CGRect]] = [:]
        for zeile in auswahl.selectionsByLine() {
            for seite in zeile.pages {
                let rechteck = zeile.bounds(for: seite)
                guard rechteck.width > 1, rechteck.height > 1 else { continue }
                proSeite[pdf.index(for: seite), default: []].append(rechteck)
            }
        }
        let text = (auswahl.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for (index, rechtecke) in proSeite.sorted(by: { $0.key < $1.key }) {
            let markierung = Markierung(seitenIndex: index, rechtecke: rechtecke, farbe: farbe, text: text)
            kontext.insert(markierung)
            markierung.dokument = dokument
        }
        ansicht.clearSelection()
        hatAuswahl = false
    }

    /// Entfernt Markierungen, die die aktuelle Auswahl überschneiden.
    func markierungEntfernen(dokument: Dokument, kontext: ModelContext) {
        guard let ansicht, let auswahl = ansicht.currentSelection, let pdf = ansicht.document else { return }
        for seite in auswahl.pages {
            let index = pdf.index(for: seite)
            let bereich = auswahl.bounds(for: seite)
            for markierung in dokument.markierungen ?? []
            where markierung.seitenIndex == index && markierung.rechtecke.contains(where: { $0.intersects(bereich) }) {
                kontext.delete(markierung)
            }
        }
        ansicht.clearSelection()
        hatAuswahl = false
    }
}

/// PDFKit-Ansicht mit Markierungen; auf dem iPad mit Apple-Pencil-Ebene pro Seite.
struct PDFAnzeige {
    let pdf: PDFDocument
    let steuerung: PDFSteuerung
    let markierungen: [PDFWerkzeuge.MarkierungsDaten]
    let zeichnungen: [PDFWerkzeuge.ZeichnungsDaten]
    var startSeite = 0
    var stiftModus = false
    var zeichnungGeaendert: (Int, Data) -> Void = { _, _ in }

    func makeCoordinator() -> Koordinator {
        Koordinator(steuerung: steuerung)
    }

    final class Koordinator: NSObject {
        let steuerung: PDFSteuerung
        var signatur: Int?
        var zeichnungGeaendert: (Int, Data) -> Void = { _, _ in }
        var zeichnungsDaten: [Int: Data] = [:]
        #if os(iOS)
        var canvases: [Int: PKCanvasView] = [:]
        var stiftAktiv = false
        var laedt = false
        let werkzeuge = PKToolPicker()
        #endif

        init(steuerung: PDFSteuerung) {
            self.steuerung = steuerung
        }

        @objc func seiteGeaendert(_ notification: Notification) {
            guard let ansicht = notification.object as? PDFView,
                  let seite = ansicht.currentPage, let dokument = ansicht.document else { return }
            steuerung.aktuelleSeite = dokument.index(for: seite)
        }

        @objc func auswahlGeaendert(_ notification: Notification) {
            guard let ansicht = notification.object as? PDFView else { return }
            let text = ansicht.currentSelection?.string ?? ""
            steuerung.hatAuswahl = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func erstellen(_ koordinator: Koordinator) -> PDFView {
        let ansicht = PDFView()
        ansicht.autoScales = true
        ansicht.displayMode = .singlePageContinuous
        ansicht.displayDirection = .vertical
        koordinator.zeichnungGeaendert = zeichnungGeaendert
        koordinator.zeichnungsDaten = Dictionary(zeichnungen.map { ($0.seitenIndex, $0.daten) }, uniquingKeysWith: { a, _ in a })
        #if os(iOS)
        ansicht.pageOverlayViewProvider = koordinator
        #endif
        ansicht.document = pdf
        steuerung.ansicht = ansicht
        steuerung.seitenzahl = pdf.pageCount
        NotificationCenter.default.addObserver(koordinator, selector: #selector(Koordinator.seiteGeaendert(_:)),
                                               name: .PDFViewPageChanged, object: ansicht)
        NotificationCenter.default.addObserver(koordinator, selector: #selector(Koordinator.auswahlGeaendert(_:)),
                                               name: .PDFViewSelectionChanged, object: ansicht)
        aktualisieren(ansicht, koordinator)
        if startSeite > 0, let seite = pdf.page(at: startSeite) {
            DispatchQueue.main.async { ansicht.go(to: seite) }
        }
        return ansicht
    }

    private func aktualisieren(_ ansicht: PDFView, _ koordinator: Koordinator) {
        koordinator.zeichnungGeaendert = zeichnungGeaendert
        var hasher = Hasher()
        hasher.combine(markierungen)
        #if os(macOS)
        hasher.combine(zeichnungen)
        let angezeigteZeichnungen = zeichnungen
        #else
        let angezeigteZeichnungen: [PDFWerkzeuge.ZeichnungsDaten] = []
        #endif
        let signatur = hasher.finalize()
        if signatur != koordinator.signatur {
            koordinator.signatur = signatur
            PDFWerkzeuge.annotationenSetzen(in: pdf, markierungen: markierungen, zeichnungen: angezeigteZeichnungen)
        }
        #if os(iOS)
        koordinator.stiftModusSetzen(stiftModus, in: ansicht)
        #endif
    }
}

#if os(macOS)
extension PDFAnzeige: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { erstellen(context.coordinator) }
    func updateNSView(_ ansicht: PDFView, context: Context) { aktualisieren(ansicht, context.coordinator) }
    static func dismantleNSView(_ ansicht: PDFView, coordinator: Koordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}
#else
extension PDFAnzeige: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { erstellen(context.coordinator) }
    func updateUIView(_ ansicht: PDFView, context: Context) { aktualisieren(ansicht, context.coordinator) }
    static func dismantleUIView(_ ansicht: PDFView, coordinator: Koordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.werkzeuge.setVisible(false, forFirstResponder: ansicht)
    }
}

extension PDFAnzeige.Koordinator: PDFPageOverlayViewProvider, PKCanvasViewDelegate {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let index = view.document?.index(for: page) ?? 0
        let canvas = canvases[index] ?? PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .default
        canvas.tag = index
        laedt = true
        canvas.delegate = nil
        if let daten = zeichnungsDaten[index], let zeichnung = try? PKDrawing(data: daten) {
            canvas.drawing = zeichnung
        }
        canvas.delegate = self
        laedt = false
        canvas.isUserInteractionEnabled = stiftAktiv
        if stiftAktiv { werkzeuge.addObserver(canvas) }
        canvases[index] = canvas
        return canvas
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView else { return }
        werkzeuge.removeObserver(canvas)
        canvases[canvas.tag] = nil
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !laedt else { return }
        let daten = canvasView.drawing.dataRepresentation()
        zeichnungsDaten[canvasView.tag] = daten
        zeichnungGeaendert(canvasView.tag, daten)
    }

    func stiftModusSetzen(_ an: Bool, in ansicht: PDFView) {
        guard an != stiftAktiv else { return }
        stiftAktiv = an
        ansicht.isInMarkupMode = an
        for canvas in canvases.values {
            canvas.isUserInteractionEnabled = an
            if an { werkzeuge.addObserver(canvas) } else { werkzeuge.removeObserver(canvas) }
        }
        let aktuelle = ansicht.currentPage.flatMap { ansicht.document?.index(for: $0) }
        if an, let index = aktuelle, let canvas = canvases[index] {
            werkzeuge.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        } else {
            for canvas in canvases.values {
                werkzeuge.setVisible(false, forFirstResponder: canvas)
                canvas.resignFirstResponder()
            }
        }
    }
}
#endif
