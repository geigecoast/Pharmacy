import SwiftUI
import PharmaCore

/// Kleines farbiges Kürzel eines Stoffgebiets.
struct StoffgebietMarke: View {
    let stoffgebiet: Stoffgebiet

    var body: some View {
        Text(stoffgebiet.code)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(minWidth: 20, minHeight: 20)
            .background(stoffgebiet.farbe, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("Stoffgebiet \(stoffgebiet.code): \(stoffgebiet.name)")
            .help(stoffgebiet.name)
    }
}

struct StatusMarke: View {
    let status: LVStatus

    var body: some View {
        Label(status.name, systemImage: status.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.farbe)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.farbe.opacity(0.12), in: Capsule())
    }
}

/// Karte mit Titel für Übersichtsseiten.
struct Karte<Inhalt: View>: View {
    let titel: Text
    let symbol: String
    var farbe: Color = .accentColor
    @ViewBuilder var inhalt: Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { titel } icon: { Image(systemName: symbol) }
                .font(.headline)
                .foregroundStyle(farbe)
            inhalt
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.abstand)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Layout.eckenradius))
    }
}

/// Countdown-Anzeige "in 12 Tagen".
struct CountdownText: View {
    let datum: Date

    var body: some View {
        let tage = Countdown.tage(bis: datum)
        Text(Countdown.text(tage: tage))
            .monospacedDigit()
            .foregroundStyle(tage <= 7 ? Color.red : (tage <= 21 ? Color.orange : Color.secondary))
    }
}

/// Platzhalter für Bereiche, die in einer späteren Ausbaustufe folgen.
struct FolgtInStufe: View {
    let titel: LocalizedStringKey
    let symbol: String
    let beschreibung: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(titel, systemImage: symbol)
        } description: {
            Text(beschreibung)
        }
    }
}

extension Date {
    var kurzesDatum: String {
        formatted(.dateTime.day().month(.abbreviated).year().locale(.deutsch))
    }
    var datumMitWochentag: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.deutsch))
    }
    var datumUndUhrzeit: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute().locale(.deutsch))
    }
}

/// Datumsfeld, das auch leer bleiben darf (z. B. noch kein Prüfungstermin bekannt).
struct OptionalesDatum: View {
    let titel: Text
    @Binding var datum: Date?
    var mitUhrzeit = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { datum != nil },
            set: { an in
                datum = an ? (datum ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()) : nil
            }
        )) {
            titel
        }
        if let aktuell = datum {
            DatePicker(selection: Binding(get: { aktuell }, set: { datum = $0 }),
                       displayedComponents: mitUhrzeit ? [.date, .hourAndMinute] : [.date]) {
                Text("Datum")
            }
        }
    }
}

/// Zeigt den Freigabezustand mit fehlenden Voraussetzungen.
struct FreigabeDetail: View {
    let freigabe: Freigabe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(freigabe.name, systemImage: freigabe.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(freigabe.farbe)
            switch freigabe {
            case .bestanden:
                EmptyView()
            case .freigeschaltet(let hinweise):
                ForEach(hinweise, id: \.self) { hinweis in
                    Text(verbatim: hinweis).font(.caption).foregroundStyle(.secondary)
                }
            case .blockiert(let fehlend):
                ForEach(fehlend, id: \.self) { eintrag in
                    Label(eintrag, systemImage: "minus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension Lehrveranstaltung {
    /// "2+1 SWS" bzw. Freitext wie "84 Zeitstunden".
    var swsAnzeige: String {
        let zahlenartig = sws.allSatisfy { $0.isNumber || "+,. ".contains($0) }
        return zahlenartig && !sws.isEmpty ? "\(sws) SWS" : sws
    }
}
