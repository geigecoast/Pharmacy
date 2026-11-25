import SwiftUI
import SwiftData
import PharmaCore

/// Startbildschirm „Heute lernen“ nach Design.
struct HeuteAnsicht: View {
    @Binding var auswahl: Bereich?

    @Environment(\.modelContext) private var kontext
    @Query private var alleTeilpruefungen: [Teilpruefung]
    @Query private var alleFristen: [Frist]
    @Query private var alleLerneinheiten: [Lerneinheit]
    @Query private var alleKarten: [Karteikarte]
    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @State private var zeigeWiederholung = false
    @AppStorage(EinstellungsSchluessel.vorname) private var vorname = ""
    @AppStorage(EinstellungsSchluessel.lernstartMinuten) private var lernstart = Standardwerte.lernstartMinuten
    @AppStorage(EinstellungsSchluessel.lvTab) private var lvTab: LVTab = .vorlesungen

    private let kalender = Calendar.deutsch

    // MARK: Daten

    private var heutigeEinheiten: [Lerneinheit] {
        alleLerneinheiten
            .filter { kalender.isDateInToday($0.tag) }
            .sorted { ($0.manuell ? 0 : 1, $0.thema) < ($1.manuell ? 0 : 1, $1.thema) }
    }

    /// Anstehende Teilprüfungen mit Termin, nach Datum.
    private var anstehend: [Teilpruefung] {
        let heute = kalender.startOfDay(for: Date())
        return alleTeilpruefungen
            .filter { tp in
                guard let lv = tp.lehrveranstaltung, !lv.status.istAbgeschlossen, tp.ergebnis == .offen,
                      let datum = tp.datum else { return false }
                return datum >= heute
            }
            .sorted { ($0.datum ?? .distantFuture) < ($1.datum ?? .distantFuture) }
    }

    private var offeneFristen: [Frist] {
        alleFristen.filter { !$0.erledigt && $0.datum != nil }
            .sorted { ($0.datum ?? .distantFuture) < ($1.datum ?? .distantFuture) }
    }

    private var offeneAnmeldungen: [Teilpruefung] {
        let heute = kalender.startOfDay(for: Date())
        let grenze = kalender.date(byAdding: .day, value: 30, to: heute) ?? heute
        return alleTeilpruefungen
            .filter { tp in
                guard tp.anmeldepflichtig, !tp.angemeldet, tp.ergebnis == .offen,
                      tp.lehrveranstaltung?.status.istAbgeschlossen == false,
                      let schluss = tp.anmeldeschluss else { return false }
                return schluss >= heute && schluss <= grenze
            }
            .sorted { ($0.anmeldeschluss ?? .distantFuture) < ($1.anmeldeschluss ?? .distantFuture) }
    }

    @Query private var alleSitzungen: [Lernsitzung]

    @AppStorage(EinstellungsSchluessel.gamificationAktiv) private var gamificationAktiv = true

    /// Tagesziel für Lernserie und Wochenleiste (ohne Gamification: jede Lernminute zählt).
    private var tagesziel: Int { gamificationAktiv ? GamificationDienst.tagesziel : 1 }

    /// Lernserie und Tage mit erreichtem Tagesziel – einmal berechnet
    /// (Lerneinheiten, Fokus-Timer, Karten, Quiz; ohne Gamification zählt jede Lernminute).
    private var lernstand: (serie: Int, tage: Set<Date>) {
        _ = alleSitzungen.count
        let minuten = AnalyseDienst.lernminuten(lv: nil, kontext: kontext)
        let grenze = Double(tagesziel)
        let serie = Gamification.serie(minutenProTag: minuten, tagesziel: tagesziel,
                                       ruhetagErlaubt: gamificationAktiv && GamificationDienst.ruhetagErlaubt,
                                       heute: Date(), kalender: kalender).aktuell
        return (serie, Set(minuten.filter { $0.value >= grenze }.keys))
    }

    private func bereitschaft(_ tp: Teilpruefung) -> Double {
        guard tp.lernaufwandMinuten > 0 else { return 0 }
        let erledigt = (tp.lerneinheiten ?? []).filter(\.erledigt).reduce(0) { $0 + $1.dauerMinuten }
        return min(1, Double(erledigt) / Double(tp.lernaufwandMinuten))
    }

    private var begruessung: String {
        let stunde = kalender.component(.hour, from: Date())
        switch stunde {
        case 5..<11: return "Guten Morgen"
        case 11..<18: return "Guten Tag"
        default: return "Guten Abend"
        }
    }

    private var aktuellesSemester: Semester? { alleSemester.first(where: \.istAktuell) }

    private var zusammenfassung: String {
        var saetze: [String] = []
        let offen = heutigeEinheiten.filter { !$0.erledigt }.count
        let karten = KartenDienst.anzahlFaellig(alleKarten)
        let kartenText = karten == 0 ? "" : (karten == 1 ? ", eine fällige Karte" : ", \(karten) fällige Karten")
        switch offen {
        case 0:
            if heutigeEinheiten.isEmpty {
                saetze.append(karten == 0 ? "Heute ist nichts geplant." : "Keine Lerneinheiten\(kartenText).")
            } else {
                saetze.append("Alle Lerneinheiten für heute sind erledigt\(karten == 0 ? "" : " – es warten noch \(karten) Karten").")
            }
        case 1: saetze.append("Eine Lerneinheit\(kartenText).")
        default: saetze.append("\(Zahlwort.text(offen, grossAmAnfang: true)) Lerneinheiten\(kartenText).")
        }
        if let tp = anstehend.first, let datum = tp.datum {
            let tage = Countdown.tage(bis: datum)
            saetze.append("Die \(tp.titel)\(tp.lehrveranstaltung.map { " " + LfdNr.anzeige($0.lfdNr) } ?? "") ist \(Countdown.text(tage: tage)).")
        }
        return saetze.joined(separator: " ")
    }

    // MARK: Ansicht

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    kopf
                    if geo.size.width > 980 {
                        HStack(alignment: .top, spacing: 56) {
                            linkeSpalte.frame(maxWidth: .infinity)
                            rechteSpalte.frame(width: 380)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 44) {
                            rechteSpalte
                            linkeSpalte
                        }
                    }
                }
                .frame(maxWidth: 1180, alignment: .leading)
                .padding(.horizontal, geo.size.width > 700 ? Thema.randAussen + 24 : Thema.randKompakt)
                .padding(.vertical, 48)
            }
        }
        .background(Thema.flaeche)
        .navigationTitle("Heute lernen")
        .sheet(isPresented: $zeigeWiederholung) {
            WiederholungsSitzung()
        }
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: [Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.deutsch)),
                            aktuellesSemester?.titel].compactMap { $0 }.joined(separator: " · "))
                .font(Thema.ui(13))
                .foregroundStyle(Thema.tinteSekundaer)
            Text(gruss)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(verbatim: zusammenfassung)
                .font(Thema.ui(16))
                .foregroundStyle(Thema.tinteSekundaer)
                .lineSpacing(5)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// „Guten Morgen, *Ann.*“ – der Name kursiv.
    private var gruss: AttributedString {
        let name = vorname.trimmingCharacters(in: .whitespaces)
        var anfang = AttributedString(name.isEmpty ? "\(begruessung)." : "\(begruessung), ")
        anfang.font = Thema.display(60)
        anfang.foregroundColor = Thema.tinte
        guard !name.isEmpty else { return anfang }
        var kursiv = AttributedString("\(name).")
        kursiv.font = Thema.display(60, kursiv: true)
        kursiv.foregroundColor = Thema.tinte
        return anfang + kursiv
    }

    // MARK: Linke Spalte: Plan

    private var linkeSpalte: some View {
        VStack(alignment: .leading, spacing: 44) {
            VStack(alignment: .leading, spacing: 0) {
                let einheiten = heutigeEinheiten
                Abschnittstitel(titel: "Heutiger Plan") {
                    Text("\(einheiten.filter(\.erledigt).count) von \(einheiten.count) erledigt")
                }
                if einheiten.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Heute ist nichts geplant.")
                            .font(Thema.ui(15))
                            .foregroundStyle(Thema.tinte)
                        Text("Der Lernplan entsteht aus deinen Prüfungsterminen und Lernzeiten. Trag Termine unter „Prüfungsvorbereitung“ ein.")
                            .font(Thema.ui(13))
                            .foregroundStyle(Thema.tinteSekundaer)
                        HStack(spacing: 16) {
                            Button("Zum Kalender") { auswahl = .kalender }
                            Button("Lernplan berechnen") { LernplanDienst.aktualisieren(kontext) }
                        }
                        .buttonStyle(.plain)
                        .font(Thema.ui(13, .mittel))
                        .foregroundStyle(Thema.tinte)
                        .underline()
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(zeitplan(einheiten)) { eintrag in
                        PlanZeile(einheit: eintrag.einheit, uhrzeit: eintrag.uhrzeit)
                    }
                }
            }

            if !offeneAnmeldungen.isEmpty || !offeneFristen.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel("Fristen & Anmeldungen")
                    ForEach(offeneAnmeldungen) { tp in
                        FristenZeile(titel: "QIS/LSF-Anmeldung: \(tp.titelMitLfdNr)",
                                     hinweis: "Verspätete Anmeldung ist nicht möglich.",
                                     datum: tp.anmeldeschluss, farbe: tp.lehrveranstaltung?.farbe ?? Thema.tinteTertiaer) {
                            if let lv = tp.lehrveranstaltung { auswahl = .lehrveranstaltung(lv) }
                        }
                    }
                    ForEach(offeneFristen.prefix(4)) { frist in
                        FristenZeile(titel: frist.titel, hinweis: frist.hinweis, datum: frist.datum,
                                     farbe: frist.lehrveranstaltung?.farbe ?? Thema.tinteTertiaer) {
                            frist.erledigt = true
                        }
                    }
                }
            }
        }
    }

    /// Ordnet den Einheiten Uhrzeiten zu: ab Lernbeginn, mit 15 Minuten Pause dazwischen.
    private struct PlanEintrag: Identifiable {
        let einheit: Lerneinheit
        let uhrzeit: Date
        var id: UUID { einheit.kennung }
    }

    private func zeitplan(_ einheiten: [Lerneinheit]) -> [PlanEintrag] {
        var zeit = kalender.date(bySettingHour: lernstart / 60, minute: lernstart % 60, second: 0, of: Date()) ?? Date()
        var ergebnis: [PlanEintrag] = []
        for einheit in einheiten {
            ergebnis.append(PlanEintrag(einheit: einheit, uhrzeit: zeit))
            zeit = zeit.addingTimeInterval(Double(einheit.dauerMinuten + 15) * 60)
        }
        return ergebnis
    }

    // MARK: Rechte Spalte

    private var rechteSpalte: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tp = anstehend.first, let datum = tp.datum {
                let tage = max(0, Countdown.tage(bis: datum))
                let wert = bereitschaft(tp)
                Button {
                    if let lv = tp.lehrveranstaltung {
                        lvTab = .pruefung
                        auswahl = .lehrveranstaltung(lv)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Kleintitel(text: "Nächste Teilprüfung")
                        GrosseZahl(zahl: "\(tage)", einheit: tage == 1 ? "Tag" : "Tage", groesse: 88)
                            .padding(.top, -4)
                        Text(verbatim: tp.titel)
                            .font(Thema.ui(15))
                            .foregroundStyle(Thema.tinte)
                            .padding(.top, 14)
                        HStack(spacing: 6) {
                            LfdNrText(text: tp.lehrveranstaltung.map { LfdNr.anzeige($0.lfdNr) } ?? "", groesse: 12,
                                      farbe: Thema.tinteSekundaer)
                            Text(verbatim: "· " + datum.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).hour().minute().locale(.deutsch)))
                                .font(Thema.ui(13))
                                .foregroundStyle(Thema.tinteSekundaer)
                        }
                        .padding(.top, 6)
                        Fortschrittslinie(wert: wert)
                            .padding(.top, 18)
                        Text("Prüfungsbereitschaft \(Int((wert * 100).rounded())) %")
                            .font(Thema.ui(12))
                            .foregroundStyle(Thema.tinteSekundaer)
                            .padding(.top, 10)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Prüfungsbereitschaft = erledigte Lernzeit im Verhältnis zum geplanten Lernaufwand")
            } else {
                Kleintitel(text: "Nächste Teilprüfung")
                Text("Noch keine Prüfungstermine eingetragen.")
                    .font(Thema.ui(15))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .padding(.top, 12)
            }

            Haarlinie().padding(.vertical, 28)

            let heute = lernstand
            HStack(alignment: .top) {
                Button {
                    zeigeWiederholung = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "\(KartenDienst.anzahlFaellig(alleKarten))").font(Thema.display(40))
                        Text("Karten fällig").font(Thema.ui(13)).foregroundStyle(Thema.tinteSekundaer)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Fällige Karten aller Lehrveranstaltungen wiederholen")
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(heute.serie)").font(Thema.display(40))
                    Text(heute.serie == 1 ? "Tag Lernserie" : "Tage Lernserie").font(Thema.ui(13)).foregroundStyle(Thema.tinteSekundaer)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Thema.tinte)

            Wochenleiste(lerntage: heute.tage, kalender: kalender)
                .padding(.top, 28)

            if gamificationAktiv {
                ErfolgsZeile(sitzungen: alleSitzungen.count) { auswahl = .erfolge }
                    .padding(.top, 24)
            }

            if let tp = anstehend.first, let lv = tp.lehrveranstaltung {
                Aktionskarte(titel: "Schnellquiz starten", untertitel: "5 Minuten · \(lv.anzeigename) \(LfdNr.anzeige(lv.lfdNr))") {
                    lvTab = .quiz
                    auswahl = .lehrveranstaltung(lv)
                }
                .padding(.top, 40)
            }
        }
    }
}

/// Eine Zeile im Tagesplan: Uhrzeit · Kreis zum Abhaken · Titel · Dauer.
private struct PlanZeile: View {
    @Bindable var einheit: Lerneinheit
    let uhrzeit: Date

    private var titel: String {
        if let tp = einheit.teilpruefung { return "Vorbereitung: \(tp.titel)" }
        return einheit.thema
    }

    private var meta: String {
        guard let lv = einheit.lehrveranstaltung else { return "" }
        return "\(LfdNr.anzeige(lv.lfdNr)) · \(lv.anzeigename)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: uhrzeit.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(.deutsch)))
                    .font(Thema.mono(13))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .frame(width: 70, alignment: .leading)
                Button {
                    einheit.umschalten()
                } label: {
                    Circle()
                        .strokeBorder(Thema.tinte, lineWidth: 1.2)
                        .background(Circle().fill(einheit.erledigt ? Thema.tinte : Color.clear))
                        .frame(width: 15, height: 15)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(einheit.erledigt ? "Als offen markieren" : "Als erledigt markieren")
                .padding(.trailing, 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: titel)
                        .font(Thema.ui(15))
                        .strikethrough(einheit.erledigt)
                        .foregroundStyle(einheit.erledigt ? Thema.tinteTertiaer : Thema.tinte)
                    if !meta.isEmpty {
                        HStack(spacing: 7) {
                            Punkt(farbe: einheit.farbe)
                            Text(verbatim: meta)
                                .font(Thema.ui(12))
                                .foregroundStyle(Thema.tinteSekundaer)
                        }
                    }
                    if einheit.verpasst {
                        Text("verpasst")
                            .font(Thema.ui(11))
                            .foregroundStyle(Stoffgebiet.i.farbe)
                    }
                }
                Spacer(minLength: 12)
                Text(verbatim: Dauer.text(minuten: einheit.dauerMinuten))
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
            .padding(.vertical, 20)
            Haarlinie()
        }
    }
}

private struct FristenZeile: View {
    let titel: String
    let hinweis: String
    let datum: Date?
    let farbe: Color
    var aktion: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: aktion) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Punkt(farbe: farbe)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: titel).font(Thema.ui(14)).foregroundStyle(Thema.tinte)
                        if !hinweis.isEmpty {
                            Text(verbatim: hinweis)
                                .font(Thema.ui(12))
                                .foregroundStyle(Thema.tinteSekundaer)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 12)
                    if let datum {
                        Text(verbatim: Countdown.text(tage: Countdown.tage(bis: datum)))
                            .font(Thema.mono(12))
                            .foregroundStyle(Thema.tinteSekundaer)
                    }
                }
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Haarlinie()
        }
    }
}

/// Stufe und Tagesziel als kompakte Zeile unter der Wochenleiste.
struct ErfolgsZeile: View {
    /// Nur, damit die Zeile nach neuen Fokus-Sitzungen neu berechnet wird.
    let sitzungen: Int
    var oeffnen: () -> Void
    @Environment(\.modelContext) private var kontext

    var body: some View {
        let stand = GamificationDienst.stand(kontext)
        let anteil = Double(stand.heuteMinuten) / Double(max(stand.tagesziel, 1))
        Button(action: oeffnen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Stufe \(stand.stufe.nummer) · \(stand.stufe.titel)")
                        .font(Thema.ui(13, .mittel))
                        .foregroundStyle(Thema.tinte)
                    Spacer(minLength: 8)
                    Text(verbatim: stand.serie.heuteErreicht
                         ? "Tagesziel erreicht"
                         : "Heute \(stand.heuteMinuten)/\(stand.tagesziel) min")
                        .font(Thema.mono(11))
                        .foregroundStyle(Thema.tinteSekundaer)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
                Fortschrittslinie(wert: anteil)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Erfolge öffnen: Lernserie, Stufe und Abzeichen")
    }
}

/// Mo–So: gefüllt = gelernt, umrandet = heute.
struct Wochenleiste: View {
    let lerntage: Set<Date>
    let kalender: Calendar

    var body: some View {
        let start = kalender.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let tage = (0..<7).compactMap { kalender.date(byAdding: .day, value: $0, to: start) }
        HStack(spacing: 7) {
            ForEach(tage, id: \.self) { tag in
                let gelernt = lerntage.contains(kalender.startOfDay(for: tag))
                let heute = kalender.isDateInToday(tag)
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gelernt ? Thema.tinte : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(heute ? Thema.tinte : Thema.rahmen, lineWidth: heute ? 1.2 : 1))
                        .frame(height: 28)
                    Text(verbatim: tag.formatted(.dateTime.weekday(.abbreviated).locale(.deutsch)).replacingOccurrences(of: ".", with: ""))
                        .font(Thema.ui(11))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
            }
        }
    }
}

/// Zahlwörter für kurze Zusammenfassungen („Vier Lerneinheiten …“).
enum Zahlwort {
    static func text(_ zahl: Int, grossAmAnfang: Bool = false) -> String {
        let woerter = ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"]
        guard zahl >= 0, zahl < woerter.count else { return "\(zahl)" }
        let wort = zahl == 1 ? "eine" : woerter[zahl]
        return grossAmAnfang ? wort.prefix(1).uppercased() + wort.dropFirst() : wort
    }
}
