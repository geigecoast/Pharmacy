import SwiftUI
import SwiftData
import AVFoundation
import QuickLook
#if os(macOS)
import Quartz
#endif
import PharmaCore

// MARK: - Präsentation

struct PraesentationsAnsicht: View {
    @Bindable var dokument: Dokument
    @State private var url: URL?
    @AppStorage("dokumentInspectorSichtbar") private var zeigeInspector = true

    var body: some View {
        Group {
            if let url {
                SchnellVorschau(url: url)
            } else {
                ContentUnavailableView("Vorschau nicht möglich", systemImage: "rectangle.on.rectangle.slash",
                                       description: Text("Die Präsentation konnte nicht geladen werden."))
            }
        }
        .task { url = DokumentImport.temporaereDatei(fuer: dokument) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    zeigeInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $zeigeInspector) {
            Form {
                Section {
                    Label("Markierungen und Handschrift sind in PDFs möglich. Exportiere die Präsentation in PowerPoint oder Keynote als PDF und importiere sie erneut.",
                          systemImage: "info.circle")
                        .font(.callout)
                }
                Section("Dokument") {
                    TextField("Titel", text: $dokument.titel)
                    DatePicker("Vorlesung vom", selection: $dokument.datum, displayedComponents: .date)
                }
                Section("Folientexte") {
                    if dokument.sortierteSeiten.isEmpty {
                        Text("Für diese Datei ist kein Text verfügbar (nur .pptx wird ausgelesen).")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(dokument.sortierteSeiten) { seite in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Folie \(seite.nummer + 1)").font(.caption.weight(.semibold))
                            Text(seite.text.isEmpty ? "–" : seite.text).font(.callout)
                        }
                    }
                }
                Section("Notizen") {
                    TextField("Notizen zur Vorlesung", text: $dokument.notizen, axis: .vertical)
                        .lineLimit(3...12)
                }
            }
            .formStyle(.grouped)
            .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
        }
    }
}

/// QuickLook-Vorschau (PowerPoint, Keynote usw.).
#if os(macOS)
struct SchnellVorschau: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let ansicht = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        ansicht.previewItem = url as NSURL
        return ansicht
    }

    func updateNSView(_ ansicht: QLPreviewView, context: Context) {
        if (ansicht.previewItem as? NSURL) as URL? != url {
            ansicht.previewItem = url as NSURL
        }
    }
}
#else
struct SchnellVorschau: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let steuerung = QLPreviewController()
        steuerung.dataSource = context.coordinator
        return steuerung
    }

    func updateUIViewController(_ steuerung: QLPreviewController, context: Context) {
        context.coordinator.url = url
        steuerung.reloadData()
    }

    func makeCoordinator() -> Koordinator { Koordinator(url: url) }

    final class Koordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

// MARK: - Audio

@Observable
final class AudioSpieler {
    @ObservationIgnored private var spieler: AVAudioPlayer?
    var dauer: Double = 0
    var fehler: String?

    var zeit: Double { spieler?.currentTime ?? 0 }
    var spielt: Bool { spieler?.isPlaying ?? false }

    func laden(_ url: URL) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        #endif
        do {
            let neu = try AVAudioPlayer(contentsOf: url)
            neu.prepareToPlay()
            spieler = neu
            dauer = neu.duration
        } catch {
            fehler = "Die Aufnahme kann nicht abgespielt werden."
        }
    }

    func umschalten() {
        guard let spieler else { return }
        if spieler.isPlaying { spieler.pause() } else { spieler.play() }
    }

    func springe(zu sekunde: Double) {
        spieler?.currentTime = max(0, min(sekunde, dauer))
    }

    func vor(_ sekunden: Double) {
        springe(zu: zeit + sekunden)
    }

    func stoppen() {
        spieler?.stop()
    }
}

struct AudioAnsicht: View {
    @Bindable var dokument: Dokument
    var oeffnen: (Dokument, Int) -> Void

    @Query private var alleDokumente: [Dokument]
    @State private var spieler = AudioSpieler()
    @State private var transkribiert = false
    @State private var fehler: String?
    @State private var markenFolie = 1

    private var verknuepft: Dokument? {
        guard let kennung = dokument.verknuepftesDokumentKennung else { return nil }
        return alleDokumente.first { $0.kennung == kennung }
    }

    private var kandidaten: [Dokument] {
        (dokument.lehrveranstaltung?.dokumente ?? []).filter(\.istPDF).sorted { $0.titel < $1.titel }
    }

    var body: some View {
        VStack(spacing: 0) {
            spielerLeiste
                .padding(Layout.abstand)
            Divider()
            List {
                folienBereich
                transkriptBereich
            }
        }
        .task {
            if let url = DokumentImport.temporaereDatei(fuer: dokument) {
                spieler.laden(url)
            }
        }
        .onDisappear { spieler.stoppen() }
    }

    private var spielerLeiste: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 10) {
                HStack(spacing: 20) {
                    Button { spieler.vor(-15) } label: { Label("15 Sekunden zurück", systemImage: "gobackward.15") }
                    Button { spieler.umschalten() } label: {
                        Label(spieler.spielt ? "Pause" : "Abspielen", systemImage: spieler.spielt ? "pause.circle.fill" : "play.circle.fill")
                            .font(.largeTitle)
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    Button { spieler.vor(15) } label: { Label("15 Sekunden vor", systemImage: "goforward.15") }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.title2)
                HStack {
                    Text(verbatim: Transkript.zeitText(spieler.zeit)).monospacedDigit()
                    Slider(value: Binding(get: { spieler.zeit }, set: { spieler.springe(zu: $0) }),
                           in: 0...max(spieler.dauer, 1))
                    Text(verbatim: Transkript.zeitText(spieler.dauer)).monospacedDigit()
                }
                .font(.caption)
                if let fehler = spieler.fehler {
                    Label(fehler, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var folienBereich: some View {
        Section {
            Picker("Verknüpfte Folien", selection: $dokument.verknuepftesDokumentKennung) {
                Text("Keine").tag(UUID?.none)
                ForEach(kandidaten) { kandidat in
                    Text(kandidat.titel).tag(UUID?.some(kandidat.kennung))
                }
            }
            if let folien = verknuepft {
                HStack {
                    Stepper(value: $markenFolie, in: 1...max(1, folien.seitenzahl)) {
                        Text("Folie \(markenFolie)")
                    }
                    Spacer()
                    Button("Marke bei \(Transkript.zeitText(spieler.zeit)) setzen") {
                        var marken = dokument.folienmarken.filter { abs($0.zeit - spieler.zeit) > 1 }
                        marken.append(Folienmarke(zeit: spieler.zeit, seitenIndex: markenFolie - 1))
                        dokument.folienmarken = marken
                    }
                }
                ForEach(dokument.folienmarken) { marke in
                    HStack {
                        Button(Transkript.zeitText(marke.zeit)) { spieler.springe(zu: marke.zeit) }
                            .monospacedDigit()
                        Text("→ Folie \(marke.seitenIndex + 1)")
                        Spacer()
                        Button("Folie öffnen") { oeffnen(folien, marke.seitenIndex) }
                        Button(role: .destructive) {
                            dokument.folienmarken = dokument.folienmarken.filter { $0 != marke }
                        } label: {
                            Label("Marke löschen", systemImage: "trash").labelStyle(.iconOnly)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Folien")
        } footer: {
            Text("Setze beim Abspielen Marken, um Abschnitte der Aufnahme mit Folien zu verbinden.")
        }
    }

    @ViewBuilder
    private var transkriptBereich: some View {
        Section {
            if dokument.transkript.isEmpty {
                Button {
                    transkribieren()
                } label: {
                    Label("Transkript erstellen", systemImage: "text.bubble")
                }
                .disabled(transkribiert)
                if transkribiert {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Aufnahme wird transkribiert – das kann bei langen Vorlesungen einige Minuten dauern.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let fehler {
                Label(fehler, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            ForEach(dokument.transkript) { abschnitt in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button(Transkript.zeitText(abschnitt.start)) { spieler.springe(zu: abschnitt.start) }
                        .monospacedDigit()
                        .buttonStyle(.borderless)
                    Text(abschnitt.text)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    if let folien = verknuepft, let folie = Transkript.folie(zu: abschnitt.start, marken: dokument.folienmarken) {
                        Button("Folie \(folie + 1)") { oeffnen(folien, folie) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Transkript")
        } footer: {
            Text("Die Spracherkennung läuft nach Möglichkeit direkt auf dem Gerät.")
        }
    }

    private func transkribieren() {
        guard let url = DokumentImport.temporaereDatei(fuer: dokument) else { return }
        transkribiert = true
        fehler = nil
        Task {
            do {
                dokument.transkript = try await TranskriptionsDienst.transkribieren(url: url)
            } catch {
                fehler = error.localizedDescription
            }
            transkribiert = false
        }
    }
}
