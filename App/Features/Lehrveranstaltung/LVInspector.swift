import SwiftUI
import SwiftData
import PharmaCore

/// Bearbeitbare Stammdaten einer Lehrveranstaltung.
struct LVInspector: View {
    @Bindable var lv: Lehrveranstaltung
    var beiLoeschen: () -> Void

    @Environment(\.modelContext) private var kontext
    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @Query private var alleLVs: [Lehrveranstaltung]
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true
    @State private var zeigeLoeschen = false

    var body: some View {
        Form {
            Section("Allgemein") {
                TextField("Lfd. Nr.", text: $lv.lfdNr)
                TextField("Bezeichnung", text: $lv.bezeichnung, axis: .vertical)
                Picker("Lehrform", selection: $lv.lehrform) {
                    ForEach(Lehrform.allCases) { form in
                        Text(verbatim: "\(form.kuerzel) – \(form.name)").tag(form)
                    }
                }
                TextField("SWS", text: $lv.sws)
                TextField("Leistungsnachweis (LN)", text: $lv.leistungsnachweis)
                TextField("Dozent:innen (durch Komma getrennt)", text: dozentenText, axis: .vertical)
                Picker("Semester", selection: $lv.semester) {
                    ForEach(alleSemester) { semester in
                        Text(semester.titel).tag(Optional(semester))
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $lv.status) {
                    ForEach(LVStatus.allCases) { status in
                        Text(status.name).tag(status)
                    }
                }
                Toggle("Anmeldepflicht im QIS/LSF (*)", isOn: $lv.anmeldepflicht)
                if lv.anmeldepflicht {
                    OptionalesDatum(titel: Text("Verbindlich angemeldet"), datum: $lv.anmeldedatum)
                    if let anmeldung = lv.anmeldedatum {
                        LabeledContent("3-Semester-Frist endet ca.",
                                       value: Studienregeln.dreiSemesterFristEnde(anmeldung: anmeldung).kurzesDatum)
                    }
                }
            }

            Section("Stoffgebiete") {
                ForEach(Stoffgebiet.allCases) { gebiet in
                    Toggle(isOn: stoffgebietBinding(gebiet)) {
                        HStack(spacing: 8) {
                            StoffgebietMarke(stoffgebiet: gebiet)
                            Text(gebiet.name)
                        }
                    }
                }
            }

            Section("Voraussetzungen") {
                Text(lv.voraussetzungen.beschreibung)
                FreigabeDetail(freigabe: lv.freigabe(in: .aus(alleLVs, ph1: ph1)))
            }

            if let lernpfad = lv.lernpfad {
                Section("Lernpfad") {
                    Text(lernpfad.titel).font(.headline)
                    ForEach(lernpfad.sortierteTeile) { teil in
                        HStack {
                            Text(teil.lfdNrAnzeige).monospacedDigit()
                            Text(verbatim: "Teil \(teil.lernpfadTeil)")
                            Spacer()
                            Text(teil.semester?.titel ?? "")
                                .foregroundStyle(.secondary)
                        }
                        .fontWeight(teil == lv ? .semibold : .regular)
                    }
                }
            }

            Section("Hinweis") {
                TextField("Hinweis", text: $lv.hinweis, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section("Notizen") {
                TextField("Eigene Notizen", text: $lv.notizen, axis: .vertical)
                    .lineLimit(3...12)
            }

            Section {
                Button("Lehrveranstaltung löschen …", role: .destructive) {
                    zeigeLoeschen = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(Text("„\(lv.bezeichnung)“ löschen?"), isPresented: $zeigeLoeschen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                let zuLoeschen = lv
                beiLoeschen()
                DispatchQueue.main.async {
                    kontext.delete(zuLoeschen)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Teilprüfungen dieser Lehrveranstaltung werden ebenfalls gelöscht.")
        }
    }

    private var dozentenText: Binding<String> {
        Binding(
            get: { lv.dozenten.joined(separator: ", ") },
            set: { text in
                lv.dozenten = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func stoffgebietBinding(_ gebiet: Stoffgebiet) -> Binding<Bool> {
        Binding(
            get: { lv.stoffgebiete.contains(gebiet) },
            set: { an in
                var gebiete = lv.stoffgebiete.filter { $0 != gebiet }
                if an { gebiete.append(gebiet) }
                lv.stoffgebiete = gebiete
            }
        )
    }
}
