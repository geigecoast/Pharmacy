import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PharmaCore

/// Tab „Quiz & Karteikarten“ nach Design: fällige Karte links, Quiz-Modi rechts.
struct QuizKartenAnsicht: View {
    @Bindable var lv: Lehrveranstaltung

    @Environment(\.modelContext) private var kontext
    @State private var bearbeiten: Karteikarte?
    @State private var neueKarte = false
    @State private var quizModus: QuizModus?
    @State private var zeigeFehler = false
    @State private var meldung: String?
    @State private var filter = ""
    @State private var exportDatei: ExportDatei?
    @State private var exportTyp: UTType = .ankiPaket
    @State private var exportName = ""
    @State private var zeigeExport = false

    private var karten: [Karteikarte] { lv.karteikarten ?? [] }

    private var gefiltert: [Karteikarte] {
        let begriff = filter.trimmingCharacters(in: .whitespaces)
        return karten
            .filter { begriff.isEmpty || $0.frageText.localizedStandardContains(begriff) || $0.thema.localizedStandardContains(begriff) }
            .sorted { ($0.prioritaet ? 0 : 1, $0.erstelltAm) < ($1.prioritaet ? 0 : 1, $1.erstelltAm) }
    }

    private var offeneFehler: Int {
        (lv.fehlereintraege ?? []).filter { !$0.verstanden }.count
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                Group {
                    if geo.size.width > 900 {
                        HStack(alignment: .top, spacing: 56) {
                            links.frame(maxWidth: .infinity)
                            rechts.frame(width: 360)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 44) {
                            links
                            rechts
                        }
                    }
                }
                .padding(.vertical, 36)
            }
        }
        .sheet(item: $bearbeiten) { karte in
            KarteBearbeiten(karte: karte)
        }
        .sheet(isPresented: $neueKarte) {
            KarteBearbeiten(neuFuer: lv)
        }
        .sheet(item: $quizModus) { modus in
            QuizSitzung(modus: modus, pool: karten, lv: lv)
        }
        .sheet(isPresented: $zeigeFehler) {
            FehlerjournalAnsicht(lv: lv)
        }
        .fileExporter(isPresented: $zeigeExport, document: exportDatei, contentType: exportTyp,
                      defaultFilename: exportName) { _ in }
    }

    // MARK: Links

    private var links: some View {
        VStack(alignment: .leading, spacing: 48) {
            KartenWiederholung(karten: karten)

            VStack(alignment: .leading, spacing: 0) {
                Abschnittstitel(titel: "Alle Karten") {
                    Text(verbatim: "\(karten.count)")
                }
                if karten.count > 6 {
                    TextField("Karten durchsuchen", text: $filter)
                        .textFieldStyle(.plain)
                        .font(Thema.ui(13))
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Haarlinie() }
                }
                if karten.isEmpty {
                    Text("Noch keine Karten. Lege eine an oder erstelle Lückentexte aus deinen Markierungen.")
                        .font(Thema.ui(13))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .padding(.vertical, 18)
                }
                ForEach(gefiltert) { karte in
                    KartenZeile(karte: karte) { bearbeiten = karte }
                        .contextMenu {
                            Button("Bearbeiten …") { bearbeiten = karte }
                            Button(karte.prioritaet ? "Nicht mehr prüfungsrelevant" : "Als prüfungsrelevant markieren") {
                                karte.prioritaet.toggle()
                            }
                            Button("Lernstand zurücksetzen") { karte.stand = .neu() }
                            Button("Löschen", role: .destructive) { kontext.delete(karte) }
                        }
                }
            }
        }
    }

    // MARK: Rechts

    private var rechts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kleintitel(text: "Quiz-Modi")
            Haarlinie(farbe: Thema.tinte).padding(.top, 10)
            ForEach(QuizModus.allCases) { modus in
                Button {
                    quizModus = modus
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: modus.name).font(Thema.ui(15)).foregroundStyle(Thema.tinte)
                        Spacer()
                        Text(verbatim: modus.kurzinfo).font(Thema.ui(12)).foregroundStyle(Thema.tinteSekundaer)
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(karten.filter(\.istGueltig).isEmpty)
                .overlay(alignment: .bottom) { Haarlinie() }
            }

            HStack(alignment: .top) {
                kennzahl("–", "Level", hilfe: "Level und XP folgen in Ausbaustufe h")
                Button {
                    zeigeFehler = true
                } label: {
                    kennzahl("\(offeneFehler)", "Fehlerjournal", hilfe: "Falsche Antworten zum Wiederholen")
                }
                .buttonStyle(.plain)
                kennzahl("\(KartenDienst.anzahlFaellig(karten))", "Karten fällig", hilfe: "Heute fällige Karten")
            }
            .padding(.top, 36)

            VStack(alignment: .leading, spacing: 0) {
                Kleintitel(text: "Karten")
                Haarlinie().padding(.top, 10)
                aktion("Neue Karte …") { neueKarte = true }
                let offen = KartenDienst.offeneMarkierungen(lv).count
                aktion("Lückentexte aus Markierungen (\(offen) neu)") {
                    let ergebnis = KartenDienst.ausMarkierungen(lv, kontext: kontext)
                    meldung = ergebnis.uebersprungen > 0
                        ? "\(ergebnis.erstellt) Karten erstellt, \(ergebnis.uebersprungen) Markierungen übersprungen (kein passender Satz gefunden)."
                        : "\(ergebnis.erstellt) Karten erstellt."
                }
                .disabled(offen == 0)
                aktion("Als Anki-Paket exportieren (.apkg)") { ankiExport() }
                    .disabled(karten.isEmpty)
                aktion("Als CSV exportieren") { csvExport() }
                    .disabled(karten.isEmpty)
                if let meldung {
                    Text(verbatim: meldung)
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .padding(.top, 12)
                }
                Text("Automatisch erzeugte Karten aus Vorlesungen und Zusammenfassungen erstellt der KI-Tutor ab Ausbaustufe e.")
                    .font(Thema.ui(11))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .padding(.top, 12)
            }
            .padding(.top, 40)
        }
    }

    private func kennzahl(_ wert: String, _ titel: LocalizedStringKey, hilfe: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: wert)
                .font(Thema.display(34))
                .foregroundStyle(Thema.tinte)
            Text(titel)
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteSekundaer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(hilfe)
    }

    private func aktion(_ titel: String, _ handlung: @escaping () -> Void) -> some View {
        Button(action: handlung) {
            HStack {
                Text(verbatim: titel).font(Thema.ui(14))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 12))
            }
            .foregroundStyle(Thema.tinte)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Haarlinie() }
    }

    private func ankiExport() {
        do {
            let stapel = "PharmaTutor::\(LfdNr.anzeige(lv.lfdNr)) \(lv.anzeigename)"
            exportDatei = ExportDatei(daten: try KartenExport.anki(karten, stapel: stapel))
            exportTyp = .ankiPaket
            exportName = "PharmaTutor \(lv.lfdNr) \(lv.anzeigename).apkg"
            zeigeExport = true
        } catch {
            meldung = "Das Anki-Paket konnte nicht erstellt werden."
        }
    }

    private func csvExport() {
        exportDatei = ExportDatei(daten: Data(KartenExport.csv(karten).utf8))
        exportTyp = .commaSeparatedText
        exportName = "PharmaTutor \(lv.lfdNr) \(lv.anzeigename).csv"
        zeigeExport = true
    }
}

private struct KartenZeile: View {
    let karte: Karteikarte
    var aktion: () -> Void

    private var status: String {
        if karte.zustandRaw == KartenZustand.neu.rawValue { return "neu" }
        if karte.istFaellig() { return "fällig" }
        return "in " + FSRS.abstandText(von: Date(), bis: karte.faellig)
    }

    var body: some View {
        Button(action: aktion) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: karte.typ.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: karte.frageText)
                        .font(Thema.ui(14))
                        .foregroundStyle(karte.istGueltig ? Thema.tinte : Thema.tinteTertiaer)
                        .lineLimit(2)
                    if !karte.thema.isEmpty {
                        Text(verbatim: karte.thema)
                            .font(Thema.ui(11))
                            .foregroundStyle(Thema.tinteTertiaer)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if karte.prioritaet {
                    Punkt(farbe: Stoffgebiet.i.farbe)
                        .help("Prüfungsrelevant")
                }
                Text(verbatim: status)
                    .font(Thema.mono(11))
                    .foregroundStyle(karte.istFaellig() ? Thema.tinte : Thema.tinteTertiaer)
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}

/// Wiederholung aller fälligen Karten (aus „Heute lernen“).
struct WiederholungsSitzung: View {
    @Query private var alleKarten: [Karteikarte]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                KartenWiederholung(karten: alleKarten, titel: "Alle fälligen Karten")
                    .padding(40)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
            }
            .background(Thema.flaeche)
            .navigationTitle("Karteikarten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 620)
        #endif
    }
}
