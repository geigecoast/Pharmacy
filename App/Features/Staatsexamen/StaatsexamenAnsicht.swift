import SwiftUI
import SwiftData
import PharmaCore

struct StaatsexamenAnsicht: View {
    @Binding var auswahl: Bereich?
    @Query private var zuordnungen: [StoffgebietZuordnung]
    @Query(sort: \Lernpfad.titel) private var lernpfade: [Lernpfad]
    @Query private var alleLVs: [Lehrveranstaltung]

    private var sortierteZuordnungen: [StoffgebietZuordnung] {
        zuordnungen.sorted { $0.code < $1.code }
    }

    private func stoffgebiete(fuer fach: StaatsexamenFach) -> [Stoffgebiet] {
        sortierteZuordnungen.filter { $0.faecher.contains(fach) }.compactMap(\.stoffgebiet)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.abstand) {
                Text("Langfristige Sicht auf den 2. Abschnitt der Pharmazeutischen Prüfung. Der Lernstand je Fach wird ab Ausbaustufe d aus Karteikarten und Quizergebnissen aller Semester berechnet.")
                    .foregroundStyle(.secondary)

                Text("Prüfungsfächer").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Layout.abstand, alignment: .top)],
                          spacing: Layout.abstand) {
                    ForEach(StaatsexamenFach.allCases) { fach in
                        fachKarte(fach)
                    }
                }

                Text("Lernpfade").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Layout.abstand, alignment: .top)],
                          spacing: Layout.abstand) {
                    ForEach(lernpfade) { pfad in
                        lernpfadKarte(pfad)
                    }
                }

                Text("Zuordnung").font(.title3.weight(.semibold))
                zuordnungKarte

                Karte(titel: Text("IMPP-Altfragen"), symbol: "list.number", farbe: .purple) {
                    Text("Der IMPP-Altfragen-Modus und die Simulation der mündlichen Prüfung folgen in den Ausbaustufen d und e.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Layout.abstand)
        }
        .navigationTitle("Staatsexamen")
    }

    private func fachKarte(_ fach: StaatsexamenFach) -> some View {
        let gebiete = stoffgebiete(fuer: fach)
        let lvs = alleLVs.filter { lv in lv.stoffgebiete.contains { gebiete.contains($0) } }
        let bestanden = lvs.filter { $0.status == .bestanden }.count
        return Karte(titel: Text(fach.name), symbol: "graduationcap", farbe: gebiete.first?.farbe ?? .accentColor) {
            HStack(spacing: 6) {
                if gebiete.isEmpty {
                    Text("Keine Stoffgebiete zugeordnet").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(gebiete) { StoffgebietMarke(stoffgebiet: $0) }
            }
            if !lvs.isEmpty {
                ProgressView(value: Double(bestanden), total: Double(lvs.count)) {
                    Text("\(bestanden) von \(lvs.count) Lehrveranstaltungen bestanden")
                        .font(.caption)
                }
            }
        }
    }

    private func lernpfadKarte(_ pfad: Lernpfad) -> some View {
        let farbe = pfad.sortierteTeile.first?.farbe ?? .accentColor
        return Karte(titel: Text(pfad.titel), symbol: "point.topleft.down.to.point.bottomright.curvepath", farbe: farbe) {
            ForEach(pfad.sortierteTeile) { lv in
                Button {
                    auswahl = .lehrveranstaltung(lv)
                } label: {
                    HStack {
                        Image(systemName: lv.status.symbol)
                            .foregroundStyle(lv.status.farbe)
                        Text(verbatim: "Teil \(lv.lernpfadTeil) \(lv.lfdNrAnzeige)")
                            .monospacedDigit()
                        Spacer()
                        Text(lv.semester?.titel ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var zuordnungKarte: some View {
        Karte(titel: Text("Stoffgebiete → Prüfungsfächer"), symbol: "arrow.triangle.branch") {
            ForEach(sortierteZuordnungen) { zuordnung in
                if let gebiet = zuordnung.stoffgebiet {
                    HStack(alignment: .firstTextBaseline) {
                        StoffgebietMarke(stoffgebiet: gebiet)
                        Text(gebiet.name).lineLimit(1)
                        Spacer()
                        Menu {
                            ForEach(StaatsexamenFach.allCases) { fach in
                                Toggle(fach.name, isOn: Binding(
                                    get: { zuordnung.faecher.contains(fach) },
                                    set: { an in
                                        var faecher = zuordnung.faecher.filter { $0 != fach }
                                        if an { faecher.append(fach) }
                                        zuordnung.faecher = StaatsexamenFach.allCases.filter { faecher.contains($0) }
                                    }
                                ))
                            }
                        } label: {
                            Text(verbatim: zuordnung.faecher.isEmpty ? "–" : zuordnung.faecher.map(\.name).joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Über das Menü rechts lässt sich die Zuordnung ändern.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
