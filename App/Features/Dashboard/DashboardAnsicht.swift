import SwiftUI
import SwiftData
import PharmaCore

struct DashboardAnsicht: View {
    @Binding var auswahl: Bereich?

    @Query private var alleLVs: [Lehrveranstaltung]
    @Query private var alleTeilpruefungen: [Teilpruefung]
    @Query private var alleLerneinheiten: [Lerneinheit]
    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @Query private var alleSitzungen: [Lernsitzung]
    @Environment(\.modelContext) private var kontext
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

    /// Restaufwand aller anstehenden Teilprüfungen in Minuten.
    private var restMinuten: Int {
        anstehend.reduce(0) { summe, tp in
            let erledigt = (tp.lerneinheiten ?? []).filter(\.erledigt).reduce(0) { $0 + $1.dauerMinuten }
            return summe + max(0, tp.lernaufwandMinuten - erledigt)
        }
    }

    private func antwort(_ minuten: [Date: Double]) -> (text: String, reicht: Bool) {
        guard let letzte = anstehend.compactMap(\.datum).max() else {
            return ("Noch keine Prüfungstermine – trag Termine ein, dann rechnet der Lernplan.", true)
        }
        let tempo = AnalyseDienst.tempo(minuten)
        let geplant = Double(wochenplan.summeProWoche) / 7
        let basis = tempo >= 15 ? tempo : geplant
        let prognose = Analyse.zeitprognose(restMinuten: restMinuten, tageBis: max(1, Countdown.tage(bis: letzte)), tempoProTag: basis)
        let quelle = tempo >= 15 ? "bei deinem Tempo" : "bei deinen geplanten Lernzeiten"
        if prognose.reicht {
            return ("Ja, bei \(Dauer.text(minuten: prognose.benoetigtProTag)) pro Tag. Puffer: \(prognose.pufferTage) \(prognose.pufferTage == 1 ? "Tag" : "Tage").", true)
        }
        return ("Noch nicht: nötig wären \(Dauer.text(minuten: prognose.benoetigtProTag)) pro Tag, \(quelle) sind es \(Dauer.text(minuten: Int(basis))).", false)
    }


    var body: some View {
        let minuten = AnalyseDienst.lernminuten(lv: nil, kontext: kontext)
        let wochenminuten = AnalyseDienst.woche(minuten)
        let ergebnis = antwort(minuten)
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
                            Text(verbatim: ergebnis.text)
                                .font(Thema.ui(14))
                                .foregroundStyle(ergebnis.reicht ? Thema.tinte : Stoffgebiet.i.farbe)
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

                    semesterFortschritt

                    VStack(alignment: .leading, spacing: 0) {
                        Abschnittstitel(titel: "Lernzeit diese Woche") {
                            Text(verbatim: Analyse.stundenText(wochenminuten.reduce(0, +)))
                        }
                        Wochenbalken(minuten: wochenminuten)
                            .frame(height: 140)
                            .padding(.top, 24)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Abschnittstitel(titel: "Lernzeit je Woche") { Text("letzte 8 Wochen") }
                        Wochenverlauf(wochen: AnalyseDienst.wochensummen(minuten))
                            .frame(height: 140)
                            .padding(.top, 24)
                        Text("Erfasst aus Fokus-Timer, erledigten Lerneinheiten, Karteikarten, Quiz und Probeklausuren.")
                            .font(Thema.ui(11))
                            .foregroundStyle(Thema.tinteTertiaer)
                            .padding(.top, 12)
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
        // Neu zeichnen, sobald neue Lernsitzungen (Fokus-Timer) dazukommen
        .animation(nil, value: alleSitzungen.count)
    }
}

extension DashboardAnsicht {
    /// Fortschrittsringe je Semester (bestandene Lehrveranstaltungen, Kartenlernstand).
    var semesterFortschritt: some View {
        let semester = alleSemester.filter { $0.typ == .regulaer && (5...8).contains($0.nummer) }
        return VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel("Fortschritt je Semester")
            HStack(alignment: .top, spacing: 24) {
                ForEach(semester) { s in
                    let lvs = s.sortierteLehrveranstaltungen
                    let bestanden = lvs.filter { $0.status == .bestanden }.count
                    let anteil = lvs.isEmpty ? 0 : Double(bestanden) / Double(lvs.count)
                    let karten = KartenDienst.lernstand(lvs.flatMap { $0.karteikarten ?? [] })
                    Button {
                        auswahl = .semester(s)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            ZStack {
                                Fortschrittsring(wert: anteil, dicke: 3)
                                if let karten {
                                    Fortschrittsring(wert: karten, farbe: Thema.tinteTertiaer, dicke: 2)
                                        .padding(9)
                                }
                                Text(verbatim: "\(Int((anteil * 100).rounded()))%")
                                    .font(Thema.display(20))
                                    .foregroundStyle(Thema.tinte)
                            }
                            .frame(width: 84, height: 84)
                            Text(verbatim: s.titel + (s.istAktuell ? " · aktuell" : ""))
                                .font(Thema.ui(13))
                                .foregroundStyle(Thema.tinte)
                            Text(verbatim: "\(bestanden)/\(lvs.count) bestanden" + (karten.map { " · Karten \(Int(($0 * 100).rounded())) %" } ?? ""))
                                .font(Thema.ui(11))
                                .foregroundStyle(Thema.tinteSekundaer)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 24)
        }
    }
}

/// Säulen je Woche (älteste links).
struct Wochenverlauf: View {
    let wochen: [(beginn: Date, minuten: Int)]

    var body: some View {
        let maximum = max(wochen.map(\.minuten).max() ?? 0, 60)
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(Array(wochen.enumerated()), id: \.offset) { _, woche in
                VStack(spacing: 8) {
                    Text(verbatim: woche.minuten > 0 ? Analyse.stundenText(woche.minuten) : "")
                        .font(Thema.mono(9))
                        .foregroundStyle(Thema.tinteTertiaer)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(woche.minuten > 0 ? Thema.tinte : Thema.linie)
                                .frame(height: max(4, geo.size.height * CGFloat(woche.minuten) / CGFloat(maximum)))
                        }
                    }
                    Text(verbatim: "KW \(Calendar.deutsch.component(.weekOfYear, from: woche.beginn))")
                        .font(Thema.ui(10))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
            }
        }
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
