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

    private var unterzeile: String {
        let lvs = semester.sortierteLehrveranstaltungen
        var teile: [String] = []
        if let beginn = semester.vorlesungsbeginn, let ende = semester.vorlesungsende {
            teile.append("Vorlesungszeit \(beginn.kurzesDatum) – \(ende.kurzesDatum)")
        }
        if !lvs.isEmpty {
            teile.append("\(lvs.filter { $0.status == .bestanden }.count) von \(lvs.count) bestanden")
        }
        return teile.joined(separator: " · ")
    }

    var body: some View {
        let lvs = semester.sortierteLehrveranstaltungen
        let stand = StudienStand.aus(alleLVs, ph1: ph1)
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Seitentitel(titel: semester.titel, unterzeile: unterzeile.isEmpty ? nil : unterzeile)

                if !semester.sortierteFristen.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Abschnittstitel("Fristen")
                        ForEach(semester.sortierteFristen) { frist in
                            FristZeile(frist: frist)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel(titel: "Lehrveranstaltungen") {
                        Button("Hinzufügen") { zeigeNeueLV = true }
                            .buttonStyle(.plain)
                            .underline()
                    }
                    if lvs.isEmpty {
                        Text("Noch keine Lehrveranstaltungen – zum Beispiel aus deinem Grundstudium.")
                            .font(Thema.ui(14))
                            .foregroundStyle(Thema.tinteSekundaer)
                            .padding(.vertical, 20)
                    }
                    ForEach(lvs) { lv in
                        SemesterKursZeile(lv: lv, freigabe: lv.freigabe(in: stand)) {
                            auswahl = .lehrveranstaltung(lv)
                        }
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .seitenrand()
        }
        .background(Thema.flaeche)
        .navigationTitle(semester.titel)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    zeigeBearbeiten = true
                } label: {
                    Label("Semester bearbeiten", systemImage: "calendar")
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
}

private struct SemesterKursZeile: View {
    let lv: Lehrveranstaltung
    let freigabe: Freigabe
    var aktion: () -> Void

    private var meta: String {
        var teile = [lv.lehrform.kuerzel]
        if !lv.sws.isEmpty { teile.append(lv.swsAnzeige) }
        if !lv.leistungsnachweis.isEmpty { teile.append("LN \(lv.leistungsnachweis)") }
        if !lv.dozenten.isEmpty { teile.append(lv.dozenten.joined(separator: " / ")) }
        return teile.joined(separator: " · ")
    }

    var body: some View {
        Button(action: aktion) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Punkt(farbe: lv.farbe)
                LfdNrText(text: lv.lfdNrAnzeige, groesse: 12)
                    .frame(width: 66, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: lv.anzeigename)
                        .font(Thema.ui(15))
                        .foregroundStyle(lv.status == .bestanden ? Thema.tinteTertiaer : Thema.tinte)
                    Text(verbatim: meta)
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .lineLimit(1)
                    if case .blockiert(let fehlend) = freigabe {
                        Text("Blockiert: \(fehlend.joined(separator: ", "))")
                            .font(Thema.ui(11))
                            .foregroundStyle(Thema.tinteTertiaer)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if let tp = lv.naechsteTeilpruefung, let datum = tp.datum {
                    Text(verbatim: "\(max(0, Countdown.tage(bis: datum))) T")
                        .font(Thema.mono(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .help(tp.titel)
                }
                Text(verbatim: lv.status.name)
                    .font(Thema.ui(12))
                    .foregroundStyle(lv.status == .offen ? Thema.tinteTertiaer : Thema.tinte)
                    .frame(width: 96, alignment: .trailing)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}

/// Frist mit Abhaken.
struct FristZeile: View {
    @Bindable var frist: Frist

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button {
                frist.erledigt.toggle()
            } label: {
                Circle()
                    .strokeBorder(Thema.tinte, lineWidth: 1.2)
                    .background(Circle().fill(frist.erledigt ? Thema.tinte : Color.clear))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(frist.erledigt ? "Als offen markieren" : "Als erledigt markieren")
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: frist.titel)
                    .font(Thema.ui(14))
                    .strikethrough(frist.erledigt)
                    .foregroundStyle(frist.erledigt ? Thema.tinteTertiaer : Thema.tinte)
                if let datum = frist.datum {
                    Text(verbatim: datum.datumMitWochentag)
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                }
                if !frist.hinweis.isEmpty {
                    Text(verbatim: frist.hinweis)
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if let datum = frist.datum, !frist.erledigt {
                Text(verbatim: Countdown.text(tage: Countdown.tage(bis: datum)))
                    .font(Thema.mono(12))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}
