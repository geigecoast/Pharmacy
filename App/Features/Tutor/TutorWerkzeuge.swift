import SwiftUI
import SwiftData
import PharmaCore

enum TutorWerkzeug: String, CaseIterable, Identifiable {
    case steckbrief, monographie, rechner

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .steckbrief: "Wirkstoff-Steckbrief"
        case .monographie: "Monographie erklären"
        case .rechner: "Analytik-Rechner"
        }
    }
}

struct TutorWerkzeugAnsicht: View {
    let werkzeug: TutorWerkzeug
    let lv: Lehrveranstaltung?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch werkzeug {
                case .steckbrief:
                    KIWerkzeug(
                        titel: "Wirkstoff-Steckbrief",
                        platzhalter: "Wirkstoff, z. B. Metoprolol",
                        abschnitte: ["Wirkstoffklasse", "Wirkmechanismus", "Indikationen", "UAW", "Kontraindikationen",
                                     "Wechselwirkungen", "Pharmakokinetik", "Merkhilfe"],
                        lv: lv,
                        auftrag: { stoff in
                            """
                            Erstelle einen prüfungsorientierten Wirkstoff-Steckbrief zu „\(stoff)“. Beginne mit einem Satz zur Einordnung. \
                            Danach genau diese Abschnitte als Überschriften (### …), jeweils knapp in Stichpunkten: \
                            Wirkstoffklasse, Wirkmechanismus, Indikationen, UAW, Kontraindikationen, Wechselwirkungen, Pharmakokinetik, Merkhilfe.
                            """
                        },
                        kartenFrage: { stoff, abschnitt in "\(abschnitt) von \(stoff)?" }
                    )
                case .monographie:
                    KIWerkzeug(
                        titel: "Monographie erklären",
                        platzhalter: "Arzneistoff, z. B. Acetylsalicylsäure",
                        abschnitte: ["Identität", "Reinheit", "Gehalt", "Merksatz"],
                        lv: lv,
                        auftrag: { stoff in
                            """
                            Erkläre die Ph.-Eur.-Monographie von „\(stoff)“ für das Praktikum Arzneistoffanalytik. Beginne mit 2–3 Sätzen \
                            zur Struktur und den analytisch relevanten funktionellen Gruppen. Danach genau diese Abschnitte (### …): \
                            Identität (welche Prüfungen und warum), Reinheit (typische Verunreinigungen, Grenzprüfungen), \
                            Gehalt (Methode, Reaktionsgleichung, Äquivalent „1 ml Maßlösung entspricht … mg“ mit Herleitung), Merksatz. \
                            Kennzeichne, wenn du dir bei Details der aktuellen Ph.-Eur.-Fassung nicht sicher bist.
                            """
                        },
                        kartenFrage: { stoff, abschnitt in "\(abschnitt) – \(stoff) nach Ph. Eur.?" }
                    )
                case .rechner:
                    AnalytikRechner()
                }
            }
            .background(Thema.flaeche)
            .navigationTitle(werkzeug.titel)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        #endif
    }
}

/// Werkzeug mit Eingabe, KI-Antwort in Abschnitten und „Als Karteikarten speichern“.
private struct KIWerkzeug: View {
    let titel: String
    let platzhalter: String
    let abschnitte: [String]
    let lv: Lehrveranstaltung?
    let auftrag: (String) -> String
    let kartenFrage: (String, String) -> String

    @Environment(\.modelContext) private var kontext
    @State private var eingabe = ""
    @State private var thema = ""
    @State private var text = ""
    @State private var laeuft = false
    @State private var fehler: String?
    @State private var gespeichert = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(verbatim: titel)
                    .font(Thema.display(40))
                    .foregroundStyle(Thema.tinte)
                HStack(spacing: 10) {
                    TextField(platzhalter, text: $eingabe)
                        .textFieldStyle(.plain)
                        .font(Thema.serif(22))
                        .onSubmit { erstellen() }
                    Button {
                        erstellen()
                    } label: {
                        Text(laeuft ? "Erstellt …" : "Erstellen")
                            .font(Thema.ui(13, .mittel))
                            .foregroundStyle(Thema.tinteInvers)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Thema.tinte, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(laeuft || eingabe.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Haarlinie(farbe: Thema.tinte)
                if let fehler {
                    Text(verbatim: fehler).font(Thema.ui(13)).foregroundStyle(Stoffgebiet.i.farbe)
                }
                if laeuft && text.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Wird erstellt …").font(Thema.ui(13)).foregroundStyle(Thema.tinteSekundaer)
                    }
                }
                if !text.isEmpty {
                    StrukturierteAntwort(text: text, abschnittTitel: abschnitte, hauptSchrift: Thema.serif(18))
                    if !laeuft, lv != nil {
                        Button(gespeichert > 0 ? "\(gespeichert) Karteikarten gespeichert" : "Als Karteikarten speichern") {
                            kartenSpeichern()
                        }
                        .buttonStyle(.plain)
                        .font(Thema.ui(13, .mittel))
                        .underline()
                        .disabled(gespeichert > 0)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(40)
        }
    }

    private func erstellen() {
        let stoff = eingabe.trimmingCharacters(in: .whitespaces)
        guard !stoff.isEmpty, !laeuft else { return }
        guard KI.istEingerichtet else {
            fehler = KIFehler.keinSchluessel.errorDescription
            return
        }
        thema = stoff
        text = ""
        fehler = nil
        gespeichert = 0
        laeuft = true
        let anfrage = KIAnfrage(modell: KI.modell, system: KIAnweisungen.basis + KIAnweisungen.kontext(lv),
                                nachrichten: [KINachricht(rolle: .nutzer, text: auftrag(stoff))], maxTokens: 8_000, aufwand: .mittel)
        Task {
            do {
                _ = try await KI.vollstaendig(anfrage) { teil in text = teil }
            } catch {
                fehler = error.localizedDescription
            }
            laeuft = false
        }
    }

    private func kartenSpeichern() {
        guard let lv else { return }
        let zerlegt = Antwortstruktur.zerlegen(text, titel: abschnitte)
        for abschnitt in zerlegt.abschnitte where !abschnitt.text.isEmpty {
            let karte = Karteikarte(typ: .frageAntwort, vorderseite: kartenFrage(thema, abschnitt.titel),
                                    rueckseite: abschnitt.text.replacingOccurrences(of: "**", with: ""), thema: thema)
            karte.quelle = .ki
            kontext.insert(karte)
            karte.lehrveranstaltung = lv
            gespeichert += 1
        }
    }
}

/// Titrations-, Verdünnungs- und Lösungsrechner (lokal, ohne KI).
private struct AnalytikRechner: View {
    private enum Art: String, CaseIterable, Identifiable {
        case titration, verduennung, loesung
        var id: String { rawValue }
        var name: String {
            switch self {
            case .titration: "Gehaltsbestimmung"
            case .verduennung: "Verdünnung"
            case .loesung: "Lösung herstellen"
            }
        }
    }

    @State private var art: Art = .titration
    // Titration
    @State private var verbrauch = ""
    @State private var blindwert = ""
    @State private var faktor = "1"
    @State private var aequivalent = ""
    @State private var einwaage = ""
    @State private var molaritaet = ""
    @State private var molareMasse = ""
    @State private var z = "1"
    // Verdünnung
    @State private var c1 = ""
    @State private var v1 = ""
    @State private var c2 = ""
    @State private var v2 = ""
    // Lösung
    @State private var lMolaritaet = ""
    @State private var lVolumen = ""
    @State private var lMasse = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Segmentleiste(werte: Art.allCases, auswahl: $art) { $0.name }
                    .frame(maxWidth: 520)
                switch art {
                case .titration: titration
                case .verduennung: verduennung
                case .loesung: loesung
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(40)
        }
    }

    private func feld(_ titel: LocalizedStringKey, _ text: Binding<String>, einheit: String) -> some View {
        Wertzeile(titel: titel) {
            HStack(spacing: 6) {
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(Thema.mono(14))
                    .frame(width: 120)
                Text(verbatim: einheit).font(Thema.ui(12)).frame(width: 52, alignment: .leading)
            }
        }
    }

    private func ergebnis(_ titel: LocalizedStringKey, _ wert: String, erklaerung: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kleintitel(text: titel)
            Text(verbatim: wert)
                .font(Thema.display(48))
                .foregroundStyle(Thema.tinte)
            Text(verbatim: erklaerung)
                .font(Thema.mono(12))
                .foregroundStyle(Thema.tinteSekundaer)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var titration: some View {
        VStack(alignment: .leading, spacing: 0) {
            feld("Verbrauch Maßlösung", $verbrauch, einheit: "ml")
            feld("Blindwert", $blindwert, einheit: "ml")
            feld("Faktor (Titer)", $faktor, einheit: "")
            feld("1 ml Maßlösung entspricht", $aequivalent, einheit: "mg")
            feld("Einwaage", $einwaage, einheit: "mg")
        }
        VStack(alignment: .leading, spacing: 0) {
            Kleintitel(text: "Äquivalent berechnen (optional)")
            feld("Molarität der Maßlösung", $molaritaet, einheit: "mol/l")
            feld("Molare Masse des Arzneistoffs", $molareMasse, einheit: "g/mol")
            feld("Stöchiometrischer Faktor z", $z, einheit: "")
            if let m = Dezimal.lesen(molaritaet), let mm = Dezimal.lesen(molareMasse),
               let wert = Analytikrechner.aequivalentMG(molaritaet: m, molareMasse: mm, z: Dezimal.lesen(z) ?? 1) {
                HStack {
                    Text("1 ml entspricht \(Dezimal.text(wert, stellen: 3)) mg")
                        .font(Thema.ui(13))
                    Spacer()
                    Button("Übernehmen") { aequivalent = Dezimal.text(wert, stellen: 3) }
                        .buttonStyle(.plain)
                        .underline()
                }
                .padding(.vertical, 14)
            }
        }
        if let v = Dezimal.lesen(verbrauch), let f = Dezimal.lesen(faktor), let a = Dezimal.lesen(aequivalent),
           let e = Dezimal.lesen(einwaage),
           let gehalt = Analytikrechner.gehaltProzent(verbrauchML: v, faktor: f, aequivalentMG: a, einwaageMG: e,
                                                       blindwertML: Dezimal.lesen(blindwert) ?? 0) {
            ergebnis("Gehalt", "\(Dezimal.text(gehalt, stellen: 2)) %",
                     erklaerung: "(\(Dezimal.text(v)) − \(Dezimal.text(Dezimal.lesen(blindwert) ?? 0))) ml × \(Dezimal.text(f, stellen: 4)) × \(Dezimal.text(a, stellen: 3)) mg/ml ÷ \(Dezimal.text(e)) mg × 100")
            if let soll = Analytikrechner.sollverbrauchML(einwaageMG: e, sollProzent: 100, faktor: f, aequivalentMG: a) {
                Text("Erwarteter Verbrauch bei 100 %: \(Dezimal.text(soll, stellen: 2)) ml")
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
        }
    }

    @ViewBuilder
    private var verduennung: some View {
        Text("Drei Werte eintragen, der vierte wird berechnet (c₁ · V₁ = c₂ · V₂).")
            .font(Thema.ui(13))
            .foregroundStyle(Thema.tinteSekundaer)
        VStack(alignment: .leading, spacing: 0) {
            feld("Konzentration c₁ (Stammlösung)", $c1, einheit: "")
            feld("Volumen V₁ (Stammlösung)", $v1, einheit: "ml")
            feld("Konzentration c₂ (Ziel)", $c2, einheit: "")
            feld("Volumen V₂ (Ziel)", $v2, einheit: "ml")
        }
        let werte = [Dezimal.lesen(c1), Dezimal.lesen(v1), Dezimal.lesen(c2), Dezimal.lesen(v2)]
        if werte.filter({ $0 == nil }).count == 1,
           let wert = Konzentrationsrechner.verduennung(c1: werte[0], v1: werte[1], c2: werte[2], v2: werte[3]) {
            let name = ["c₁", "V₁", "c₂", "V₂"][werte.firstIndex(where: { $0 == nil }) ?? 0]
            ergebnis("Ergebnis", "\(name) = \(Dezimal.text(wert, stellen: 4))", erklaerung: "c₁ · V₁ = c₂ · V₂")
        }
    }

    @ViewBuilder
    private var loesung: some View {
        VStack(alignment: .leading, spacing: 0) {
            feld("Gewünschte Molarität", $lMolaritaet, einheit: "mol/l")
            feld("Volumen", $lVolumen, einheit: "ml")
            feld("Molare Masse", $lMasse, einheit: "g/mol")
        }
        if let c = Dezimal.lesen(lMolaritaet), let v = Dezimal.lesen(lVolumen), let m = Dezimal.lesen(lMasse) {
            let masse = Konzentrationsrechner.masseMG(molaritaet: c, volumenML: v, molareMasse: m)
            ergebnis("Einwaage", "\(Dezimal.text(masse, stellen: 2)) mg",
                     erklaerung: "\(Dezimal.text(c, stellen: 4)) mol/l × \(Dezimal.text(v)) ml × \(Dezimal.text(m)) g/mol")
            if let prozent = Konzentrationsrechner.prozentMV(masseG: masse / 1000, volumenML: v) {
                Text("entspricht \(Dezimal.text(prozent, stellen: 3)) % (m/V)")
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
        }
    }
}
