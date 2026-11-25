import SwiftUI
import SwiftData

struct EinstellungenAnsicht: View {
    @Environment(\.modelContext) private var kontext
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true
    @AppStorage(EinstellungsSchluessel.onboardingAbgeschlossen) private var onboardingAbgeschlossen = true
    @State private var zeigeZuruecksetzen = false
    @State private var zeigeLernzeiten = false

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

            Section {
                Button("Lernzeiten festlegen …") { zeigeLernzeiten = true }
            } header: {
                Text("Lernplan")
            } footer: {
                Text("Aus Prüfungsterminen und Lernzeiten entsteht ein Tag-für-Tag-Plan, der sich täglich an verpasste Einheiten anpasst.")
            }

            ErinnerungenBereich()

            SystemkalenderBereich()

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
        .sheet(isPresented: $zeigeLernzeiten) {
            LernzeitenAnsicht()
        }
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

struct ErinnerungenBereich: View {
    @Environment(\.modelContext) private var kontext
    @AppStorage(EinstellungsSchluessel.erinnerungenAktiv) private var aktiv = false
    @AppStorage(EinstellungsSchluessel.taeglicheErinnerung) private var taeglich = true
    @AppStorage(EinstellungsSchluessel.erinnerungUhrzeitMinuten) private var uhrzeitMinuten = Standardwerte.erinnerungUhrzeitMinuten
    @State private var hinweis: String?

    private var uhrzeit: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: uhrzeitMinuten / 60, minute: uhrzeitMinuten % 60, second: 0, of: Date()) ?? Date()
            },
            set: { neu in
                let teile = Calendar.current.dateComponents([.hour, .minute], from: neu)
                uhrzeitMinuten = (teile.hour ?? 17) * 60 + (teile.minute ?? 0)
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Erinnerungen", isOn: $aktiv)
            if aktiv {
                Toggle("Tägliche Lernerinnerung", isOn: $taeglich)
                if taeglich {
                    DatePicker("Uhrzeit", selection: uhrzeit, displayedComponents: .hourAndMinute)
                }
            }
            if let hinweis {
                Label(hinweis, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Erinnerungen")
        } footer: {
            Text("Erinnert an Teilprüfungen (eine Woche und einen Tag vorher), QIS/LSF-Anmeldeschlüsse und Fristen wie die Platzvergabe des Wahlpflichtfachs. Bestandene Lehrveranstaltungen werden nicht erinnert.")
        }
        .onChange(of: aktiv) { _, an in
            Task {
                if an {
                    let erlaubt = await ErinnerungsDienst.berechtigungAnfragen()
                    if !erlaubt {
                        aktiv = false
                        hinweis = "Mitteilungen sind für PharmaTutor in den Systemeinstellungen ausgeschaltet."
                    } else {
                        hinweis = nil
                    }
                }
                await ErinnerungsDienst.planen(kontext)
            }
        }
        .onChange(of: taeglich) { _, _ in
            Task { await ErinnerungsDienst.planen(kontext) }
        }
        .onChange(of: uhrzeitMinuten) { _, _ in
            Task { await ErinnerungsDienst.planen(kontext) }
        }
    }
}

struct SystemkalenderBereich: View {
    @Environment(\.modelContext) private var kontext
    @AppStorage(EinstellungsSchluessel.kalenderLerneinheitenExport) private var mitLerneinheiten = true
    @State private var meldung: String?
    @State private var laeuft = false

    var body: some View {
        Section {
            Toggle("Lerneinheiten mitübertragen", isOn: $mitLerneinheiten)
            Button {
                laeuft = true
                Task {
                    do {
                        let anzahl = try await SystemkalenderDienst.shared.abgleichen(kontext, mitLerneinheiten: mitLerneinheiten)
                        meldung = "\(anzahl) Termine übertragen."
                    } catch {
                        meldung = error.localizedDescription
                    }
                    laeuft = false
                }
            } label: {
                Label("Jetzt abgleichen", systemImage: "calendar.badge.plus")
            }
            .disabled(laeuft)
            if let meldung {
                Text(meldung)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Systemkalender")
        } footer: {
            Text("Teilprüfungen, Blockpraktika, Fristen und auf Wunsch Lerneinheiten werden in einen eigenen Kalender „PharmaTutor“ geschrieben. Bei jedem Abgleich wird dieser Kalender vollständig ersetzt; andere Kalender bleiben unberührt.")
        }
    }
}
