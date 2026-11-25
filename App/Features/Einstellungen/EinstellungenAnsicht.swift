import SwiftUI
import SwiftData

struct EinstellungenAnsicht: View {
    @Environment(\.modelContext) private var kontext
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true
    @AppStorage(EinstellungsSchluessel.onboardingAbgeschlossen) private var onboardingAbgeschlossen = true
    @State private var zeigeZuruecksetzen = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section("Studium") {
                AktuellesSemesterPicker()
                Toggle("Zulassung Ph1 (1. Abschnitt bestanden)", isOn: $ph1)
            }

            APISchluesselBereich()

            Section {
                GoogleDriveHinweis()
            } header: {
                Text("Google Drive")
            }

            Section {
                Button("Einführung erneut anzeigen") {
                    onboardingAbgeschlossen = false
                }
                Button("Curriculum zurücksetzen …", role: .destructive) {
                    zeigeZuruecksetzen = true
                }
            } header: {
                Text("Daten")
            } footer: {
                Text("Alle Daten bleiben lokal auf diesem Gerät. An die KI gehen nur Inhalte, die du ausdrücklich auswählst.")
            }

            Section("Über PharmaTutor") {
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .confirmationDialog("Curriculum zurücksetzen?", isPresented: $zeigeZuruecksetzen, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) {
                Seeder.zuruecksetzen(kontext)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Lehrveranstaltungen, Teilprüfungen und Fristen werden gelöscht und das vorgeladene Curriculum neu geladen.")
        }
    }
}

/// Eingabe des Claude-API-Schlüssels (gespeichert im Schlüsselbund).
struct APISchluesselBereich: View {
    @State private var eingabe = ""
    @State private var vorhanden = false
    @State private var fehlermeldung: String?

    var body: some View {
        Section {
            SecureField("API-Schlüssel", text: $eingabe, prompt: Text("sk-ant-…"))
                .textContentType(.password)
                .autocorrectionDisabled()
            HStack {
                Button("Speichern") { speichern() }
                    .disabled(eingabe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if vorhanden {
                    Spacer()
                    Button("Schlüssel entfernen", role: .destructive) {
                        Schluesselbund.loeschen(konto: Schluesselbund.claudeAPIKonto)
                        vorhanden = false
                    }
                }
            }
            if vorhanden {
                Label("Ein API-Schlüssel ist im Schlüsselbund gespeichert.", systemImage: "checkmark.shield")
                    .foregroundStyle(.green)
            }
            if let fehlermeldung {
                Label(fehlermeldung, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("KI (Claude)")
        } footer: {
            Text("Den Schlüssel erstellst du in der Anthropic Console. Er wird nur im Schlüsselbund dieses Geräts gespeichert. Die KI-Funktionen folgen ab Ausbaustufe e.")
        }
        .onAppear {
            vorhanden = Schluesselbund.lesen(konto: Schluesselbund.claudeAPIKonto) != nil
        }
    }

    private func speichern() {
        do {
            try Schluesselbund.speichern(eingabe.trimmingCharacters(in: .whitespacesAndNewlines),
                                         konto: Schluesselbund.claudeAPIKonto)
            eingabe = ""
            vorhanden = true
            fehlermeldung = nil
        } catch {
            fehlermeldung = error.localizedDescription
        }
    }
}

struct GoogleDriveHinweis: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Google Drive über den Dateien-Anbieter", systemImage: "externaldrive.connected.to.line.below")
                .font(.headline)
            #if os(macOS)
            Text("Installiere „Google Drive für Desktop“ und melde dich dort an. Dein Drive erscheint dann im Finder und direkt im Import-Dialog von PharmaTutor – ein eigenes Login in PharmaTutor ist nicht nötig.")
            #else
            Text("Installiere die App „Google Drive“ und aktiviere sie in der Dateien-App unter „Durchsuchen“ → „Bearbeiten“. Dein Drive erscheint dann direkt im Import-Dialog von PharmaTutor – ein eigenes Login in PharmaTutor ist nicht nötig.")
            #endif
            Text("Der Import von Vorlesungen folgt in Ausbaustufe c.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
