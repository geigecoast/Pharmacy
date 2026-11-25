import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PharmaCore

/// Karte anlegen oder bearbeiten (alle vier Typen, inkl. Masken für Bild-Okklusion).
struct KarteBearbeiten: View {
    private let karte: Karteikarte?
    private let lv: Lehrveranstaltung?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var kontext

    @State private var typ: KartenTyp
    @State private var vorderseite: String
    @State private var rueckseite: String
    @State private var optionen: [String]
    @State private var richtige: Set<Int>
    @State private var bild: Data?
    @State private var masken: [CGRect]
    @State private var thema: String
    @State private var prioritaet: Bool
    @State private var impp: Bool
    @State private var zeigeBildImport = false
    @State private var zeigeLoeschen = false

    init(karte: Karteikarte) {
        self.karte = karte
        self.lv = karte.lehrveranstaltung
        _typ = State(initialValue: karte.typ)
        _vorderseite = State(initialValue: karte.vorderseite)
        _rueckseite = State(initialValue: karte.rueckseite)
        _optionen = State(initialValue: karte.optionen.isEmpty ? ["", "", "", ""] : karte.optionen)
        _richtige = State(initialValue: Set(karte.richtigeOptionen))
        _bild = State(initialValue: karte.bildDaten)
        _masken = State(initialValue: karte.masken)
        _thema = State(initialValue: karte.thema)
        _prioritaet = State(initialValue: karte.prioritaet)
        _impp = State(initialValue: karte.istIMPP)
    }

    init(neuFuer lv: Lehrveranstaltung) {
        self.karte = nil
        self.lv = lv
        _typ = State(initialValue: .frageAntwort)
        _vorderseite = State(initialValue: "")
        _rueckseite = State(initialValue: "")
        _optionen = State(initialValue: ["", "", "", ""])
        _richtige = State(initialValue: [])
        _bild = State(initialValue: nil)
        _masken = State(initialValue: [])
        _thema = State(initialValue: "")
        _prioritaet = State(initialValue: false)
        _impp = State(initialValue: false)
    }

    private var bereinigteOptionen: [String] {
        optionen.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private var gueltig: Bool {
        switch typ {
        case .frageAntwort:
            !vorderseite.trimmingCharacters(in: .whitespaces).isEmpty && !rueckseite.trimmingCharacters(in: .whitespaces).isEmpty
        case .lueckentext:
            Lueckentext.hatLuecke(vorderseite)
        case .multipleChoice:
            !vorderseite.isEmpty && bereinigteOptionen.filter { !$0.isEmpty }.count >= 2
                && richtige.contains { bereinigteOptionen.indices.contains($0) && !bereinigteOptionen[$0].isEmpty }
        case .bildOkklusion:
            bild != nil && !masken.isEmpty
        }
    }

    private var themen: [String] {
        Array(Set((lv?.karteikarten ?? []).map(\.thema).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kartentyp", selection: $typ) {
                        ForEach(KartenTyp.allCases) { typ in
                            Text(typ.name).tag(typ)
                        }
                    }
                }
                switch typ {
                case .frageAntwort: frageAntwort
                case .lueckentext: lueckentext
                case .multipleChoice: multipleChoice
                case .bildOkklusion: bildOkklusion
                }
                Section("Einordnung") {
                    HStack {
                        TextField("Thema (z. B. Komplexometrie)", text: $thema)
                        if !themen.isEmpty {
                            Menu {
                                ForEach(themen, id: \.self) { vorhanden in
                                    Button(vorhanden) { thema = vorhanden }
                                }
                            } label: {
                                Image(systemName: "chevron.down.circle")
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .fixedSize()
                        }
                    }
                    Toggle("Prüfungsrelevant (wird bevorzugt)", isOn: $prioritaet)
                    if typ == .multipleChoice {
                        Toggle("IMPP-Altfrage", isOn: $impp)
                    }
                }
                if let karte {
                    Section {
                        LabeledContent("Lernstand", value: karte.stand.zustand.name)
                        if karte.wiederholungen > 0 {
                            LabeledContent("Wiederholungen", value: "\(karte.wiederholungen), davon \(karte.fehlschlaege) vergessen")
                        }
                        Button("Lernstand zurücksetzen") { karte.stand = .neu() }
                        Button("Karte löschen …", role: .destructive) { zeigeLoeschen = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(karte == nil ? "Neue Karte" : "Karte bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { sichern() }
                        .disabled(!gueltig)
                }
            }
            .fileImporter(isPresented: $zeigeBildImport, allowedContentTypes: [.image]) { ergebnis in
                if case .success(let url) = ergebnis {
                    let zugriff = url.startAccessingSecurityScopedResource()
                    defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
                    if let daten = try? Data(contentsOf: url) {
                        bild = daten
                        masken = []
                    }
                }
            }
            .confirmationDialog("Karte löschen?", isPresented: $zeigeLoeschen, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let karte { kontext.delete(karte) }
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    // MARK: Typen

    @ViewBuilder
    private var frageAntwort: some View {
        Section("Frage") {
            TextField("Frage", text: $vorderseite, axis: .vertical)
                .lineLimit(2...8)
        }
        Section("Antwort") {
            TextField("Antwort", text: $rueckseite, axis: .vertical)
                .lineLimit(2...12)
        }
    }

    @ViewBuilder
    private var lueckentext: some View {
        Section {
            TextField("Text", text: $vorderseite, axis: .vertical)
                .lineLimit(3...10)
            if Lueckentext.hatLuecke(vorderseite) {
                LabeledContent("Vorschau", value: Lueckentext.frage(vorderseite))
            }
        } header: {
            Text("Lückentext")
        } footer: {
            Text("Lücken in doppelte geschweifte Klammern setzen: „Paracetamol hemmt {{COX-2}} im ZNS.“")
        }
        Section("Zusatz (optional)") {
            TextField("Erscheint auf der Antwortseite", text: $rueckseite, axis: .vertical)
        }
    }

    @ViewBuilder
    private var multipleChoice: some View {
        Section("Frage") {
            TextField("Frage, z. B. „Welche Aussage trifft zu?“", text: $vorderseite, axis: .vertical)
                .lineLimit(2...8)
        }
        Section {
            ForEach(optionen.indices, id: \.self) { index in
                HStack {
                    Button {
                        if richtige.contains(index) { richtige.remove(index) } else { richtige.insert(index) }
                    } label: {
                        Image(systemName: richtige.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(richtige.contains(index) ? Thema.tinte : Thema.tinteTertiaer)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(richtige.contains(index) ? "Richtig" : "Falsch")
                    TextField("Antwort \(Karteikarte.buchstabe(index))", text: Binding(
                        get: { optionen.indices.contains(index) ? optionen[index] : "" },
                        set: { if optionen.indices.contains(index) { optionen[index] = $0 } }
                    ))
                    if optionen.count > 2 {
                        Button {
                            entfernen(index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Antwort entfernen")
                    }
                }
            }
            if optionen.count < 8 {
                Button("Antwort hinzufügen") { optionen.append("") }
            }
        } header: {
            Text("Antworten")
        } footer: {
            Text("Richtige Antworten mit dem Kreis markieren – auch mehrere (Mehrfachauswahl).")
        }
        Section("Erklärung (optional)") {
            TextField("Warum ist das richtig?", text: $rueckseite, axis: .vertical)
        }
    }

    @ViewBuilder
    private var bildOkklusion: some View {
        Section {
            if let bild {
                MaskenEditor(bild: bild, masken: $masken)
                    .frame(minHeight: 260, maxHeight: 420)
                HStack {
                    Text("\(masken.count) Masken")
                        .foregroundStyle(Thema.tinteSekundaer)
                    Spacer()
                    if !masken.isEmpty {
                        Button("Alle Masken entfernen") { masken = [] }
                    }
                    Button("Anderes Bild …") { zeigeBildImport = true }
                }
            } else {
                Button("Bild wählen …") { zeigeBildImport = true }
            }
        } header: {
            Text("Bild")
        } footer: {
            Text("Ziehe Rechtecke über Beschriftungen, z. B. Strukturformeln oder Abbildungen. Tippe auf eine Maske, um sie zu entfernen.")
        }
        Section("Text (optional)") {
            TextField("Frage, z. B. „Benenne die markierten Gruppen“", text: $vorderseite, axis: .vertical)
            TextField("Zusatz auf der Antwortseite", text: $rueckseite, axis: .vertical)
        }
    }

    private func entfernen(_ index: Int) {
        guard optionen.indices.contains(index) else { return }
        optionen.remove(at: index)
        richtige = Set(richtige.compactMap { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) })
    }

    private func sichern() {
        let ziel: Karteikarte
        if let karte {
            ziel = karte
        } else {
            ziel = Karteikarte(typ: typ)
            kontext.insert(ziel)
            ziel.lehrveranstaltung = lv
        }
        ziel.typ = typ
        ziel.vorderseite = vorderseite.trimmingCharacters(in: .whitespacesAndNewlines)
        ziel.rueckseite = rueckseite.trimmingCharacters(in: .whitespacesAndNewlines)
        ziel.thema = thema.trimmingCharacters(in: .whitespaces)
        ziel.prioritaet = prioritaet
        ziel.istIMPP = typ == .multipleChoice && impp
        if typ == .multipleChoice {
            let paare = bereinigteOptionen.enumerated().filter { !$0.element.isEmpty }
            ziel.optionen = paare.map(\.element)
            ziel.richtigeOptionen = paare.enumerated().compactMap { neuerIndex, paar in
                richtige.contains(paar.offset) ? neuerIndex : nil
            }
        } else {
            ziel.optionen = []
            ziel.richtigeOptionen = []
        }
        ziel.bildDaten = typ == .bildOkklusion ? bild : nil
        ziel.masken = typ == .bildOkklusion ? masken : []
        dismiss()
    }
}

/// Rechtecke über ein Bild ziehen (Masken in relativen Koordinaten).
struct MaskenEditor: View {
    let bild: Data
    @Binding var masken: [CGRect]
    @State private var entwurf: CGRect?

    var body: some View {
        if let plattformBild = PlattformBild(data: bild) {
            Image(plattformBild: plattformBild)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 4)
                                        .onChanged { wert in
                                            entwurf = Self.rechteck(wert.startLocation, wert.location, in: geo.size)
                                        }
                                        .onEnded { _ in
                                            if let entwurf, entwurf.width > 0.01, entwurf.height > 0.01 {
                                                masken.append(entwurf)
                                            }
                                            entwurf = nil
                                        }
                                )
                            ForEach(Array(masken.enumerated()), id: \.offset) { index, maske in
                                maskenAnsicht(maske, in: geo.size, gestrichelt: false)
                                    .onTapGesture {
                                        if masken.indices.contains(index) { masken.remove(at: index) }
                                    }
                            }
                            if let entwurf {
                                maskenAnsicht(entwurf, in: geo.size, gestrichelt: true)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
        } else {
            Text("Bild kann nicht angezeigt werden.")
        }
    }

    private func maskenAnsicht(_ maske: CGRect, in groesse: CGSize, gestrichelt: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Stoffgebiet.h.farbe.opacity(gestrichelt ? 0.25 : 0.85))
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Stoffgebiet.h.farbe, style: StrokeStyle(lineWidth: 1.5, dash: gestrichelt ? [4] : [])))
            .frame(width: groesse.width * maske.width, height: groesse.height * maske.height)
            .position(x: groesse.width * maske.midX, y: groesse.height * maske.midY)
    }

    static func rechteck(_ a: CGPoint, _ b: CGPoint, in groesse: CGSize) -> CGRect {
        guard groesse.width > 0, groesse.height > 0 else { return .zero }
        let x1 = min(max(min(a.x, b.x), 0), groesse.width)
        let x2 = min(max(max(a.x, b.x), 0), groesse.width)
        let y1 = min(max(min(a.y, b.y), 0), groesse.height)
        let y2 = min(max(max(a.y, b.y), 0), groesse.height)
        return CGRect(x: x1 / groesse.width, y: y1 / groesse.height,
                      width: (x2 - x1) / groesse.width, height: (y2 - y1) / groesse.height)
    }
}
