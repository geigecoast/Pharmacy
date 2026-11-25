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

    @SceneStorage("lvTab") private var tab: LVTab = .vorlesungen
    @AppStorage("lvInspectorSichtbar") private var zeigeInspector = true

    var body: some View {
        VStack(spacing: 0) {
            LVKopf(lv: lv)
                .padding(.horizontal, Layout.abstand)
                .padding(.top, 8)
                .padding(.bottom, 10)
            tabAuswahl
                .padding(.horizontal, Layout.abstand)
                .padding(.bottom, 10)
            Divider()
            inhalt
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(lv.lfdNrAnzeige)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    zeigeInspector.toggle()
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
                .help("Details ein- oder ausblenden")
            }
        }
        .inspector(isPresented: $zeigeInspector) {
            LVInspector(lv: lv, beiLoeschen: beiLoeschen)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
    }

    private var tabAuswahl: some View {
        ViewThatFits(in: .horizontal) {
            Picker("Bereich", selection: $tab) {
                ForEach(LVTab.allCases) { t in
                    Text(t.titel).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Picker("Bereich", selection: $tab) {
                ForEach(LVTab.allCases) { t in
                    Label(t.titel, systemImage: t.symbol).tag(t)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inhalt: some View {
        switch tab {
        case .vorlesungen:
            FolgtInStufe(titel: "Vorlesungen", symbol: "doc.richtext",
                         beschreibung: "Import von PDFs, Folien, Scans und Audio, Markierungen mit Maus, Trackpad und Apple Pencil sowie KI-Zusammenfassungen folgen in Ausbaustufe c.")
        case .pruefung:
            PruefungsvorbereitungAnsicht(lv: lv)
        case .tutor:
            FolgtInStufe(titel: "Tutor", symbol: "bubble.left.and.text.bubble.right",
                         beschreibung: "Der KI-Nachhilfelehrer mit „Nur meine Unterlagen“, Erklärmodi und Wirkstoff-Steckbriefen folgt in Ausbaustufe e.")
        case .quiz:
            FolgtInStufe(titel: "Quiz & Karteikarten", symbol: "rectangle.on.rectangle.angled",
                         beschreibung: "Karteikarten mit FSRS-Wiederholung, Quizmodi und Fehlerjournal folgen in Ausbaustufe d.")
        case .analysen:
            FolgtInStufe(titel: "Analysen", symbol: "chart.pie",
                         beschreibung: "Beherrschung je Thema, Prüfungsbereitschaft und Lernzeit folgen in Ausbaustufe g.")
        }
    }
}

/// Kopfbereich mit den wichtigsten Angaben.
struct LVKopf: View {
    let lv: Lehrveranstaltung
    @Query private var alleLVs: [Lehrveranstaltung]
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true

    var body: some View {
        let freigabe = lv.freigabe(in: .aus(alleLVs, ph1: ph1))
        VStack(alignment: .leading, spacing: 8) {
            Text(lv.bezeichnung)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(lv.stoffgebiete) { gebiet in
                    StoffgebietMarke(stoffgebiet: gebiet)
                }
                Text(verbatim: [lv.lehrform.name, lv.swsAnzeige, lv.leistungsnachweis.isEmpty ? nil : "LN \(lv.leistungsnachweis)"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusMarke(status: lv.status)
                if freigabe != .bestanden {
                    Label(freigabe.name, systemImage: freigabe.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(freigabe.farbe)
                }
            }
            if lv.status == .bestanden {
                Label("Bestanden – die Unterlagen bleiben als Archiv und Staatsexamen-Material erhalten. Es gibt keine Prüfungserinnerungen mehr.",
                      systemImage: "archivebox")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else if lv.anmeldepflicht {
                Label("Anmeldepflichtig im QIS/LSF (*)", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }
}
