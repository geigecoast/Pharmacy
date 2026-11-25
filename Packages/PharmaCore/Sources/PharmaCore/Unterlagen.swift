import Foundation

/// Bedeutung der Markierfarben.
public enum MarkierungsFarbe: String, Codable, CaseIterable, Identifiable, Sendable {
    case gelb, rot, gruen, blau, lila

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .gelb: "Gelb"
        case .rot: "Rot"
        case .gruen: "Grün"
        case .blau: "Blau"
        case .lila: "Lila"
        }
    }

    public var bedeutung: String {
        switch self {
        case .gelb: "Wichtig"
        case .rot: "Prüfungsrelevant"
        case .gruen: "Definition"
        case .blau: "Strukturformel/Mechanismus"
        case .lila: "Arzneibuch-Methode/Analytik (Identität, Reinheit, Gehalt)"
        }
    }

    /// sRGB-Werte 0…1.
    public var rgb: (rot: Double, gruen: Double, blau: Double) {
        switch self {
        case .gelb: (1.00, 0.84, 0.20)
        case .rot: (0.94, 0.33, 0.31)
        case .gruen: (0.40, 0.78, 0.42)
        case .blau: (0.33, 0.60, 0.96)
        case .lila: (0.69, 0.47, 0.90)
        }
    }
}

public enum MarkierungsQuelle: String, Codable, Sendable {
    case nutzer
    case ki
}

public enum MarkierungsStatus: String, Codable, Sendable {
    case angenommen
    case vorgeschlagen
    case abgelehnt
}

public enum DokumentTyp: String, Codable, CaseIterable, Sendable {
    case pdf
    case scan
    case praesentation
    case audio

    public var name: String {
        switch self {
        case .pdf: "PDF"
        case .scan: "Scan/Bild"
        case .praesentation: "Präsentation"
        case .audio: "Audioaufnahme"
        }
    }

    public var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .scan: "doc.viewfinder"
        case .praesentation: "rectangle.on.rectangle"
        case .audio: "waveform"
        }
    }

    /// Ordnet eine Dateiendung einem Dokumenttyp zu.
    public static func typ(fuerEndung endung: String) -> DokumentTyp? {
        switch endung.lowercased() {
        case "pdf": .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp": .scan
        case "pptx", "ppt", "key", "odp": .praesentation
        case "m4a", "mp3", "wav", "aac", "aiff", "aif", "caf", "mp4", "m4b": .audio
        default: nil
        }
    }
}

/// Abschnitt eines Audio-Transkripts.
public struct Transkriptabschnitt: Codable, Equatable, Sendable, Identifiable {
    public var start: Double
    public var text: String
    public var id: Double { start }

    public init(start: Double, text: String) {
        self.start = start
        self.text = text
    }
}

/// Verknüpft einen Zeitpunkt einer Aufnahme mit einer Folie.
public struct Folienmarke: Codable, Equatable, Sendable, Identifiable {
    public var zeit: Double
    public var seitenIndex: Int
    public var id: Double { zeit }

    public init(zeit: Double, seitenIndex: Int) {
        self.zeit = zeit
        self.seitenIndex = seitenIndex
    }
}

public enum Transkript {
    /// Fasst erkannte Wörter zu gut lesbaren Abschnitten zusammen (Satzende oder spätestens nach `maxDauer` Sekunden).
    public static func abschnitte(woerter: [(zeit: Double, text: String)], maxDauer: Double = 20) -> [Transkriptabschnitt] {
        var ergebnis: [Transkriptabschnitt] = []
        var aktuell: [String] = []
        var start: Double?
        for wort in woerter {
            if start == nil { start = wort.zeit }
            aktuell.append(wort.text)
            let satzende = wort.text.hasSuffix(".") || wort.text.hasSuffix("?") || wort.text.hasSuffix("!")
            if let s = start, satzende || wort.zeit - s >= maxDauer {
                ergebnis.append(Transkriptabschnitt(start: s, text: aktuell.joined(separator: " ")))
                aktuell = []
                start = nil
            }
        }
        if let s = start, !aktuell.isEmpty {
            ergebnis.append(Transkriptabschnitt(start: s, text: aktuell.joined(separator: " ")))
        }
        return ergebnis
    }

    /// Folie, die zu einem Zeitpunkt gehört (letzte Marke davor).
    public static func folie(zu zeit: Double, marken: [Folienmarke]) -> Int? {
        marken.filter { $0.zeit <= zeit }.max { $0.zeit < $1.zeit }?.seitenIndex
    }

    /// "1:05:09" bzw. "12:34".
    public static func zeitText(_ sekunden: Double) -> String {
        let gesamt = Int(max(0, sekunden))
        let h = gesamt / 3600
        let m = (gesamt % 3600) / 60
        let s = gesamt % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

public enum Textausschnitt {
    /// Kurzer Ausschnitt rund um den ersten Treffer, z. B. für Suchergebnisse.
    public static func um(_ begriff: String, in text: String, umfeld: Int = 50) -> String {
        let bereinigt = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let treffer = bereinigt.range(of: begriff, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(bereinigt.prefix(umfeld * 2))
        }
        let anfang = bereinigt.index(treffer.lowerBound, offsetBy: -umfeld, limitedBy: bereinigt.startIndex) ?? bereinigt.startIndex
        let ende = bereinigt.index(treffer.upperBound, offsetBy: umfeld, limitedBy: bereinigt.endIndex) ?? bereinigt.endIndex
        var ausschnitt = String(bereinigt[anfang..<ende]).trimmingCharacters(in: .whitespaces)
        if anfang > bereinigt.startIndex { ausschnitt = "…" + ausschnitt }
        if ende < bereinigt.endIndex { ausschnitt += "…" }
        return ausschnitt
    }
}
