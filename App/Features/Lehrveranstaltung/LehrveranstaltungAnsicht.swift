import SwiftUI
import SwiftData
import PharmaCore

enum LVTab: String, CaseIterable, Identifiable {
    case vorlesungen
    case pruefung
    case tutor
    case quiz
    case analysen

    var id: String { rawValue }

    var titel: LocalizedStringKey {
        switch self {
        case .vorlesungen: "Vorlesungen"
        case .pruefung: "Prüfungsvorbereitung"
        case .tutor: "Tutor"
        case .quiz: "Quiz & Karteikarten"
        case .analysen: "Analysen"
        }
    }

    var symbol: String {
        switch self {
        case .vorlesungen: "doc.richtext"
        case .pruefung: "checklist"
        case .tutor: "bubble.left.and.text.bubble.right"
        case .quiz: "rectangle.on.rectangle.angled"
        case .analysen: "chart.pie"
        }
    }
}

struct LehrveranstaltungAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    var beiLoeschen: () -> Void = {}
    var oeffnen: (Dokument, Int) -> Void = { _, _ in }

    @AppStorage(EinstellungsSchluessel.lvTab) private var tab: LVTab = .vorlesungen
    @AppStorage("lvInspectorSichtbar") private var zeigeInspector = false

    var body: some View {
        GeometryReader { geo in
            let rand = geo.size.width > 700 ? Thema.randAussen : Thema.randKompakt
            VStack(alignment: .leading, spacing: 0) {
                LVKopf(lv: lv)
                    .padding(.horizontal, rand)
                    .padding(.top, 36)
                Unterstrichtabs(werte: LVTab.allCases, auswahl: $tab) { $0.titel }
                    .padding(.horizontal, rand)
                    .padding(.top, 26)
                inhalt(rand: rand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Thema.flaeche)
        .navigationTitle(lv.lfdNrAnzeige)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    zeigeInspector.toggle()
                } label: {
                    Label("Angaben bearbeiten", systemImage: "slider.horizontal.3")
                }
                .help("Stammdaten, Voraussetzungen und Notizen bearbeiten")
            }
        }
        .inspector(isPresented: $zeigeInspector) {
            LVInspector(lv: lv, beiLoeschen: beiLoeschen)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
    }

    @ViewBuilder
    private func inhalt(rand: CGFloat) -> some View {
        switch tab {
        case .vorlesungen:
            VorlesungenAnsicht(lv: lv, oeffnen: oeffnen, rand: rand)
        case .pruefung:
            PruefungsvorbereitungAnsicht(lv: lv, oeffnen: oeffnen)
                .padding(.horizontal, rand)
        case .tutor:
            TutorAnsicht(lv: lv, oeffnen: oeffnen)
                .padding(.horizontal, rand)
        case .quiz:
            QuizKartenAnsicht(lv: lv)
                .padding(.horizontal, rand)
        case .analysen:
            FolgtInStufe(titel: "Analysen", symbol: "chart.pie",
                         beschreibung: "Beherrschung je Thema, Prüfungsbereitschaft und Lernzeit folgen in Ausbaustufe g.")
        }
    }
}

/// Kopf: „[43] • Stoffgebiet H · P+S · 8 SWS · Prof. …“, großer Titel, Status-Pillen.
struct LVKopf: View {
    @Bindable var lv: Lehrveranstaltung
    @Query private var alleLVs: [Lehrveranstaltung]
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true

    private var metazeile: String {
        var teile: [String] = []
        if !lv.stoffgebiete.isEmpty {
            teile.append("Stoffgebiet " + lv.stoffgebiete.map(\.code).joined(separator: "+"))
        }
        teile.append(lv.lehrform.kuerzel)
        if !lv.sws.isEmpty { teile.append(lv.swsAnzeige) }
        if !lv.leistungsnachweis.isEmpty { teile.append("LN \(lv.leistungsnachweis)") }
        if !lv.dozenten.isEmpty { teile.append(lv.dozenten.joined(separator: " / ")) }
        return teile.joined(separator: "  ·  ")
    }

    var body: some View {
        let freigabe = lv.freigabe(in: .aus(alleLVs, ph1: ph1))
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LfdNrText(text: LfdNr.anzeige(lv.lfdNr), groesse: 13, farbe: Thema.tinte)
                    Punkt(farbe: lv.farbe)
                    Text(verbatim: metazeile)
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(verbatim: lv.anzeigename)
                    .font(Thema.display(44))
                    .foregroundStyle(Thema.tinte)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if lv.anzeigename != lv.bezeichnung {
                    Text(verbatim: lv.bezeichnung)
                        .font(Thema.ui(13))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .lineLimit(2)
                }
                if lv.status == .bestanden {
                    Text("Bestanden – Unterlagen bleiben als Archiv und Staatsexamen-Material erhalten.")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                } else if case .blockiert(let fehlend) = freigabe {
                    Text("Noch blockiert: \(fehlend.joined(separator: ", "))")
                        .font(Thema.ui(12))
                        .foregroundStyle(Stoffgebiet.i.farbe)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Menu {
                    Picker("Status", selection: $lv.status) {
                        ForEach(LVStatus.allCases) { status in
                            Text(status.name).tag(status)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Pille(text: lv.status.name, betont: lv.status != .offen)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Status ändern")
                if lv.anmeldepflicht {
                    Pille(text: "Anmeldung QIS/LSF *")
                        .help(Studienregeln.anmeldeHinweis)
                }
            }
        }
    }
}
