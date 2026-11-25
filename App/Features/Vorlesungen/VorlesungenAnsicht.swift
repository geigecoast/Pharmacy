import SwiftUI
import SwiftData
import PharmaCore
#if os(iOS)
import VisionKit
#endif

/// Tab „Vorlesungen“: Liste der Unterlagen links, Leser in der Mitte, Zusammenfassung/Markierungen rechts.
struct VorlesungenAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    var oeffnen: (Dokument, Int) -> Void
    var rand: CGFloat = Thema.randAussen

    @Environment(\.modelContext) private var kontext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var mehrereFenster
    @State private var gewaehlt: Dokument?
    @State private var startSeite = 0
    @State private var zeigeImport = false
    @State private var zeigeScanner = false
    @State private var fehler: [String] = []
    @State private var zuLoeschen: Dokument?
    @State private var zielMarkiert = false

    /// Chronologisch; Nummer „VL n“ zählt nur PDFs, Scans und Präsentationen.
    private var dokumente: [Dokument] {
        (lv.dokumente ?? []).sorted { ($0.datum, $0.importiertAm) < ($1.datum, $1.importiertAm) }
    }

    private func metazeile(_ dokument: Dokument, nummer: Int?) -> String {
        let datum = dokument.datum.formatted(.dateTime.day().month(.abbreviated).locale(.deutsch))
        if let nummer { return "VL \(nummer) · \(datum)" }
        return "\(dokument.typ.name) · \(datum)"
    }

    var body: some View {
        let liste = dokumente
        Group {
            if liste.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Unterlagen", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("Importiere Folien, Skripte, Scans oder Aufnahmen – aus Dateien, iCloud Drive oder Google Drive. Du kannst Dateien auch hierher ziehen.")
                } actions: {
                    Button("Importieren …") { zeigeImport = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    seitenliste(liste)
                        .frame(width: 236)
                        .padding(.leading, max(rand - 12, 8))
                    Rectangle().fill(Thema.linie).frame(width: 1)
                    if let dokument = gewaehlt ?? liste.last {
                        DokumentArbeitsflaeche(dokument: dokument, startSeite: startSeite) { anderes, seite in
                            if anderes.lehrveranstaltung == lv {
                                startSeite = seite
                                gewaehlt = anderes
                            } else {
                                oeffnen(anderes, seite)
                            }
                        }
                        .id("\(dokument.kennung)-\(startSeite)")
                    }
                }
            }
        }
        .overlay {
            if zielMarkiert {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Thema.tinte, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
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
                if let dokument = zuLoeschen {
                    if gewaehlt == dokument { gewaehlt = nil }
                    kontext.delete(dokument)
                }
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

    private func seitenliste(_ liste: [Dokument]) -> some View {
        let aktuell = gewaehlt ?? liste.last
        var zaehler = 0
        let nummern: [UUID: Int] = liste.reduce(into: [:]) { ergebnis, dokument in
            if dokument.typ != .audio {
                zaehler += 1
                ergebnis[dokument.kennung] = zaehler
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Kleintitel(text: "Vorlesungen")
                Spacer()
                Menu {
                    Button {
                        zeigeImport = true
                    } label: {
                        Label("Importieren …", systemImage: "square.and.arrow.down")
                    }
                    #if os(iOS)
                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            zeigeScanner = true
                        } label: {
                            Label("Scannen", systemImage: "doc.viewfinder")
                        }
                    }
                    #endif
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Unterlagen importieren")
            }
            .padding(.horizontal, 10)
            .padding(.top, 24)
            .padding(.bottom, 10)

            if !fehler.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fehler, id: \.self) { meldung in
                        Text(verbatim: meldung)
                            .font(Thema.ui(11))
                            .foregroundStyle(Stoffgebiet.i.farbe)
                    }
                    Button("Ausblenden") { fehler = [] }
                        .buttonStyle(.plain)
                        .font(Thema.ui(11))
                        .underline()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(liste) { dokument in
                        Button {
                            startSeite = 0
                            gewaehlt = dokument
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: dokument.titel)
                                        .font(Thema.ui(13))
                                        .foregroundStyle(Thema.tinte)
                                        .lineLimit(2)
                                    Text(verbatim: metazeile(dokument, nummer: nummern[dokument.kennung]))
                                        .font(Thema.ui(11))
                                        .foregroundStyle(Thema.tinteTertiaer)
                                }
                                Spacer(minLength: 0)
                                if dokument.texterkennungLaeuft {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(aktuell == dokument ? Thema.flaecheGedaempft : Color.clear))
                            .contentShape(Rectangle())
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
                .padding(.bottom, 16)
            }
        }
        .padding(.trailing, 12)
    }

    private func importieren(_ urls: [URL]) {
        for url in urls {
            do {
                gewaehlt = try DokumentImport.importieren(url: url, in: lv, kontext: kontext)
                startSeite = 0
            } catch {
                fehler.append(error.localizedDescription)
            }
        }
    }

    #if os(iOS)
    private func scanSpeichern(_ bilder: [UIImage]) {
        guard !bilder.isEmpty, let daten = PDFWerkzeuge.pdf(ausBildern: bilder) else { return }
        let titel = "Scan vom \(Date().kurzesDatum)"
        gewaehlt = DokumentImport.anlegen(titel: titel, dateiname: titel + ".pdf", typ: .scan, daten: daten, in: lv, kontext: kontext)
    }
    #endif
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
