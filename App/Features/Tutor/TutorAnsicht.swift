import SwiftUI
import SwiftData
import PharmaCore

/// Tab „Tutor“: Chat zur Lehrveranstaltung mit Erklärmodi und „Nur meine Unterlagen“.
struct TutorAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    var oeffnen: (Dokument, Int) -> Void

    @Environment(\.modelContext) private var kontext
    @AppStorage("tutorModus") private var modus: TutorModus = .einfach
    @AppStorage("nurMeineUnterlagen") private var nurUnterlagen = true
    @State private var eingabe = ""
    @State private var laeuft = false
    @State private var stream = ""
    @State private var fehler: String?
    @State private var gewaehlterChat: TutorChat?
    @State private var aufgabe: Task<Void, Never>?
    @State private var werkzeug: TutorWerkzeug?

    private var chat: TutorChat? {
        if let gewaehlterChat, !gewaehlterChat.isDeleted { return gewaehlterChat }
        return (lv.tutorChats ?? []).max { $0.erstelltAm < $1.erstelltAm }
    }

    private var nachrichten: [TutorNachricht] { chat?.sortierteNachrichten ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            modusleiste
            Haarlinie()
            ScrollViewReader { leser in
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        if nachrichten.isEmpty && !laeuft {
                            willkommen
                        }
                        ForEach(nachrichten) { nachricht in
                            NachrichtAnsicht(nachricht: nachricht, quelleOeffnen: quelleOeffnen) {
                                alsKarteSpeichern(nachricht)
                            }
                            .id(nachricht.persistentModelID)
                        }
                        if laeuft {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Tutor · \(modus.name)")
                                    .font(Thema.ui(11))
                                    .foregroundStyle(Thema.tinteTertiaer)
                                if stream.isEmpty {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("Denkt nach …").font(Thema.ui(13)).foregroundStyle(Thema.tinteSekundaer)
                                    }
                                } else {
                                    StrukturierteAntwort(text: stream)
                                }
                            }
                            .id("stream")
                        }
                        if let fehler {
                            Text(verbatim: fehler)
                                .font(Thema.ui(13))
                                .foregroundStyle(Stoffgebiet.i.farbe)
                                .id("fehler")
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .onChange(of: stream) { _, _ in leser.scrollTo("stream", anchor: .bottom) }
                .onChange(of: nachrichten.count) { _, _ in
                    if let letzte = nachrichten.last { withAnimation { leser.scrollTo(letzte.persistentModelID, anchor: .top) } }
                }
            }
            eingabeleiste
        }
        .sheet(item: $werkzeug) { werkzeug in
            TutorWerkzeugAnsicht(werkzeug: werkzeug, lv: lv)
        }
    }

    // MARK: Kopf

    private var modusleiste: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TutorModus.allCases) { eintrag in
                        Pille(text: eintrag.name, aktiv: modus == eintrag) { modus = eintrag }
                    }
                }
            }
            Spacer(minLength: 12)
            Toggle(isOn: $nurUnterlagen) {
                Text("Nur meine Unterlagen")
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Thema.tinte)
            .fixedSize()
            .help("Antwortet nur aus deinen importierten Unterlagen – mit Quellenangabe (Folie/Seite)")
            Menu {
                Button("Neues Gespräch") { neuesGespraech() }
                let fruehere = (lv.tutorChats ?? []).sorted { $0.erstelltAm > $1.erstelltAm }
                if fruehere.count > 1 {
                    Menu("Frühere Gespräche") {
                        ForEach(fruehere) { eintrag in
                            Button("\(eintrag.erstelltAm.kurzesDatum) · \(eintrag.titel)") { gewaehlterChat = eintrag }
                        }
                    }
                }
                Divider()
                ForEach(TutorWerkzeug.allCases) { eintrag in
                    Button(eintrag.titel) { werkzeug = eintrag }
                }
                if let chat {
                    Divider()
                    Button("Gespräch löschen", role: .destructive) {
                        gewaehlterChat = nil
                        kontext.delete(chat)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Gespräche und Werkzeuge")
        }
        .padding(.vertical, 14)
    }

    private var willkommen: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Frag mich alles zu \(lv.anzeigename).")
                .font(Thema.display(32))
                .foregroundStyle(Thema.tinte)
            Text(nurUnterlagen
                 ? "Ich antworte nur aus deinen Unterlagen dieser Lehrveranstaltung und nenne Folie bzw. Seite."
                 : "Ich antworte mit meinem Fachwissen – schalte „Nur meine Unterlagen“ ein, um nur aus deinen Folien zu antworten.")
                .font(Thema.ui(14))
                .foregroundStyle(Thema.tinteSekundaer)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(vorschlaege, id: \.self) { vorschlag in
                    Button {
                        eingabe = vorschlag
                        senden()
                    } label: {
                        HStack {
                            Text(verbatim: vorschlag).font(Thema.ui(14)).foregroundStyle(Thema.tinte)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Thema.tinteTertiaer)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Haarlinie() }
                }
            }
            HStack(spacing: 8) {
                ForEach(TutorWerkzeug.allCases) { eintrag in
                    Pille(text: eintrag.titel) { werkzeug = eintrag }
                }
            }
        }
    }

    private var vorschlaege: [String] {
        if modus == .muendlich { return ["Starte die mündliche Prüfung."] }
        let gebiete = Set(lv.stoffgebiete)
        if gebiete.contains(.h) {
            return ["Wie unterscheide ich Identität, Reinheit und Gehalt in einer Monographie?",
                    "Erkläre die komplexometrische Titration Schritt für Schritt.",
                    "Was sind typische Fallen bei Grenzprüfungen?"]
        }
        if gebiete.contains(.i) {
            return ["Erkläre den Wirkmechanismus der NSAR.",
                    "Welche Wechselwirkungen sind bei Antikoagulanzien prüfungsrelevant?",
                    "Was sind die wichtigsten UAW der Opioide?"]
        }
        return ["Fasse die wichtigsten Prüfungsthemen dieser Lehrveranstaltung zusammen.",
                "Erkläre mir das schwierigste Thema der letzten Vorlesung.",
                "Stell mir drei Prüfungsfragen."]
    }

    // MARK: Eingabe

    private var eingabeleiste: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Frag deinen Tutor zu \(LfdNr.anzeige(lv.lfdNr))", text: $eingabe, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Thema.ui(15))
                    .lineLimit(1...6)
                    .onSubmit { senden() }
                    .padding(.vertical, 6)
                Button {
                    if laeuft { abbrechen() } else { senden() }
                } label: {
                    Image(systemName: laeuft ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Thema.tinteInvers)
                        .frame(width: 30, height: 30)
                        .background(Thema.tinte, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!laeuft && eingabe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help(laeuft ? "Antwort abbrechen" : "Senden (⌘↩)")
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Thema.flaeche, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Thema.rahmen))
            Text(nurUnterlagen
                 ? "Gesendet werden deine Frage und passende Auszüge aus deinen Unterlagen."
                 : "Gesendet wird nur deine Frage – keine Unterlagen.")
                .font(Thema.ui(11))
                .foregroundStyle(Thema.tinteTertiaer)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: Ablauf

    private func neuesGespraech() {
        let neu = TutorChat(titel: "Neues Gespräch")
        kontext.insert(neu)
        neu.lehrveranstaltung = lv
        gewaehlterChat = neu
        fehler = nil
    }

    private func abbrechen() {
        aufgabe?.cancel()
        aufgabe = nil
        laeuft = false
    }

    private func senden() {
        let frage = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frage.isEmpty, !laeuft else { return }
        guard KI.istEingerichtet else {
            fehler = KIFehler.keinSchluessel.errorDescription
            return
        }
        let aktuellerChat: TutorChat
        if let chat {
            aktuellerChat = chat
        } else {
            aktuellerChat = TutorChat(titel: String(frage.prefix(60)))
            kontext.insert(aktuellerChat)
            aktuellerChat.lehrveranstaltung = lv
        }
        if aktuellerChat.titel == "Neues Gespräch" { aktuellerChat.titel = String(frage.prefix(60)) }
        gewaehlterChat = aktuellerChat
        let verlauf = aktuellerChat.sortierteNachrichten.suffix(12)
        let nutzerNachricht = TutorNachricht(vonNutzer: true, text: frage, modus: modus)
        kontext.insert(nutzerNachricht)
        nutzerNachricht.chat = aktuellerChat
        eingabe = ""
        fehler = nil
        stream = ""
        laeuft = true

        let quellen = nurUnterlagen ? TutorSuche.auszuege(fuer: frage, in: lv) : []
        var system = KIAnweisungen.basis + KIAnweisungen.kontext(lv) + "\n\n" + modus.anweisung
        if modus.mitStruktur { system += KIAnweisungen.struktur }
        if nurUnterlagen {
            system += """


            Beantworte ausschließlich auf Grundlage der beigefügten Auszüge aus den Unterlagen der Studierenden. \
            Steht die Antwort nicht darin, sag das deutlich und nenne, was in den Unterlagen fehlt.
            """
        }
        var nachrichtenKI = verlauf.map { KINachricht(rolle: $0.vonNutzer ? .nutzer : .assistent, text: $0.text) }
        nachrichtenKI.append(KINachricht(rolle: .nutzer, text: frage, dokumente: quellen.map(\.dokument)))
        let anfrage = KIAnfrage(modell: KI.modell, system: system, nachrichten: nachrichtenKI,
                                maxTokens: 16_000, aufwand: modus == .pruefungsniveau ? .hoch : .mittel)
        let gewaehlterModus = modus

        aufgabe = Task {
            do {
                let (text, zitate) = try await KI.vollstaendig(anfrage) { teil in stream = teil }
                let antwort = TutorNachricht(vonNutzer: false, text: text, modus: gewaehlterModus)
                var gefunden: [TutorQuelle] = []
                for zitat in zitate where quellen.indices.contains(zitat.dokumentIndex) {
                    let quelle = quellen[zitat.dokumentIndex].quelle
                    if !gefunden.contains(quelle) { gefunden.append(quelle) }
                }
                antwort.quellen = gefunden
                kontext.insert(antwort)
                antwort.chat = aktuellerChat
            } catch is CancellationError {
            } catch {
                fehler = error.localizedDescription
            }
            stream = ""
            laeuft = false
        }
    }

    private func quelleOeffnen(_ quelle: TutorQuelle) {
        guard let kennung = quelle.dokument,
              let dokument = (lv.dokumente ?? []).first(where: { $0.kennung == kennung })
                ?? (try? kontext.fetch(FetchDescriptor<Dokument>()))?.first(where: { $0.kennung == kennung }) else { return }
        oeffnen(dokument, quelle.seite)
    }

    private func alsKarteSpeichern(_ antwort: TutorNachricht) {
        guard let chat = antwort.chat else { return }
        let liste = chat.sortierteNachrichten
        guard let position = liste.firstIndex(where: { $0 === antwort }), position > 0 else { return }
        let frage = liste[position - 1].text
        let zerlegt = Antwortstruktur.zerlegen(antwort.text)
        let karte = Karteikarte(typ: .frageAntwort, vorderseite: frage, rueckseite: zerlegt.haupttext, thema: "Tutor")
        karte.quelle = .ki
        kontext.insert(karte)
        karte.lehrveranstaltung = lv
    }
}

/// Eine Nachricht im Verlauf.
private struct NachrichtAnsicht: View {
    let nachricht: TutorNachricht
    var quelleOeffnen: (TutorQuelle) -> Void
    var alsKarte: () -> Void
    @State private var gespeichert = false

    var body: some View {
        if nachricht.vonNutzer {
            HStack {
                Spacer(minLength: 80)
                Text(verbatim: nachricht.text)
                    .font(Thema.ui(15))
                    .foregroundStyle(Thema.tinte)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Thema.flaecheGedaempft, in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tutor · \(nachricht.modus.name)")
                    .font(Thema.ui(11))
                    .foregroundStyle(Thema.tinteTertiaer)
                StrukturierteAntwort(text: nachricht.text)
                HStack(spacing: 6) {
                    if !nachricht.quellen.isEmpty {
                        Text("Quellen:").font(Thema.ui(12)).foregroundStyle(Thema.tinteSekundaer)
                        ForEach(Array(nachricht.quellen.enumerated()), id: \.offset) { index, quelle in
                            if index > 0 { Text(verbatim: "·").foregroundStyle(Thema.tinteTertiaer) }
                            Button(quelle.titel) { quelleOeffnen(quelle) }
                                .buttonStyle(.plain)
                                .font(Thema.ui(12))
                                .underline()
                                .foregroundStyle(Thema.tinteSekundaer)
                        }
                    }
                    Spacer()
                    Button(gespeichert ? "Als Karte gespeichert" : "Als Karteikarte speichern") {
                        alsKarte()
                        gespeichert = true
                    }
                    .buttonStyle(.plain)
                    .font(Thema.ui(11))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .disabled(gespeichert)
                }
            }
        }
    }
}

/// Auszüge aus den Unterlagen für „Nur meine Unterlagen“ (BM25 über Seitentexte).
@MainActor
enum TutorSuche {
    struct Auszug {
        let dokument: KIDokument
        let quelle: TutorQuelle
    }

    static func auszuege(fuer frage: String, in lv: Lehrveranstaltung, anzahl: Int = 6) -> [Auszug] {
        // Unterlagen dieser Lehrveranstaltung und der vorherigen Teile ihres Lernpfads
        var lvs = [lv]
        if let pfad = lv.lernpfad {
            lvs += pfad.sortierteTeile.filter { $0.lernpfadTeil < lv.lernpfadTeil }
        }
        var seiten: [String: (dokument: Dokument, nummer: Int, text: String)] = [:]
        var eintraege: [Suchindex.Eintrag] = []
        for dokument in lvs.flatMap({ $0.dokumente ?? [] }) {
            for seite in dokument.sortierteSeiten where !seite.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let id = "\(dokument.kennung.uuidString)|\(seite.nummer)"
                seiten[id] = (dokument, seite.nummer, seite.text)
                eintraege.append(.init(id: id, text: dokument.titel + "\n" + seite.text))
            }
            if dokument.typ == .audio, !dokument.transkriptText.isEmpty {
                let id = "\(dokument.kennung.uuidString)|transkript"
                seiten[id] = (dokument, 0, dokument.transkriptText)
                eintraege.append(.init(id: id, text: dokument.titel + "\n" + dokument.transkriptText))
            }
        }
        let treffer = Suchindex(eintraege).suchen(frage, anzahl: anzahl)
        return treffer.compactMap { eintrag in
            guard let fund = seiten[eintrag.id] else { return nil }
            let dokument = fund.dokument
            let art = dokument.typ == .praesentation ? "Folie" : "Seite"
            let titel = dokument.typ == .audio ? "\(dokument.titel), Transkript" : "\(dokument.titel), \(art) \(fund.nummer + 1)"
            return Auszug(dokument: KIDokument(titel: titel, text: String(fund.text.prefix(8_000))),
                          quelle: TutorQuelle(titel: titel, dokument: dokument.kennung, seite: fund.nummer))
        }
    }
}
