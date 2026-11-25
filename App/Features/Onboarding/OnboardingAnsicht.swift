import SwiftUI
import SwiftData
import PharmaCore

/// Einführung beim ersten Start: Semester, Prüfungstermine, API-Schlüssel, Google Drive.
struct OnboardingAnsicht: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(EinstellungsSchluessel.onboardingAbgeschlossen) private var abgeschlossen = false
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true
    @Query(sort: \Semester.sortierung) private var alleSemester: [Semester]
    @State private var schritt = 0

    private let anzahlSchritte = 5

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(schritt + 1), total: Double(anzahlSchritte))
                .padding()
            Group {
                switch schritt {
                case 0: willkommen
                case 1: semesterSchritt
                case 2: pruefungstermine
                case 3: apiSchritt
                default: driveSchritt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if schritt > 0 {
                    Button("Zurück") { schritt -= 1 }
                }
                Spacer()
                if schritt < anzahlSchritte - 1 {
                    if schritt > 0 {
                        Button("Überspringen") { abschliessen() }
                    }
                    Button("Weiter") { schritt += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Los geht’s") { abschliessen() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 600, idealHeight: 680)
        #endif
        .interactiveDismissDisabled()
    }

    private func abschliessen() {
        abgeschlossen = true
        dismiss()
    }

    // MARK: Schritte

    private var willkommen: some View {
        VStack(spacing: 20) {
            Image(systemName: "cross.vial.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Willkommen bei PharmaTutor")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Deine Lern-App für das Pharmaziestudium: Vorlesungen, Prüfungsvorbereitung, KI-Tutor, Karteikarten und Lernplan – geordnet nach Semester und Lehrveranstaltung.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Text("Der Studienverlaufsplan des FB 14 (5.–8. Semester) ist bereits vorgeladen und jederzeit änderbar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding()
    }

    private var semesterSchritt: some View {
        Form {
            Section {
                AktuellesSemesterPicker()
                Toggle("Zulassung Ph1 (1. Abschnitt bestanden)", isOn: $ph1)
            } header: {
                Text("In welchem Semester bist du?")
            } footer: {
                Text("[44] Arzneimittelanalytik Teil 1 ist als bestanden eingetragen. Den Status jeder Lehrveranstaltung kannst du jederzeit ändern.")
            }
        }
        .formStyle(.grouped)
    }

    private var pruefungstermine: some View {
        let aktuelles = alleSemester.first(where: \.istAktuell)
        let lvs = (aktuelles?.sortierteLehrveranstaltungen ?? []).filter {
            $0.status != .bestanden && !($0.teilpruefungen ?? []).isEmpty
        }
        return Form {
            Section {
                Text("Trage bekannte Prüfungstermine ein. Fehlende Termine kannst du später unter „Prüfungsvorbereitung“ ergänzen.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Prüfungstermine")
            }
            ForEach(lvs) { lv in
                Section {
                    ForEach(lv.sortierteTeilpruefungen) { tp in
                        OnboardingTermin(tp: tp)
                    }
                } header: {
                    Text(verbatim: "\(lv.lfdNrAnzeige) \(lv.bezeichnung)")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var apiSchritt: some View {
        Form {
            APISchluesselBereich()
            Section {
                Label("Deine Daten bleiben lokal auf diesem Gerät.", systemImage: "lock.shield")
                Label("An die KI gehen nur Inhalte, die du ausdrücklich auswählst.", systemImage: "hand.raised")
                Label("Ohne Schlüssel oder Internet funktioniert alles außer den KI-Funktionen.", systemImage: "wifi.slash")
            } header: {
                Text("Datenschutz")
            }
        }
        .formStyle(.grouped)
    }

    private var driveSchritt: some View {
        Form {
            Section {
                GoogleDriveHinweis()
            } header: {
                Text("Google Drive verbinden")
            }
        }
        .formStyle(.grouped)
    }
}

private struct OnboardingTermin: View {
    @Bindable var tp: Teilpruefung

    var body: some View {
        OptionalesDatum(titel: Text(verbatim: tp.titel + (tp.anmeldepflichtig ? " *" : "")),
                        datum: $tp.datum, mitUhrzeit: true)
    }
}
