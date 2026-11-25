import SwiftUI
import SwiftData
import PharmaCore

struct SemesterUebersicht: View {
    @Bindable var semester: Semester
    @Binding var auswahl: Bereich?

    @Query private var alleLVs: [Lehrveranstaltung]
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true
    @State private var zeigeNeueLV = false
    @State private var zeigeBearbeiten = false

    private var stand: StudienStand { .aus(alleLVs, ph1: ph1) }

    var body: some View {
        let lvs = semester.sortierteLehrveranstaltungen
        let stand = self.stand

        ScrollView {
            VStack(alignment: .leading, spacing: Layout.abstand) {
                kopf(lvs: lvs)

                if !semester.sortierteFristen.isEmpty {
                    Karte(titel: Text("Fristen in diesem Semester"), symbol: "calendar.badge.exclamationmark", farbe: .orange) {
                        ForEach(semester.sortierteFristen) { frist in
                            FristZeile(frist: frist)
                        }
                    }
                }

                if lvs.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Lehrveranstaltungen", systemImage: "books.vertical")
                    } description: {
                        Text("Füge Lehrveranstaltungen hinzu, zum Beispiel aus deinem Grundstudium.")
                    } actions: {
                        Button("Lehrveranstaltung hinzufügen") { zeigeNeueLV = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: Layout.abstand, alignment: .top)],
                              spacing: Layout.abstand) {
                        ForEach(lvs) { lv in
                            Button {
                                auswahl = .lehrveranstaltung(lv)
                            } label: {
                                LVKarte(lv: lv, freigabe: lv.freigabe(in: stand))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Layout.abstand)
        }
        .navigationTitle(semester.titel)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    zeigeBearbeiten = true
                } label: {
                    Label("Semester bearbeiten", systemImage: "calendar")
                }
                Button {
                    zeigeNeueLV = true
                } label: {
                    Label("Lehrveranstaltung hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $zeigeNeueLV) {
            NeueLehrveranstaltungAnsicht(semester: semester) { lv in
                auswahl = .lehrveranstaltung(lv)
            }
        }
        .sheet(isPresented: $zeigeBearbeiten) {
            SemesterBearbeitenAnsicht(semester: semester)
        }
    }

    @ViewBuilder
    private func kopf(lvs: [Lehrveranstaltung]) -> some View {
        let bestanden = lvs.filter { $0.status == .bestanden }.count
        VStack(alignment: .leading, spacing: 6) {
            if let beginn = semester.vorlesungsbeginn, let ende = semester.vorlesungsende {
                Text("Vorlesungszeit: \(beginn.kurzesDatum) – \(ende.kurzesDatum)")
                    .foregroundStyle(.secondary)
            }
            if !lvs.isEmpty {
                HStack(spacing: 12) {
                    ProgressView(value: Double(bestanden), total: Double(lvs.count))
                        .frame(maxWidth: 220)
                    Text("\(bestanden) von \(lvs.count) Lehrveranstaltungen bestanden")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Karte einer Lehrveranstaltung in der Semesterübersicht.
struct LVKarte: View {
    let lv: Lehrveranstaltung
    let freigabe: Freigabe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(lv.lfdNrAnzeige)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(lv.farbe)
                Spacer()
                ForEach(lv.stoffgebiete) { gebiet in
                    StoffgebietMarke(stoffgebiet: gebiet)
                }
            }
            Text(lv.bezeichnung)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: [lv.lehrform.kuerzel, lv.swsAnzeige, lv.leistungsnachweis.isEmpty ? nil : "LN \(lv.leistungsnachweis)"]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !lv.dozenten.isEmpty {
                Text(lv.dozenten.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                StatusMarke(status: lv.status)
                Spacer()
                if freigabe != .bestanden {
                    Image(systemName: freigabe.symbol)
                        .foregroundStyle(freigabe.farbe)
                        .help(freigabe.name)
                        .accessibilityLabel(freigabe.name)
                }
            }
            if let tp = lv.naechsteTeilpruefung, let datum = tp.datum {
                HStack(spacing: 6) {
                    Image(systemName: tp.typ.symbol)
                    Text(tp.titel).lineLimit(1)
                    Spacer()
                    CountdownText(datum: datum)
                }
                .font(.caption)
            }
        }
        .padding(Layout.abstand)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Layout.eckenradius))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Layout.eckenradius, bottomLeadingRadius: Layout.eckenradius)
                .fill(lv.farbe)
                .frame(width: 5)
        }
        .contentShape(RoundedRectangle(cornerRadius: Layout.eckenradius))
    }
}
