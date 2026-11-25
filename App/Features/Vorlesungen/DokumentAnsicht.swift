import SwiftUI
import SwiftData
import PDFKit
import PharmaCore

/// Öffnet eine Unterlage passend zu ihrem Typ.
struct DokumentAnsicht: View {
    @Bindable var dokument: Dokument
    var startSeite = 0
    var zurueck: () -> Void
    var oeffnen: (Dokument, Int) -> Void

    var body: some View {
        Group {
            switch dokument.typ {
            case .pdf, .scan:
                PDFDokumentAnsicht(dokument: dokument, startSeite: startSeite)
            case .praesentation:
                PraesentationsAnsicht(dokument: dokument)
            case .audio:
                AudioAnsicht(dokument: dokument, oeffnen: oeffnen)
            }
        }
        .navigationTitle(dokument.titel)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: zurueck) {
                    Label(dokument.lehrveranstaltung?.lfdNrAnzeige ?? "Zurück", systemImage: "chevron.left")
                }
                .help("Zurück zur Lehrveranstaltung")
            }
        }
    }
}

struct PDFDokumentAnsicht: View {
    @Bindable var dokument: Dokument
    let startSeite: Int

    @Environment(\.modelContext) private var kontext
    @State private var pdf: PDFDocument?
    @State private var ladefehler = false
    @State private var steuerung = PDFSteuerung()
    @State private var stiftModus = false
    @State private var geaenderteSeiten: Set<Int> = []
    @State private var suche = ""
    @State private var exportDatei: PDFDatei?
    @State private var zeigeExport = false
    @AppStorage("dokumentInspectorSichtbar") private var zeigeInspector = true

    private var markierungsDaten: [PDFWerkzeuge.MarkierungsDaten] {
        dokument.sichtbareMarkierungen.map {
            PDFWerkzeuge.MarkierungsDaten(kennung: $0.kennung, seitenIndex: $0.seitenIndex, rechtecke: $0.rechtecke,
                                          farbe: $0.farbe, vorgeschlagen: $0.status == .vorgeschlagen)
        }
    }

    private var zeichnungsDaten: [PDFWerkzeuge.ZeichnungsDaten] {
        (dokument.zeichnungen ?? []).compactMap { zeichnung in
            zeichnung.daten.map { PDFWerkzeuge.ZeichnungsDaten(seitenIndex: zeichnung.seitenIndex, daten: $0, geaendertAm: zeichnung.geaendertAm) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let pdf {
                PDFAnzeige(pdf: pdf, steuerung: steuerung, markierungen: markierungsDaten, zeichnungen: zeichnungsDaten,
                           startSeite: startSeite, stiftModus: stiftModus, zeichnungGeaendert: zeichnungSpeichern)
                werkzeugleiste
                    .padding(.bottom, 12)
            } else if ladefehler {
                ContentUnavailableView("Dokument kann nicht geöffnet werden", systemImage: "exclamationmark.triangle",
                                       description: Text("Die Datei ist beschädigt oder leer."))
            } else {
                ProgressView("Dokument wird geladen …")
            }
        }
        .task {
            guard pdf == nil else { return }
            if let daten = dokument.daten, let geladen = PDFDocument(data: daten) {
                pdf = geladen
            } else {
                ladefehler = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                suchfeld
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportieren()
                } label: {
                    Label("Mit Markierungen exportieren", systemImage: "square.and.arrow.up")
                }
                .help("Als PDF mit Markierungen und Handschrift exportieren")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    zeigeInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $zeigeInspector) {
            DokumentInspector(dokument: dokument, steuerung: steuerung)
                .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
        }
        .fileExporter(isPresented: $zeigeExport, document: exportDatei, contentType: .pdf,
                      defaultFilename: dokument.titel) { _ in }
        .onChange(of: stiftModus) { _, an in
            if !an { handschriftErkennen() }
        }
        .onChange(of: suche) { _, neu in
            if neu.isEmpty { steuerung.suchen("") }
        }
    }

    private var suchfeld: some View {
        HStack(spacing: 4) {
            TextField("Im Dokument suchen", text: $suche)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .onSubmit { steuerung.suchen(suche) }
            if steuerung.trefferAnzahl > 0 {
                Text(verbatim: "\(steuerung.trefferIndex + 1)/\(steuerung.trefferAnzahl)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { steuerung.naechsterTreffer(-1) } label: { Label("Vorheriger Treffer", systemImage: "chevron.up") }
                Button { steuerung.naechsterTreffer(1) } label: { Label("Nächster Treffer", systemImage: "chevron.down") }
            }
        }
        .labelStyle(.iconOnly)
    }

    private var werkzeugleiste: some View {
        HStack(spacing: 12) {
            ForEach(MarkierungsFarbe.allCases) { farbe in
                Button {
                    steuerung.markieren(farbe, dokument: dokument, kontext: kontext)
                } label: {
                    Circle()
                        .fill(farbe.farbe)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .help("\(farbe.name): \(farbe.bedeutung)")
                .accessibilityLabel("Markieren: \(farbe.bedeutung)")
            }
            .disabled(!steuerung.hatAuswahl)
            .opacity(steuerung.hatAuswahl ? 1 : 0.45)

            Button {
                steuerung.markierungEntfernen(dokument: dokument, kontext: kontext)
            } label: {
                Label("Markierung entfernen", systemImage: "eraser")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .disabled(!steuerung.hatAuswahl)
            .help("Markierungen in der Auswahl entfernen")

            #if os(iOS)
            Divider().frame(height: 22)
            Button {
                stiftModus.toggle()
            } label: {
                Label(stiftModus ? "Stift beenden" : "Mit Stift schreiben", systemImage: "pencil.tip.crop.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(stiftModus ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            #endif

            Divider().frame(height: 22)
            Text("Seite \(steuerung.aktuelleSeite + 1) von \(steuerung.seitenzahl)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private func zeichnungSpeichern(_ seitenIndex: Int, _ daten: Data) {
        if let vorhanden = (dokument.zeichnungen ?? []).first(where: { $0.seitenIndex == seitenIndex }) {
            vorhanden.daten = daten
            vorhanden.geaendertAm = Date()
        } else {
            let zeichnung = Zeichnung(seitenIndex: seitenIndex, daten: daten)
            kontext.insert(zeichnung)
            zeichnung.dokument = dokument
        }
        geaenderteSeiten.insert(seitenIndex)
    }

    private func handschriftErkennen() {
        let seiten = geaenderteSeiten
        geaenderteSeiten = []
        let betroffen = (dokument.zeichnungen ?? []).filter { seiten.contains($0.seitenIndex) }
        Task {
            for zeichnung in betroffen {
                await TexterkennungsDienst.handschriftErkennen(zeichnung)
            }
        }
    }

    private func exportieren() {
        guard let daten = dokument.daten,
              let pdf = PDFWerkzeuge.exportieren(daten: daten, markierungen: markierungsDaten, zeichnungen: zeichnungsDaten) else { return }
        exportDatei = PDFDatei(daten: pdf)
        zeigeExport = true
    }
}

/// Seitenleiste eines Dokuments: Angaben, Farblegende, Markierungen, Handschrift, Notizen.
struct DokumentInspector: View {
    @Bindable var dokument: Dokument
    let steuerung: PDFSteuerung

    @Environment(\.modelContext) private var kontext
    @State private var farbFilter: MarkierungsFarbe?

    private var gefiltert: [Markierung] {
        dokument.sichtbareMarkierungen.filter { farbFilter == nil || $0.farbe == farbFilter }
    }

    var body: some View {
        Form {
            Section("Dokument") {
                TextField("Titel", text: $dokument.titel)
                DatePicker("Vorlesung vom", selection: $dokument.datum, displayedComponents: .date)
                LabeledContent("Seiten", value: "\(dokument.seitenzahl)")
                if dokument.texterkennungLaeuft {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Texterkennung läuft …")
                    }
                } else {
                    let erkannt = (dokument.seiten ?? []).filter(\.ausTexterkennung).count
                    if erkannt > 0 {
                        LabeledContent("Per Texterkennung gelesen", value: "\(erkannt) Seiten")
                    }
                }
            }

            Section("Farben") {
                ForEach(MarkierungsFarbe.allCases) { farbe in
                    HStack(spacing: 8) {
                        Circle().fill(farbe.farbe).frame(width: 12, height: 12)
                        Text(farbe.bedeutung).font(.callout)
                    }
                }
            }

            Section {
                Picker("Anzeigen", selection: $farbFilter) {
                    Text("Alle Farben").tag(MarkierungsFarbe?.none)
                    ForEach(MarkierungsFarbe.allCases) { farbe in
                        Text(farbe.bedeutung).tag(MarkierungsFarbe?.some(farbe))
                    }
                }
                if gefiltert.isEmpty {
                    Text("Text auswählen und eine Farbe in der Leiste unten antippen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(gefiltert) { markierung in
                    MarkierungsZeile(markierung: markierung) {
                        steuerung.gehe(zu: markierung.seitenIndex)
                    } loeschen: {
                        kontext.delete(markierung)
                    }
                }
            } header: {
                Text("Markierungen (\(dokument.sichtbareMarkierungen.count))")
            }

            let handschrift = (dokument.zeichnungen ?? []).sorted { $0.seitenIndex < $1.seitenIndex }
            if !handschrift.isEmpty {
                Section("Handschrift") {
                    ForEach(handschrift) { zeichnung in
                        Button {
                            steuerung.gehe(zu: zeichnung.seitenIndex)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Seite \(zeichnung.seitenIndex + 1)").font(.caption.weight(.semibold))
                                Text(zeichnung.text.isEmpty ? "Noch nicht erkannt" : zeichnung.text)
                                    .font(.callout)
                                    .foregroundStyle(zeichnung.text.isEmpty ? .secondary : .primary)
                                    .lineLimit(3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Notizen") {
                TextField("Notizen zur Vorlesung", text: $dokument.notizen, axis: .vertical)
                    .lineLimit(3...12)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MarkierungsZeile: View {
    @Bindable var markierung: Markierung
    var springen: () -> Void
    var loeschen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: springen) {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(markierung.farbe.farbe)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Seite \(markierung.seitenIndex + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(markierung.text.isEmpty ? "–" : markierung.text)
                            .font(.callout)
                            .lineLimit(4)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Picker("Farbe", selection: $markierung.farbe) {
                    ForEach(MarkierungsFarbe.allCases) { farbe in
                        Text(farbe.bedeutung).tag(farbe)
                    }
                }
                Button("Löschen", role: .destructive, action: loeschen)
            } label: {
                Label("Optionen", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
    }
}
