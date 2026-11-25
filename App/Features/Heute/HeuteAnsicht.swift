import SwiftUI
import SwiftData
import PharmaCore

struct HeuteAnsicht: View {
    @Binding var auswahl: Bereich?
    @Environment(\.modelContext) private var kontext
    @Query private var alleTeilpruefungen: [Teilpruefung]
    @Query private var alleFristen: [Frist]
    @Query private var alleLerneinheiten: [Lerneinheit]

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

    private var heutigeEinheiten: [Lerneinheit] {
        alleLerneinheiten
            .filter { Calendar.current.isDateInToday($0.tag) }
            .sorted { ($0.erledigt ? 1 : 0, $0.thema) < ($1.erledigt ? 1 : 0, $1.thema) }
    }

    /// Anmeldepflichtige Teilprüfungen ohne Anmeldung, deren Anmeldeschluss in den nächsten 30 Tagen liegt.
    private var offeneAnmeldungen: [Teilpruefung] {
        let heute = Calendar.current.startOfDay(for: Date())
        let grenze = Calendar.current.date(byAdding: .day, value: 30, to: heute) ?? heute
        return alleTeilpruefungen
            .filter { tp in
                guard tp.anmeldepflichtig, !tp.angemeldet, tp.ergebnis == .offen,
                      tp.lehrveranstaltung?.status.istAbgeschlossen == false,
                      let schluss = tp.anmeldeschluss else { return false }
                return schluss >= heute && schluss <= grenze
            }
            .sorted { ($0.anmeldeschluss ?? .distantFuture) < ($1.anmeldeschluss ?? .distantFuture) }
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
                    lernplanKarte
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

    private var lernplanKarte: some View {
        Karte(titel: Text("Lernplan für heute"), symbol: "list.bullet.clipboard", farbe: .teal) {
            let einheiten = heutigeEinheiten
            if einheiten.isEmpty {
                Text("Heute ist nichts geplant. Der Lernplan entsteht automatisch aus deinen Prüfungsterminen und Lernzeiten.")
                    .foregroundStyle(.secondary)
            } else {
                let erledigt = einheiten.filter(\.erledigt).reduce(0) { $0 + $1.dauerMinuten }
                let gesamt = einheiten.reduce(0) { $0 + $1.dauerMinuten }
                ProgressView(value: Double(erledigt), total: Double(max(gesamt, 1))) {
                    Text("\(Dauer.text(minuten: erledigt)) von \(Dauer.text(minuten: gesamt)) erledigt")
                        .font(.caption)
                }
                ForEach(einheiten) { einheit in
                    HeuteLerneinheit(einheit: einheit)
                }
            }
            HStack {
                Button("Zum Kalender") { auswahl = .kalender }
                Spacer()
                Button("Neu berechnen") { LernplanDienst.aktualisieren(kontext) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private var fristenKarte: some View {
        Karte(titel: Text("Fristen & Anmeldungen"), symbol: "calendar.badge.exclamationmark", farbe: .orange) {
            ForEach(offeneAnmeldungen) { tp in
                Button {
                    if let lv = tp.lehrveranstaltung { auswahl = .lehrveranstaltung(lv) }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Label {
                            Text("QIS/LSF-Anmeldung: \(tp.titelMitLfdNr)")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        Spacer()
                        if let schluss = tp.anmeldeschluss {
                            CountdownText(datum: schluss).font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if offeneFristen.isEmpty && offeneAnmeldungen.isEmpty {
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

private struct HeuteLerneinheit: View {
    @Bindable var einheit: Lerneinheit

    var body: some View {
        Button {
            einheit.umschalten()
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: einheit.erledigt ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(einheit.erledigt ? Color.green : einheit.farbe)
                Text(einheit.thema)
                    .strikethrough(einheit.erledigt)
                    .lineLimit(2)
                Spacer()
                Text(verbatim: Dauer.text(minuten: einheit.dauerMinuten))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
