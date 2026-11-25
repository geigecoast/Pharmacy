import SwiftUI
import SwiftData
import PharmaCore

/// Übersicht: welche Veranstaltung schaltet welche frei, was ist blockiert und warum.
struct VoraussetzungenAnsicht: View {
    @Binding var auswahl: Bereich?
    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @Query private var alleLVs: [Lehrveranstaltung]
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true

    var body: some View {
        let stand = StudienStand.aus(alleLVs, ph1: ph1)
        let schaltetFrei = freischaltungen()

        List {
            Section {
                Toggle("Zulassung Ph1 (1. Abschnitt bestanden)", isOn: $ph1)
                Label(Studienregeln.anmeldeHinweis, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } header: {
                Text("Studienregeln")
            } footer: {
                Text("Der grafische Voraussetzungs-Graph folgt in Ausbaustufe g.")
            }

            ForEach(alleSemester.filter { $0.typ == .regulaer && !($0.lehrveranstaltungen ?? []).isEmpty }) { semester in
                Section(semester.titel) {
                    ForEach(semester.sortierteLehrveranstaltungen.filter(istRelevant)) { lv in
                        Button {
                            auswahl = .lehrveranstaltung(lv)
                        } label: {
                            VoraussetzungsZeile(
                                lv: lv,
                                freigabe: lv.freigabe(in: stand),
                                schaltetFrei: lv.lfdNrTeile.flatMap { schaltetFrei[$0] ?? [] }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: freigabe.symbol)
                .foregroundStyle(freigabe.farbe)
                .frame(width: 22)
                .accessibilityLabel(freigabe.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(lv.lfdNrAnzeige) \(lv.bezeichnung)")
                    .fontWeight(.medium)
                if lv.voraussetzungen != .keine {
                    Text("Voraussetzung: \(lv.voraussetzungen.beschreibung)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                switch freigabe {
                case .blockiert(let fehlend):
                    ForEach(fehlend, id: \.self) { eintrag in
                        Label(eintrag, systemImage: "minus.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                case .freigeschaltet(let hinweise):
                    ForEach(hinweise, id: \.self) { hinweis in
                        Label(hinweis, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                case .bestanden:
                    EmptyView()
                }
                if !schaltetFrei.isEmpty {
                    Text("Schaltet frei: \(schaltetFrei.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
            StatusMarke(status: lv.status)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
