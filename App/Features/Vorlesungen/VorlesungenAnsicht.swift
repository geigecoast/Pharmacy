import SwiftUI
import SwiftData
import PharmaCore
#if os(iOS)
import VisionKit
#endif

/// Tab „Vorlesungen“: Unterlagen einer Lehrveranstaltung importieren und öffnen.
struct VorlesungenAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    var oeffnen: (Dokument, Int) -> Void

    @Environment(\.modelContext) private var kontext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var mehrereFenster
    @State private var zeigeImport = false
    @State private var zeigeScanner = false
    @State private var fehler: [String] = []
    @State private var filter = ""
    @State private var zuLoeschen: Dokument?
    @State private var zielMarkiert = false

    private var dokumente: [Dokument] {
        (lv.dokumente ?? [])
            .filter { filter.isEmpty || $0.titel.localizedStandardContains(filter) }
            .sorted { ($0.datum, $0.titel) < ($1.datum, $1.titel) }
    }

    var body: some View {
        VStack(spacing: 0) {
            kopfzeile
            if !fehler.isEmpty {
                fehlerliste
            }
            if (lv.dokumente ?? []).isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Unterlagen", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("Importiere Folien, Skripte, Scans oder Aufnahmen – aus Dateien, iCloud Drive oder Google Drive. Du kannst Dateien auch hierher ziehen.")
                } actions: {
                    Button("Importieren …") { zeigeImport = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(dokumente) { dokument in
                        Button {
                            oeffnen(dokument, 0)
                        } label: {
                            DokumentZeile(dokument: dokument)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if mehrereFenster {
                                Button {
                                    openWindow(id: DokumentFenster.fensterID, value: dokument.persistentModelID)
                                } label: {
                                    Label("In neuem Fenster öffnen", systemImage: "macwindow.badge.plus")
                                }
                            }
                            Button(role: .destructive) {
                                zuLoeschen = dokument
                            } label: {
                                Label("Löschen …", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .background(zielMarkiert ? Color.accentColor.opacity(0.08) : Color.clear)
        .dropDestination(for: ImportDatei.self) { dateien, _ in
            importieren(dateien.map(\.url))
            return true
        } isTargeted: { aktiv in
            zielMarkiert = aktiv
        }
        .fileImporter(isPresented: $zeigeImport, allowedContentTypes: DokumentImport.erlaubteTypen,
                      allowsMultipleSelection: true) { ergebnis in
            switch ergebnis {
            case .success(let urls):
                importieren(urls)
            case .failure(let fehler):
                self.fehler.append(fehler.localizedDescription)
            }
        }
        .confirmationDialog(
            Text("„\(zuLoeschen?.titel ?? "")“ löschen?"),
            isPresented: Binding(get: { zuLoeschen != nil }, set: { if !$0 { zuLoeschen = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let dokument = zuLoeschen { kontext.delete(dokument) }
                zuLoeschen = nil
            }
            Button("Abbrechen", role: .cancel) { zuLoeschen = nil }
        } message: {
            Text("Markierungen, Handschrift und Notizen dieser Unterlage werden ebenfalls gelöscht.")
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $zeigeScanner) {
            DokumentScanner { bilder in
                zeigeScanner = false
                scanSpeichern(bilder)
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private var kopfzeile: some View {
        HStack(spacing: 10) {
            Button {
                zeigeImport = true
            } label: {
                Label("Importieren …", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            #if os(iOS)
            if VNDocumentCameraViewController.isSupported {
                Button {
                    zeigeScanner = true
                } label: {
                    Label("Scannen", systemImage: "doc.viewfinder")
                }
                .buttonStyle(.bordered)
            }
            #endif
            Spacer()
            TextField("Unterlagen filtern", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        }
        .padding(Layout.abstand)
    }

    private var fehlerliste: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(fehler, id: \.self) { meldung in
                Label(meldung, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            Button("Ausblenden") { fehler = [] }
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, Layout.abstand)
        .padding(.bottom, 8)
    }

    private func importieren(_ urls: [URL]) {
        for url in urls {
            do {
                try DokumentImport.importieren(url: url, in: lv, kontext: kontext)
            } catch {
                fehler.append(error.localizedDescription)
            }
        }
    }

    #if os(iOS)
    private func scanSpeichern(_ bilder: [UIImage]) {
        guard !bilder.isEmpty, let daten = PDFWerkzeuge.pdf(ausBildern: bilder) else { return }
        let titel = "Scan vom \(Date().kurzesDatum)"
        DokumentImport.anlegen(titel: titel, dateiname: titel + ".pdf", typ: .scan, daten: daten, in: lv, kontext: kontext)
    }
    #endif
}

struct DokumentZeile: View {
    let dokument: Dokument

    private var info: String {
        var teile = [dokument.datum.kurzesDatum, dokument.typ.name]
        switch dokument.typ {
        case .pdf, .scan, .praesentation:
            teile.append(dokument.seitenzahl == 1 ? "1 Seite" : "\(dokument.seitenzahl) Seiten")
            let anzahl = dokument.sichtbareMarkierungen.count
            if anzahl > 0 { teile.append(anzahl == 1 ? "1 Markierung" : "\(anzahl) Markierungen") }
        case .audio:
            if !dokument.transkript.isEmpty { teile.append("mit Transkript") }
        }
        return teile.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: dokument.typ.symbol)
                .font(.title2)
                .foregroundStyle(dokument.lehrveranstaltung?.farbe ?? .accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(dokument.titel)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if dokument.texterkennungLaeuft {
                ProgressView()
                    .controlSize(.small)
                    .help("Texterkennung läuft")
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Eigenes Fenster für eine Unterlage.
struct DokumentFenster: View {
    static let fensterID = "dokument"

    let id: PersistentIdentifier?
    @Environment(\.modelContext) private var kontext
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let id, let dokument = kontext.model(for: id) as? Dokument, !dokument.isDeleted {
            NavigationStack {
                DokumentAnsicht(dokument: dokument, zurueck: {
                    dismissWindow(id: Self.fensterID, value: id)
                }, oeffnen: { anderes, _ in
                    openWindow(id: Self.fensterID, value: anderes.persistentModelID)
                })
            }
        } else {
            ContentUnavailableView("Unterlage nicht gefunden", systemImage: "questionmark.folder",
                                   description: Text("Sie wurde vielleicht gelöscht."))
        }
    }
}

#if os(iOS)
/// Dokumentenscanner der Kamera (VisionKit).
struct DokumentScanner: UIViewControllerRepresentable {
    var fertig: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let steuerung = VNDocumentCameraViewController()
        steuerung.delegate = context.coordinator
        return steuerung
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(fertig: fertig) }

    final class Koordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let fertig: ([UIImage]) -> Void

        init(fertig: @escaping ([UIImage]) -> Void) { self.fertig = fertig }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            fertig((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            fertig([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            fertig([])
        }
    }
}
#endif
