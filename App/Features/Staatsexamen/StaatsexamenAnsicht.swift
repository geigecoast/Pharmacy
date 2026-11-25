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
            VStack(alignment: .leading, spacing: 48) {
                Seitentitel(titel: "Staatsexamen",
                            unterzeile: "Langfristige Sicht auf den 2. Abschnitt. Der Lernstand je Fach wird ab Ausbaustufe d aus Karteikarten und Quizergebnissen aller Semester berechnet.")

                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel("Prüfungsfächer")
                    ForEach(StaatsexamenFach.allCases) { fach in
                        fachZeile(fach)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel("Lernpfade")
                    ForEach(lernpfade) { pfad in
                        lernpfadZeile(pfad)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel(titel: "Zuordnung") {
                        Text("Stoffgebiet → Prüfungsfach")
                    }
                    ForEach(sortierteZuordnungen) { zuordnung in
                        if let gebiet = zuordnung.stoffgebiet {
                            zuordnungZeile(zuordnung, gebiet: gebiet)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel("IMPP-Altfragen")
                    Text("Der IMPP-Altfragen-Modus und die Simulation der mündlichen Prüfung folgen in den Ausbaustufen d und e.")
                        .font(Thema.ui(14))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .padding(.vertical, 18)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .seitenrand()
        }
        .background(Thema.flaeche)
        .navigationTitle("Staatsexamen")
    }

    private func fachZeile(_ fach: StaatsexamenFach) -> some View {
        let gebiete = stoffgebiete(fuer: fach)
        let lvs = alleLVs.filter { lv in lv.stoffgebiete.contains { gebiete.contains($0) } }
        let bestanden = lvs.filter { $0.status == .bestanden }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: fach.name)
                    .font(Thema.ui(15))
                    .foregroundStyle(Thema.tinte)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(gebiete) { gebiet in
                        HStack(spacing: 4) {
                            Punkt(farbe: gebiet.farbe)
                            Text(verbatim: gebiet.code).font(Thema.mono(11)).foregroundStyle(Thema.tinteTertiaer)
                        }
                    }
                }
                Text(verbatim: "\(bestanden)/\(lvs.count)")
                    .font(Thema.mono(12))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .frame(width: 50, alignment: .trailing)
            }
            Fortschrittslinie(wert: lvs.isEmpty ? 0 : Double(bestanden) / Double(lvs.count))
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Haarlinie() }
        .help("Bestandene Lehrveranstaltungen der zugeordneten Stoffgebiete")
    }

    private func lernpfadZeile(_ pfad: Lernpfad) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: pfad.titel)
                .font(Thema.ui(15))
                .foregroundStyle(Thema.tinte)
            HStack(spacing: 18) {
                ForEach(pfad.sortierteTeile) { lv in
                    Button {
                        auswahl = .lehrveranstaltung(lv)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .strokeBorder(lv.farbe, lineWidth: 1.2)
                                .background(Circle().fill(lv.status == .bestanden ? lv.farbe : Color.clear))
                                .frame(width: 9, height: 9)
                            Text(verbatim: "Teil \(lv.lernpfadTeil)")
                                .font(Thema.ui(12))
                                .foregroundStyle(Thema.tinte)
                            LfdNrText(text: LfdNr.anzeige(lv.lfdNr), groesse: 11)
                            Text(verbatim: lv.semester?.titel ?? "")
                                .font(Thema.ui(11))
                                .foregroundStyle(Thema.tinteTertiaer)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Haarlinie() }
    }

    private func zuordnungZeile(_ zuordnung: StoffgebietZuordnung, gebiet: Stoffgebiet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Punkt(farbe: gebiet.farbe)
            Text(verbatim: gebiet.code).font(Thema.mono(12)).foregroundStyle(Thema.tinteTertiaer)
            Text(verbatim: gebiet.name).font(Thema.ui(14)).foregroundStyle(Thema.tinte).lineLimit(1)
            Spacer(minLength: 12)
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
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .underline()
                    .multilineTextAlignment(.trailing)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}
