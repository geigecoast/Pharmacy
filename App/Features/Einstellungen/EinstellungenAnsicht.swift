import SwiftUI
import SwiftData
import UniformTypeIdentifiers
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
    @AppStorage(EinstellungsSchluessel.gamificationAktiv) private var gamificationAktiv = true
    @AppStorage(EinstellungsSchluessel.tageszielMinuten) private var tagesziel = Standardwerte.tageszielMinuten
    @AppStorage(EinstellungsSchluessel.wochenzielMinuten) private var wochenziel = 0
    @AppStorage(EinstellungsSchluessel.ruhetagErlaubt) private var ruhetag = true

    @State private var zeigeAPI = false
    @State private var zeigeLernzeiten = false
    @State private var zeigeZuruecksetzen = false
    @State private var apiVorhanden = false
    @State private var erinnerungsHinweis: String?
    @State private var kalenderMeldung: String?
    @State private var kalenderLaeuft = false

    // Abgleich und Sicherung
    @Environment(Datenspeicher.self) private var speicher
    private enum ImportZiel { case ordner, sicherung }
    @State private var importZiel: ImportZiel?
    @State private var sicherungsDatei: ExportDatei?
    @State private var wiederherstellenDaten: Data?
    @State private var abgleichMeldung: String?
    @State private var abgleichLaeuft = false
    @State private var zeigeLizenz = false
    private var abgleich: AbgleichDienst { AbgleichDienst.shared }

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

                gruppe("Erfolge") {
                    Wertzeile(titel: "Lernserie, Stufen und Abzeichen") {
                        Toggle("Erfolge", isOn: $gamificationAktiv).labelsHidden()
                    }
                    if gamificationAktiv {
                        Wertzeile(titel: "Tagesziel für die Lernserie") {
                            Stepper(value: $tagesziel, in: 5...240, step: 5) {
                                Text(verbatim: Dauer.text(minuten: tagesziel))
                            }
                            .fixedSize()
                        }
                        Wertzeile(titel: "Wochenziel") {
                            Stepper(value: $wochenziel, in: 0...3000, step: 30) {
                                Text(verbatim: wochenziel == 0
                                     ? "Wie Lernzeiten (\(Analyse.stundenText(wochenplan.summeProWoche)))"
                                     : Analyse.stundenText(wochenziel))
                            }
                            .fixedSize()
                        }
                        Wertzeile(titel: "Ein Ruhetag pro Woche") {
                            Toggle("Ruhetag", isOn: $ruhetag).labelsHidden()
                        }
                    }
                    Text("Die Lernserie zählt Tage, an denen du das Tagesziel erreichst. Mit Ruhetag darf pro Woche ein einzelner Tag fehlen. Punkte und Abzeichen entstehen aus Lernzeit, Karten, Quiz, Probeklausuren und bestandenen Teilprüfungen.")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
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
                }

                abgleichGruppe

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
                    Wertzeile(titel: "Schriften") {
                        Button("Geist, Newsreader · Lizenz") { zeigeLizenz = true }
                            .buttonStyle(.plain)
                            .underline()
                    }
                    Text("Alle Daten bleiben auf deinen Geräten – beim Abgleich nur in dem Ordner, den du auswählst. An die KI gehen nur Inhalte, die du ausdrücklich auswählst.")
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
        .sheet(isPresented: $zeigeLizenz) {
            LizenzAnsicht()
        }
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
        .fileImporter(isPresented: Binding(get: { importZiel != nil }, set: { if !$0 { importZiel = nil } }),
                      allowedContentTypes: importZiel == .ordner ? [.folder] : [.pharmatutorSicherung, .data]) { ergebnis in
            let ziel = importZiel
            importZiel = nil
            guard case .success(let url) = ergebnis else { return }
            if ziel == .ordner {
                ordnerGewaehlt(url)
            } else {
                sicherungGewaehlt(url)
            }
        }
        .fileExporter(isPresented: Binding(get: { sicherungsDatei != nil }, set: { if !$0 { sicherungsDatei = nil } }),
                      document: sicherungsDatei, contentType: .pharmatutorSicherung,
                      defaultFilename: "PharmaTutor-Sicherung-\(Date().formatted(.iso8601.year().month().day()))") { ergebnis in
            if case .failure(let fehler) = ergebnis {
                abgleichMeldung = fehler.localizedDescription
            } else {
                abgleichMeldung = "Sicherung gespeichert."
            }
        }
        .confirmationDialog("Sicherung wiederherstellen?", isPresented: Binding(
            get: { wiederherstellenDaten != nil },
            set: { if !$0 { wiederherstellenDaten = nil } }
        ), titleVisibility: .visible) {
            Button("Wiederherstellen", role: .destructive) { wiederherstellen() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Daten auf diesem Gerät werden durch die Sicherung ersetzt.")
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

    // MARK: Abgleich und Sicherung

    private var abgleichGruppe: some View {
        gruppe("Abgleich & Sicherung") {
            Wertzeile(titel: "Abgleichsordner") {
                Button(abgleich.ordnerName.map { "„\($0)“" } ?? "Auswählen …") { importZiel = .ordner }
                    .buttonStyle(.plain)
                    .underline()
            }
            if abgleich.istEingerichtet {
                Wertzeile(titel: "Letzter Abgleich") {
                    HStack(spacing: 12) {
                        if abgleichLaeuft { ProgressView().controlSize(.small) }
                        Text(verbatim: abgleich.letzterAbgleich.map {
                            $0.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(.deutsch))
                        } ?? "noch nie")
                        Button("Jetzt abgleichen") { jetztAbgleichen() }
                            .buttonStyle(.plain)
                            .underline()
                            .disabled(abgleichLaeuft)
                    }
                }
                Wertzeile(titel: "Abgleich beenden") {
                    Button("Ordner entfernen") {
                        abgleich.ordnerEntfernen()
                        abgleichMeldung = nil
                    }
                    .buttonStyle(.plain)
                    .underline()
                }
            }
            Wertzeile(titel: "Sicherung") {
                HStack(spacing: 16) {
                    Button("Erstellen …") { sicherungErstellen() }
                        .buttonStyle(.plain)
                        .underline()
                    Button("Wiederherstellen …") { importZiel = .sicherung }
                        .buttonStyle(.plain)
                        .underline()
                }
            }
            if let abgleichMeldung {
                Text(verbatim: abgleichMeldung)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .padding(.top, 12)
            }
            Text("Wähle auf Mac und iPad denselben Ordner, z. B. in iCloud Drive oder Google Drive. PharmaTutor legt dort beim Verlassen der App den aktuellen Stand ab und bietet ihn auf dem anderen Gerät zur Übernahme an. Änderungen auf beiden Geräten werden nicht zusammengeführt – dann entscheidest du, welcher Stand gilt. Eine Sicherung enthält alle Daten einschließlich Unterlagen.")
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteTertiaer)
                .lineSpacing(3)
                .padding(.top, 12)
        }
    }

    private func ordnerGewaehlt(_ url: URL) {
        do {
            try abgleich.ordnerFestlegen(url)
            jetztAbgleichen()
        } catch {
            abgleichMeldung = "Der Ordner konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    /// Prüft zuerst auf einen neueren Stand des anderen Geräts, sonst wird der eigene abgelegt.
    private func jetztAbgleichen() {
        abgleichLaeuft = true
        defer { abgleichLaeuft = false }
        switch abgleich.pruefen() {
        case .uebernehmen(let stand), .konflikt(let stand):
            abgleichMeldung = "Ein neuerer Stand von „\(stand.geraetName)“ liegt bereit."
            NotificationCenter.default.post(name: .abgleichPruefen, object: nil)
        case .neuereVersion(let stand):
            abgleichMeldung = "„\(stand.geraetName)“ nutzt eine neuere App-Version (\(stand.appVersion)). Bitte aktualisiere PharmaTutor."
        case .nichts:
            do {
                try abgleich.ablegen(kontext: kontext, speicher: speicher.speicherURL)
                abgleichMeldung = "Aktueller Stand abgelegt."
            } catch {
                abgleichMeldung = error.localizedDescription
            }
        }
    }

    private func sicherungErstellen() {
        do {
            let stand = Abgleich.Stand(basisID: nil, geraetID: Geraet.id, geraetName: Geraet.name,
                                       erstelltAm: Date(), appVersion: Geraet.appVersion)
            let daten = try SicherungsDienst.erstellen(kontext: kontext, speicher: speicher.speicherURL, stand: stand)
            sicherungsDatei = ExportDatei(daten: daten)
        } catch {
            abgleichMeldung = error.localizedDescription
        }
    }

    private func sicherungGewaehlt(_ url: URL) {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        do {
            wiederherstellenDaten = try Data(contentsOf: url)
        } catch {
            abgleichMeldung = error.localizedDescription
        }
    }

    private func wiederherstellen() {
        guard let daten = wiederherstellenDaten else { return }
        wiederherstellenDaten = nil
        do {
            let ergebnis = try SicherungsDienst.entpacken(daten)
            abgleich.nachWiederherstellung()
            try speicher.wechseln(zu: ergebnis.speicher)
        } catch {
            abgleichMeldung = error.localizedDescription
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


/// Lizenztext der mitgelieferten Schriften (SIL Open Font License).
struct LizenzAnsicht: View {
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        guard let url = Bundle.main.url(forResource: "LIZENZ", withExtension: "txt"),
              let inhalt = try? String(contentsOf: url, encoding: .utf8) else {
            return "Geist und Geist Mono (Vercel) sowie Newsreader (Production Type) stehen unter der SIL Open Font License 1.1."
        }
        return inhalt
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: text)
                    .font(Thema.mono(11))
                    .foregroundStyle(Thema.tinte)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .background(Thema.flaeche)
            .navigationTitle("Schriftlizenzen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }
}
