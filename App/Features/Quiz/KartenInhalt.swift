import SwiftUI
import PharmaCore

extension Image {
    init(plattformBild bild: PlattformBild) {
        #if os(macOS)
        self.init(nsImage: bild)
        #else
        self.init(uiImage: bild)
        #endif
    }
}

/// Darstellung einer Karte (Frage- oder Antwortseite) für alle vier Kartentypen.
struct KartenInhalt: View {
    let karte: Karteikarte
    let aufgedeckt: Bool
    /// Multiple Choice interaktiv (Quiz); `nil` = nur anzeigen.
    var mcAuswahl: Binding<Set<Int>>?
    /// Bei Multiple Choice: richtige/falsche Optionen hervorheben.
    var mcAufloesen = false

    var body: some View {
        VStack(spacing: 18) {
            Kleintitel(text: aufgedeckt ? "Antwort" : "Frage")
            switch karte.typ {
            case .frageAntwort: frageAntwort
            case .lueckentext: lueckentext
            case .multipleChoice: multipleChoice
            case .bildOkklusion: bildOkklusion
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var frageAntwort: some View {
        VStack(spacing: 18) {
            Text(verbatim: karte.vorderseite)
                .font(Thema.serif(aufgedeckt ? 22 : 28))
                .foregroundStyle(aufgedeckt ? Thema.tinteSekundaer : Thema.tinte)
                .multilineTextAlignment(.center)
            if aufgedeckt {
                Haarlinie().frame(width: 60)
                Text(verbatim: karte.rueckseite)
                    .font(Thema.ui(17))
                    .foregroundStyle(Thema.tinte)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    private var lueckentext: some View {
        VStack(spacing: 14) {
            Text(lueckenText)
                .font(Thema.serif(26))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            if aufgedeckt && !karte.rueckseite.isEmpty {
                Text(verbatim: karte.rueckseite)
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteTertiaer)
            }
        }
    }

    private var lueckenText: AttributedString {
        var ergebnis = AttributedString()
        for teil in Lueckentext.teile(karte.vorderseite) {
            if teil.istLuecke {
                var luecke = AttributedString(aufgedeckt ? teil.text : "[ … ]")
                luecke.swiftUI.foregroundColor = aufgedeckt ? Thema.tinte : Thema.tinteTertiaer
                if aufgedeckt {
                    luecke.swiftUI.underlineStyle = Text.LineStyle(pattern: .solid)
                    luecke.swiftUI.backgroundColor = MarkierungsFarbe.lila.farbe
                }
                ergebnis += luecke
            } else {
                var normal = AttributedString(teil.text)
                normal.swiftUI.foregroundColor = Thema.tinte
                ergebnis += normal
            }
        }
        return ergebnis
    }

    private var multipleChoice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: karte.vorderseite)
                .font(Thema.serif(24))
                .foregroundStyle(Thema.tinte)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(Array(karte.optionen.enumerated()), id: \.offset) { index, option in
                    optionZeile(index: index, text: option)
                }
            }
            if aufgedeckt && !karte.rueckseite.isEmpty {
                Text(verbatim: karte.rueckseite)
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
        }
        .frame(maxWidth: 560)
    }

    private func optionZeile(index: Int, text: String) -> some View {
        let gewaehlt = mcAuswahl?.wrappedValue.contains(index) ?? false
        let richtig = karte.richtigeOptionen.contains(index)
        let aufloesen = aufgedeckt || mcAufloesen
        let hintergrund: Color = {
            if aufloesen && richtig { return Stoffgebiet.g.hintergrund }
            if aufloesen && gewaehlt && !richtig { return Stoffgebiet.i.hintergrund }
            if gewaehlt { return Thema.auswahl }
            return Color.clear
        }()
        return Button {
            guard let auswahl = mcAuswahl, !mcAufloesen else { return }
            if auswahl.wrappedValue.contains(index) {
                auswahl.wrappedValue.remove(index)
            } else {
                auswahl.wrappedValue.insert(index)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: Karteikarte.buchstabe(index))
                    .font(Thema.mono(13))
                    .foregroundStyle(Thema.tinteSekundaer)
                Text(verbatim: text)
                    .font(Thema.ui(15))
                    .foregroundStyle(Thema.tinte)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if aufloesen && richtig {
                    Image(systemName: "checkmark").foregroundStyle(Thema.tinte)
                } else if aufloesen && gewaehlt {
                    Image(systemName: "xmark").foregroundStyle(Stoffgebiet.i.farbe)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(hintergrund, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(gewaehlt ? Thema.tinte : Thema.rahmen))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(mcAuswahl == nil)
    }

    private var bildOkklusion: some View {
        VStack(spacing: 12) {
            if !karte.vorderseite.isEmpty {
                Text(verbatim: karte.vorderseite)
                    .font(Thema.serif(20))
                    .foregroundStyle(Thema.tinte)
                    .multilineTextAlignment(.center)
            }
            if let daten = karte.bildDaten {
                OkklusionsBild(daten: daten, masken: karte.masken, verdeckt: !aufgedeckt)
                    .frame(maxHeight: 420)
            }
            if aufgedeckt && !karte.rueckseite.isEmpty {
                Text(verbatim: karte.rueckseite)
                    .font(Thema.ui(14))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
        }
    }
}

/// Bild mit Masken (verdeckt = gefüllt, aufgedeckt = nur Umriss).
struct OkklusionsBild: View {
    let daten: Data
    let masken: [CGRect]
    let verdeckt: Bool

    var body: some View {
        if let bild = PlattformBild(data: daten) {
            Image(plattformBild: bild)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(masken.enumerated()), id: \.offset) { _, maske in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(verdeckt ? Stoffgebiet.h.farbe : Color.clear)
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Stoffgebiet.h.farbe, lineWidth: 2))
                                    .frame(width: geo.size.width * maske.width, height: geo.size.height * maske.height)
                                    .position(x: geo.size.width * maske.midX, y: geo.size.height * maske.midY)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
        } else {
            Text("Bild kann nicht angezeigt werden.")
                .font(Thema.ui(13))
                .foregroundStyle(Thema.tinteTertiaer)
        }
    }
}

/// Wiederholung fälliger Karten mit FSRS-Bewertung.
struct KartenWiederholung: View {
    let karten: [Karteikarte]
    var titel: LocalizedStringKey = "Karteikarten · fällig"

    @Environment(\.modelContext) private var kontext
    @State private var aufgedeckt = false
    @State private var bewertet = 0
    @State private var start = Date()

    var body: some View {
        let jetzt = Date()
        let schlange = KartenDienst.warteschlange(karten, jetzt: jetzt)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(titel)
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
                Spacer()
                if !schlange.isEmpty {
                    Text("\(bewertet + 1) von \(bewertet + schlange.count)")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                }
            }
            if let karte = schlange.first {
                Button {
                    aufgedeckt.toggle()
                } label: {
                    KartenInhalt(karte: karte, aufgedeckt: aufgedeckt)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .background(Thema.flaeche, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .topTrailing) {
                            if karte.prioritaet {
                                Text("Prüfungsrelevant")
                                    .font(Thema.ui(10))
                                    .foregroundStyle(Thema.tinte)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(MarkierungsFarbe.rot.farbe, in: Capsule())
                                    .padding(14)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Thema.rahmen))
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                if aufgedeckt {
                    bewertungsleiste(karte, jetzt: jetzt)
                } else {
                    Text("Klicken zum Umdrehen · Leertaste")
                        .font(Thema.ui(12))
                        .foregroundStyle(Thema.tinteTertiaer)
                        .frame(maxWidth: .infinity)
                }
            } else {
                leer
            }
        }
    }

    private func bewertungsleiste(_ karte: Karteikarte, jetzt: Date) -> some View {
        let vorschau = KartenDienst.fsrs.vorschau(karte.stand, jetzt: jetzt)
        return HStack(spacing: 10) {
            ForEach(Bewertung.allCases) { bewertung in
                Button {
                    KartenDienst.bewerten(karte, bewertung, dauer: Date().timeIntervalSince(start), kontext: kontext)
                    bewertet += 1
                    aufgedeckt = false
                    start = Date()
                } label: {
                    VStack(spacing: 4) {
                        Text(verbatim: bewertung.name)
                            .font(Thema.ui(13, .mittel))
                            .foregroundStyle(bewertung == .nochmal ? Stoffgebiet.i.farbe : Thema.tinte)
                        Text(verbatim: vorschau[bewertung].map { FSRS.abstandText(von: jetzt, bis: $0.faellig) } ?? "")
                            .font(Thema.mono(11))
                            .foregroundStyle(Thema.tinteTertiaer)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Thema.rahmen))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(bewertung.taste), modifiers: [])
                .help("Taste \(String(bewertung.taste))")
            }
        }
    }

    private var leer: some View {
        let naechste = karten.filter(\.istGueltig).map(\.faellig).filter { $0 > Date() }.min()
        return VStack(spacing: 10) {
            Text(karten.isEmpty ? "Noch keine Karten" : "Alles erledigt für heute.")
                .font(Thema.serif(26))
                .foregroundStyle(Thema.tinte)
            Group {
                if karten.isEmpty {
                    Text("Lege Karten an oder erstelle sie aus deinen Markierungen.")
                } else if let naechste {
                    Text("Nächste Karte fällig in \(FSRS.abstandText(von: Date(), bis: naechste)).")
                }
            }
            .font(Thema.ui(13))
            .foregroundStyle(Thema.tinteSekundaer)
            if bewertet > 0 {
                Text("\(bewertet) Karten in dieser Sitzung wiederholt.")
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteTertiaer)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(Thema.flaecheGedaempft, in: RoundedRectangle(cornerRadius: 14))
    }
}
