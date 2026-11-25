import SwiftUI
import SwiftData
import PharmaCore

struct HeuteAnsicht: View {
    @Binding var auswahl: Bereich?
    @Query private var alleTeilpruefungen: [Teilpruefung]
    @Query private var alleFristen: [Frist]

    private struct Termin: Identifiable {
        let teilpruefung: Teilpruefung
        let lv: Lehrveranstaltung
        let datum: Date
        var id: PersistentIdentifier { teilpruefung.persistentModelID }
    }

    private var naechsteTermine: [Termin] {
        let heute = Calendar.current.startOfDay(for: Date())
        return alleTeilpruefungen.compactMap { tp in
            guard let lv = tp.lehrveranstaltung, !lv.status.istAbgeschlossen,
                  tp.ergebnis == .offen, let datum = tp.datum, datum >= heute else { return nil }
            return Termin(teilpruefung: tp, lv: lv, datum: datum)
        }
        .sorted { $0.datum < $1.datum }
    }

    private var offeneFristen: [Frist] {
        alleFristen.filter { !$0.erledigt }
            .sorted { ($0.datum ?? .distantFuture) < ($1.datum ?? .distantFuture) }
    }

    private var ohneTermin: Int {
        alleTeilpruefungen.filter { tp in
            guard let lv = tp.lehrveranstaltung, lv.semester?.istAktuell == true else { return false }
            return tp.datum == nil && tp.ergebnis == .offen && !lv.status.istAbgeschlossen
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.abstand) {
                Text(Date().datumMitWochentag)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Layout.abstand, alignment: .top)],
                          spacing: Layout.abstand) {
                    naechstePruefungKarte
                    fristenKarte
                    Karte(titel: Text("Lernplan für heute"), symbol: "list.bullet.clipboard", farbe: .teal) {
                        Text("Der automatische Lernplan wird in Ausbaustufe b aus deinen Prüfungsterminen und Lernzeiten erstellt.")
                            .foregroundStyle(.secondary)
                    }
                    Karte(titel: Text("Fällige Karteikarten"), symbol: "rectangle.on.rectangle.angled", farbe: .indigo) {
                        Text("Karteikarten mit Wiederholungsplanung (FSRS) folgen in Ausbaustufe d.")
                            .foregroundStyle(.secondary)
                    }
                    Karte(titel: Text("Schnellquiz"), symbol: "bolt.circle", farbe: .orange) {
                        Text("Das 5-Minuten-Quiz folgt in Ausbaustufe d.")
                            .foregroundStyle(.secondary)
                    }
                    Karte(titel: Text("Lernserie"), symbol: "flame", farbe: .red) {
                        Text("Lernserie, XP und Abzeichen folgen in Ausbaustufe h.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Layout.abstand)
        }
        .navigationTitle("Heute lernen")
    }

    private var naechstePruefungKarte: some View {
        Karte(titel: Text("Nächste Teilprüfungen"), symbol: "hourglass", farbe: .red) {
            if naechsteTermine.isEmpty {
                Text("Noch keine Prüfungstermine eingetragen.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(naechsteTermine.prefix(4)) { termin in
                    Button {
                        auswahl = .lehrveranstaltung(termin.lv)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "\(termin.lv.lfdNrAnzeige) \(termin.teilpruefung.titel)")
                                    .lineLimit(2)
                                Text(termin.datum.datumMitWochentag)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            CountdownText(datum: termin.datum)
                                .font(.callout.weight(.semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if ohneTermin > 0 {
                Text("\(ohneTermin) Teilprüfungen im aktuellen Semester haben noch keinen Termin.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var fristenKarte: some View {
        Karte(titel: Text("Fristen & Anmeldungen"), symbol: "calendar.badge.exclamationmark", farbe: .orange) {
            if offeneFristen.isEmpty {
                Text("Keine offenen Fristen.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(offeneFristen.prefix(4)) { frist in
                    FristZeile(frist: frist)
                }
            }
        }
    }
}

struct FristZeile: View {
    @Bindable var frist: Frist

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                frist.erledigt.toggle()
            } label: {
                Image(systemName: frist.erledigt ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(frist.erledigt ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(frist.erledigt ? "Als offen markieren" : "Als erledigt markieren")

            VStack(alignment: .leading, spacing: 2) {
                Text(frist.titel)
                    .strikethrough(frist.erledigt)
                if let datum = frist.datum {
                    Text(datum.datumMitWochentag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !frist.hinweis.isEmpty {
                    Text(frist.hinweis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let datum = frist.datum, !frist.erledigt {
                CountdownText(datum: datum).font(.caption)
            }
        }
    }
}
