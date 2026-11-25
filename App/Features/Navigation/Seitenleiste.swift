import SwiftUI
import SwiftData
import PharmaCore

struct Seitenleiste: View {
    @Binding var auswahl: Bereich?
    @Binding var semesterNummer: Int
    let suche: String

    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @Query(sort: \Lehrveranstaltung.lfdNr) private var alleLVs: [Lehrveranstaltung]
    @Environment(\.modelContext) private var kontext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var mehrereFenster

    private var ausgewaehltesSemester: Semester? {
        alleSemester.first { $0.nummer == semesterNummer } ?? alleSemester.first(where: \.istAktuell)
    }

    private var treffer: [Lehrveranstaltung] {
        alleLVs.filter { LfdNr.passt(lfdNr: $0.lfdNr, bezeichnung: $0.bezeichnung, suchbegriff: suche) }
            .sorted { ($0.semester?.sortierung ?? 0, $0.sortierung) < ($1.semester?.sortierung ?? 0, $1.sortierung) }
    }

    private struct Unterlagentreffer: Identifiable {
        let id: String
        let dokument: Dokument
        let seite: Int
        let ort: String
        let ausschnitt: String
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
        List(selection: $auswahl) {
            if !suche.trimmingCharacters(in: .whitespaces).isEmpty {
                let unterlagen = unterlagenTreffer
                if !unterlagen.isEmpty {
                    Section("In Unterlagen") {
                        ForEach(unterlagen) { treffer in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(treffer.dokument.titel, systemImage: treffer.dokument.typ.symbol)
                                    .lineLimit(1)
                                Text(verbatim: "\(treffer.dokument.lehrveranstaltung?.lfdNrAnzeige ?? "") \(treffer.ort)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(treffer.ausschnitt)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                            .tag(Bereich.dokument(treffer.dokument, seite: treffer.seite))
                        }
                    }
                }
                Section("Lehrveranstaltungen") {
                    if treffer.isEmpty {
                        Text("Keine Treffer").foregroundStyle(.secondary)
                    }
                    ForEach(treffer) { lv in
                        LVZeile(lv: lv, zeigeSemester: true)
                            .tag(Bereich.lehrveranstaltung(lv))
                            .contextMenu { kontextMenue(lv) }
                    }
                }
            } else {
                Section {
                    semesterAuswahl
                }

                if let semester = ausgewaehltesSemester {
                    Section(semester.titel) {
                        if semester.typ == .staatsexamen {
                            Label("Staatsexamen-Übersicht", systemImage: "graduationcap")
                                .tag(Bereich.semester(semester))
                        } else {
                            Label("Semesterübersicht", systemImage: "square.grid.2x2")
                                .tag(Bereich.semester(semester))
                            ForEach(semester.sortierteLehrveranstaltungen) { lv in
                                LVZeile(lv: lv)
                                    .tag(Bereich.lehrveranstaltung(lv))
                                    .contextMenu { kontextMenue(lv) }
                            }
                        }
                    }
                }

                Section("Lernen") {
                    Label("Heute lernen", systemImage: "sun.max")
                        .tag(Bereich.heute)
                    Label("Kalender", systemImage: "calendar")
                        .tag(Bereich.kalender)
                    Label("Dashboard & Analysen", systemImage: "chart.bar.xaxis")
                        .tag(Bereich.dashboard)
                    Label("Voraussetzungen", systemImage: "point.3.connected.trianglepath.dotted")
                        .tag(Bereich.voraussetzungen)
                }

                Section {
                    Label("Einstellungen", systemImage: "gearshape")
                        .tag(Bereich.einstellungen)
                }
            }
        }
        .navigationTitle("PharmaTutor")
        .onChange(of: semesterNummer) { _, neueNummer in
            if let semester = alleSemester.first(where: { $0.nummer == neueNummer }) {
                auswahl = .semester(semester)
            }
        }
    }

    private var semesterAuswahl: some View {
        Picker(selection: $semesterNummer) {
            Section("Hauptstudium") {
                ForEach(alleSemester.filter { $0.typ == .regulaer }) { s in
                    Text(verbatim: s.istAktuell ? s.titel + " (aktuell)" : s.titel).tag(s.nummer)
                }
            }
            Section {
                ForEach(alleSemester.filter { $0.typ == .staatsexamen }) { s in
                    Text(s.titel).tag(s.nummer)
                }
            }
            Section("Grundstudium-Archiv") {
                ForEach(alleSemester.filter { $0.typ == .archiv }) { s in
                    Text(s.titel).tag(s.nummer)
                }
            }
        } label: {
            Label("Semester", systemImage: "books.vertical")
        }
        .pickerStyle(.menu)
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
                Label(status.name, systemImage: status.symbol).tag(status)
            }
        } label: {
            Label("Status", systemImage: "flag")
        }
    }
}

/// Zeile einer Lehrveranstaltung in Listen.
struct LVZeile: View {
    let lv: Lehrveranstaltung
    var zeigeSemester = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(lv.farbe)
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(lv.lfdNrAnzeige)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(lv.farbe)
                Text(lv.bezeichnung)
                    .lineLimit(2)
                if zeigeSemester, let semester = lv.semester {
                    Text(semester.titel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if lv.status != .offen {
                Image(systemName: lv.status.symbol)
                    .foregroundStyle(lv.status.farbe)
                    .help(lv.status.name)
                    .accessibilityLabel(lv.status.name)
            }
        }
    }
}
