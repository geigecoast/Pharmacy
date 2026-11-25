import SwiftUI
import SwiftData
import PharmaCore

struct DashboardAnsicht: View {
    @Binding var auswahl: Bereich?

    @Query private var alleLVs: [Lehrveranstaltung]
    @Query private var alleTeilpruefungen: [Teilpruefung]
    @Query private var alleLerneinheiten: [Lerneinheit]
    @AppStorage(EinstellungsSchluessel.lernplanWarnungen) private var warnungen = ""
    @AppStorage(EinstellungsSchluessel.lernzeiten) private var wochenplan: Wochenplan = .standard

    private let kalender = Calendar.deutsch
    private let gebiete: [Stoffgebiet] = [.e, .f, .g, .h, .i]

    private func kurzname(_ gebiet: Stoffgebiet) -> String {
        switch gebiet {
        case .e: "Biochemie, Klinische Chemie"
        case .f: "Pharmazeutische Technologie"
        case .g: "Pharmazeutische Biologie"
        case .h: "Pharm./Med. Chemie, Analytik"
        case .i: "Pharmakologie, Klinische Pharmazie"
        case .k: "Wahlpflichtfach"
        }
    }

    /// Lernstand: mittlere Abrufwahrscheinlichkeit aller Karteikarten des Stoffgebiets (FSRS).
    /// Ohne gelernte Karten: Anteil bestandener Lehrveranstaltungen.
    private func lernstand(_ gebiet: Stoffgebiet) -> Double {
        let lvs = alleLVs.filter { $0.stoffgebiete.contains(gebiet) && $0.semester?.typ != .staatsexamen }
        if let ausKarten = KartenDienst.lernstand(lvs.flatMap { $0.karteikarten ?? [] }) {
            return ausKarten
        }
        let regulaer = lvs.filter { $0.semester?.typ == .regulaer }
        guard !regulaer.isEmpty else { return 0 }
        return Double(regulaer.filter { $0.status == .bestanden }.count) / Double(regulaer.count)
    }

    private var anstehend: [Teilpruefung] {
        let heute = kalender.startOfDay(for: Date())
        return alleTeilpruefungen.filter { tp in
            guard let lv = tp.lehrveranstaltung, !lv.status.istAbgeschlossen, tp.ergebnis == .offen,
                  let datum = tp.datum, tp.lernaufwandMinuten > 0 else { return false }
            return datum > heute
        }
    }

    /// Kleinster Abstand zwischen letzter geplanter Lerneinheit und Prüfung (Tage ohne Lernbedarf davor).
    private var puffer: Int? {
        let werte = anstehend.compactMap { tp -> Int? in
            guard let datum = tp.datum else { return nil }
            let letzte = (tp.lerneinheiten ?? []).filter { !$0.erledigt }.map(\.tag).max()
            guard let letzte else { return nil }
            return max(0, Countdown.tage(von: letzte, bis: datum) - 1)
        }
        return werte.min()
    }

    private var antwort: String {
        let liste = warnungen.split(separator: "\n")
        if anstehend.isEmpty {
            return "Noch keine Prüfungstermine – trag Termine ein, dann rechnet der Lernplan."
        }
        let schnitt = Dauer.text(minuten: wochenplan.summeProWoche / 7)
        if liste.isEmpty {
            if let puffer {
                return "Ja, bei Ø \(schnitt) pro Tag. Puffer: \(puffer) \(puffer == 1 ? "Tag" : "Tage")."
            }
            return "Ja, bei Ø \(schnitt) pro Tag."
        }
        return "Knapp: Für \(liste.count) \(liste.count == 1 ? "Prüfung reicht" : "Prüfungen reicht") die Zeit nicht ganz."
    }

    /// Erledigte Lernminuten Mo–So der laufenden Woche.
    private var wochenminuten: [Int] {
        let start = kalender.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<7).map { offset in
            guard let tag = kalender.date(byAdding: .day, value: offset, to: start) else { return 0 }
            return alleLerneinheiten
                .filter { $0.erledigt && kalender.isDate($0.erledigtAm ?? $0.tag, inSameDayAs: tag) }
                .reduce(0) { $0 + $1.dauerMinuten }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 56) {
                    Seitentitel(titel: "Dashboard", unterzeile: "Lernstand nach Stoffgebiet, aggregiert über alle Semester.")

                    VStack(alignment: .leading, spacing: 16) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top),
                                                 count: geo.size.width > 900 ? 5 : 2),
                                  alignment: .leading, spacing: 32) {
                            ForEach(gebiete) { gebiet in
                                VStack(alignment: .leading, spacing: 0) {
                                    Rectangle().fill(gebiet.farbe).frame(height: 2)
                                    Text(verbatim: gebiet.code)
                                        .font(Thema.mono(11))
                                        .foregroundStyle(Thema.tinteTertiaer)
                                        .padding(.top, 22)
                                    Text(verbatim: "\(Int((lernstand(gebiet) * 100).rounded()))%")
                                        .font(Thema.display(48))
                                        .foregroundStyle(Thema.tinte)
                                    Text(verbatim: kurzname(gebiet))
                                        .font(Thema.ui(13))
                                        .foregroundStyle(Thema.tinteSekundaer)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 6)
                                }
                            }
                        }
                        Text("Lernstand = mittlere Erinnerungswahrscheinlichkeit deiner Karteikarten (FSRS). Ohne gelernte Karten: Anteil bestandener Lehrveranstaltungen.")
                            .font(Thema.ui(11))
                            .foregroundStyle(Thema.tinteTertiaer)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Haarlinie(farbe: Thema.tinte)
                        HStack(alignment: .firstTextBaseline) {
                            Text("Bist du rechtzeitig fertig?")
                                .font(Thema.display(26))
                                .foregroundStyle(Thema.tinte)
                            Spacer(minLength: 16)
                            Text(verbatim: antwort)
                                .font(Thema.ui(14))
                                .foregroundStyle(Thema.tinte)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.top, 18)
                        ForEach(warnungen.split(separator: "\n").map(String.init), id: \.self) { warnung in
                            Text(verbatim: warnung)
                                .font(Thema.ui(12))
                                .foregroundStyle(Stoffgebiet.i.farbe)
                                .padding(.top, 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Abschnittstitel(titel: "Lernzeit diese Woche") {
                            Text(verbatim: Dauer.text(minuten: wochenminuten.reduce(0, +)))
                        }
                        Wochenbalken(minuten: wochenminuten)
                            .frame(height: 140)
                            .padding(.top, 24)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Abschnittstitel("Studienverlauf")
                        Button {
                            auswahl = .voraussetzungen
                        } label: {
                            HStack {
                                Text("Voraussetzungen und Freischaltungen")
                                    .font(Thema.ui(14))
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .foregroundStyle(Thema.tinte)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Haarlinie() }
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(.horizontal, geo.size.width > 700 ? Thema.randAussen + 24 : Thema.randKompakt)
                .padding(.vertical, 48)
            }
        }
        .background(Thema.flaeche)
        .navigationTitle("Dashboard & Analysen")
    }
}

/// Säulen Mo–So; leere Tage als hellgraue Stummel.
struct Wochenbalken: View {
    let minuten: [Int]
    private let tage = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        let maximum = max(minuten.max() ?? 0, 60)
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(Array(minuten.enumerated()), id: \.offset) { index, wert in
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(wert > 0 ? Thema.tinte : Thema.linie)
                                .frame(height: max(4, geo.size.height * CGFloat(wert) / CGFloat(maximum)))
                        }
                    }
                    Text(verbatim: tage[index])
                        .font(Thema.ui(11))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
                .help(Dauer.text(minuten: wert))
            }
        }
    }
}
