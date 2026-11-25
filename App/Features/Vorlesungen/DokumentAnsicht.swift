import SwiftUI
import SwiftData
import PDFKit
import PharmaCore

/// Eigenständige Ansicht einer Unterlage (aus der Suche oder in einem eigenen Fenster).
struct DokumentAnsicht: View {
    @Bindable var dokument: Dokument
    var startSeite = 0
    var zurueck: () -> Void
    var oeffnen: (Dokument, Int) -> Void

    var body: some View {
        DokumentArbeitsflaeche(dokument: dokument, startSeite: startSeite, oeffnen: oeffnen)
            .navigationTitle(dokument.titel)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: zurueck) {
                        Label(dokument.lehrveranstaltung.map { LfdNr.anzeige($0.lfdNr) } ?? "Zurück", systemImage: "chevron.left")
                    }
                    .help("Zurück zur Lehrveranstaltung")
                }
            }
    }
}

/// Leser plus Seitenpanel – je nach Typ der Unterlage.
struct DokumentArbeitsflaeche: View {
    @Bindable var dokument: Dokument
    var startSeite = 0
    var oeffnen: (Dokument, Int) -> Void

    @State private var steuerung = PDFSteuerung()
    @AppStorage("dokumentPanelSichtbar") private var zeigePanel = true

    var body: some View {
        switch dokument.typ {
        case .pdf, .scan:
            GeometryReader { geo in
                HStack(spacing: 0) {
                    PDFLeser(dokument: dokument, startSeite: startSeite, steuerung: steuerung, zeigePanel: $zeigePanel)
                    if zeigePanel && geo.size.width > 640 {
                        Rectangle().fill(Thema.linie).frame(width: 1)
                        DokumentSeitenpanel(dokument: dokument, steuerung: steuerung)
                            .frame(width: min(320, geo.size.width * 0.34))
                    }
                }
            }
            .id(dokument.persistentModelID)
        case .praesentation:
            PraesentationsAnsicht(dokument: dokument)
        case .audio:
            AudioAnsicht(dokument: dokument, oeffnen: oeffnen)
        }
    }
}

/// PDF-Leser mit Kopfzeile („Seite 12 von 38“, Suche, Markierfarben).
struct PDFLeser: View {
    @Bindable var dokument: Dokument
    let startSeite: Int
    let steuerung: PDFSteuerung
    @Binding var zeigePanel: Bool

    @Environment(\.modelContext) private var kontext
    @State private var pdf: PDFDocument?
    @State private var ladefehler = false
    @State private var stiftModus = false
    @State private var geaenderteSeiten: Set<Int> = []
    @State private var suche = ""
    @State private var exportDatei: PDFDatei?
    @State private var zeigeExport = false

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
        VStack(spacing: 0) {
            kopfzeile
            ZStack {
                if let pdf {
                    PDFAnzeige(pdf: pdf, steuerung: steuerung, markierungen: markierungsDaten, zeichnungen: zeichnungsDaten,
                               startSeite: startSeite, stiftModus: stiftModus, zeichnungGeaendert: zeichnungSpeichern)
                } else if ladefehler {
                    ContentUnavailableView("Dokument kann nicht geöffnet werden", systemImage: "exclamationmark.triangle",
                                           description: Text("Die Datei ist beschädigt oder leer."))
                } else {
                    ProgressView("Dokument wird geladen …")
                }
            }
        }
        .background(Thema.flaecheGedaempft)
        .task {
            guard pdf == nil else { return }
            if let daten = dokument.daten, let geladen = PDFDocument(data: daten) {
                pdf = geladen
            } else {
                ladefehler = true
            }
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

    private var kopfzeile: some View {
        HStack(spacing: 14) {
            Text("Seite \(steuerung.aktuelleSeite + 1) von \(max(steuerung.seitenzahl, dokument.seitenzahl))")
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteSekundaer)
                .monospacedDigit()
            Spacer(minLength: 8)

            HStack(spacing: 4) {
                TextField("Suchen", text: $suche)
                    .textFieldStyle(.plain)
                    .font(Thema.ui(12))
                    .frame(width: 120)
                    .onSubmit { steuerung.suchen(suche) }
                if steuerung.trefferAnzahl > 0 {
                    Text(verbatim: "\(steuerung.trefferIndex + 1)/\(steuerung.trefferAnzahl)")
                        .font(Thema.mono(11))
                        .foregroundStyle(Thema.tinteTertiaer)
                    Button { steuerung.naechsterTreffer(-1) } label: { Image(systemName: "chevron.up") }
                        .accessibilityLabel("Vorheriger Treffer")
                    Button { steuerung.naechsterTreffer(1) } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Nächster Treffer")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Thema.flaeche, in: Capsule())
            .overlay(Capsule().strokeBorder(Thema.rahmen))

            HStack(spacing: 7) {
                ForEach(MarkierungsFarbe.allCases) { farbe in
                    Button {
                        steuerung.markieren(farbe, dokument: dokument, kontext: kontext)
                    } label: {
                        Circle()
                            .fill(farbe.farbe)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.08)))
                            .frame(width: 16, height: 16)
                    }
                    .help("\(farbe.name) – \(farbe.bedeutung)")
                    .accessibilityLabel("Markieren: \(farbe.bedeutung)")
                }
                .disabled(!steuerung.hatAuswahl)
                .opacity(steuerung.hatAuswahl ? 1 : 0.55)

                Button {
                    steuerung.markierungEntfernen(dokument: dokument, kontext: kontext)
                } label: {
                    Image(systemName: "eraser")
                }
                .disabled(!steuerung.hatAuswahl)
                .help("Markierungen in der Auswahl entfernen")
            }

            #if os(iOS)
            Button {
                stiftModus.toggle()
            } label: {
                Image(systemName: stiftModus ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
            }
            .help(stiftModus ? "Stift beenden" : "Mit Apple Pencil schreiben")
            #endif

            Button {
                exportieren()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Als PDF mit Markierungen und Handschrift exportieren")

            Button {
                zeigePanel.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Seitenleiste ein- oder ausblenden")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Thema.tinteSekundaer)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

/// Rechte Spalte: Zusammenfassung, Kernaussagen (KI), Markierungen, Handschrift, Notizen.
struct DokumentSeitenpanel: View {
    @Bindable var dokument: Dokument
    let steuerung: PDFSteuerung

    @Environment(\.modelContext) private var kontext
    @State private var stufe: ZusammenfassungsStufe = .lernen
    @State private var farbFilter: MarkierungsFarbe?
    @State private var kiLaeuft: String?
    @State private var kiStream = ""
    @State private var kiMeldung: String?
    @State private var exportDatei: PDFDatei?
    @State private var zeigeExport = false

    private var zusammenfassung: Zusammenfassung? {
        (dokument.zusammenfassungen ?? []).filter { $0.stufe == stufe }.max { $0.erstelltAm < $1.erstelltAm }
    }

    private func kiStarten(_ name: String, _ arbeit: @escaping () async throws -> String?) {
        guard KI.istEingerichtet else {
            kiMeldung = KIFehler.keinSchluessel.errorDescription
            return
        }
        guard VorlesungsKI.hatText(dokument) else {
            kiMeldung = "Diese Unterlage enthält (noch) keinen lesbaren Text. Warte, bis die Texterkennung fertig ist."
            return
        }
        kiLaeuft = name
        kiMeldung = nil
        kiStream = ""
        Task {
            do {
                kiMeldung = try await arbeit()
            } catch {
                kiMeldung = error.localizedDescription
            }
            kiLaeuft = nil
            kiStream = ""
        }
    }

    private func zusammenfassungExportieren(_ eintrag: Zusammenfassung) {
        let lv = dokument.lehrveranstaltung
        let kopf = [lv.map { "\(LfdNr.anzeige($0.lfdNr)) \($0.anzeigename)" } ?? "", dokument.titel, Date().kurzesDatum]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let unter = "Vorlesung vom \(dokument.datum.kurzesDatum) · erstellt am \(eintrag.erstelltAm.kurzesDatum)"
        guard let daten = BerichtPDF.erstellen(titel: eintrag.stufe.name, untertitel: unter, kopfzeile: kopf, markdown: eintrag.text) else { return }
        exportDatei = PDFDatei(daten: daten)
        zeigeExport = true
    }

    private var vorschlaege: [Markierung] {
        (dokument.markierungen ?? []).filter { $0.quelle == .ki && $0.status == .vorgeschlagen }
            .sorted { $0.seitenIndex < $1.seitenIndex }
    }

    private var eigene: [Markierung] {
        dokument.sichtbareMarkierungen.filter { $0.status == .angenommen && (farbFilter == nil || $0.farbe == farbFilter) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Kleintitel(text: "Zusammenfassung")
                Segmentleiste(werte: ZusammenfassungsStufe.allCases, auswahl: $stufe) { $0.segment }
                    .padding(.top, 12)
                Group {
                    if kiLaeuft == "zusammenfassung" {
                        if kiStream.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("\(stufe.name) wird erstellt …").font(Thema.ui(12)).foregroundStyle(Thema.tinteSekundaer)
                            }
                        } else {
                            MarkdownText(text: kiStream, schrift: Thema.ui(13))
                        }
                    } else if let zusammenfassung {
                        MarkdownText(text: zusammenfassung.text, schrift: Thema.ui(13))
                        HStack(spacing: 14) {
                            Button("Als PDF exportieren") { zusammenfassungExportieren(zusammenfassung) }
                            Button("Neu erstellen") { zusammenfassen() }
                        }
                        .buttonStyle(.plain)
                        .font(Thema.ui(12))
                        .underline()
                        .foregroundStyle(Thema.tinteSekundaer)
                        .padding(.top, 4)
                    } else {
                        Button("\(stufe.name) erstellen (KI)") { zusammenfassen() }
                            .buttonStyle(.plain)
                            .font(Thema.ui(13, .mittel))
                            .underline()
                            .disabled(kiLaeuft != nil)
                    }
                }
                .padding(.top, 14)

                Haarlinie().padding(.vertical, 24)

                HStack {
                    Kleintitel(text: "Kernaussagen (KI)")
                    Spacer()
                    Text("\(vorschlaege.count) offen")
                        .font(Thema.ui(11))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
                if kiLaeuft == "kernaussagen" {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Kernaussagen werden gesucht …").font(Thema.ui(12)).foregroundStyle(Thema.tinteSekundaer)
                    }
                    .padding(.top, 10)
                } else if vorschlaege.isEmpty {
                    Button("Kernaussagen markieren (KI)") { kernaussagen() }
                        .buttonStyle(.plain)
                        .font(Thema.ui(13, .mittel))
                        .underline()
                        .disabled(kiLaeuft != nil || !dokument.istPDF)
                        .padding(.top, 10)
                    Text("Die KI schlägt wichtige Aussagen und wahrscheinliche Prüfungsthemen vor – du übernimmst oder lehnst jede einzeln ab.")
                        .font(Thema.ui(11))
                        .foregroundStyle(Thema.tinteTertiaer)
                        .padding(.top, 4)
                }
                if !vorschlaege.isEmpty {
                    HStack(spacing: 14) {
                        Button("Alle übernehmen") { vorschlaege.forEach { $0.status = .angenommen } }
                        Button("Alle ablehnen") { vorschlaege.forEach { $0.status = .abgelehnt } }
                    }
                    .buttonStyle(.plain)
                    .font(Thema.ui(11))
                    .underline()
                    .foregroundStyle(Thema.tinteSekundaer)
                    .padding(.top, 8)
                }
                ForEach(vorschlaege) { vorschlag in
                    KernaussageKarte(markierung: vorschlag) {
                        steuerung.gehe(zu: vorschlag.seitenIndex)
                    }
                    .padding(.top, 10)
                }

                Haarlinie().padding(.vertical, 24)

                HStack {
                    Kleintitel(text: "Markierungen")
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(MarkierungsFarbe.allCases) { farbe in
                            Button {
                                farbFilter = farbFilter == farbe ? nil : farbe
                            } label: {
                                Circle()
                                    .fill(farbe.farbe)
                                    .overlay(Circle().strokeBorder(farbFilter == farbe ? Thema.tinte : Color.black.opacity(0.08)))
                                    .frame(width: 11, height: 11)
                            }
                            .buttonStyle(.plain)
                            .help("Nur „\(farbe.bedeutung)“ anzeigen")
                        }
                    }
                }
                if eigene.isEmpty {
                    Text("Text auswählen und oben eine Farbe wählen: Gelb = wichtig, Rot = prüfungsrelevant, Grün = Definition, Blau = Strukturformel/Mechanismus, Lila = Arzneibuch-Methode.")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                        .lineSpacing(3)
                        .padding(.top, 10)
                }
                ForEach(eigene) { markierung in
                    MarkierungsZeile(markierung: markierung) {
                        steuerung.gehe(zu: markierung.seitenIndex)
                    } loeschen: {
                        kontext.delete(markierung)
                    }
                    .padding(.top, 10)
                }

                let handschrift = (dokument.zeichnungen ?? []).sorted { $0.seitenIndex < $1.seitenIndex }
                if !handschrift.isEmpty {
                    Haarlinie().padding(.vertical, 24)
                    Kleintitel(text: "Handschrift")
                    ForEach(handschrift) { zeichnung in
                        Button {
                            steuerung.gehe(zu: zeichnung.seitenIndex)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Seite \(zeichnung.seitenIndex + 1)").font(Thema.ui(11)).foregroundStyle(Thema.tinteTertiaer)
                                Text(verbatim: zeichnung.text.isEmpty ? "Noch nicht erkannt" : zeichnung.text)
                                    .font(Thema.ui(13))
                                    .foregroundStyle(zeichnung.text.isEmpty ? Thema.tinteTertiaer : Thema.tinte)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }

                Haarlinie().padding(.vertical, 24)
                Kleintitel(text: "Karteikarten")
                Button(kiLaeuft == "karten" ? "Karten werden erzeugt …" : "Karteikarten aus dieser Vorlesung erzeugen (KI)") {
                    kiStarten("karten") {
                        let anzahl = try await VorlesungsKI.kartenErzeugen(dokument, kontext: kontext)
                        return "\(anzahl) Karteikarten erstellt – zu finden unter „Quiz & Karteikarten“."
                    }
                }
                .buttonStyle(.plain)
                .font(Thema.ui(13, .mittel))
                .underline()
                .disabled(kiLaeuft != nil)
                .padding(.top, 10)
                if let kiMeldung {
                    Text(verbatim: kiMeldung)
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .padding(.top, 10)
                }

                Haarlinie().padding(.vertical, 24)
                Kleintitel(text: "Notizen")
                TextField("Notizen zur Vorlesung", text: $dokument.notizen, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Thema.ui(13))
                    .lineLimit(3...14)
                    .padding(.top, 10)

                Haarlinie().padding(.vertical, 24)
                Kleintitel(text: "Unterlage")
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Titel", text: $dokument.titel)
                        .textFieldStyle(.plain)
                        .font(Thema.ui(13))
                    DatePicker("Vorlesung vom", selection: $dokument.datum, displayedComponents: .date)
                        .font(Thema.ui(13))
                    if dokument.texterkennungLaeuft {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Texterkennung läuft …").font(Thema.ui(12)).foregroundStyle(Thema.tinteSekundaer)
                        }
                    } else {
                        let erkannt = (dokument.seiten ?? []).filter(\.ausTexterkennung).count
                        if erkannt > 0 {
                            Text("\(erkannt) Seiten per Texterkennung gelesen")
                                .font(Thema.ui(12))
                                .foregroundStyle(Thema.tinteTertiaer)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(24)
        }
        .background(Thema.flaeche)
        .fileExporter(isPresented: $zeigeExport, document: exportDatei, contentType: .pdf,
                      defaultFilename: "\(dokument.titel) – \(stufe.name)") { _ in }
    }

    private func zusammenfassen() {
        let gewaehlt = stufe
        kiStarten("zusammenfassung") {
            try await VorlesungsKI.zusammenfassen(dokument, stufe: gewaehlt, kontext: kontext) { teil in kiStream = teil }
            return nil
        }
    }

    private func kernaussagen() {
        kiStarten("kernaussagen") {
            let ergebnis = try await VorlesungsKI.kernaussagenMarkieren(dokument, kontext: kontext)
            if ergebnis.vorgeschlagen == 0 { return "Es wurden keine passenden Stellen im Text gefunden." }
            return ergebnis.nichtGefunden > 0
                ? "\(ergebnis.vorgeschlagen) Vorschläge markiert, \(ergebnis.nichtGefunden) Zitate im PDF nicht gefunden."
                : "\(ergebnis.vorgeschlagen) Vorschläge markiert."
        }
    }
}

/// KI-Vorschlag mit „Ablehnen“ und „Übernehmen“.
private struct KernaussageKarte: View {
    @Bindable var markierung: Markierung
    var springen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: springen) {
                Text(verbatim: markierung.begruendung.isEmpty ? markierung.text : markierung.begruendung)
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinte)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Text("Vorschlag").font(Thema.ui(11)).foregroundStyle(Thema.tinteTertiaer)
                Spacer()
                Button {
                    markierung.status = .abgelehnt
                } label: {
                    Text("Ablehnen")
                        .font(Thema.ui(12))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Thema.rahmenStark))
                }
                Button {
                    markierung.status = .angenommen
                } label: {
                    Text("Übernehmen")
                        .font(Thema.ui(12, .mittel))
                        .foregroundStyle(Thema.tinteInvers)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Thema.tinte, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Thema.rahmen))
    }
}

/// Eigene Markierung in der Seitenleiste.
struct MarkierungsZeile: View {
    @Bindable var markierung: Markierung
    var springen: () -> Void
    var loeschen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: springen) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(markierung.farbe.farbe)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Seite \(markierung.seitenIndex + 1)")
                            .font(Thema.ui(11))
                            .foregroundStyle(Thema.tinteTertiaer)
                        Text(verbatim: markierung.text.isEmpty ? "–" : markierung.text)
                            .font(Thema.ui(13))
                            .foregroundStyle(Thema.tinte)
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
                Image(systemName: "ellipsis")
                    .foregroundStyle(Thema.tinteTertiaer)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Optionen")
        }
    }
}
