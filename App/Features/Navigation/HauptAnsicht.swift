import SwiftUI
import SwiftData

struct HauptAnsicht: View {
    @Environment(\.modelContext) private var kontext
    @Environment(\.scenePhase) private var szenenPhase
    @AppStorage(EinstellungsSchluessel.onboardingAbgeschlossen) private var onboardingAbgeschlossen = false
    @AppStorage(EinstellungsSchluessel.ausgewaehltesSemester) private var semesterNummer = 5
    @State private var auswahl: Bereich? = .heute
    @State private var suche = ""
    @State private var bereit = false

    @State private var spalten: NavigationSplitViewVisibility = .all
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
        }
        .searchable(text: $suche, placement: .sidebar, prompt: Text("Suchen, z. B. [43]"))
        .focusedSceneValue(\.navigationsAuswahl, $auswahl)
        .task {
            Seeder.ladeFallsNoetig(kontext)
            LernplanDienst.taeglichAktualisierenFallsNoetig(kontext)
            bereit = true
            await ErinnerungsDienst.planen(kontext)
        }
        .onChange(of: szenenPhase) { _, phase in
            if phase != .active {
                Task { await ErinnerungsDienst.planen(kontext) }
            } else {
                LernplanDienst.taeglichAktualisierenFallsNoetig(kontext)
            }
        }
        .sheet(isPresented: Binding(
            get: { bereit && !onboardingAbgeschlossen },
            set: { if !$0 { onboardingAbgeschlossen = true } }
        )) {
            OnboardingAnsicht()
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
