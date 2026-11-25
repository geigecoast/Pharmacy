import SwiftUI
import SwiftData
import PharmaCore

struct SemesterBearbeitenAnsicht: View {
    @Bindable var semester: Semester
    @Environment(\.dismiss) private var dismiss
    @Query private var alleSemester: [Semester]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung", text: $semester.titel)
                    if semester.typ == .regulaer {
                        Toggle("Aktuelles Semester", isOn: Binding(
                            get: { semester.istAktuell },
                            set: { an in
                                if an {
                                    for s in alleSemester { s.istAktuell = false }
                                }
                                semester.istAktuell = an
                            }
                        ))
                    }
                }
                Section {
                    OptionalesDatum(titel: Text("Vorlesungsbeginn"), datum: $semester.vorlesungsbeginn)
                    OptionalesDatum(titel: Text("Vorlesungsende"), datum: $semester.vorlesungsende)
                } header: {
                    Text("Vorlesungszeit")
                } footer: {
                    Text("Die vorgeladenen Daten sind Näherungswerte. Bitte mit dem Vorlesungsverzeichnis abgleichen.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(semester.titel)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}

/// Auswahl des aktuellen Semesters (setzt genau ein Semester als aktuell).
struct AktuellesSemesterPicker: View {
    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @AppStorage(EinstellungsSchluessel.ausgewaehltesSemester) private var ausgewaehlt = 5

    var body: some View {
        Picker("Aktuelles Semester", selection: Binding<Int>(
            get: { alleSemester.first(where: \.istAktuell)?.nummer ?? 0 },
            set: { nummer in
                for s in alleSemester { s.istAktuell = (s.nummer == nummer) }
                ausgewaehlt = nummer
            }
        )) {
            ForEach(alleSemester.filter { $0.typ == .regulaer }) { s in
                Text(s.titel).tag(s.nummer)
            }
        }
    }
}

struct NeueLehrveranstaltungAnsicht: View {
    let semester: Semester
    var beiErstellung: (Lehrveranstaltung) -> Void

    @Environment(\.modelContext) private var kontext
    @Environment(\.dismiss) private var dismiss

    @State private var lfdNr = ""
    @State private var bezeichnung = ""
    @State private var lehrform: Lehrform = .v
    @State private var sws = ""
    @State private var stoffgebiete: Set<Stoffgebiet> = []
    @State private var anmeldepflicht = false
    @State private var bestanden = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Lfd. Nr. (z. B. 43)", text: $lfdNr)
                    TextField("Bezeichnung", text: $bezeichnung, axis: .vertical)
                    Picker("Lehrform", selection: $lehrform) {
                        ForEach(Lehrform.allCases) { form in
                            Text(verbatim: "\(form.kuerzel) – \(form.name)").tag(form)
                        }
                    }
                    TextField("SWS", text: $sws)
                    Toggle("Anmeldepflicht im QIS/LSF (*)", isOn: $anmeldepflicht)
                    if semester.typ == .archiv {
                        Toggle("Bereits bestanden", isOn: $bestanden)
                    }
                }
                Section("Stoffgebiete") {
                    ForEach(Stoffgebiet.allCases) { gebiet in
                        Toggle(isOn: Binding(
                            get: { stoffgebiete.contains(gebiet) },
                            set: { if $0 { stoffgebiete.insert(gebiet) } else { stoffgebiete.remove(gebiet) } }
                        )) {
                            HStack(spacing: 8) {
                                StoffgebietMarke(stoffgebiet: gebiet)
                                Text(gebiet.name)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Neue Lehrveranstaltung")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { anlegen() }
                        .disabled(bezeichnung.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func anlegen() {
        let naechsteSortierung = ((semester.lehrveranstaltungen ?? []).map(\.sortierung).max() ?? -1) + 1
        let lv = Lehrveranstaltung(
            lfdNr: lfdNr.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")),
            bezeichnung: bezeichnung.trimmingCharacters(in: .whitespacesAndNewlines),
            lehrform: lehrform,
            sws: sws,
            sortierung: naechsteSortierung
        )
        lv.stoffgebiete = Array(stoffgebiete)
        lv.anmeldepflicht = anmeldepflicht
        if bestanden { lv.status = .bestanden }
        kontext.insert(lv)
        lv.semester = semester
        beiErstellung(lv)
        dismiss()
    }
}
