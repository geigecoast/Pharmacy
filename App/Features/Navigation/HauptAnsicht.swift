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

    var body: some View {
        NavigationSplitView {
            Seitenleiste(auswahl: $auswahl, semesterNummer: $semesterNummer, suche: suche)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 380)
        } detail: {
            DetailAnsicht(auswahl: $auswahl)
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
            FolgtInStufe(titel: "Dashboard & Analysen", symbol: "chart.bar.xaxis",
                         beschreibung: "Fortschritt je Semester und Stoffgebiet, Lernzeit und die Prognose „Bist du rechtzeitig fertig?“ folgen in Ausbaustufe g.")
                .navigationTitle("Dashboard & Analysen")
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
            LehrveranstaltungAnsicht(lv: lv) {
                auswahl = lv.semester.map { .semester($0) } ?? .heute
            }
            .id(lv.persistentModelID)
        }
    }
}

/// Eigenes Fenster für eine Lehrveranstaltung (Mac und iPad mit Stage Manager).
struct LVFenster: View {
    static let fensterID = "lehrveranstaltung"

    let id: PersistentIdentifier?
    @Environment(\.modelContext) private var kontext
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if let id, let lv = kontext.model(for: id) as? Lehrveranstaltung, !lv.isDeleted {
            NavigationStack {
                LehrveranstaltungAnsicht(lv: lv) {
                    dismissWindow(id: Self.fensterID, value: id)
                }
            }
        } else {
            ContentUnavailableView("Lehrveranstaltung nicht gefunden", systemImage: "questionmark.folder",
                                   description: Text("Sie wurde vielleicht gelöscht."))
        }
    }
}
