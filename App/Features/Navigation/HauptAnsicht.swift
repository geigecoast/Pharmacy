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
    @Environment(Datenspeicher.self) private var speicher
    @State private var abgleichFrage: Abgleich.Entscheidung?
    @State private var abgleichFehler: String?
    private var abgleich: AbgleichDienst { AbgleichDienst.shared }
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
            abgleich.ruhig(5)
            Seeder.ladeFallsNoetig(kontext)
            LernplanDienst.taeglichAktualisierenFallsNoetig(kontext)
            bereit = true
            abgleichPruefen()
            abzeichenPruefen()
            await ErinnerungsDienst.planen(kontext)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            abgleich.lokaleAenderung()
            abzeichenPruefen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .abgleichPruefen)) { _ in
            abgleichPruefen()
        }
        .alert(abgleichTitel, isPresented: abgleichZeigen, presenting: abgleichFrage) { entscheidung in
            switch entscheidung {
            case .uebernehmen(let stand):
                Button("Übernehmen") { abgleichUebernehmen(stand) }
                Button("Später", role: .cancel) { abgleichSpaeter(stand) }
            case .konflikt(let stand):
                Button("Stand von „\(stand.geraetName)“ übernehmen", role: .destructive) { abgleichUebernehmen(stand) }
                Button("Diesen Stand behalten") { abgleichBehalten(stand) }
                Button("Später", role: .cancel) { abgleichSpaeter(stand) }
            case .neuereVersion(let stand):
                Button("OK", role: .cancel) { abgleichSpaeter(stand) }
            case .nichts:
                Button("OK", role: .cancel) {}
            }
        } message: { entscheidung in
            Text(verbatim: Self.abgleichNachricht(entscheidung))
        }
        .alert("Abgleich nicht möglich", isPresented: Binding(
            get: { abgleichFehler != nil },
            set: { if !$0 { abgleichFehler = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: abgleichFehler ?? "")
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
                abgleich.ablegenFallsNoetig(kontext: kontext, speicher: speicher.speicherURL)
                Task { await ErinnerungsDienst.planen(kontext) }
            } else {
                abgleich.ruhig(3)
                LernplanDienst.taeglichAktualisierenFallsNoetig(kontext)
                abgleichPruefen()
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

    // MARK: Abgleich

    private var abgleichZeigen: Binding<Bool> {
        Binding(get: { abgleichFrage != nil }, set: { if !$0 { abgleichFrage = nil; abgleich.frageOffen = false } })
    }

    private var abgleichTitel: String {
        guard let frage = abgleichFrage else { return "" }
        switch frage {
        case .uebernehmen(let stand): return "Neuerer Stand von „\(stand.geraetName)“"
        case .konflikt: return "Auf beiden Geräten wurde gelernt"
        case .neuereVersion: return "Neuere App-Version auf dem anderen Gerät"
        case .nichts: return ""
        }
    }

    private static func abgleichNachricht(_ entscheidung: Abgleich.Entscheidung) -> String {
        func zeit(_ stand: Abgleich.Stand) -> String {
            stand.erstelltAm.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(.deutsch))
        }
        switch entscheidung {
        case .uebernehmen(let stand):
            return "Abgelegt \(zeit(stand)). Übernehmen ersetzt die Daten auf diesem Gerät durch diesen Stand."
        case .konflikt(let stand):
            return "Der Stand von „\(stand.geraetName)“ (\(zeit(stand))) und dieser Stand haben sich beide verändert. Änderungen werden nicht zusammengeführt – wähle, welcher Stand gilt. Der andere wird ersetzt."
        case .neuereVersion(let stand):
            return "„\(stand.geraetName)“ nutzt PharmaTutor \(stand.appVersion). Aktualisiere die App auf diesem Gerät, um den Stand zu übernehmen."
        case .nichts:
            return ""
        }
    }

    private func abgleichPruefen() {
        guard bereit, abgleich.istEingerichtet, !abgleich.frageOffen else { return }
        let entscheidung = abgleich.pruefen()
        guard entscheidung != .nichts else { return }
        abgleich.frageOffen = true
        abgleichFrage = entscheidung
    }

    private func abgleichUebernehmen(_ stand: Abgleich.Stand) {
        abgleich.frageOffen = false
        do {
            try abgleich.uebernehmen(stand, speicher: speicher)
        } catch {
            abgleichFehler = error.localizedDescription
        }
    }

    private func abgleichBehalten(_ stand: Abgleich.Stand) {
        abgleich.frageOffen = false
        do {
            try abgleich.behalten(stand, kontext: kontext, speicher: speicher.speicherURL)
        } catch {
            abgleichFehler = error.localizedDescription
        }
    }

    private func abgleichSpaeter(_ stand: Abgleich.Stand) {
        abgleich.frageOffen = false
        abgleich.spaeter(stand)
    }

    /// Prüft (verzögert, gebündelt) auf neu erreichte Abzeichen und zeigt sie an.
    private func abzeichenPruefen() {
        abzeichenPruefung?.cancel()
        abzeichenPruefung = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, bereit else { return }
            abgleich.ruhig()
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
