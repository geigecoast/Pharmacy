import SwiftUI
import SwiftData
import Combine
import PharmaCore

struct HauptAnsicht: View {
    @Environment(\.modelContext) private var kontext
    @Environment(\.scenePhase) private var szenenPhase
    @AppStorage(EinstellungsSchluessel.onboardingAbgeschlossen) private var onboardingAbgeschlossen = false
    @AppStorage(EinstellungsSchluessel.ausgewaehltesSemester) private var semesterNummer = 5
    @State private var auswahl: Bereich? = .heute
    @State private var suche = ""
    @State private var bereit = false

    @State private var fokus = FokusTimer()
    @State private var neueAbzeichen: [Gamification.Abzeichen] = []
    @State private var abzeichenPruefung: Task<Void, Never>?
    @State private var spalten: NavigationSplitViewVisibility = .all

    /// Lehrveranstaltung der aktuellen Auswahl (für den Fokus-Timer).
    private var aktuelleLV: Lehrveranstaltung? {
        switch auswahl {
        case .lehrveranstaltung(let lv): lv
        case .dokument(let dokument, _): dokument.lehrveranstaltung
        default: nil
        }
    }
    @State private var kompaktSpalte: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(columnVisibility: $spalten, preferredCompactColumn: $kompaktSpalte) {
            Seitenleiste(auswahl: $auswahl, semesterNummer: $semesterNummer, suche: suche) {
                kompaktSpalte = .detail
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 256, max: 320)
        } detail: {
            DetailAnsicht(auswahl: $auswahl)
                .background(Thema.flaeche)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        FokusKnopf(lv: aktuelleLV)
                    }
                }
        }
        .environment(fokus)
        .searchable(text: $suche, placement: .sidebar, prompt: Text("Suchen, z. B. [43]"))
        .focusedSceneValue(\.navigationsAuswahl, $auswahl)
        .task {
            Seeder.ladeFallsNoetig(kontext)
            LernplanDienst.taeglichAktualisierenFallsNoetig(kontext)
            bereit = true
            abzeichenPruefen()
            await ErinnerungsDienst.planen(kontext)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            abzeichenPruefen()
        }
        .overlay(alignment: .bottom) {
            if let erstes = neueAbzeichen.first {
                AbzeichenMeldung(abzeichen: erstes, weitere: neueAbzeichen.count - 1, oeffnen: {
                    auswahl = .erfolge
                    kompaktSpalte = .detail
                    neueAbzeichen = []
                }, schliessen: {
                    withAnimation(.easeOut(duration: 0.25)) { neueAbzeichen = [] }
                })
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: szenenPhase) { _, phase in
            if phase != .active {
                Task { await ErinnerungsDienst.planen(kontext) }
            } else {
                LernplanDienst.taeglichAktualisierenFallsNoetig(kontext)
                abzeichenPruefen()
            }
        }
        .sheet(isPresented: Binding(
            get: { bereit && !onboardingAbgeschlossen },
            set: { if !$0 { onboardingAbgeschlossen = true } }
        )) {
            OnboardingAnsicht()
        }
    }

    /// Prüft (verzögert, gebündelt) auf neu erreichte Abzeichen und zeigt sie an.
    private func abzeichenPruefen() {
        abzeichenPruefung?.cancel()
        abzeichenPruefung = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, bereit else { return }
            let neu = GamificationDienst.pruefen(kontext)
            guard !neu.isEmpty else { return }
            withAnimation(.spring(duration: 0.4)) { neueAbzeichen = neu }
        }
    }
}

struct DetailAnsicht: View {
    @Binding var auswahl: Bereich?

    var body: some View {
        switch auswahl {
        case .heute, .none:
            HeuteAnsicht(auswahl: $auswahl)
        case .kalender:
            KalenderAnsicht(auswahl: $auswahl)
        case .dashboard:
            DashboardAnsicht(auswahl: $auswahl)
        case .voraussetzungen:
            VoraussetzungenAnsicht(auswahl: $auswahl)
        case .erfolge:
            ErfolgeAnsicht(auswahl: $auswahl)
        case .einstellungen:
            EinstellungenAnsicht()
        case .semester(let semester):
            if semester.typ == .staatsexamen {
                StaatsexamenAnsicht(auswahl: $auswahl)
            } else {
                SemesterUebersicht(semester: semester, auswahl: $auswahl)
                    .id(semester.persistentModelID)
            }
        case .lehrveranstaltung(let lv):
            LehrveranstaltungAnsicht(lv: lv, beiLoeschen: {
                auswahl = lv.semester.map { .semester($0) } ?? .heute
            }, oeffnen: { dokument, seite in
                auswahl = .dokument(dokument, seite: seite)
            })
            .id(lv.persistentModelID)
        case .dokument(let dokument, let seite):
            DokumentAnsicht(dokument: dokument, startSeite: seite, zurueck: {
                auswahl = dokument.lehrveranstaltung.map { .lehrveranstaltung($0) } ?? .heute
            }, oeffnen: { anderes, andereSeite in
                auswahl = .dokument(anderes, seite: andereSeite)
            })
            .id("\(dokument.persistentModelID.hashValue)-\(seite)")
        }
    }
}

/// Eigenes Fenster für eine Lehrveranstaltung (Mac und iPad mit Stage Manager).
struct LVFenster: View {
    static let fensterID = "lehrveranstaltung"

    let id: PersistentIdentifier?
    @Environment(\.modelContext) private var kontext
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var offen: OffenesDokument?

    private struct OffenesDokument: Hashable {
        let dokument: Dokument
        let seite: Int
    }

    var body: some View {
        if let id, let lv = kontext.model(for: id) as? Lehrveranstaltung, !lv.isDeleted {
            NavigationStack {
                if let offen {
                    DokumentAnsicht(dokument: offen.dokument, startSeite: offen.seite, zurueck: {
                        self.offen = nil
                    }, oeffnen: { dokument, seite in
                        self.offen = OffenesDokument(dokument: dokument, seite: seite)
                    })
                    .id(offen)
                } else {
                    LehrveranstaltungAnsicht(lv: lv, beiLoeschen: {
                        dismissWindow(id: Self.fensterID, value: id)
                    }, oeffnen: { dokument, seite in
                        offen = OffenesDokument(dokument: dokument, seite: seite)
                    })
                }
            }
        } else {
            ContentUnavailableView("Lehrveranstaltung nicht gefunden", systemImage: "questionmark.folder",
                                   description: Text("Sie wurde vielleicht gelöscht."))
        }
    }
}

/// Schwarze Meldung „Neues Abzeichen“ am unteren Rand; verschwindet nach einigen Sekunden.
struct AbzeichenMeldung: View {
    let abzeichen: Gamification.Abzeichen
    let weitere: Int
    var oeffnen: () -> Void
    var schliessen: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: abzeichen.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Thema.tinte)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Thema.tinteInvers))
            VStack(alignment: .leading, spacing: 3) {
                Text("Neues Abzeichen")
                    .textCase(.uppercase)
                    .font(Thema.ui(10))
                    .tracking(0.8)
                    .opacity(0.7)
                Text(verbatim: abzeichen.titel)
                    .font(Thema.display(22))
                Text(verbatim: abzeichen.beschreibung + (weitere > 0 ? " · und \(weitere) \(weitere == 1 ? "weiteres" : "weitere")" : ""))
                    .font(Thema.ui(12))
                    .opacity(0.75)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(action: schliessen) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Schließen")
        }
        .foregroundStyle(Thema.tinteInvers)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 460)
        .background(Thema.tinte, in: RoundedRectangle(cornerRadius: Thema.radius))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: Thema.radius))
        .onTapGesture(perform: oeffnen)
        .padding(.horizontal, 16)
        .task {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            schliessen()
        }
    }
}
