import SwiftUI
import SwiftData
import PharmaCore

/// Probeklausur: einrichten → bearbeiten (mit Zeit) → korrigieren → Auswertung mit Schwächenanalyse.
struct ProbeklausurSitzung: View {
    let lv: Lehrveranstaltung

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var kontext

    private enum Phase { case einrichten, erstellen, laeuft, korrigieren, ergebnis }

    @State private var phase: Phase
    @State private var klausur: Probeklausur?
    @State private var teilpruefung: Teilpruefung?
    @State private var dauer = 60
    @State private var anzahl = 10
    @State private var index = 0
    @State private var antworten: [Int: String] = [:]
    @State private var verbleibend: Int?
    @State private var fehler: String?
    @State private var zeigeAbgabe = false

    init(lv: Lehrveranstaltung, vorhanden: Probeklausur? = nil) {
        self.lv = lv
        _klausur = State(initialValue: vorhanden)
        _antworten = State(initialValue: vorhanden?.antworten ?? [:])
        if let vorhanden {
            _phase = State(initialValue: vorhanden.abgegebenAm == nil ? .laeuft : .ergebnis)
        } else {
            _phase = State(initialValue: .einrichten)
        }
        let naechste = lv.naechsteTeilpruefung ?? lv.sortierteTeilpruefungen.first { $0.typ != .praktischerTeil && $0.ergebnis == .offen }
        _teilpruefung = State(initialValue: naechste)
        let muendlicheTypen: [TeilpruefungTyp] = [.muendlicheEingangspruefung, .muendlicheAbschlusspruefung, .abschlusskolloquium]
        let muendlich = naechste.map { muendlicheTypen.contains($0.typ) } ?? false
        _dauer = State(initialValue: vorhanden?.dauerMinuten ?? (muendlich ? 20 : 60))
        _anzahl = State(initialValue: muendlich ? 6 : 10)
    }

    private var fragen: [PKFrage] { klausur?.fragen ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch phase {
                    case .einrichten: einrichten
                    case .erstellen: arbeitet("Die Probeklausur wird erstellt – aus Prognose, Altfragen und deinen Unterlagen …")
                    case .laeuft: laeuft
                    case .korrigieren: arbeitet("Deine Antworten werden korrigiert …")
                    case .ergebnis: ergebnis
                    }
                }
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(40)
            }
            .background(Thema.flaeche)
            .navigationTitle(klausur?.titel ?? "Probeklausur")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .laeuft ? "Unterbrechen" : "Schließen") { dismiss() }
                        .help(phase == .laeuft ? "Antworten bleiben gespeichert – du kannst später weitermachen" : "")
                }
                if phase == .laeuft {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Abgeben") { zeigeAbgabe = true }
                    }
                }
            }
            .confirmationDialog("Probeklausur abgeben?", isPresented: $zeigeAbgabe, titleVisibility: .visible) {
                Button("Abgeben") { abgeben() }
                Button("Weiter bearbeiten", role: .cancel) {}
            } message: {
                let offen = fragen.filter { (antworten[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
                Text(offen == 0 ? "Alle Fragen sind beantwortet." : "\(offen) Fragen sind noch unbeantwortet.")
            }
        }
        .task(id: phase == .laeuft) {
            guard phase == .laeuft else { return }
            if verbleibend == nil, let klausur {
                verbleibend = klausur.dauerMinuten * 60
            }
            while !Task.isCancelled, phase == .laeuft {
                try? await Task.sleep(for: .seconds(1))
                guard phase == .laeuft, let rest = verbleibend else { return }
                verbleibend = rest - 1
                if rest - 1 <= 0 { abgeben() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 680)
        #endif
    }

    // MARK: Einrichten

    private var einrichten: some View {
        let prognose = PruefungsKI.prognose(lv)
        return VStack(alignment: .leading, spacing: 26) {
            Text("Probeklausur")
                .font(Thema.display(48))
                .foregroundStyle(Thema.tinte)
            Text("Zeitgesteuert und im Stil der echten Prüfung – erstellt aus deiner Prüfungsprognose, den Altfragen und deinen Unterlagen. Multiple Choice und Rechenaufgaben werden sofort korrigiert, offene Antworten von der KI anhand einer Musterlösung.")
                .font(Thema.ui(14))
                .foregroundStyle(Thema.tinteSekundaer)
                .lineSpacing(4)
            VStack(alignment: .leading, spacing: 0) {
                Wertzeile(titel: "Teilprüfung") {
                    Picker("Teilprüfung", selection: $teilpruefung) {
                        Text("Allgemein").tag(Teilpruefung?.none)
                        ForEach(lv.sortierteTeilpruefungen.filter { $0.typ != .praktischerTeil }) { tp in
                            Text(verbatim: tp.titel).tag(Teilpruefung?.some(tp))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Wertzeile(titel: "Bearbeitungszeit") {
                    Stepper(value: $dauer, in: 10...180, step: 10) {
                        Text("\(dauer) min").font(Thema.mono(13))
                    }
                    .fixedSize()
                }
                Wertzeile(titel: "Anzahl Fragen") {
                    Stepper(value: $anzahl, in: 4...30) {
                        Text("\(anzahl)").font(Thema.mono(13))
                    }
                    .fixedSize()
                }
                Wertzeile(titel: "Grundlage") {
                    Text(prognose.isEmpty ? "Unterlagen (noch keine Prognose)" : "Prognose mit \(prognose.count) Themen")
                }
            }
            if let fehler {
                Text(verbatim: fehler).font(Thema.ui(13)).foregroundStyle(Stoffgebiet.i.farbe)
            }
            Aktionskarte(titel: "Probeklausur erstellen", untertitel: "\(anzahl) Fragen · \(dauer) min · per KI") {
                erstellen()
            }
            .frame(maxWidth: 420)
        }
    }

    private func arbeitet(_ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
            Text(text).font(Thema.ui(14)).foregroundStyle(Thema.tinteSekundaer)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func erstellen() {
        guard KI.istEingerichtet else {
            fehler = KIFehler.keinSchluessel.errorDescription
            return
        }
        fehler = nil
        phase = .erstellen
        Task {
            do {
                let neu = try await PruefungsKI.probeklausurErstellen(lv, teilpruefung: teilpruefung, dauer: dauer, anzahl: anzahl, kontext: kontext)
                klausur = neu
                antworten = [:]
                index = 0
                verbleibend = dauer * 60
                phase = neu.fragen.isEmpty ? .einrichten : .laeuft
                if neu.fragen.isEmpty { fehler = KIFehler.unlesbareAntwort.errorDescription }
            } catch {
                fehler = error.localizedDescription
                phase = .einrichten
            }
        }
    }

    // MARK: Bearbeiten

    @ViewBuilder
    private var laeuft: some View {
        if fragen.indices.contains(index) {
            let frage = fragen[index]
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Frage \(index + 1) von \(fragen.count)")
                        .font(Thema.ui(13))
                        .foregroundStyle(Thema.tinteSekundaer)
                    Spacer()
                    if let verbleibend {
                        Text(verbatim: String(format: "%d:%02d", max(0, verbleibend) / 60, max(0, verbleibend) % 60))
                            .font(Thema.mono(15))
                            .foregroundStyle(verbleibend < 300 ? Stoffgebiet.i.farbe : Thema.tinte)
                    }
                }
                fragenleiste
                VStack(alignment: .leading, spacing: 18) {
                    Text(verbatim: "\(frage.typ.name) · \(Dezimal.text(frage.punkte, stellen: 1)) Punkte" + (frage.thema.isEmpty ? "" : " · \(frage.thema)"))
                        .textCase(.uppercase)
                        .font(Thema.ui(11))
                        .tracking(0.8)
                        .foregroundStyle(Thema.tinteTertiaer)
                    Text(verbatim: frage.text)
                        .font(Thema.serif(23))
                        .foregroundStyle(Thema.tinte)
                        .fixedSize(horizontal: false, vertical: true)
                    eingabe(frage)
                }
                .padding(30)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Thema.rahmen))
                HStack {
                    Button("Zurück") { index = max(0, index - 1) }
                        .disabled(index == 0)
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                    Spacer()
                    if index < fragen.count - 1 {
                        Button("Weiter") { index += 1 }
                            .keyboardShortcut(.rightArrow, modifiers: .command)
                    } else {
                        Button("Abgeben") { zeigeAbgabe = true }
                    }
                }
                .buttonStyle(.plain)
                .font(Thema.ui(14, .mittel))
                .underline()
            }
        }
    }

    private var fragenleiste: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(fragen.indices, id: \.self) { i in
                    let beantwortet = !(antworten[fragen[i].id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                    Button {
                        index = i
                    } label: {
                        Text(verbatim: "\(i + 1)")
                            .font(Thema.mono(11))
                            .foregroundStyle(beantwortet ? Thema.tinteInvers : Thema.tinte)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(beantwortet ? Thema.tinte : Color.clear))
                            .overlay(Circle().strokeBorder(i == index ? Thema.tinte : Thema.rahmen, lineWidth: i == index ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func antwortBinding(_ frage: PKFrage) -> Binding<String> {
        Binding(
            get: { antworten[frage.id] ?? "" },
            set: { neu in
                antworten[frage.id] = neu
                klausur?.antworten = antworten
            }
        )
    }

    @ViewBuilder
    private func eingabe(_ frage: PKFrage) -> some View {
        switch frage.typ {
        case .mc:
            let auswahl = Set((antworten[frage.id] ?? "").split(separator: ",").compactMap { Int($0) })
            VStack(spacing: 8) {
                ForEach(Array(frage.optionen.enumerated()), id: \.offset) { i, option in
                    Button {
                        var neu = auswahl
                        if neu.contains(i) { neu.remove(i) } else { neu.insert(i) }
                        antwortBinding(frage).wrappedValue = neu.sorted().map(String.init).joined(separator: ",")
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: Karteikarte.buchstabe(i)).font(Thema.mono(13)).foregroundStyle(Thema.tinteSekundaer)
                            Text(verbatim: option).font(Thema.ui(15)).foregroundStyle(Thema.tinte).multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(auswahl.contains(i) ? Thema.auswahl : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(auswahl.contains(i) ? Thema.tinte : Thema.rahmen))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .rechnung:
            HStack(spacing: 10) {
                TextField("Ergebnis", text: antwortBinding(frage))
                    .textFieldStyle(.plain)
                    .font(Thema.mono(18))
                    .frame(maxWidth: 220)
                Text(verbatim: frage.einheit).font(Thema.ui(14)).foregroundStyle(Thema.tinteSekundaer)
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Thema.rahmen))
            Text("Rechenweg gern im Kopf oder auf Papier – bewertet wird das Ergebnis (Toleranz 2 %).")
                .font(Thema.ui(11))
                .foregroundStyle(Thema.tinteTertiaer)
        default:
            TextField(frage.typ == .muendlich ? "Antworte so, wie du es in der mündlichen Prüfung sagen würdest …"
                      : (frage.typ == .struktur ? "Beschreibe Struktur bzw. Mechanismus in Worten (Gruppen, Bindungen, Schritte) …" : "Deine Antwort …"),
                      text: antwortBinding(frage), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Thema.ui(15))
                .lineLimit(5...16)
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Thema.rahmen))
        }
    }

    private func abgeben() {
        guard let klausur, phase == .laeuft else { return }
        klausur.antworten = antworten
        phase = .korrigieren
        Task {
            do {
                try await PruefungsKI.bewerten(klausur, kontext: kontext)
                phase = .ergebnis
            } catch {
                fehler = error.localizedDescription
                phase = .ergebnis
            }
        }
    }

    // MARK: Ergebnis

    private func themenWerte(_ bewertungen: [Int: PKBewertung]) -> [ThemenWert] {
        var erreicht: [String: Double] = [:]
        var gesamt: [String: Double] = [:]
        for frage in fragen {
            let thema: String = frage.thema.isEmpty ? "Ohne Thema" : frage.thema
            let punkte: Double = bewertungen[frage.id]?.punkte ?? 0
            erreicht[thema, default: 0] += punkte
            gesamt[thema, default: 0] += frage.punkte
        }
        var werte: [ThemenWert] = []
        for (thema, summe) in gesamt {
            werte.append(ThemenWert(thema: thema, erreicht: erreicht[thema] ?? 0, gesamt: summe))
        }
        return werte.sorted { (a: ThemenWert, b: ThemenWert) -> Bool in
            a.anteil < b.anteil
        }
    }

    @ViewBuilder
    private var ergebnis: some View {
        if let klausur {
            ErgebnisAnsicht(klausur: klausur, fragen: fragen, themen: themenWerte(klausur.bewertungen), fehler: fehler)
        }
    }
}

private struct ThemenWert: Identifiable {
    let thema: String
    let erreicht: Double
    let gesamt: Double
    var id: String { thema }
    var anteil: Double { gesamt > 0 ? erreicht / gesamt : 0 }
}

private struct ErgebnisAnsicht: View {
    let klausur: Probeklausur
    let fragen: [PKFrage]
    let themen: [ThemenWert]
    let fehler: String?

    private var punkteText: String {
        let erreicht: String = Dezimal.text(klausur.punkteErreicht, stellen: 1)
        let gesamt: String = Dezimal.text(klausur.punkteGesamt, stellen: 1)
        return "\(erreicht)/\(gesamt)"
    }

    private var einheitText: String {
        let prozent: Int = Int(klausur.prozent.rounded())
        return "Punkte · \(prozent) %"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Kleintitel(text: "Ergebnis")
                GrosseZahl(zahl: punkteText, einheit: einheitText, groesse: 64)
                Text("Orientierungsnote \(Klausurbewertung.note(prozent: klausur.prozent)) – die tatsächliche Bewertung legt die Prüfung fest.")
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
                if let fehler {
                    Text(verbatim: fehler).font(Thema.ui(13)).foregroundStyle(Stoffgebiet.i.farbe)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Abschnittstitel(titel: "Schwächenanalyse") { Text("schwächste Themen zuerst") }
                ForEach(themen) { wert in
                    ThemenZeile(wert: wert)
                }
                Text("Schwach beantwortete Fragen stehen jetzt im Fehlerjournal.")
                    .font(Thema.ui(11))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 0) {
                Abschnittstitel("Fragen im Einzelnen")
                ForEach(fragen) { frage in
                    FragenAuswertungZeile(frage: frage,
                                          bewertung: klausur.bewertungen[frage.id],
                                          antwort: klausur.antworten[frage.id] ?? "")
                }
            }
        }
    }
}

private struct ThemenZeile: View {
    let wert: ThemenWert

    var body: some View {
        let text: String = Dezimal.text(wert.erreicht, stellen: 1) + "/" + Dezimal.text(wert.gesamt, stellen: 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: wert.thema).font(Thema.ui(14))
                Spacer()
                Text(verbatim: text)
                    .font(Thema.mono(12)).foregroundStyle(Thema.tinteSekundaer)
            }
            Fortschrittslinie(wert: wert.anteil)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}

private struct FragenAuswertungZeile: View {
    let frage: PKFrage
    let bewertung: PKBewertung?
    let antwort: String

    private var erreicht: Double { bewertung?.punkte ?? 0 }
    private var voll: Bool { erreicht >= frage.punkte }
    private var punkteText: String {
        Dezimal.text(erreicht, stellen: 1) + "/" + Dezimal.text(frage.punkte, stellen: 1)
    }
    private var titel: String { "\(frage.id + 1). \(frage.text)" }
    private var antwortText: String { "Deine Antwort: " + PruefungsKI.antwortText(frage, antwort) }

    var body: some View {
        let farbe: Color = voll ? Thema.tinte : Stoffgebiet.i.farbe
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: titel).font(Thema.ui(14)).foregroundStyle(Thema.tinte)
                Spacer(minLength: 12)
                Text(verbatim: punkteText)
                    .font(Thema.mono(12))
                    .foregroundStyle(farbe)
            }
            Text(verbatim: antwortText)
                .font(Thema.ui(12)).foregroundStyle(Thema.tinteSekundaer)
            if let bewertung {
                Text(verbatim: bewertung.rueckmeldung).font(Thema.ui(12)).foregroundStyle(Thema.tinte)
            }
            DisclosureGroup("Musterlösung") {
                MarkdownText(text: frage.musterloesung, schrift: Thema.ui(12))
                    .padding(.top, 6)
            }
            .font(Thema.ui(12))
            .foregroundStyle(Thema.tinteSekundaer)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}
