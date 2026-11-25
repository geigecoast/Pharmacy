import SwiftUI
import SwiftData
import PharmaCore

/// Welche Veranstaltung schaltet welche frei, was ist blockiert und warum.
struct VoraussetzungenAnsicht: View {
    @Binding var auswahl: Bereich?
    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @Query private var alleLVs: [Lehrveranstaltung]
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true

    var body: some View {
        let stand = StudienStand.aus(alleLVs, ph1: ph1)
        let schaltetFrei = freischaltungen()
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                Seitentitel(titel: "Voraussetzungen", unterzeile: Studienregeln.anmeldeHinweis)
                Toggle("Zulassung Ph1 (1. Abschnitt bestanden)", isOn: $ph1)
                    .font(Thema.ui(14))
                    .frame(maxWidth: 420, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel(titel: "Graph") { Text("Klick öffnet die Lehrveranstaltung") }
                    VoraussetzungsGraph(semester: alleSemester.filter { $0.typ == .regulaer && (5...8).contains($0.nummer) },
                                        stand: stand) { lv in
                        auswahl = .lehrveranstaltung(lv)
                    }
                    .padding(.top, 20)
                }

                ForEach(alleSemester.filter { $0.typ == .regulaer && !($0.lehrveranstaltungen ?? []).isEmpty }) { semester in
                    VStack(alignment: .leading, spacing: 0) {
                        Abschnittstitel(titel: LocalizedStringKey(semester.titel)) { EmptyView() }
                        ForEach(semester.sortierteLehrveranstaltungen.filter(istRelevant)) { lv in
                            Button {
                                auswahl = .lehrveranstaltung(lv)
                            } label: {
                                VoraussetzungsZeile(lv: lv, freigabe: lv.freigabe(in: stand),
                                                    schaltetFrei: lv.lfdNrTeile.flatMap { schaltetFrei[$0] ?? [] })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .seitenrand()
        }
        .background(Thema.flaeche)
        .navigationTitle("Voraussetzungen")
    }

    private func istRelevant(_ lv: Lehrveranstaltung) -> Bool {
        lv.voraussetzungen != .keine || lv.anmeldepflicht
    }

    /// Lfd.-Nr.-Teil → Veranstaltungen, die ihn voraussetzen.
    private func freischaltungen() -> [String: [String]] {
        var ergebnis: [String: [String]] = [:]
        for lv in alleLVs {
            for referenz in lv.voraussetzungen.referenzierteKurse {
                ergebnis[referenz, default: []].append(LfdNr.anzeige(lv.lfdNr))
            }
        }
        return ergebnis.mapValues { Array(Set($0)).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    }
}

struct VoraussetzungsZeile: View {
    let lv: Lehrveranstaltung
    let freigabe: Freigabe
    let schaltetFrei: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: freigabe.symbol)
                .font(.system(size: 11))
                .foregroundStyle(freigabe.farbe)
                .frame(width: 16)
                .accessibilityLabel(freigabe.name)
            LfdNrText(text: lv.lfdNrAnzeige, groesse: 12)
                .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: lv.anzeigename)
                    .font(Thema.ui(15))
                    .foregroundStyle(Thema.tinte)
                if lv.voraussetzungen != .keine {
                    Text("Voraussetzung: \(lv.voraussetzungen.beschreibung)")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                }
                switch freigabe {
                case .blockiert(let fehlend):
                    ForEach(fehlend, id: \.self) { eintrag in
                        Text("Fehlt: \(eintrag)")
                            .font(Thema.ui(12))
                            .foregroundStyle(Stoffgebiet.i.farbe)
                    }
                case .freigeschaltet(let hinweise):
                    ForEach(hinweise, id: \.self) { hinweis in
                        Text(verbatim: hinweis)
                            .font(Thema.ui(12))
                            .foregroundStyle(Thema.tinteSekundaer)
                    }
                case .bestanden:
                    EmptyView()
                }
                if !schaltetFrei.isEmpty {
                    Text("Schaltet frei: \(schaltetFrei.joined(separator: ", "))")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
            }
            Spacer(minLength: 12)
            Text(verbatim: freigabe.name)
                .font(Thema.ui(12))
                .foregroundStyle(freigabe.farbe)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}
