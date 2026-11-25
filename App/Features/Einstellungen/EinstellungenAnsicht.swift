import SwiftUI
import SwiftData
import PharmaCore

struct EinstellungenAnsicht: View {
    @Environment(\.modelContext) private var kontext
    @AppStorage(EinstellungsSchluessel.vorname) private var vorname = ""
    @AppStorage(EinstellungsSchluessel.erscheinungsbild) private var erscheinungsbild = "system"
    @AppStorage(EinstellungsSchluessel.zulassungPh1) private var ph1 = true
    @AppStorage(EinstellungsSchluessel.onboardingAbgeschlossen) private var onboardingAbgeschlossen = true
    @AppStorage(EinstellungsSchluessel.lernzeiten) private var wochenplan: Wochenplan = .standard
    @AppStorage(EinstellungsSchluessel.lernstartMinuten) private var lernstart = Standardwerte.lernstartMinuten
    @AppStorage(EinstellungsSchluessel.erinnerungenAktiv) private var erinnerungen = false
    @AppStorage(EinstellungsSchluessel.taeglicheErinnerung) private var taeglich = true
    @AppStorage(EinstellungsSchluessel.erinnerungUhrzeitMinuten) private var erinnerungUm = Standardwerte.erinnerungUhrzeitMinuten
    @AppStorage(EinstellungsSchluessel.kalenderLerneinheitenExport) private var lerneinheitenExportieren = true
    @AppStorage(EinstellungsSchluessel.kiModell) private var kiModell = ClaudeAPI.standardModell

    @State private var zeigeAPI = false
    @State private var zeigeLernzeiten = false
    @State private var zeigeZuruecksetzen = false
    @State private var apiVorhanden = false
    @State private var erinnerungsHinweis: String?
    @State private var kalenderMeldung: String?
    @State private var kalenderLaeuft = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    private func uhrzeit(_ minuten: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minuten.wrappedValue / 60, minute: minuten.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { neu in
                let teile = Calendar.current.dateComponents([.hour, .minute], from: neu)
                minuten.wrappedValue = (teile.hour ?? 0) * 60 + (teile.minute ?? 0)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Seitentitel(titel: "Einstellungen")

                gruppe("Allgemein") {
                    Wertzeile(titel: "Dein Vorname") {
                        TextField("", text: $vorname, prompt: Text("für die Begrüßung"))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 240)
                    }
                    Wertzeile(titel: "Erscheinungsbild") {
                        Picker("Erscheinungsbild", selection: $erscheinungsbild) {
                            Text("Wie System").tag("system")
                            Text("Hell").tag("hell")
                            Text("Dunkel").tag("dunkel")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Wertzeile(titel: "Aktuelles Semester") {
                        AktuellesSemesterPicker()
                            .labelsHidden()
                            .fixedSize()
                    }
                    Wertzeile(titel: "Zulassung Ph1 (1. Abschnitt bestanden)") {
                        Toggle("Zulassung Ph1", isOn: $ph1).labelsHidden()
                    }
                }

                gruppe("Lernen") {
                    Wertzeile(titel: "Lernzeit pro Tag") {
                        Button("Ø \(Dauer.text(minuten: wochenplan.summeProWoche / 7))") { zeigeLernzeiten = true }
                            .buttonStyle(.plain)
                            .underline()
                    }
                    Wertzeile(titel: "Lernbeginn im Tagesplan") {
                        DatePicker("Lernbeginn", selection: uhrzeit($lernstart), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Wertzeile(titel: "Erinnerungen") {
                        Toggle("Erinnerungen", isOn: $erinnerungen).labelsHidden()
                    }
                    if erinnerungen {
                        Wertzeile(titel: "Tägliche Lernerinnerung") {
                            HStack(spacing: 12) {
                                if taeglich {
                                    DatePicker("Uhrzeit", selection: uhrzeit($erinnerungUm), displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                }
                                Toggle("Tägliche Lernerinnerung", isOn: $taeglich).labelsHidden()
                            }
                        }
                    }
                    Text(erinnerungsHinweis.map { LocalizedStringKey($0) } ?? "Erinnert an Teilprüfungen (eine Woche und einen Tag vorher), QIS/LSF-Anmeldeschlüsse und Fristen wie die Platzvergabe des Wahlpflichtfachs. Bestandene Lehrveranstaltungen werden nicht erinnert.")
                        .font(Thema.ui(12))
                        .foregroundStyle(erinnerungsHinweis == nil ? Thema.tinteTertiaer : Stoffgebiet.i.farbe)
                        .lineSpacing(3)
                        .padding(.top, 12)
                }

                gruppe("Verbindungen") {
                    Wertzeile(titel: "Claude API-Schlüssel") {
                        Button(apiVorhanden ? "In Schlüsselbund gespeichert" : "Nicht hinterlegt") { zeigeAPI = true }
                            .buttonStyle(.plain)
                            .underline()
                    }
                    Wertzeile(titel: "KI-Modell") {
                        Picker("KI-Modell", selection: $kiModell) {
                            ForEach(ClaudeAPI.modelle.map { $0.id }, id: \.self) { kennung in
                                Text(verbatim: ClaudeAPI.modelle.first { $0.id == kennung }?.name ?? kennung).tag(kennung)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Wertzeile(titel: "Google Drive") {
                        Text("Über die Dateien-App")
                            .help("Google Drive erscheint im Import-Dialog, sobald die Google-Drive-App (iPad) bzw. „Google Drive für Desktop“ (Mac) installiert ist.")
                    }
                    Wertzeile(titel: "Systemkalender „PharmaTutor“") {
                        HStack(spacing: 10) {
                            if kalenderLaeuft { ProgressView().controlSize(.small) }
                            Button("Jetzt abgleichen") { kalenderAbgleichen() }
                                .buttonStyle(.plain)
                                .underline()
                                .disabled(kalenderLaeuft)
                        }
                    }
                    Wertzeile(titel: "Lerneinheiten in den Kalender übertragen") {
                        Toggle("Lerneinheiten übertragen", isOn: $lerneinheitenExportieren).labelsHidden()
                    }
                    if let kalenderMeldung {
                        Text(verbatim: kalenderMeldung)
                            .font(Thema.ui(12))
                            .foregroundStyle(Thema.tinteSekundaer)
                            .padding(.top, 12)
                    }
                    Wertzeile(titel: "Synchronisierung") {
                        Text("Nur dieses Gerät")
                            .help("Die Synchronisierung zwischen Mac und iPad folgt in Ausbaustufe i.")
                    }
                }

                gruppe("Daten") {
                    Wertzeile(titel: "Einführung") {
                        Button("Erneut anzeigen") { onboardingAbgeschlossen = false }
                            .buttonStyle(.plain)
                            .underline()
                    }
                    Wertzeile(titel: "Curriculum") {
                        Button("Zurücksetzen …") { zeigeZuruecksetzen = true }
                            .buttonStyle(.plain)
                            .underline()
                            .foregroundStyle(Stoffgebiet.i.farbe)
                    }
                    Wertzeile(titel: "Version") {
                        Text(verbatim: version)
                    }
                    Text("Alle Daten bleiben lokal auf diesem Gerät. An die KI gehen nur Inhalte, die du ausdrücklich auswählst.")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .seitenrand()
        }
        .background(Thema.flaeche)
        .navigationTitle("Einstellungen")
        .onAppear {
            apiVorhanden = Schluesselbund.lesen(konto: Schluesselbund.claudeAPIKonto) != nil
        }
        .onChange(of: erinnerungen) { _, an in
            Task {
                if an {
                    let erlaubt = await ErinnerungsDienst.berechtigungAnfragen()
                    if !erlaubt {
                        erinnerungen = false
                        erinnerungsHinweis = "Mitteilungen sind für PharmaTutor in den Systemeinstellungen ausgeschaltet."
                    } else {
                        erinnerungsHinweis = nil
                    }
                }
                await ErinnerungsDienst.planen(kontext)
            }
        }
        .onChange(of: taeglich) { _, _ in Task { await ErinnerungsDienst.planen(kontext) } }
        .onChange(of: erinnerungUm) { _, _ in Task { await ErinnerungsDienst.planen(kontext) } }
        .sheet(isPresented: $zeigeLernzeiten) {
            LernzeitenAnsicht()
        }
        .sheet(isPresented: $zeigeAPI, onDismiss: {
            apiVorhanden = Schluesselbund.lesen(konto: Schluesselbund.claudeAPIKonto) != nil
        }) {
            NavigationStack {
                Form {
                    APISchluesselBereich()
                }
                .formStyle(.grouped)
                .navigationTitle("Claude API-Schlüssel")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { zeigeAPI = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 300)
            #endif
        }
        .confirmationDialog("Curriculum zurücksetzen?", isPresented: $zeigeZuruecksetzen, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) {
                Seeder.zuruecksetzen(kontext)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Lehrveranstaltungen, Teilprüfungen, Fristen, Lerneinheiten und Unterlagen werden gelöscht und das vorgeladene Curriculum neu geladen.")
        }
    }

    private func gruppe<Inhalt: View>(_ titel: LocalizedStringKey, @ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Kleintitel(text: titel)
            Haarlinie().padding(.top, 10)
            inhalt()
        }
    }

    private func kalenderAbgleichen() {
        kalenderLaeuft = true
        Task {
            do {
                let anzahl = try await SystemkalenderDienst.shared.abgleichen(kontext, mitLerneinheiten: lerneinheitenExportieren)
                kalenderMeldung = "\(anzahl) Termine in den Kalender „\(SystemkalenderDienst.kalenderName)“ übertragen."
            } catch {
                kalenderMeldung = error.localizedDescription
            }
            kalenderLaeuft = false
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
            Text("Den Schlüssel erstellst du in der Anthropic Console (console.anthropic.com). Er wird nur im Schlüsselbund dieses Geräts gespeichert. An die KI gehen nur Inhalte, die du ausdrücklich auswählst – z. B. deine Frage und passende Auszüge aus deinen Unterlagen.")
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

