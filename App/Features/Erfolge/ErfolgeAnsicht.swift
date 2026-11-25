import SwiftUI
import SwiftData
import PharmaCore

/// Erfolge: Stufe, Lernserie, Wochenziel, Lernkalender und Abzeichen.
struct ErfolgeAnsicht: View {
    @Binding var auswahl: Bereich?

    @Environment(\.modelContext) private var kontext
    @Query private var erfolge: [Erfolg]
    @Query private var sitzungen: [Lernsitzung]
    @AppStorage(EinstellungsSchluessel.gamificationAktiv) private var aktiv = true

    var body: some View {
        // Neu berechnen, wenn Abzeichen oder Fokus-Sitzungen dazukommen.
        let _ = (erfolge.count, sitzungen.count)
        let stand = GamificationDienst.stand(kontext)
        let freigeschaltet = GamificationDienst.erfolge(kontext)
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 56) {
                    Seitentitel(titel: "Erfolge",
                                unterzeile: "Lernserie, Punkte und Abzeichen – ein Anreiz, dranzubleiben. In den Einstellungen abschaltbar.")
                    if !aktiv {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Erfolge sind ausgeschaltet.")
                                .font(Thema.ui(15))
                                .foregroundStyle(Thema.tinte)
                            Pille(text: "Einschalten", betont: true) { aktiv = true }
                        }
                    } else {
                        kennzahlen(stand, breit: geo.size.width > 900)
                        VStack(alignment: .leading, spacing: 0) {
                            Abschnittstitel(titel: "Lernkalender") { Text("letzte 16 Wochen") }
                            Lernkalender(minutenProTag: stand.minutenProTag, tagesziel: stand.tagesziel)
                                .padding(.top, 24)
                        }
                        abzeichen(stand.statistik, freigeschaltet: freigeschaltet, breit: geo.size.width > 700)
                        punkteErklaerung
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(.horizontal, geo.size.width > 700 ? Thema.randAussen + 24 : Thema.randKompakt)
                .padding(.vertical, 48)
            }
        }
        .background(Thema.flaeche)
        .navigationTitle("Erfolge")
    }

    // MARK: Kennzahlen

    @ViewBuilder
    private func kennzahlen(_ stand: GamificationDienst.Stand, breit: Bool) -> some View {
        let spalten = Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: breit ? 3 : 1)
        LazyVGrid(columns: spalten, alignment: .leading, spacing: 40) {
            StufenKachel(stufe: stand.stufe, punkte: stand.punkte)
            SerienKachel(serie: stand.serie, heuteMinuten: stand.heuteMinuten, tagesziel: stand.tagesziel,
                         ruhetagErlaubt: GamificationDienst.ruhetagErlaubt)
            WochenzielKachel(minuten: stand.wocheMinuten, ziel: stand.wochenziel)
        }
    }

    // MARK: Abzeichen

    private func abzeichen(_ statistik: Gamification.Statistik, freigeschaltet: [String: Date], breit: Bool) -> some View {
        let alle = Gamification.Abzeichen.allCases
        let anzahl = alle.filter { freigeschaltet[$0.rawValue] != nil }.count
        // Erreichte zuerst (neueste oben), dann nach Fortschritt.
        let sortiert = alle.sorted { (a: Gamification.Abzeichen, b: Gamification.Abzeichen) -> Bool in
            let da = freigeschaltet[a.rawValue]
            let db = freigeschaltet[b.rawValue]
            switch (da, db) {
            case let (x?, y?): return x > y
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return Self.anteil(a, statistik) > Self.anteil(b, statistik)
            }
        }
        let spalten = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: breit ? 3 : 1)
        return VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel(titel: "Abzeichen") { Text(verbatim: "\(anzahl) von \(alle.count)") }
            LazyVGrid(columns: spalten, alignment: .leading, spacing: 0) {
                ForEach(sortiert) { eintrag in
                    AbzeichenZeile(abzeichen: eintrag, statistik: statistik, erreichtAm: freigeschaltet[eintrag.rawValue])
                }
            }
        }
    }

    private static func anteil(_ abzeichen: Gamification.Abzeichen, _ statistik: Gamification.Statistik) -> Double {
        let f = abzeichen.fortschritt(statistik)
        return Double(f.wert) / Double(max(f.ziel, 1))
    }

    private var punkteErklaerung: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel("So entstehen Punkte")
            ForEach(Gamification.punkteRegeln.indices, id: \.self) { index in
                let regel = Gamification.punkteRegeln[index]
                HStack {
                    Text(verbatim: regel.0)
                        .font(Thema.ui(14))
                        .foregroundStyle(Thema.tinte)
                    Spacer()
                    Text(verbatim: "\(regel.1) \(regel.1 == 1 ? "Punkt" : "Punkte")")
                        .font(Thema.mono(12))
                        .foregroundStyle(Thema.tinteSekundaer)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Haarlinie() }
            }
            Text("Gezählt werden nur Teilprüfungen ab dem Hauptstudium. Lernzeit ohne Doppelzählung aus Fokus-Timer, Lerneinheiten, Karten, Quiz und Probeklausuren.")
                .font(Thema.ui(11))
                .foregroundStyle(Thema.tinteTertiaer)
                .padding(.top, 12)
        }
    }
}

// MARK: - Kacheln

private struct StufenKachel: View {
    let stufe: Gamification.Stufe
    let punkte: Int

    private var hinweis: String {
        guard let naechste = stufe.naechsteAb else { return "Höchste Stufe erreicht." }
        let titel = Gamification.stufentitel[min(stufe.nummer, Gamification.stufentitel.count - 1)]
        return "Noch \(naechste - punkte) Punkte bis Stufe \(stufe.nummer + 1) · \(titel)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kleintitel(text: "Stufe")
            GrosseZahl(zahl: "\(stufe.nummer)", einheit: stufe.titel, groesse: 72)
            Fortschrittslinie(wert: stufe.fortschritt)
                .padding(.top, 16)
            Text(verbatim: hinweis)
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteSekundaer)
                .padding(.top, 10)
            Text(verbatim: "\(punkte.formatted(.number.locale(.deutsch))) Punkte insgesamt")
                .font(Thema.mono(11))
                .foregroundStyle(Thema.tinteTertiaer)
                .padding(.top, 4)
        }
    }
}

private struct SerienKachel: View {
    let serie: Gamification.Serie
    let heuteMinuten: Int
    let tagesziel: Int
    let ruhetagErlaubt: Bool

    private var heuteText: String {
        if serie.heuteErreicht { return "Tagesziel heute erreicht." }
        return "Heute \(heuteMinuten) von \(tagesziel) min – noch \(max(0, tagesziel - heuteMinuten)) min für die Serie."
    }

    private var ruhetagText: String? {
        guard ruhetagErlaubt, serie.aktuell > 0 else { return nil }
        return serie.ruhetagDieseWocheGenutzt ? "Ruhetag dieser Woche genutzt." : "Ein Ruhetag pro Woche ist frei."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kleintitel(text: "Lernserie")
            GrosseZahl(zahl: "\(serie.aktuell)", einheit: serie.aktuell == 1 ? "Tag" : "Tage", groesse: 72)
            Fortschrittslinie(wert: Double(heuteMinuten) / Double(max(tagesziel, 1)))
                .padding(.top, 16)
            Text(verbatim: heuteText)
                .font(Thema.ui(12))
                .foregroundStyle(serie.heuteErreicht ? Thema.tinte : Thema.tinteSekundaer)
                .padding(.top, 10)
            Text(verbatim: ["Längste Serie: \(serie.laengste) \(serie.laengste == 1 ? "Tag" : "Tage")", ruhetagText]
                .compactMap { $0 }.joined(separator: " · "))
                .font(Thema.ui(11))
                .foregroundStyle(Thema.tinteTertiaer)
                .padding(.top, 4)
        }
    }
}

private struct WochenzielKachel: View {
    let minuten: Int
    let ziel: Int

    var body: some View {
        let anteil = Double(minuten) / Double(max(ziel, 1))
        VStack(alignment: .leading, spacing: 0) {
            Kleintitel(text: "Wochenziel")
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Fortschrittsring(wert: anteil, dicke: 3)
                    Text(verbatim: "\(Int((min(anteil, 9.99) * 100).rounded()))%")
                        .font(Thema.display(22))
                        .foregroundStyle(Thema.tinte)
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: Analyse.stundenText(minuten))
                        .font(Thema.display(30))
                        .foregroundStyle(Thema.tinte)
                    Text(verbatim: "von \(Analyse.stundenText(ziel))")
                        .font(Thema.ui(13))
                        .foregroundStyle(Thema.tinteSekundaer)
                }
            }
            .padding(.top, 14)
            Text(anteil >= 1 ? "Wochenziel erreicht." : "Montag bis Sonntag, aus deinen Lernzeiten.")
                .font(Thema.ui(12))
                .foregroundStyle(anteil >= 1 ? Thema.tinte : Thema.tinteSekundaer)
                .padding(.top, 14)
        }
    }
}

// MARK: - Abzeichen

private struct AbzeichenZeile: View {
    let abzeichen: Gamification.Abzeichen
    let statistik: Gamification.Statistik
    let erreichtAm: Date?

    var body: some View {
        let erreicht = erreichtAm != nil
        let f = abzeichen.fortschritt(statistik)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: abzeichen.symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(erreicht ? Thema.tinteInvers : Thema.tinteTertiaer)
                .frame(width: 38, height: 38)
                .background(Circle().fill(erreicht ? Thema.tinte : Color.clear))
                .overlay(Circle().strokeBorder(erreicht ? Thema.tinte : Thema.rahmen))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: abzeichen.titel)
                    .font(Thema.ui(14, erreicht ? .mittel : .normal))
                    .foregroundStyle(erreicht ? Thema.tinte : Thema.tinteSekundaer)
                Text(verbatim: abzeichen.beschreibung)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .fixedSize(horizontal: false, vertical: true)
                if let erreichtAm {
                    Text(verbatim: "Erreicht am " + erreichtAm.formatted(.dateTime.day().month(.wide).year().locale(.deutsch)))
                        .font(Thema.ui(11))
                        .foregroundStyle(Thema.tinteTertiaer)
                } else if f.ziel > 1 {
                    HStack(spacing: 10) {
                        Fortschrittslinie(wert: Double(f.wert) / Double(f.ziel))
                        Text(verbatim: "\(min(f.wert, f.ziel))/\(f.ziel)")
                            .font(Thema.mono(10))
                            .foregroundStyle(Thema.tinteTertiaer)
                            .fixedSize()
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}

// MARK: - Lernkalender

/// Raster der letzten Wochen (Spalten = Wochen, Zeilen = Mo–So).
/// Gefüllt = Tagesziel erreicht, hell = etwas gelernt, Rahmen = nichts.
struct Lernkalender: View {
    let minutenProTag: [Date: Double]
    let tagesziel: Int
    var wochen = 16

    private let kalender = Calendar.deutsch
    private let tage = ["Mo", "", "Mi", "", "Fr", "", "So"]

    private func farbe(_ minuten: Double) -> Color {
        if minuten >= Double(tagesziel) { return Thema.tinte }
        if minuten >= 1 { return Thema.tinte.opacity(0.3) }
        return Color.clear
    }

    var body: some View {
        let dieseWoche = kalender.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let starts: [Date] = (0..<wochen).reversed().compactMap { kalender.date(byAdding: .weekOfYear, value: -$0, to: dieseWoche) }
        let heute = kalender.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(0..<7, id: \.self) { zeile in
                        Text(verbatim: tage[zeile])
                            .font(Thema.ui(9))
                            .foregroundStyle(Thema.tinteTertiaer)
                            .frame(height: 14)
                    }
                }
                .padding(.trailing, 4)
                ForEach(starts, id: \.self) { start in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { versatz in
                            let tag = kalender.date(byAdding: .day, value: versatz, to: start) ?? start
                            let minuten = minutenProTag[kalender.startOfDay(for: tag)] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(tag > heute ? Color.clear : farbe(minuten))
                                .overlay(RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(tag > heute ? Color.clear : Thema.rahmen, lineWidth: minuten >= 1 ? 0 : 1))
                                .frame(width: 14, height: 14)
                                .help(tag.formatted(.dateTime.day().month().locale(.deutsch)) + ": " + Dauer.text(minuten: Int(minuten.rounded())))
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legende(Thema.tinte, "Tagesziel erreicht")
                legende(Thema.tinte.opacity(0.3), "gelernt")
            }
        }
    }

    private func legende(_ farbe: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(farbe).frame(width: 10, height: 10)
            Text(verbatim: text).font(Thema.ui(11)).foregroundStyle(Thema.tinteTertiaer)
        }
    }
}
