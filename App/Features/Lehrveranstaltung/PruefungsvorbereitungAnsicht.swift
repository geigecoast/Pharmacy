import SwiftUI
import SwiftData
import PharmaCore

struct PruefungsvorbereitungAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    @Environment(\.modelContext) private var kontext

    var body: some View {
        let teilpruefungen = lv.sortierteTeilpruefungen
        List {
            if lv.anmeldepflicht && lv.status != .bestanden {
                Section {
                    Label(Studienregeln.anmeldeHinweis, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } header: {
                    Text("QIS/LSF-Anmeldung")
                }
            }

            Section {
                if teilpruefungen.isEmpty {
                    Text("Keine Teilprüfungen eingetragen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(teilpruefungen) { tp in
                    TeilpruefungZeile(tp: tp)
                }
                .onDelete { indizes in
                    for index in indizes {
                        kontext.delete(teilpruefungen[index])
                    }
                }
                Menu {
                    ForEach(TeilpruefungTyp.allCases) { typ in
                        Button(typ.name) { hinzufuegen(typ) }
                    }
                } label: {
                    Label("Teilprüfung hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Teilprüfungen")
            }

            Section {
                Text("Altklausuren-Analyse mit Prüfungsprognose und Probeklausuren folgen in Ausbaustufe f.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Altklausuren & Probeklausuren")
            }
        }
    }

    private func hinzufuegen(_ typ: TeilpruefungTyp) {
        let tp = Teilpruefung(typ: typ, anmeldepflichtig: lv.anmeldepflicht,
                              sortierung: (lv.teilpruefungen ?? []).count)
        kontext.insert(tp)
        tp.lehrveranstaltung = lv
    }
}

struct TeilpruefungZeile: View {
    @Bindable var tp: Teilpruefung
    @State private var bearbeiten = false

    var body: some View {
        Button {
            bearbeiten = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tp.typ.symbol)
                    .frame(width: 24)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tp.titel + (tp.anmeldepflichtig ? " *" : ""))
                    if let datum = tp.datum {
                        Text(datum.datumUndUhrzeit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Noch kein Termin eingetragen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !tp.hinweis.isEmpty {
                        Text(tp.hinweis)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if tp.anmeldepflichtig && !tp.angemeldet && tp.ergebnis == .offen {
                        Label("Noch nicht angemeldet", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if tp.ergebnis != .offen {
                    Text(tp.ergebnis.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tp.ergebnis == .bestanden ? Color.green : Color.red)
                } else if let datum = tp.datum {
                    CountdownText(datum: datum)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $bearbeiten) {
            TeilpruefungBearbeiten(tp: tp)
        }
    }
}

struct TeilpruefungBearbeiten: View {
    @Bindable var tp: Teilpruefung
    @Environment(\.dismiss) private var dismiss

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
