import SwiftUI
import SwiftData
import PharmaCore

/// Quiz in vier Modi: Schnellquiz (5 min), Themenquiz, IMPP-Modus (MC), Prüfungssimulation (90 min).
struct QuizSitzung: View {
    let modus: QuizModus
    let pool: [Karteikarte]
    var lv: Lehrveranstaltung?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var kontext

    private enum Phase { case vorbereitung, laeuft, ergebnis }

    @State private var phase: Phase = .vorbereitung
    @State private var thema = ""
    @State private var fragen: [Karteikarte] = []
    @State private var index = 0
    @State private var aufgedeckt = false
    @State private var auswahl: Set<Int> = []
    @State private var geprueft = false
    @State private var ergebnisse: [UUID: Bool] = [:]
    @State private var antworten: [UUID: String] = [:]
    @State private var start = Date()
    @State private var verbleibend: Int?
    @State private var aktuellerModus: QuizModus?

    private var gueltig: [Karteikarte] { pool.filter(\.istGueltig) }

    private var themen: [String] {
        Array(Set(gueltig.map(\.thema).filter { !$0.isEmpty })).sorted()
    }

    private var laufenderModus: QuizModus { aktuellerModus ?? modus }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch phase {
                    case .vorbereitung: vorbereitung
                    case .laeuft: laeuft
                    case .ergebnis: ergebnis
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(40)
            }
            .background(Thema.flaeche)
            .navigationTitle(laufenderModus.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .laeuft ? "Abbrechen" : "Schließen") { dismiss() }
                }
                if phase == .laeuft {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Auswerten") { beenden() }
                    }
                }
            }
        }
        .task(id: phase == .laeuft) {
            guard phase == .laeuft, verbleibend != nil else { return }
            while !Task.isCancelled, phase == .laeuft {
                try? await Task.sleep(for: .seconds(1))
                guard phase == .laeuft, let rest = verbleibend else { return }
                verbleibend = rest - 1
                if rest - 1 <= 0 { beenden() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        #endif
    }

    // MARK: Vorbereitung

    private var beschreibung: LocalizedStringKey {
        switch modus {
        case .schnellquiz: "Fünf Minuten, fällige und prüfungsrelevante Karten zuerst."
        case .themenquiz: "Ein Thema gezielt üben – ohne Zeitlimit."
        case .impp: "Multiple-Choice-Fragen im IMPP-Stil: „Welche Aussage trifft zu?“"
        case .pruefungssimulation: "90 Minuten, gemischte Fragen, Auswertung erst am Ende – wie in der echten Prüfung."
        }
    }

    private func kandidaten() -> [Karteikarte] {
        switch modus {
        case .schnellquiz:
            let faellig = KartenDienst.warteschlange(gueltig)
            let rest = gueltig.filter { karte in !faellig.contains(where: { $0 === karte }) }
                .shuffled()
                .sorted { ($0.prioritaet ? 0 : 1) < ($1.prioritaet ? 0 : 1) }
            return Array((faellig + rest).prefix(20))
        case .themenquiz:
            return gueltig.filter { thema.isEmpty || $0.thema == thema }.shuffled()
        case .impp:
            let mc = gueltig.filter { $0.typ == .multipleChoice }
            return (mc.filter(\.istIMPP).shuffled() + mc.filter { !$0.istIMPP }.shuffled())
        case .pruefungssimulation:
            return Array(gueltig.shuffled().prefix(40))
        }
    }

    private var vorbereitung: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(verbatim: modus.name)
                .font(Thema.display(48))
                .foregroundStyle(Thema.tinte)
            Text(beschreibung)
                .font(Thema.ui(15))
                .foregroundStyle(Thema.tinteSekundaer)
            if modus == .themenquiz {
                Picker("Thema", selection: $thema) {
                    Text("Alle Themen").tag("")
                    ForEach(themen, id: \.self) { t in
                        Text(verbatim: t).tag(t)
                    }
                }
                .frame(maxWidth: 360)
            }
            let anzahl = kandidaten().count
            if anzahl == 0 {
                Text(modus == .impp ? "Noch keine Multiple-Choice-Karten vorhanden. Lege MC-Karten an (z. B. IMPP-Altfragen)." : "Keine passenden Karten vorhanden.")
                    .font(Thema.ui(14))
                    .foregroundStyle(Stoffgebiet.i.farbe)
            } else {
                Aktionskarte(titel: "Starten", untertitel: "\(anzahl) Fragen" + (modus.zeitlimit.map { " · \($0 / 60) min" } ?? "")) {
                    starten(mit: kandidaten())
                }
                .frame(maxWidth: 420)
            }
        }
    }

    private func starten(mit liste: [Karteikarte], modus neuerModus: QuizModus? = nil) {
        fragen = liste
        index = 0
        ergebnisse = [:]
        antworten = [:]
        zuruecksetzen()
        aktuellerModus = neuerModus
        verbleibend = (neuerModus ?? modus).zeitlimit
        start = Date()
        phase = .laeuft
    }

    // MARK: Laufendes Quiz

    @ViewBuilder
    private var laeuft: some View {
        if index < fragen.count {
            let karte = fragen[index]
            let sofort = laufenderModus.sofortRueckmeldung
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Frage \(index + 1) von \(fragen.count)")
                        .font(Thema.ui(13))
                        .foregroundStyle(Thema.tinteSekundaer)
                    Spacer()
                    if let verbleibend {
                        Text(verbatim: String(format: "%d:%02d", max(0, verbleibend) / 60, max(0, verbleibend) % 60))
                            .font(Thema.mono(14))
                            .foregroundStyle(verbleibend < 60 ? Stoffgebiet.i.farbe : Thema.tinte)
                    }
                }
                Fortschrittslinie(wert: Double(index) / Double(max(fragen.count, 1)))

                KartenInhalt(karte: karte,
                             aufgedeckt: karte.typ == .multipleChoice ? (geprueft && sofort) : aufgedeckt,
                             mcAuswahl: karte.typ == .multipleChoice ? $auswahl : nil,
                             mcAufloesen: geprueft && sofort)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Thema.rahmen))

                steuerung(karte, sofort: sofort)
            }
        }
    }

    @ViewBuilder
    private func steuerung(_ karte: Karteikarte, sofort: Bool) -> some View {
        if karte.typ == .multipleChoice {
            if geprueft && sofort {
                let richtig = ergebnisse[karte.kennung] ?? false
                HStack {
                    Text(richtig ? "Richtig." : "Leider falsch – die richtigen Antworten sind markiert.")
                        .font(Thema.ui(14, .mittel))
                        .foregroundStyle(richtig ? Thema.tinte : Stoffgebiet.i.farbe)
                    Spacer()
                    knopf("Weiter", hervorgehoben: true) { weiter() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack {
                    Spacer()
                    knopf("Antwort prüfen", hervorgehoben: true) { mcPruefen(karte, sofort: sofort) }
                        .disabled(auswahl.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        } else if !aufgedeckt {
            HStack {
                Spacer()
                knopf("Aufdecken", hervorgehoben: true) { aufgedeckt = true }
                    .keyboardShortcut(.space, modifiers: [])
            }
        } else {
            HStack(spacing: 12) {
                Spacer()
                knopf("Nicht gewusst", hervorgehoben: false) { selbstbewertung(karte, richtig: false) }
                    .keyboardShortcut("1", modifiers: [])
                knopf("Gewusst", hervorgehoben: true) { selbstbewertung(karte, richtig: true) }
                    .keyboardShortcut("2", modifiers: [])
            }
        }
    }

    private func knopf(_ titel: LocalizedStringKey, hervorgehoben: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(titel)
                .font(Thema.ui(14, .mittel))
                .foregroundStyle(hervorgehoben ? Thema.tinteInvers : Thema.tinte)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(hervorgehoben ? Thema.tinte : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Thema.tinte))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mcPruefen(_ karte: Karteikarte, sofort: Bool) {
        let richtig = auswahl == Set(karte.richtigeOptionen)
        let gewaehlt = auswahl.sorted().map { "\(Karteikarte.buchstabe($0)) \(karte.optionen.indices.contains($0) ? karte.optionen[$0] : "")" }
        erfassen(karte, richtig: richtig, antwort: gewaehlt.joined(separator: "; "))
        geprueft = true
        if !sofort { weiter() }
    }

    private func selbstbewertung(_ karte: Karteikarte, richtig: Bool) {
        erfassen(karte, richtig: richtig, antwort: richtig ? "Gewusst" : "Nicht gewusst")
        weiter()
    }

    private func erfassen(_ karte: Karteikarte, richtig: Bool, antwort: String) {
        ergebnisse[karte.kennung] = richtig
        antworten[karte.kennung] = antwort
        if !richtig {
            KartenDienst.fehlerEintragen(karte, deineAntwort: antwort, herkunft: laufenderModus.name, kontext: kontext)
        }
    }

    private func zuruecksetzen() {
        aufgedeckt = false
        auswahl = []
        geprueft = false
    }

    private func weiter() {
        zuruecksetzen()
        index += 1
        if index >= fragen.count { beenden() }
    }

    private func beenden() {
        guard phase == .laeuft else { return }
        phase = .ergebnis
        let beantwortet = ergebnisse.count
        guard beantwortet > 0 else { return }
        let ergebnis = QuizErgebnis(modus: laufenderModus, fragen: beantwortet,
                                    richtig: ergebnisse.values.filter { $0 }.count,
                                    dauerSekunden: Date().timeIntervalSince(start))
        kontext.insert(ergebnis)
        ergebnis.lehrveranstaltung = lv
    }

    // MARK: Ergebnis

    private struct ThemenErgebnis {
        let thema: String
        let richtig: Int
        let gesamt: Int
    }

    private var ergebnis: some View {
        let beantwortet = fragen.filter { ergebnisse[$0.kennung] != nil }
        let richtig = beantwortet.filter { ergebnisse[$0.kennung] == true }.count
        let falsch = beantwortet.filter { ergebnisse[$0.kennung] == false }
        let dauer = Int(Date().timeIntervalSince(start))
        let nachThema = Dictionary(grouping: beantwortet) { $0.thema.isEmpty ? "Ohne Thema" : $0.thema }
            .map { ThemenErgebnis(thema: $0.key, richtig: $0.value.filter { ergebnisse[$0.kennung] == true }.count, gesamt: $0.value.count) }
            .sorted { Double($0.richtig) / Double($0.gesamt) < Double($1.richtig) / Double($1.gesamt) }

        return VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Kleintitel(text: "Ergebnis")
                GrosseZahl(zahl: "\(richtig)/\(beantwortet.count)",
                           einheit: beantwortet.isEmpty ? "" : "\(Int((Double(richtig) / Double(beantwortet.count) * 100).rounded())) % richtig",
                           groesse: 72)
                Text("Dauer: \(Dauer.text(minuten: max(1, dauer / 60)))" + (beantwortet.count < fragen.count ? " · \(fragen.count - beantwortet.count) Fragen nicht beantwortet" : ""))
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
            }

            if nachThema.count > 1 || (nachThema.first.map { $0.thema != "Ohne Thema" } ?? false) {
                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel(titel: "Nach Thema") { Text("schwächste zuerst") }
                    ForEach(nachThema, id: \.thema) { eintrag in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(verbatim: eintrag.thema).font(Thema.ui(14))
                                Spacer()
                                Text(verbatim: "\(eintrag.richtig)/\(eintrag.gesamt)").font(Thema.mono(12)).foregroundStyle(Thema.tinteSekundaer)
                            }
                            Fortschrittslinie(wert: Double(eintrag.richtig) / Double(eintrag.gesamt))
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) { Haarlinie() }
                    }
                }
            }

            if !falsch.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Abschnittstitel(titel: "Falsch beantwortet") { Text("im Fehlerjournal") }
                    ForEach(falsch) { karte in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: karte.frageText).font(Thema.ui(14)).foregroundStyle(Thema.tinte)
                            Text(verbatim: "Deine Antwort: \(antworten[karte.kennung] ?? "–")")
                                .font(Thema.ui(12)).foregroundStyle(Stoffgebiet.i.farbe)
                            Text(verbatim: "Richtig: \(karte.antwortText)")
                                .font(Thema.ui(12)).foregroundStyle(Thema.tinteSekundaer)
                        }
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Haarlinie() }
                    }
                    Aktionskarte(titel: "Fehler wiederholen", untertitel: "\(falsch.count) Fragen · ohne Zeitlimit") {
                        starten(mit: falsch.shuffled(), modus: .themenquiz)
                    }
                    .frame(maxWidth: 420)
                    .padding(.top, 24)
                }
            }
        }
    }
}
