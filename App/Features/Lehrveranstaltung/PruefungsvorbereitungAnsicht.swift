import SwiftUI
import SwiftData
import PharmaCore

struct PruefungsvorbereitungAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    @Environment(\.modelContext) private var kontext

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if geo.size.width > 860 {
                    HStack(alignment: .top, spacing: 56) {
                        teilpruefungen.frame(maxWidth: 420)
                        prognose.frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 36)
                } else {
                    VStack(alignment: .leading, spacing: 44) {
                        teilpruefungen
                        prognose
                    }
                    .padding(.vertical, 36)
                }
            }
        }
    }

    private var teilpruefungen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel(titel: "Teilprüfungen") {
                Menu {
                    ForEach(TeilpruefungTyp.allCases) { typ in
                        Button(typ.name) { hinzufuegen(typ) }
                    }
                } label: {
                    Text("Hinzufügen")
                        .underline()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            let liste = lv.sortierteTeilpruefungen
            if liste.isEmpty {
                Text("Keine Teilprüfungen eingetragen.")
                    .font(Thema.ui(14))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .padding(.vertical, 20)
            }
            ForEach(liste) { tp in
                TeilpruefungZeile(tp: tp) {
                    kontext.delete(tp)
                }
            }
            if lv.anmeldepflicht && lv.status != .bestanden {
                Text(Studienregeln.anmeldeHinweis)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .lineSpacing(3)
                    .padding(.top, 18)
            }
            Aktionskarte(titel: "Probeklausur starten", untertitel: "Zeitgesteuert im Stil der echten Prüfung · ab Ausbaustufe f") {}
                .opacity(0.35)
                .disabled(true)
                .padding(.top, 28)
        }
    }

    private var prognose: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel(titel: "Prüfungsprognose") {
                Text("Basis: noch keine Altklausuren")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Importiere Altklausuren, Probeklausuren, Altfragen und Notizen dazu, was der Prüfer betont hat. Daraus entsteht eine Prognose in drei Stufen – mit Begründung, Datenbasis und Verweis auf die passenden Folien.")
                    .font(Thema.ui(14))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .lineSpacing(4)
                HStack(spacing: 18) {
                    ForEach(["Sehr wahrscheinlich", "Wahrscheinlich", "Möglich"].indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { punkt in
                                    Circle()
                                        .fill(punkt < 3 - index ? Thema.tinte : Thema.rahmen)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            Text(verbatim: ["Sehr wahrscheinlich", "Wahrscheinlich", "Möglich"][index])
                                .font(Thema.ui(12))
                                .foregroundStyle(Thema.tinteSekundaer)
                        }
                    }
                }
                .padding(.top, 4)
                Text("Die Altklausuren-Analyse folgt in Ausbaustufe f.")
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteTertiaer)
            }
            .padding(.vertical, 20)
            Haarlinie()
            Text("Prognosen beruhen auf Häufigkeit, Aktualität und Punktgewichtung. Keine Garantie.")
                .font(Thema.ui(11))
                .foregroundStyle(Thema.tinteTertiaer)
                .padding(.top, 14)
        }
    }

    private func hinzufuegen(_ typ: TeilpruefungTyp) {
        let tp = Teilpruefung(typ: typ, anmeldepflichtig: lv.anmeldepflicht,
                              sortierung: (lv.teilpruefungen ?? []).count)
        kontext.insert(tp)
        tp.lehrveranstaltung = lv
    }
}

/// Teilprüfung: Name (* = anmeldepflichtig), Termin, Countdown „12 T“, Bereitschaftslinie.
struct TeilpruefungZeile: View {
    @Bindable var tp: Teilpruefung
    var loeschen: () -> Void = {}
    @State private var bearbeiten = false

    private var bereitschaft: Double {
        guard tp.lernaufwandMinuten > 0 else { return 0 }
        let erledigt = (tp.lerneinheiten ?? []).filter(\.erledigt).reduce(0) { $0 + $1.dauerMinuten }
        return min(1, Double(erledigt) / Double(tp.lernaufwandMinuten))
    }

    private var terminzeile: String {
        if let datum = tp.datum {
            var text = datum.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).hour().minute().locale(.deutsch))
            if let ende = tp.ende, ende > datum { text += " – " + ende.kurzesDatum }
            return text
        }
        return tp.hinweis.isEmpty ? "Noch kein Termin eingetragen" : tp.hinweis
    }

    var body: some View {
        Button {
            bearbeiten = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: tp.titel + (tp.anmeldepflichtig ? " *" : ""))
                        .font(Thema.ui(14))
                        .foregroundStyle(tp.ergebnis == .offen ? Thema.tinte : Thema.tinteTertiaer)
                    Spacer(minLength: 12)
                    Group {
                        if tp.ergebnis != .offen {
                            Text(verbatim: tp.ergebnis.name)
                        } else if let datum = tp.datum {
                            Text(verbatim: "\(max(0, Countdown.tage(bis: datum))) T")
                        } else {
                            Text(verbatim: "–")
                        }
                    }
                    .font(Thema.mono(12))
                    .foregroundStyle(Thema.tinteSekundaer)
                }
                Text(verbatim: terminzeile)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .padding(.top, 5)
                if tp.anmeldepflichtig && !tp.angemeldet && tp.ergebnis == .offen {
                    Text("Noch nicht im QIS/LSF angemeldet")
                        .font(Thema.ui(11))
                        .foregroundStyle(Stoffgebiet.i.farbe)
                        .padding(.top, 4)
                }
                Fortschrittslinie(wert: bereitschaft)
                    .padding(.top, 14)
            }
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Haarlinie() }
        .contextMenu {
            Button("Bearbeiten …") { bearbeiten = true }
            Button("Löschen", role: .destructive, action: loeschen)
        }
        .help("Bereitschaft: erledigte Lernzeit im Verhältnis zum Lernaufwand")
        .sheet(isPresented: $bearbeiten) {
            TeilpruefungBearbeiten(tp: tp)
        }
    }
}

struct TeilpruefungBearbeiten: View {
    @Bindable var tp: Teilpruefung
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var kontext

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $tp.typ) {
                        ForEach(TeilpruefungTyp.allCases) { typ in
                            Text(typ.name).tag(typ)
                        }
                    }
                    TextField("Bezeichnung (optional)", text: $tp.bezeichnung)
                    TextField("Ort", text: $tp.ort)
                }
                Section("Termin") {
                    OptionalesDatum(titel: Text("Termin bekannt"), datum: $tp.datum, mitUhrzeit: true)
                    OptionalesDatum(titel: Text("Ende (z. B. Blockpraktikum)"), datum: $tp.ende)
                }
                Section("Anmeldung") {
                    Toggle("Anmeldepflichtig im QIS/LSF (*)", isOn: $tp.anmeldepflichtig)
                    if tp.anmeldepflichtig {
                        Toggle("Angemeldet", isOn: $tp.angemeldet)
                        OptionalesDatum(titel: Text("Anmeldeschluss"), datum: $tp.anmeldeschluss)
                    }
                }
                Section {
                    Stepper(value: Binding(
                        get: { tp.effektiverLernaufwandStunden },
                        set: { tp.lernaufwandStunden = $0 }
                    ), in: 0...200, step: 1) {
                        Text("Lernaufwand: \(Int(tp.effektiverLernaufwandStunden)) Stunden")
                    }
                    if tp.lernaufwandStunden != nil {
                        Button("Auf Standardwert zurücksetzen") { tp.lernaufwandStunden = nil }
                    }
                } header: {
                    Text("Lernplan")
                } footer: {
                    Text("Der Lernplan verteilt diesen Aufwand auf die Tage vor der Prüfung.")
                }
                Section("Ergebnis") {
                    Picker("Ergebnis", selection: $tp.ergebnis) {
                        ForEach(PruefungsErgebnis.allCases) { ergebnis in
                            Text(ergebnis.name).tag(ergebnis)
                        }
                    }
                    TextField("Note", text: $tp.note)
                }
                Section("Hinweis") {
                    TextField("Hinweis", text: $tp.hinweis, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Teilprüfung")
            .onDisappear {
                LernplanDienst.aktualisieren(kontext)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }
}
