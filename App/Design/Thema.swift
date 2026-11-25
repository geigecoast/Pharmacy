import SwiftUI
import CoreText
import PharmaCore

/// Gestaltungsgrundlagen nach dem PharmaTutor-Design: ruhig, fast monochrom,
/// Newsreader für Überschriften, Geist für die Oberfläche, Geist Mono für Nummern und Zeiten.
enum Thema {
    // MARK: Farben

    /// Haupttext und primäre Flächen (z. B. schwarze Aktionskarten).
    static let tinte = Color(hell: 0x111111, dunkel: 0xEDEDEA)
    static let tinteSekundaer = Color(hell: 0x6B6B68, dunkel: 0xA6A6A1)
    static let tinteTertiaer = Color(hell: 0x8A8A86, dunkel: 0x7E7E79)
    /// Text auf `tinte`-Flächen.
    static let tinteInvers = Color(hell: 0xFFFFFF, dunkel: 0x111111)

    static let flaeche = Color(hell: 0xFFFFFF, dunkel: 0x161615)
    static let seitenleiste = Color(hell: 0xF6F6F4, dunkel: 0x1D1D1B)
    static let flaecheGedaempft = Color(hell: 0xF2F2EF, dunkel: 0x232321)
    static let auswahl = Color(hell: 0xEBEBE8, dunkel: 0x2D2D2A)
    static let segmentGrund = Color(hell: 0xEFEFEC, dunkel: 0x262624)
    static let segmentAktiv = Color(hell: 0xFFFFFF, dunkel: 0x3A3A37)

    static let linie = Color(hell: 0xECECEA, dunkel: 0x2C2C2A)
    static let rahmen = Color(hell: 0xE2E2DF, dunkel: 0x383835)
    static let rahmenStark = Color(hell: 0xDCDCD8, dunkel: 0x45453F)

    // MARK: Schriften

    enum Schnitt {
        case leicht, normal, mittel
    }

    /// Große Überschriften (Newsreader, optische Größe für Display).
    static func display(_ groesse: CGFloat, kursiv: Bool = false, schwer: Bool = false) -> Font {
        let name = kursiv ? "PTNewsreaderDisplay-LightItalic" : (schwer ? "PTNewsreaderDisplay-Regular" : "PTNewsreaderDisplay-Light")
        return .custom(name, size: groesse, relativeTo: .largeTitle)
    }

    /// Serifentext in Lesegröße (z. B. Tutor-Antworten, Karteikarten).
    static func serif(_ groesse: CGFloat, kursiv: Bool = false) -> Font {
        .custom(kursiv ? "PTNewsreaderText-LightItalic" : "PTNewsreaderText-Regular", size: groesse, relativeTo: .body)
    }

    /// Oberflächentext (Geist).
    static func ui(_ groesse: CGFloat = 14, _ schnitt: Schnitt = .normal) -> Font {
        let name: String
        switch schnitt {
        case .leicht: name = "PTGeist-Light"
        case .normal: name = "PTGeist-Regular"
        case .mittel: name = "PTGeist-Medium"
        }
        return .custom(name, size: groesse, relativeTo: .body)
    }

    /// Nummern, Zeiten, Lfd. Nr. (Geist Mono).
    static func mono(_ groesse: CGFloat = 12) -> Font {
        .custom("PTGeistMono-Regular", size: groesse, relativeTo: .caption)
    }

    // MARK: Maße

    static let randAussen: CGFloat = 48
    static let randKompakt: CGFloat = 24
    static let radius: CGFloat = 10

    /// Registriert die mitgelieferten Schriften (einmal beim Start).
    static func schriftenRegistrieren() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

extension Stoffgebiet {
    /// Farbpunkt des Stoffgebiets.
    var farbe: Color {
        switch self {
        case .e: Color(hell: 0xC9A27A, dunkel: 0xD4B08C)
        case .f: Color(hell: 0x7FA7C9, dunkel: 0x8FB4D4)
        case .g: Color(hell: 0x8FB58A, dunkel: 0x9DC198)
        case .h: Color(hell: 0xB48AC2, dunkel: 0xC29CCE)
        case .i: Color(hell: 0xD48A8A, dunkel: 0xDD9A9A)
        case .k: Color(hell: 0x9A9A94, dunkel: 0xA8A8A2)
        }
    }

    /// Zarte Hintergrundfarbe, z. B. für Kalendereinträge.
    var hintergrund: Color {
        switch self {
        case .e: Color(hell: 0xF5ECE2, dunkel: 0x3A3127)
        case .f: Color(hell: 0xE6EEF6, dunkel: 0x26313B)
        case .g: Color(hell: 0xE8F1E6, dunkel: 0x283326)
        case .h: Color(hell: 0xF1E7F4, dunkel: 0x342A38)
        case .i: Color(hell: 0xF7E6E6, dunkel: 0x3A2A2A)
        case .k: Color(hell: 0xEFEFEC, dunkel: 0x2E2E2B)
        }
    }
}

// MARK: - Bausteine

/// Feine Trennlinie.
struct Haarlinie: View {
    var farbe: Color = Thema.linie
    var body: some View {
        Rectangle().fill(farbe).frame(height: 1)
    }
}

/// Kleine Überschrift in Großbuchstaben („NÄCHSTE TEILPRÜFUNG“).
struct Kleintitel: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(Thema.ui(11))
            .tracking(0.8)
            .foregroundStyle(Thema.tinteTertiaer)
    }
}

/// Abschnittsüberschrift in Serif mit durchgezogener Linie darunter („Heutiger Plan … 1 von 4 erledigt“).
struct Abschnittstitel<Rechts: View>: View {
    let titel: LocalizedStringKey
    @ViewBuilder var rechts: Rechts

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(titel)
                    .font(Thema.display(26))
                    .foregroundStyle(Thema.tinte)
                Spacer(minLength: 12)
                rechts
                    .font(Thema.ui(12))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
            Haarlinie(farbe: Thema.tinte)
        }
    }
}

extension Abschnittstitel where Rechts == EmptyView {
    init(_ titel: LocalizedStringKey) {
        self.titel = titel
        self.rechts = EmptyView()
    }
}

/// Farbpunkt (Stoffgebiet).
struct Punkt: View {
    var farbe: Color
    var groesse: CGFloat = 6
    var body: some View {
        Circle().fill(farbe).frame(width: groesse, height: groesse)
    }
}

/// Lfd. Nr. in Monospace: „[43]“.
struct LfdNrText: View {
    let text: String
    var groesse: CGFloat = 12
    var farbe: Color = Thema.tinteTertiaer
    var body: some View {
        Text(verbatim: text)
            .font(Thema.mono(groesse))
            .foregroundStyle(farbe)
    }
}

/// Schwarze Aktionskarte mit Pfeil („Schnellquiz starten →“).
struct Aktionskarte: View {
    let titel: LocalizedStringKey
    let untertitel: String
    var aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titel).font(Thema.ui(14, .mittel))
                    Text(verbatim: untertitel).font(Thema.ui(12)).opacity(0.75)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .regular))
            }
            .foregroundStyle(Thema.tinteInvers)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(Thema.tinte, in: RoundedRectangle(cornerRadius: Thema.radius))
            .contentShape(RoundedRectangle(cornerRadius: Thema.radius))
        }
        .buttonStyle(.plain)
    }
}

/// Umrandete Pille; ausgewählt schwarz gefüllt.
struct Pille: View {
    let text: String
    var aktiv = false
    /// Kräftiger Rand ohne Füllung (z. B. Status „Angemeldet“).
    var betont = false
    var aktion: (() -> Void)?

    var body: some View {
        let inhalt = Text(verbatim: text)
            .font(Thema.ui(12, aktiv ? .mittel : .normal))
            .foregroundStyle(aktiv ? Thema.tinteInvers : Thema.tinte)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(aktiv ? Thema.tinte : Color.clear))
            .overlay(Capsule().strokeBorder(aktiv || betont ? Thema.tinte : Thema.rahmenStark))
        if let aktion {
            Button(action: aktion) { inhalt }.buttonStyle(.plain)
        } else {
            inhalt
        }
    }
}

/// Graue Segmentleiste mit weißem aktivem Segment (Semesterwahl, Zusammenfassungsstufen).
struct Segmentleiste<Wert: Hashable>: View {
    let werte: [Wert]
    @Binding var auswahl: Wert
    let titel: (Wert) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(werte, id: \.self) { wert in
                let aktiv = wert == auswahl
                Button {
                    auswahl = wert
                } label: {
                    Text(verbatim: titel(wert))
                        .font(Thema.ui(12, aktiv ? .mittel : .normal))
                        .foregroundStyle(aktiv ? Thema.tinte : Thema.tinteSekundaer)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if aktiv {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Thema.segmentAktiv)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Thema.segmentGrund, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Text-Tabs mit Unterstrich (Vorlesungen · Prüfungsvorbereitung · …).
struct Unterstrichtabs<Wert: Hashable>: View {
    let werte: [Wert]
    @Binding var auswahl: Wert
    let titel: (Wert) -> LocalizedStringKey

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    ForEach(werte, id: \.self) { wert in
                        let aktiv = wert == auswahl
                        Button {
                            auswahl = wert
                        } label: {
                            VStack(spacing: 10) {
                                Text(titel(wert))
                                    .font(Thema.ui(14))
                                    .foregroundStyle(aktiv ? Thema.tinte : Thema.tinteTertiaer)
                                Rectangle()
                                    .fill(aktiv ? Thema.tinte : Color.clear)
                                    .frame(height: 1.5)
                            }
                            .fixedSize()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Haarlinie()
        }
    }
}

/// Fortschrittslinie (dünn, schwarz auf hellgrau).
struct Fortschrittslinie: View {
    let wert: Double
    var hoehe: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Thema.linie)
                Rectangle().fill(Thema.tinte)
                    .frame(width: geo.size.width * min(max(wert, 0), 1))
            }
        }
        .frame(height: hoehe)
    }
}

/// Große Serifenziffer mit Einheit („12 Tage“).
struct GrosseZahl: View {
    let zahl: String
    let einheit: String
    var groesse: CGFloat = 72

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(verbatim: zahl)
                .font(Thema.display(groesse))
                .foregroundStyle(Thema.tinte)
            Text(verbatim: einheit)
                .font(Thema.ui(14))
                .foregroundStyle(Thema.tinteSekundaer)
        }
    }
}

/// Seitenkopf mit großem Serifentitel.
struct Seitentitel: View {
    let titel: String
    var unterzeile: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: titel)
                .font(Thema.display(52))
                .foregroundStyle(Thema.tinte)
                .fixedSize(horizontal: false, vertical: true)
            if let unterzeile {
                Text(verbatim: unterzeile)
                    .font(Thema.ui(15))
                    .foregroundStyle(Thema.tinteSekundaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Zeile „Bezeichnung … Wert“ mit Haarlinie (Einstellungen).
struct Wertzeile<Wert: View>: View {
    let titel: LocalizedStringKey
    @ViewBuilder var wert: Wert

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(titel)
                    .font(Thema.ui(14))
                    .foregroundStyle(Thema.tinte)
                Spacer(minLength: 16)
                wert
                    .font(Thema.ui(14))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
            .padding(.vertical, 18)
            Haarlinie()
        }
    }
}

extension View {
    /// Inhaltsbereich mit großzügigem Rand wie im Design.
    func seitenrand() -> some View {
        padding(.horizontal, Thema.randAussen)
            .padding(.vertical, 40)
    }
}
