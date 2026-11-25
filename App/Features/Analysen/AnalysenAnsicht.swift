import SwiftUI
import SwiftData
import PharmaCore

/// Tab „Analysen“ einer Lehrveranstaltung.
struct AnalysenAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    @Environment(\.modelContext) private var kontext

    var body: some View {
        let themen = AnalyseDienst.themen(lv)
        let minuten = AnalyseDienst.lernminuten(lv: lv, kontext: kontext)
        let woche = AnalyseDienst.woche(minuten)
        GeometryReader { geo in
            ScrollView {
                Group {
                    if geo.size.width > 900 {
                        HStack(alignment: .top, spacing: 56) {
                            links(themen).frame(maxWidth: .infinity)
                            rechts(woche: woche, gesamt: Int(minuten.values.reduce(0, +))).frame(width: 380)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 44) {
                            rechts(woche: woche, gesamt: Int(minuten.values.reduce(0, +)))
                            links(themen)
                        }
                    }
                }
                .padding(.vertical, 36)
            }
        }
    }

    // MARK: Themen

    private func links(_ themen: [Analyse.ThemenWert]) -> some View {
        VStack(alignment: .leading, spacing: 44) {
            VStack(alignment: .leading, spacing: 0) {
                Abschnittstitel(titel: "Beherrschung nach Thema") {
                    Text("Karten, Probeklausuren, Fehler")
                }
                if themen.isEmpty {
                    Text("Noch keine Daten. Lerne Karteikarten mit Themen oder schreibe eine Probeklausur – dann erscheint hier, wie gut du welches Thema beherrschst.")
                        .font(Thema.ui(14))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .lineSpacing(4)
                        .padding(.vertical, 20)
                }
                ForEach(themen.sorted { $0.wert > $1.wert }) { thema in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(verbatim: thema.thema).font(Thema.ui(14)).foregroundStyle(Thema.tinte)
                            Spacer()
                            Text(verbatim: "\(Int((thema.wert * 100).rounded())) %")
                                .font(Thema.mono(12))
                                .foregroundStyle(thema.wert < 0.5 ? Stoffgebiet.i.farbe : Thema.tinteSekundaer)
                        }
                        Fortschrittslinie(wert: thema.wert)
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Haarlinie() }
                }
            }

            let schwach = themen.filter { $0.wert < 0.5 }.prefix(5)
            if !schwach.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Kleintitel(text: "Schwache Themen")
                    Text(verbatim: schwach.map(\.thema).joined(separator: " · "))
                        .font(Thema.serif(20))
                        .foregroundStyle(Thema.tinte)
                    Text("Tipp: Frag den Tutor im Modus „Schritt für Schritt“ oder starte ein Themenquiz.")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
            }

            kartenStatistik
        }
    }

    private var kartenStatistik: some View {
        let karten = (lv.karteikarten ?? []).filter(\.istGueltig)
        let neu = karten.filter { $0.zustandRaw == KartenZustand.neu.rawValue }.count
        let lernen = karten.filter { $0.zustandRaw == KartenZustand.lernen.rawValue || $0.zustandRaw == KartenZustand.neuLernen.rawValue }.count
        let wiederholen = karten.filter { $0.zustandRaw == KartenZustand.wiederholen.rawValue }.count
        let grenze = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let protokoll = karten.flatMap { $0.protokoll ?? [] }.filter { $0.datum >= grenze }
        let quote = protokoll.isEmpty ? nil : Double(protokoll.filter { $0.bewertung != .nochmal }.count) / Double(protokoll.count)
        return VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel(titel: "Karteikarten") { Text("\(karten.count) Karten") }
            HStack(alignment: .top) {
                kennzahl("\(neu)", "neu")
                kennzahl("\(lernen)", "in Lernschritten")
                kennzahl("\(wiederholen)", "in Wiederholung")
                kennzahl(quote.map { "\(Int(($0 * 100).rounded())) %" } ?? "–", "behalten (30 Tage)")
            }
            .padding(.top, 20)
        }
    }

    // MARK: Bereitschaft und Lernzeit

    private func rechts(woche: [Int], gesamt: Int) -> some View {
        VStack(alignment: .leading, spacing: 44) {
            VStack(alignment: .leading, spacing: 0) {
                Abschnittstitel("Prüfungsbereitschaft")
                let pruefungen = lv.sortierteTeilpruefungen.filter { $0.typ != .praktischerTeil && $0.ergebnis == .offen }
                if pruefungen.isEmpty {
                    Text("Keine offenen Teilprüfungen.")
                        .font(Thema.ui(14))
                        .foregroundStyle(Thema.tinteSekundaer)
                        .padding(.vertical, 18)
                }
                ForEach(pruefungen) { tp in
                    BereitschaftsZeile(tp: tp, bereitschaft: AnalyseDienst.bereitschaft(tp))
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Abschnittstitel(titel: "Lernzeit diese Woche") {
                    Text(verbatim: Analyse.stundenText(woche.reduce(0, +)))
                }
                Wochenbalken(minuten: woche)
                    .frame(height: 120)
                    .padding(.top, 20)
                Text("Insgesamt erfasst: \(Analyse.stundenText(gesamt)) – aus Fokus-Timer, Lerneinheiten, Karteikarten und Quiz.")
                    .font(Thema.ui(11))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .padding(.top, 12)
            }
        }
    }

    private func kennzahl(_ wert: String, _ titel: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: wert).font(Thema.display(30)).foregroundStyle(Thema.tinte)
            Text(titel).font(Thema.ui(11)).foregroundStyle(Thema.tinteSekundaer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BereitschaftsZeile: View {
    let tp: Teilpruefung
    let bereitschaft: AnalyseDienst.Bereitschaft

    private func prozent(_ wert: Double?) -> String {
        wert.map { "\(Int(($0 * 100).rounded())) %" } ?? "–"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tp.titel).font(Thema.ui(14)).foregroundStyle(Thema.tinte)
                    if let datum = tp.datum {
                        Text(verbatim: "\(datum.datumMitWochentag) · \(Countdown.text(tage: Countdown.tage(bis: datum)))")
                            .font(Thema.ui(11)).foregroundStyle(Thema.tinteTertiaer)
                    }
                }
                Spacer()
                Text(verbatim: prozent(bereitschaft.gesamt))
                    .font(Thema.display(34))
                    .foregroundStyle(Thema.tinte)
            }
            Fortschrittslinie(wert: bereitschaft.gesamt ?? 0)
            HStack(spacing: 16) {
                Text("Lernzeit \(prozent(bereitschaft.lernanteil))")
                Text("Karten \(prozent(bereitschaft.karten))")
                Text("Probeklausur \(prozent(bereitschaft.probeklausur))")
            }
            .font(Thema.ui(11))
            .foregroundStyle(Thema.tinteSekundaer)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Haarlinie() }
        .help("Gewichtung: Lernzeit 40 %, Karteikarten 35 %, Probeklausur 25 % – fehlende Werte werden ausgelassen")
    }
}

/// Fortschrittsring (z. B. je Semester).
struct Fortschrittsring: View {
    let wert: Double
    var farbe: Color = Thema.tinte
    var dicke: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(Thema.linie, lineWidth: dicke)
            Circle()
                .trim(from: 0, to: min(max(wert, 0), 1))
                .stroke(farbe, style: StrokeStyle(lineWidth: dicke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
