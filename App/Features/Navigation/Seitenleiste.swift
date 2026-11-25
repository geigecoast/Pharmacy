import SwiftUI
import SwiftData
import PharmaCore

/// Seitenleiste nach Design: Wortmarke, Navigation, Semester-Segmente, Kursliste, Einstellungen.
struct Seitenleiste: View {
    @Binding var auswahl: Bereich?
    @Binding var semesterNummer: Int
    let suche: String
    var navigiert: () -> Void = {}

    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @Query(sort: \Lehrveranstaltung.lfdNr) private var alleLVs: [Lehrveranstaltung]
    @Query private var alleLerneinheiten: [Lerneinheit]
    @Query(sort: \Lernpfad.titel) private var lernpfade: [Lernpfad]
    @Environment(\.modelContext) private var kontext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var mehrereFenster

    /// Segmente: 5.–8., Staatsexamen, Grundstudium-Archiv (0 = Archiv 1.–4.).
    private static let archivSegment = 0
    private var segmente: [Int] { [5, 6, 7, 8, Curriculum.nummerStaatsexamen, Self.archivSegment] }

    private func segmentTitel(_ nummer: Int) -> String {
        switch nummer {
        case Curriculum.nummerStaatsexamen: return "StEx"
        case Self.archivSegment: return "1–4"
        default: return "\(nummer)."
        }
    }

    private var segmentAuswahl: Binding<Int> {
        Binding(
            get: { (1...4).contains(semesterNummer) ? Self.archivSegment : semesterNummer },
            set: { neu in
                semesterNummer = neu == Self.archivSegment ? 1 : neu
                if let semester = alleSemester.first(where: { $0.nummer == semesterNummer }), neu != Self.archivSegment {
                    gehe(zu: .semester(semester))
                }
            }
        )
    }

    private var ausgewaehltesSemester: Semester? {
        alleSemester.first { $0.nummer == semesterNummer } ?? alleSemester.first(where: \.istAktuell)
    }

    private var offeneEinheitenHeute: Int {
        alleLerneinheiten.filter { !$0.erledigt && Calendar.current.isDateInToday($0.tag) }.count
    }

    private func gehe(zu bereich: Bereich) {
        auswahl = bereich
        navigiert()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PharmaTutor")
                        .font(Thema.display(24))
                        .foregroundStyle(Thema.tinte)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 22)

                    if suche.trimmingCharacters(in: .whitespaces).isEmpty {
                        navigation
                    } else {
                        Suchergebnisse(suche: suche, auswahl: auswahl, gehe: gehe)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            navZeile("Einstellungen", .einstellungen)
                .padding(12)
        }
        .background(Thema.seitenleiste)
        .onChange(of: semesterNummer) { _, neueNummer in
            if let semester = alleSemester.first(where: { $0.nummer == neueNummer }) {
                gehe(zu: .semester(semester))
            }
        }
    }

    @ViewBuilder
    private var navigation: some View {
        navZeile("Heute lernen", .heute, zaehler: offeneEinheitenHeute)
        navZeile("Kalender", .kalender)
        navZeile("Dashboard & Analysen", .dashboard)

        Segmentleiste(werte: segmente, auswahl: segmentAuswahl, titel: segmentTitel)
            .padding(.top, 22)
            .padding(.bottom, 20)

        if segmentAuswahl.wrappedValue == Self.archivSegment {
            ForEach(alleSemester.filter { $0.typ == .archiv }) { semester in
                semesterKopf(semester, zusatz: nil)
                kursliste(semester.sortierteLehrveranstaltungen, leer: "Noch leer")
                    .padding(.bottom, 10)
            }
        } else if let semester = ausgewaehltesSemester {
            if semester.typ == .staatsexamen {
                semesterKopf(semester, zusatz: nil)
                einfacheZeile("Übersicht", aktiv: auswahl == .semester(semester)) { gehe(zu: .semester(semester)) }
                einfacheZeile("Voraussetzungen", aktiv: auswahl == .voraussetzungen) { gehe(zu: .voraussetzungen) }
                ForEach(lernpfade) { pfad in
                    einfacheZeile("Lernpfad \(pfad.titel)", aktiv: false) {
                        if let teil = pfad.sortierteTeile.first(where: { $0.status != .bestanden }) ?? pfad.sortierteTeile.first {
                            gehe(zu: .lehrveranstaltung(teil))
                        }
                    }
                }
            } else {
                semesterKopf(semester, zusatz: semester.istAktuell ? "(aktuell)" : nil)
                kursliste(semester.sortierteLehrveranstaltungen, leer: "Keine Lehrveranstaltungen")
            }
        }
    }

    private func semesterKopf(_ semester: Semester, zusatz: String?) -> some View {
        Button {
            gehe(zu: .semester(semester))
        } label: {
            Text(verbatim: [semester.titel, zusatz].compactMap { $0 }.joined(separator: " "))
                .textCase(.uppercase)
                .font(Thema.ui(11))
                .tracking(0.8)
                .foregroundStyle(auswahl == .semester(semester) ? Thema.tinte : Thema.tinteTertiaer)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Semesterübersicht öffnen")
    }

    @ViewBuilder
    private func kursliste(_ lvs: [Lehrveranstaltung], leer: LocalizedStringKey) -> some View {
        if lvs.isEmpty {
            Text(leer)
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteTertiaer)
                .padding(.horizontal, 10)
        }
        ForEach(lvs) { lv in
            KursZeile(lv: lv, aktiv: auswahl == .lehrveranstaltung(lv)) {
                gehe(zu: .lehrveranstaltung(lv))
            }
            .contextMenu { kontextMenue(lv) }
        }
    }

    private func navZeile(_ titel: LocalizedStringKey, _ bereich: Bereich, zaehler: Int = 0) -> some View {
        Button {
            gehe(zu: bereich)
        } label: {
            HStack {
                Text(titel)
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinte)
                Spacer()
                if zaehler > 0 {
                    Text(verbatim: "\(zaehler)")
                        .font(Thema.mono(11))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(auswahl == bereich ? Thema.auswahl : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func einfacheZeile(_ titel: String, aktiv: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(verbatim: titel)
                .font(Thema.ui(13))
                .foregroundStyle(Thema.tinte)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(aktiv ? Thema.auswahl : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func kontextMenue(_ lv: Lehrveranstaltung) -> some View {
        if mehrereFenster {
            Button {
                openWindow(id: LVFenster.fensterID, value: lv.persistentModelID)
            } label: {
                Label("In neuem Fenster öffnen", systemImage: "macwindow.badge.plus")
            }
        }
        Picker(selection: Binding(get: { lv.status }, set: { lv.status = $0 })) {
            ForEach(LVStatus.allCases) { status in
                Text(status.name).tag(status)
            }
        } label: {
            Label("Status", systemImage: "flag")
        }
    }
}

/// Kurszeile: Farbpunkt · [Lfd. Nr.] · Kurzname.
struct KursZeile: View {
    let lv: Lehrveranstaltung
    var aktiv = false
    var aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 10) {
                Punkt(farbe: lv.farbe)
                LfdNrText(text: LfdNr.anzeige(lv.lfdNr), groesse: 11)
                    .frame(width: 54, alignment: .leading)
                Text(lv.anzeigename)
                    .font(Thema.ui(13))
                    .foregroundStyle(lv.status == .bestanden ? Thema.tinteTertiaer : Thema.tinte)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(aktiv ? Thema.auswahl : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(lv.bezeichnung)
    }
}

/// Suchergebnisse: Lehrveranstaltungen (auch per „[43]“) und Volltext in Unterlagen.
private struct Suchergebnisse: View {
    let suche: String
    let auswahl: Bereich?
    var gehe: (Bereich) -> Void

    @Query(sort: \Lehrveranstaltung.lfdNr) private var alleLVs: [Lehrveranstaltung]
    @Environment(\.modelContext) private var kontext

    private struct Unterlagentreffer: Identifiable {
        let id: String
        let dokument: Dokument
        let seite: Int
        let ort: String
        let ausschnitt: String
    }

    private var lvTreffer: [Lehrveranstaltung] {
        alleLVs.filter {
            LfdNr.passt(lfdNr: $0.lfdNr, bezeichnung: $0.bezeichnung, suchbegriff: suche)
                || $0.kurzname.localizedStandardContains(suche.trimmingCharacters(in: .whitespaces))
        }
        .sorted { ($0.semester?.sortierung ?? 0, $0.sortierung) < ($1.semester?.sortierung ?? 0, $1.sortierung) }
    }

    /// Volltextsuche in Seiten (inkl. Texterkennung), Handschrift, Markierungen und Transkripten.
    private var unterlagenTreffer: [Unterlagentreffer] {
        let begriff = suche.trimmingCharacters(in: .whitespaces)
        guard begriff.count >= 3 else { return [] }
        var ergebnis: [Unterlagentreffer] = []
        var gesehen = Set<String>()

        func hinzufuegen(_ dokument: Dokument?, seite: Int, ort: String, text: String) {
            guard let dokument else { return }
            let schluessel = "\(dokument.kennung)-\(seite)"
            guard !gesehen.contains(schluessel) else { return }
            gesehen.insert(schluessel)
            ergebnis.append(Unterlagentreffer(id: schluessel, dokument: dokument, seite: seite, ort: ort,
                                              ausschnitt: Textausschnitt.um(begriff, in: text, umfeld: 40)))
        }

        var seitenAbfrage = FetchDescriptor<Seite>(predicate: #Predicate { $0.text.localizedStandardContains(begriff) })
        seitenAbfrage.fetchLimit = 40
        for seite in (try? kontext.fetch(seitenAbfrage)) ?? [] {
            let art = seite.dokument?.typ == .praesentation ? "Folie" : "Seite"
            hinzufuegen(seite.dokument, seite: seite.nummer, ort: "\(art) \(seite.nummer + 1)", text: seite.text)
        }
        let zeichnungen = FetchDescriptor<Zeichnung>(predicate: #Predicate { $0.text.localizedStandardContains(begriff) })
        for zeichnung in (try? kontext.fetch(zeichnungen)) ?? [] {
            hinzufuegen(zeichnung.dokument, seite: zeichnung.seitenIndex, ort: "Handschrift, Seite \(zeichnung.seitenIndex + 1)", text: zeichnung.text)
        }
        let markierungen = FetchDescriptor<Markierung>(predicate: #Predicate { $0.text.localizedStandardContains(begriff) })
        for markierung in (try? kontext.fetch(markierungen)) ?? [] {
            hinzufuegen(markierung.dokument, seite: markierung.seitenIndex, ort: "Markierung, Seite \(markierung.seitenIndex + 1)", text: markierung.text)
        }
        let aufnahmen = FetchDescriptor<Dokument>(predicate: #Predicate {
            $0.transkriptText.localizedStandardContains(begriff) || $0.titel.localizedStandardContains(begriff)
        })
        for dokument in (try? kontext.fetch(aufnahmen)) ?? [] {
            let text = dokument.transkriptText.isEmpty ? dokument.titel : dokument.transkriptText
            hinzufuegen(dokument, seite: 0, ort: dokument.typ == .audio ? "Transkript" : "Titel", text: text)
        }
        return ergebnis
    }

    var body: some View {
        let lvs = lvTreffer
        let unterlagen = unterlagenTreffer
        Kleintitel(text: "Lehrveranstaltungen")
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        if lvs.isEmpty {
            Text("Keine Treffer")
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteTertiaer)
                .padding(.horizontal, 10)
        }
        ForEach(lvs) { lv in
            KursZeile(lv: lv, aktiv: auswahl == .lehrveranstaltung(lv)) { gehe(.lehrveranstaltung(lv)) }
        }
        if !unterlagen.isEmpty {
            Kleintitel(text: "In Unterlagen")
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 6)
            ForEach(unterlagen) { treffer in
                Button {
                    gehe(.dokument(treffer.dokument, seite: treffer.seite))
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(treffer.dokument.titel)
                            .font(Thema.ui(13))
                            .foregroundStyle(Thema.tinte)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            LfdNrText(text: treffer.dokument.lehrveranstaltung.map { LfdNr.anzeige($0.lfdNr) } ?? "", groesse: 10)
                            Text(verbatim: treffer.ort)
                                .font(Thema.ui(11))
                                .foregroundStyle(Thema.tinteTertiaer)
                        }
                        Text(treffer.ausschnitt)
                            .font(Thema.ui(12))
                            .foregroundStyle(Thema.tinteSekundaer)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
