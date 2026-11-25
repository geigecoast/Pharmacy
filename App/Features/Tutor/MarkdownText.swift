import SwiftUI
import PharmaCore

/// Leichtgewichtige Markdown-Darstellung: Überschriften, Aufzählungen, **fett**, *kursiv*.
struct MarkdownText: View {
    let text: String
    var schrift: Font = Thema.ui(14)
    var zeilenabstand: CGFloat = 4

    private enum Zeile: Hashable {
        case ueberschrift(String, ebene: Int)
        case punkt(String)
        case nummer(String, String)
        case absatz(String)
        case leer
    }

    private var zeilen: [Zeile] {
        text.components(separatedBy: "\n").map { roh in
            let zeile = roh.trimmingCharacters(in: .whitespaces)
            if zeile.isEmpty { return .leer }
            if zeile.hasPrefix("#") {
                let ebene = zeile.prefix { $0 == "#" }.count
                return .ueberschrift(zeile.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces), ebene: ebene)
            }
            if zeile.hasPrefix("- ") || zeile.hasPrefix("* ") || zeile.hasPrefix("• ") {
                return .punkt(String(zeile.dropFirst(2)))
            }
            if let punkt = zeile.firstIndex(of: "."), zeile[zeile.startIndex..<punkt].allSatisfy(\.isNumber),
               punkt > zeile.startIndex, zeile[zeile.index(after: punkt)...].hasPrefix(" ") {
                return .nummer(String(zeile[...punkt]), String(zeile[zeile.index(punkt, offsetBy: 2)...]))
            }
            return .absatz(zeile)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(zeilen.enumerated()), id: \.offset) { _, zeile in
                switch zeile {
                case .ueberschrift(let text, let ebene):
                    Text(Self.inline(text))
                        .font(ebene <= 2 ? Thema.serif(19) : Thema.ui(14, .mittel))
                        .foregroundStyle(Thema.tinte)
                        .padding(.top, 6)
                case .punkt(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "–").foregroundStyle(Thema.tinteTertiaer)
                        Text(Self.inline(text))
                    }
                    .font(schrift)
                    .lineSpacing(zeilenabstand)
                case .nummer(let nummer, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: nummer).font(Thema.mono(12)).foregroundStyle(Thema.tinteTertiaer)
                        Text(Self.inline(text)).font(schrift)
                    }
                    .lineSpacing(zeilenabstand)
                case .absatz(let text):
                    Text(Self.inline(text))
                        .font(schrift)
                        .lineSpacing(zeilenabstand)
                case .leer:
                    Color.clear.frame(height: 2)
                }
            }
        }
        .foregroundStyle(Thema.tinte)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Darstellung einer strukturierten KI-Antwort: Haupttext und Abschnitte im Raster.
struct StrukturierteAntwort: View {
    let text: String
    var abschnittTitel: [String] = Antwortstruktur.abschnitte
    var hauptSchrift: Font = Thema.serif(19)
    var spalten = 2

    var body: some View {
        let zerlegt = Antwortstruktur.zerlegen(text, titel: abschnittTitel)
        VStack(alignment: .leading, spacing: 22) {
            if !zerlegt.haupttext.isEmpty {
                MarkdownText(text: zerlegt.haupttext, schrift: hauptSchrift, zeilenabstand: 6)
            }
            if !zerlegt.abschnitte.isEmpty {
                let reihen = stride(from: 0, to: zerlegt.abschnitte.count, by: spalten).map {
                    Array(zerlegt.abschnitte[$0..<min($0 + spalten, zerlegt.abschnitte.count)])
                }
                VStack(spacing: 0) {
                    ForEach(Array(reihen.enumerated()), id: \.offset) { reihenIndex, reihe in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(reihe.enumerated()), id: \.offset) { spaltenIndex, abschnitt in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(verbatim: abschnitt.titel)
                                        .textCase(.uppercase)
                                        .font(Thema.ui(11))
                                        .tracking(0.8)
                                        .foregroundStyle(Thema.tinteTertiaer)
                                    MarkdownText(text: abschnitt.text, schrift: Thema.ui(13), zeilenabstand: 3)
                                }
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .overlay(alignment: .leading) {
                                    if spaltenIndex > 0 { Rectangle().fill(Thema.rahmen).frame(width: 1) }
                                }
                            }
                            if reihe.count < spalten {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .overlay(alignment: .top) {
                            if reihenIndex > 0 { Rectangle().fill(Thema.rahmen).frame(height: 1) }
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Thema.rahmen))
            }
        }
    }
}
