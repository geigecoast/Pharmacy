import Foundation

// MARK: - Anfrage

public struct KIDokument: Sendable, Equatable {
    public var titel: String
    public var text: String

    public init(titel: String, text: String) {
        self.titel = titel
        self.text = text
    }
}

public struct KINachricht: Sendable, Equatable {
    public enum Rolle: String, Sendable { case nutzer = "user", assistent = "assistant" }
    public var rolle: Rolle
    public var text: String
    /// Nur bei Nutzernachrichten: Auszüge aus den Unterlagen (mit Zitaten).
    public var dokumente: [KIDokument]

    public init(rolle: Rolle, text: String, dokumente: [KIDokument] = []) {
        self.rolle = rolle
        self.text = text
        self.dokumente = dokumente
    }
}

public struct KIAnfrage: Sendable {
    public enum Aufwand: String, Sendable { case niedrig = "low", mittel = "medium", hoch = "high" }

    public var modell: String
    public var system: String
    public var nachrichten: [KINachricht]
    public var maxTokens: Int
    public var aufwand: Aufwand
    /// JSON-Schema für strukturierte Ausgaben (als JSON-Daten). Nicht zusammen mit Zitaten verwendbar.
    public var schema: Data?

    public init(modell: String, system: String, nachrichten: [KINachricht], maxTokens: Int = 16_000,
                aufwand: Aufwand = .mittel, schema: Data? = nil) {
        self.modell = modell
        self.system = system
        self.nachrichten = nachrichten
        self.maxTokens = maxTokens
        self.aufwand = aufwand
        self.schema = schema
    }
}

/// Aufbau der Anfragen an die Claude-API (Messages, Streaming).
public enum ClaudeAPI {
    public static let endpunkt = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let version = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public static let modelle: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5 (empfohlen)"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5 (schneller, günstiger)"),
        ("claude-haiku-5-5", "Claude Haiku 5.5 (am günstigsten)"),
    ]
    public static let standardModell = "claude-opus-5-5"

    /// Server-seitiger Rückfall bei Ablehnungen (nicht für Haiku verfügbar).
    static func unterstuetztFallback(_ modell: String) -> Bool { !modell.contains("haiku") }

    public static func kopfzeilen(schluessel: String, modell: String) -> [String: String] {
        var kopf = [
            "content-type": "application/json",
            "x-api-key": schluessel,
            "anthropic-version": version,
        ]
        if unterstuetztFallback(modell) { kopf["anthropic-beta"] = fallbackBeta }
        return kopf
    }

    public static func koerper(_ anfrage: KIAnfrage) throws -> Data {
        let zitate = anfrage.schema == nil
        let nachrichten: [[String: Any]] = anfrage.nachrichten.map { nachricht in
            guard nachricht.rolle == .nutzer, !nachricht.dokumente.isEmpty else {
                return ["role": nachricht.rolle.rawValue, "content": nachricht.text]
            }
            var inhalt: [[String: Any]] = nachricht.dokumente.map { dokument in
                var block: [String: Any] = [
                    "type": "document",
                    "source": ["type": "text", "media_type": "text/plain", "data": dokument.text],
                    "title": dokument.titel,
                ]
                if zitate { block["citations"] = ["enabled": true] }
                return block
            }
            inhalt.append(["type": "text", "text": nachricht.text])
            return ["role": "user", "content": inhalt]
        }
        var ausgabe: [String: Any] = ["effort": anfrage.aufwand.rawValue]
        if let schema = anfrage.schema, let objekt = try? JSONSerialization.jsonObject(with: schema) {
            ausgabe["format"] = ["type": "json_schema", "schema": objekt]
        }
        var koerper: [String: Any] = [
            "model": anfrage.modell,
            "max_tokens": anfrage.maxTokens,
            "stream": true,
            "system": [["type": "text", "text": anfrage.system, "cache_control": ["type": "ephemeral"]]],
            "messages": nachrichten,
            "output_config": ausgabe,
        ]
        if unterstuetztFallback(anfrage.modell) { koerper["fallbacks"] = "default" }
        return try JSONSerialization.data(withJSONObject: koerper, options: [.sortedKeys])
    }

    /// Fehlermeldung aus einer JSON-Fehlerantwort der API.
    public static func fehlermeldung(aus daten: Data) -> (typ: String, meldung: String)? {
        guard let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let fehler = objekt["error"] as? [String: Any] else { return nil }
        return (fehler["type"] as? String ?? "", fehler["message"] as? String ?? "")
    }
}

// MARK: - Streaming

public struct KIZitat: Sendable, Equatable {
    public var dokumentIndex: Int
    public var dokumentTitel: String?
    public var zitierterText: String
}

public enum KIEreignis: Sendable, Equatable {
    case text(String)
    case zitat(KIZitat)
    case ende(stopGrund: String?)
    case fehler(typ: String, meldung: String)
}

/// Zerlegt Server-Sent Events der Claude-API zeilenweise.
public struct SSEZerleger: Sendable {
    private var stopGrund: String?

    public init() {}

    public mutating func zeile(_ zeile: String) -> [KIEreignis] {
        guard zeile.hasPrefix("data:") else { return [] }
        let json = zeile.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let daten = json.data(using: .utf8),
              let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let typ = objekt["type"] as? String else { return [] }
        switch typ {
        case "content_block_delta":
            guard let delta = objekt["delta"] as? [String: Any], let art = delta["type"] as? String else { return [] }
            if art == "text_delta", let text = delta["text"] as? String {
                return [.text(text)]
            }
            if art == "citations_delta", let zitat = delta["citation"] as? [String: Any] {
                return [.zitat(KIZitat(dokumentIndex: zitat["document_index"] as? Int ?? 0,
                                       dokumentTitel: zitat["document_title"] as? String,
                                       zitierterText: zitat["cited_text"] as? String ?? ""))]
            }
            return []
        case "message_delta":
            if let delta = objekt["delta"] as? [String: Any], let grund = delta["stop_reason"] as? String {
                stopGrund = grund
            }
            return []
        case "message_stop":
            return [.ende(stopGrund: stopGrund)]
        case "error":
            let fehler = objekt["error"] as? [String: Any]
            return [.fehler(typ: fehler?["type"] as? String ?? "error", meldung: fehler?["message"] as? String ?? "")]
        default:
            return []
        }
    }
}

// MARK: - Antwortstruktur

/// Zerlegt Tutor-Antworten in Haupttext und die festen Abschnitte (Merksatz, Signalwörter, …).
public enum Antwortstruktur {
    public static let abschnitte = ["Merksatz", "Signalwörter", "Typische Falle", "In der Klausur"]

    public struct Zerlegt: Equatable, Sendable {
        public var haupttext: String
        public var abschnitte: [(titel: String, text: String)]

        public static func == (a: Zerlegt, b: Zerlegt) -> Bool {
            a.haupttext == b.haupttext && a.abschnitte.map { $0.titel } == b.abschnitte.map { $0.titel }
                && a.abschnitte.map { $0.text } == b.abschnitte.map { $0.text }
        }
    }

    /// Erkennt Überschriften „### Merksatz“ (auch „## “, „**Merksatz**“ oder „Merksatz:“ am Zeilenanfang).
    public static func zerlegen(_ text: String, titel: [String] = abschnitte) -> Zerlegt {
        var haupt: [String] = []
        var gefunden: [(titel: String, text: [String])] = []
        for zeile in text.components(separatedBy: "\n") {
            if let treffer = ueberschrift(zeile, titel: titel) {
                gefunden.append((treffer.titel, treffer.rest.isEmpty ? [] : [treffer.rest]))
            } else if gefunden.isEmpty {
                haupt.append(zeile)
            } else {
                gefunden[gefunden.count - 1].text.append(zeile)
            }
        }
        return Zerlegt(
            haupttext: haupt.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            abschnitte: gefunden.map { ($0.titel, $0.text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    private static func ueberschrift(_ zeile: String, titel: [String]) -> (titel: String, rest: String)? {
        var rest = zeile.trimmingCharacters(in: .whitespaces)
        while rest.hasPrefix("#") { rest.removeFirst() }
        rest = rest.trimmingCharacters(in: .whitespaces)
        let ohneFett = rest.replacingOccurrences(of: "**", with: "")
        for kandidat in titel {
            guard ohneFett.lowercased().hasPrefix(kandidat.lowercased()) else { continue }
            let nach = ohneFett.dropFirst(kandidat.count)
            let getrimmt = nach.trimmingCharacters(in: .whitespaces)
            // Nur echte Überschriften: Zeile endet nach dem Titel oder es folgt ein Doppelpunkt.
            if getrimmt.isEmpty { return (kandidat, "") }
            if getrimmt.hasPrefix(":") {
                return (kandidat, getrimmt.dropFirst().trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
}

// MARK: - Suche für „Nur meine Unterlagen“

/// BM25-Suche über Seitentexte (einfaches deutsches Stemming, ohne Stoppwörter).
public struct Suchindex: Sendable {
    public struct Eintrag: Sendable {
        public var id: String
        public var text: String
        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    private let dokumente: [(id: String, haeufigkeit: [String: Int], laenge: Int)]
    private let dokumentFrequenz: [String: Int]
    private let mittlereLaenge: Double

    static let stoppwoerter: Set<String> = [
        "der", "die", "das", "und", "oder", "ein", "eine", "einer", "eines", "einem", "einen", "ist", "sind", "wird",
        "werden", "wie", "was", "wer", "wo", "mit", "von", "vom", "zu", "zum", "zur", "im", "in", "an", "am", "auf",
        "fur", "bei", "nach", "aus", "als", "auch", "nicht", "es", "sie", "er", "ich", "du", "wir", "ihr", "den", "dem",
        "des", "sich", "dass", "kann", "konnen", "uber", "unter", "durch", "zwischen", "welche", "welcher", "welches",
        "the", "and", "of",
    ]

    public init(_ eintraege: [Eintrag]) {
        var dokumente: [(id: String, haeufigkeit: [String: Int], laenge: Int)] = []
        var frequenz: [String: Int] = [:]
        for eintrag in eintraege {
            let woerter = Self.woerter(eintrag.text)
            let haeufigkeit = woerter.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            for wort in haeufigkeit.keys { frequenz[wort, default: 0] += 1 }
            dokumente.append((id: eintrag.id, haeufigkeit: haeufigkeit, laenge: woerter.count))
        }
        self.dokumente = dokumente
        self.dokumentFrequenz = frequenz
        self.mittlereLaenge = dokumente.isEmpty ? 1 : Double(dokumente.map { $0.laenge }.reduce(0, +)) / Double(dokumente.count)
    }

    public static func woerter(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 && !stoppwoerter.contains($0) }
            .map(stamm)
    }

    /// Sehr einfaches Stemming für deutsche Endungen.
    static func stamm(_ wort: String) -> String {
        guard wort.count > 5 else { return wort }
        for endung in ["ungen", "ung", "en", "er", "es", "em", "e", "s"] where wort.hasSuffix(endung) && wort.count - endung.count >= 4 {
            return String(wort.dropLast(endung.count))
        }
        return wort
    }

    public func suchen(_ anfrage: String, anzahl: Int = 6) -> [(id: String, wert: Double)] {
        let begriffe = Set(Self.woerter(anfrage))
        guard !begriffe.isEmpty else { return [] }
        let n = Double(dokumente.count)
        let k1 = 1.5
        let b = 0.75
        var ergebnis: [(id: String, wert: Double)] = []
        for dokument in dokumente {
            var wert = 0.0
            for begriff in begriffe {
                guard let tf = dokument.haeufigkeit[begriff] else { continue }
                let df = Double(dokumentFrequenz[begriff] ?? 0)
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                let laenge = Double(dokument.laenge)
                wert += idf * (Double(tf) * (k1 + 1)) / (Double(tf) + k1 * (1 - b + b * laenge / mittlereLaenge))
            }
            if wert > 0 { ergebnis.append((dokument.id, wert)) }
        }
        return Array(ergebnis.sorted { $0.wert > $1.wert }.prefix(anzahl))
    }
}
