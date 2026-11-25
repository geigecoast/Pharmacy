import SwiftUI
import SwiftData
import PharmaCore

struct PruefungsvorbereitungAnsicht: View {
    @Bindable var lv: Lehrveranstaltung
    var oeffnen: (Dokument, Int) -> Void = { _, _ in }

    @Environment(\.modelContext) private var kontext
    @State private var zeigeProbeklausur = false
    @State private var offeneProbeklausur: Probeklausur?
    @State private var importArt: AltklausurArt?
    @State private var zeigeImport = false
    @State private var zeigeNotiz = false
    @State private var notiz = ""
    @State private var meldung: String?
    @State private var analysiert = Set<UUID>()

    private var altklausuren: [Altklausur] {
        (lv.altklausuren ?? []).sorted { ($0.jahr ?? 0, $0.importiertAm) > ($1.jahr ?? 0, $1.importiertAm) }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if geo.size.width > 860 {
                    HStack(alignment: .top, spacing: 56) {
                        links.frame(maxWidth: 420)
                        rechts.frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 36)
                } else {
                    VStack(alignment: .leading, spacing: 44) {
                        links
                        rechts
                    }
                    .padding(.vertical, 36)
                }
            }
        }
        .sheet(isPresented: $zeigeProbeklausur) {
            ProbeklausurSitzung(lv: lv)
        }
        .sheet(item: $offeneProbeklausur) { klausur in
            ProbeklausurSitzung(lv: lv, vorhanden: klausur)
        }
        .fileImporter(isPresented: $zeigeImport, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { ergebnis in
            guard case .success(let urls) = ergebnis, let art = importArt else { return }
            Task {
                for url in urls {
                    do {
                        let klausur = try await PruefungsKI.importieren(url: url, art: art, in: lv, kontext: kontext)
                        if KI.istEingerichtet { await analysieren(klausur) }
                    } catch {
                        meldung = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $zeigeNotiz) {
            NavigationStack {
                Form {
                    Section {
                        TextField("z. B. „Prof. Kaiser hat Komplexometrie und Grenzprüfungen mehrfach betont.“", text: $notiz, axis: .vertical)
                            .lineLimit(4...12)
                    } footer: {
                        Text("Betonte Themen fließen in die Prüfungsprognose ein.")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Notiz zum Prüfer")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { zeigeNotiz = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            let neu = PruefungsKI.notizAnlegen(notiz, in: lv, kontext: kontext)
                            notiz = ""
                            zeigeNotiz = false
                            if KI.istEingerichtet { Task { await analysieren(neu) } }
                        }
                        .disabled(notiz.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 300)
            #endif
        }
    }

    // MARK: Links: Teilprüfungen und Probeklausuren

    private var links: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel(titel: "Teilprüfungen") {
                Menu {
                    ForEach(TeilpruefungTyp.allCases) { typ in
                        Button(typ.name) { hinzufuegen(typ) }
                    }
                } label: {
                    Text("Hinzufügen").underline()
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
                TeilpruefungZeile(tp: tp) { kontext.delete(tp) }
            }
            if lv.anmeldepflicht && lv.status != .bestanden {
                Text(Studienregeln.anmeldeHinweis)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .lineSpacing(3)
                    .padding(.top, 18)
            }
            Aktionskarte(titel: "Probeklausur starten", untertitel: probeklausurUntertitel) {
                zeigeProbeklausur = true
            }
            .padding(.top, 28)

            let fruehere = (lv.probeklausuren ?? []).sorted { $0.erstelltAm > $1.erstelltAm }
            if !fruehere.isEmpty {
                Kleintitel(text: "Bisherige Probeklausuren")
                    .padding(.top, 32)
                Haarlinie().padding(.top, 10)
                ForEach(fruehere) { klausur in
                    Button {
                        offeneProbeklausur = klausur
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: klausur.titel).font(Thema.ui(14)).foregroundStyle(Thema.tinte).lineLimit(1)
                                Text(verbatim: "\(klausur.erstelltAm.kurzesDatum) · \(klausur.fragen.count) Fragen · \(klausur.dauerMinuten) min")
                                    .font(Thema.ui(11)).foregroundStyle(Thema.tinteTertiaer)
                            }
                            Spacer()
                            Text(verbatim: klausur.abgegebenAm == nil ? "offen" : "\(Int(klausur.prozent.rounded())) %")
                                .font(Thema.mono(12))
                                .foregroundStyle(Thema.tinteSekundaer)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Haarlinie() }
                    .contextMenu {
                        Button("Löschen", role: .destructive) { kontext.delete(klausur) }
                    }
                }
            }
        }
    }

    private var probeklausurUntertitel: String {
        if let tp = lv.naechsteTeilpruefung {
            let muendlich = tp.typ == .muendlicheEingangspruefung || tp.typ == .muendlicheAbschlusspruefung
            return muendlich ? "Mündliche Prüfungsfragen · 20 min" : "\(tp.typ.name) · im Stil der echten Prüfung"
        }
        return "Im Stil der echten Prüfung · automatisch korrigiert"
    }

    // MARK: Rechts: Prognose und Altklausuren

    private var rechts: some View {
        let prognose = PruefungsKI.prognose(lv)
        let klausuren = (lv.altklausuren ?? []).filter { $0.art != .notiz && $0.analysiert }
        let jahre = klausuren.compactMap(\.jahr)
        let basis = klausuren.isEmpty ? "Basis: noch keine Altklausuren"
            : "Basis: \(klausuren.count) \(klausuren.count == 1 ? "Klausur" : "Klausuren")" + (jahre.isEmpty ? "" : ", \(jahre.min()!)–\(jahre.max()!)")
        return VStack(alignment: .leading, spacing: 0) {
            Abschnittstitel(titel: "Prüfungsprognose") {
                Text(verbatim: basis)
            }
            if prognose.isEmpty {
                Text("Importiere Altklausuren, Probeklausuren, Altfragen oder eine Notiz dazu, was der Prüfer betont hat. Die KI extrahiert die Fragen und Themen; daraus entsteht eine Prognose in drei Stufen – mit Begründung, Datenbasis und Verweis auf die passende Folie.")
                    .font(Thema.ui(14))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .lineSpacing(4)
                    .padding(.vertical, 20)
            }
            ForEach(prognose.prefix(20)) { eintrag in
                PrognoseZeile(eintrag: eintrag, folie: PruefungsKI.folie(zu: eintrag.thema, in: lv)) { dokument, seite in
                    oeffnen(dokument, seite)
                }
            }
            Text("Prognosen beruhen auf Häufigkeit, Aktualität und Punktgewichtung. Keine Garantie.")
                .font(Thema.ui(11))
                .foregroundStyle(Thema.tinteTertiaer)
                .padding(.top, 14)

            Abschnittstitel(titel: "Altklausuren & Notizen") {
                Menu {
                    ForEach([AltklausurArt.klausur, .probeklausur, .altfragen]) { art in
                        Button("\(art.name) importieren …") {
                            importArt = art
                            zeigeImport = true
                        }
                    }
                    Button("Notiz zum Prüfer …") { zeigeNotiz = true }
                } label: {
                    Text("Hinzufügen").underline()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.top, 44)
            if let meldung {
                Text(verbatim: meldung)
                    .font(Thema.ui(12))
                    .foregroundStyle(Stoffgebiet.i.farbe)
                    .padding(.top, 12)
            }
            if altklausuren.isEmpty {
                Text("Noch keine Altklausuren. PDFs und Fotos werden per Texterkennung gelesen.")
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteTertiaer)
                    .padding(.vertical, 16)
            }
            ForEach(altklausuren) { klausur in
                AltklausurZeile(klausur: klausur) {
                    Task { await analysieren(klausur) }
                }
                .contextMenu {
                    Button("Erneut analysieren") { Task { await analysieren(klausur) } }
                    Button("Löschen", role: .destructive) { kontext.delete(klausur) }
                }
            }
        }
    }

    private func analysieren(_ klausur: Altklausur) async {
        guard KI.istEingerichtet else {
            meldung = KIFehler.keinSchluessel.errorDescription
            return
        }
        meldung = nil
        do {
            try await PruefungsKI.analysieren(klausur, kontext: kontext)
        } catch {
            meldung = error.localizedDescription
        }
    }

    private func hinzufuegen(_ typ: TeilpruefungTyp) {
        let tp = Teilpruefung(typ: typ, anmeldepflichtig: lv.anmeldepflicht,
                              sortierung: (lv.teilpruefungen ?? []).count)
        kontext.insert(tp)
        tp.lehrveranstaltung = lv
    }
}

/// Prognose-Zeile: ●●● Stufe · Thema · Begründung · Folie.
private struct PrognoseZeile: View {
    let eintrag: PrognoseEintrag
    let folie: (dokument: Dokument, seite: Int, titel: String)?
    var oeffnen: (Dokument, Int) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(1...3, id: \.self) { punkt in
                        Circle()
                            .fill(punkt <= eintrag.stufe.rawValue ? Thema.tinte : Thema.rahmen)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(verbatim: eintrag.stufe.name)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinte)
            }
            .frame(width: 160, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: eintrag.thema)
                    .font(Thema.ui(15))
                    .foregroundStyle(Thema.tinte)
                Text(verbatim: eintrag.begruendung)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
            Spacer(minLength: 12)
            if let folie {
                Button(folie.titel) { oeffnen(folie.dokument, folie.seite) }
                    .buttonStyle(.plain)
                    .font(Thema.ui(12))
                    .underline()
                    .foregroundStyle(Thema.tinteSekundaer)
                    .help("Passende Stelle in deinen Unterlagen öffnen")
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}

private struct AltklausurZeile: View {
    @Bindable var klausur: Altklausur
    var analysieren: () -> Void

    private var info: String {
        var teile = [klausur.art.name]
        if let jahr = klausur.jahr { teile.append(String(jahr)) }
        if klausur.analysiert {
            if klausur.art == .notiz {
                teile.append(klausur.betonteThemen.isEmpty ? "keine Themen erkannt" : klausur.betonteThemen.joined(separator: ", "))
            } else {
                teile.append("\((klausur.fragen ?? []).count) Fragen")
            }
        }
        return teile.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: klausur.art == .notiz ? "note.text" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(Thema.tinteTertiaer)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: klausur.titel).font(Thema.ui(14)).foregroundStyle(Thema.tinte).lineLimit(2)
                Text(verbatim: info).font(Thema.ui(11)).foregroundStyle(Thema.tinteTertiaer).lineLimit(2)
            }
            Spacer(minLength: 12)
            if klausur.analyseLaeuft {
                ProgressView().controlSize(.small)
            } else if !klausur.analysiert {
                Button("Analysieren (KI)", action: analysieren)
                    .buttonStyle(.plain)
                    .font(Thema.ui(12))
                    .underline()
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Haarlinie() }
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
