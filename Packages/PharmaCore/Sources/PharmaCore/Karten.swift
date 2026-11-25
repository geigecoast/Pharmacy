import Foundation

public enum KartenTyp: String, Codable, CaseIterable, Identifiable, Sendable {
    case frageAntwort
    case lueckentext
    case bildOkklusion
    case multipleChoice

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .frageAntwort: "Frage/Antwort"
        case .lueckentext: "Lückentext"
        case .bildOkklusion: "Bild-Okklusion"
        case .multipleChoice: "Multiple Choice"
        }
    }

    public var symbol: String {
        switch self {
        case .frageAntwort: "questionmark.bubble"
        case .lueckentext: "text.badge.minus"
        case .bildOkklusion: "photo.on.rectangle"
        case .multipleChoice: "list.bullet.circle"
        }
    }
}

public enum KartenQuelle: String, Codable, Sendable {
    case manuell
    case markierung
    case ki
    case impp
}

/// Quizmodi.
public enum QuizModus: String, Codable, CaseIterable, Identifiable, Sendable {
    case schnellquiz
    case themenquiz
    case impp
    case pruefungssimulation

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .schnellquiz: "Schnellquiz"
        case .themenquiz: "Themenquiz"
        case .impp: "IMPP-Modus"
        case .pruefungssimulation: "Prüfungssimulation"
        }
    }

    public var kurzinfo: String {
        switch self {
        case .schnellquiz: "5 min"
        case .themenquiz: "frei"
        case .impp: "MC"
        case .pruefungssimulation: "90 min"
        }
    }

    /// Zeitlimit in Sekunden (nil = ohne Zeitlimit).
    public var zeitlimit: Int? {
        switch self {
        case .schnellquiz: 5 * 60
        case .themenquiz, .impp: nil
        case .pruefungssimulation: 90 * 60
        }
    }

    /// Rückmeldung sofort nach jeder Frage (Simulation: erst am Ende).
    public var sofortRueckmeldung: Bool { self != .pruefungssimulation }
}

/// Lückentexte im Format „Paracetamol hemmt {{COX-2}} im ZNS“.
public enum Lueckentext {
    public struct Teil: Equatable, Sendable {
        public var text: String
        public var istLuecke: Bool
    }

    public static func teile(_ text: String) -> [Teil] {
        var ergebnis: [Teil] = []
        var rest = Substring(text)
        while let start = rest.range(of: "{{") {
            if start.lowerBound > rest.startIndex {
                ergebnis.append(Teil(text: String(rest[rest.startIndex..<start.lowerBound]), istLuecke: false))
            }
            let nachStart = rest[start.upperBound...]
            guard let ende = nachStart.range(of: "}}") else {
                ergebnis.append(Teil(text: String(rest[start.lowerBound...]), istLuecke: false))
                return ergebnis
            }
            var luecke = String(nachStart[nachStart.startIndex..<ende.lowerBound])
            // Anki-Schreibweise {{c1::…}} akzeptieren
            if let trenner = luecke.range(of: "::"), luecke.hasPrefix("c") {
                luecke = String(luecke[trenner.upperBound...])
                if let hinweis = luecke.range(of: "::") { luecke = String(luecke[..<hinweis.lowerBound]) }
            }
            ergebnis.append(Teil(text: luecke, istLuecke: true))
            rest = nachStart[ende.upperBound...]
        }
        if !rest.isEmpty { ergebnis.append(Teil(text: String(rest), istLuecke: false)) }
        return ergebnis
    }

    public static func hatLuecke(_ text: String) -> Bool { teile(text).contains(where: \.istLuecke) }

    /// Frageansicht als Klartext: Lücken durch „[…]“ ersetzt.
    public static func frage(_ text: String) -> String {
        teile(text).map { $0.istLuecke ? "[…]" : $0.text }.joined()
    }

    /// Antwortansicht als Klartext.
    public static func antwort(_ text: String) -> String {
        teile(text).map(\.text).joined()
    }

    public static func luecken(_ text: String) -> [String] {
        teile(text).filter(\.istLuecke).map(\.text)
    }

    /// Anki-Schreibweise: alle Lücken als c1 (eine Karte).
    public static func alsAnki(_ text: String) -> String {
        teile(text).map { $0.istLuecke ? "{{c1::\($0.text)}}" : $0.text }.joined()
    }
}

/// Erzeugt Kartenvorschläge ohne KI, z. B. aus Markierungen.
public enum Kartenvorschlag {
    /// Sucht den Satz mit dem markierten Begriff und macht den Begriff zur Lücke.
    public static func lueckentext(markiert: String, seitentext: String) -> String? {
        let begriff = markiert.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).joined(separator: " ")
        guard begriff.count >= 2 else { return nil }
        let text = seitentext.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let treffer = text.range(of: begriff, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let satzzeichen: Set<Character> = [".", "!", "?", "•", "·", ";"]
        // Satzgrenze: Satzzeichen, auf das ein Leerzeichen oder das Textende folgt (nicht „2.2.24“).
        var anfang = treffer.lowerBound
        while anfang > text.startIndex {
            let davor = text.index(before: anfang)
            if satzzeichen.contains(text[davor]) && text[anfang].isWhitespace { break }
            anfang = davor
        }
        var ende = treffer.upperBound
        while ende < text.endIndex {
            let zeichen = text[ende]
            ende = text.index(after: ende)
            if satzzeichen.contains(zeichen) && (ende == text.endIndex || text[ende].isWhitespace) { break }
        }
        let vorher = text[anfang..<treffer.lowerBound]
        let nachher = text[treffer.upperBound..<ende]
        var satz = (vorher + "{{" + text[treffer] + "}}" + nachher).trimmingCharacters(in: .whitespaces)
        // Ganzer Satz markiert: dann ist eine Lücke über alles wenig sinnvoll
        if Lueckentext.frage(satz).trimmingCharacters(in: .whitespaces) == "[…]" { return nil }
        if satz.count > 400 { satz = String(satz.prefix(400)) + "…" }
        return satz
    }
}

/// Einfacher CSV-Export (Semikolon, Anführungszeichen nach RFC 4180) – von Anki importierbar.
public enum CSV {
    public static func zeile(_ felder: [String]) -> String {
        felder.map { feld in
            let ersetzt = feld.replacingOccurrences(of: "\"", with: "\"\"")
            return ersetzt.contains(";") || ersetzt.contains("\"") || ersetzt.contains("\n") ? "\"\(ersetzt)\"" : ersetzt
        }.joined(separator: ";")
    }

    public static func dokument(_ zeilen: [[String]]) -> String {
        (["#separator:Semicolon", "#html:true"] + zeilen.map(zeile)).joined(separator: "\n") + "\n"
    }
}
