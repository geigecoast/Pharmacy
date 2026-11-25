import Foundation

/// Verfügbare Lernzeit pro Wochentag in Minuten (Montag … Sonntag).
public struct Wochenplan: Equatable, Sendable, RawRepresentable {
    public var minuten: [Int]

    public static let wochentage = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    public static let standard = Wochenplan(minuten: [120, 120, 120, 120, 120, 90, 60])

    public init(minuten: [Int]) {
        var werte = Array(minuten.prefix(7)).map { max(0, $0) }
        while werte.count < 7 { werte.append(0) }
        self.minuten = werte
    }

    public init?(rawValue: String) {
        let teile = rawValue.split(separator: ",").compactMap { Int($0) }
        guard teile.count == 7 else { return nil }
        self.init(minuten: teile)
    }

    public var rawValue: String { minuten.map(String.init).joined(separator: ",") }

    /// Index 0 = Montag.
    public static func index(fuer datum: Date, kalender: Calendar) -> Int {
        (kalender.component(.weekday, from: datum) + 5) % 7
    }

    public func minuten(fuer datum: Date, kalender: Calendar) -> Int {
        minuten[Self.index(fuer: datum, kalender: kalender)]
    }

    public var summeProWoche: Int { minuten.reduce(0, +) }
}

/// Eine Prüfung, auf die gelernt werden soll.
public struct LernZiel: Equatable, Sendable {
    public var id: String
    public var pruefungstag: Date
    public var bedarfMinuten: Int
    /// Bereits erledigte oder fest eingeplante Minuten.
    public var erledigtMinuten: Int
    public var istEingangspruefung: Bool
    public var gewicht: Double

    public init(id: String, pruefungstag: Date, bedarfMinuten: Int, erledigtMinuten: Int = 0,
                istEingangspruefung: Bool = false, gewicht: Double = 1) {
        self.id = id
        self.pruefungstag = pruefungstag
        self.bedarfMinuten = bedarfMinuten
        self.erledigtMinuten = erledigtMinuten
        self.istEingangspruefung = istEingangspruefung
        self.gewicht = gewicht
    }

    public var restMinuten: Int { max(0, bedarfMinuten - erledigtMinuten) }
}

public struct GeplanteEinheit: Equatable, Sendable {
    public var zielID: String
    /// Tagesbeginn.
    public var tag: Date
    public var minuten: Int
}

public struct Lernplan: Equatable, Sendable {
    public var einheiten: [GeplanteEinheit]
    /// Minuten, die bis zur Prüfung nicht mehr untergebracht werden konnten.
    public var fehlendeMinuten: [String: Int]
}

/// Erstellt einen Tag-für-Tag-Lernplan aus Prüfungsterminen und verfügbarer Zeit.
///
/// Vorgehen: Für jeden Tag bis zur letzten Prüfung wird die verfügbare Zeit in Blöcken an die
/// Prüfung mit der höchsten Dringlichkeit vergeben (Restaufwand ÷ verbleibende Tage).
/// Eingangsprüfungen, die einen Praktischen Teil freischalten, werden stärker gewichtet.
/// Wird ab heute neu geplant, verteilt sich verpasste Zeit automatisch auf die restlichen Tage.
public enum Lernplaner {
    public struct Optionen: Sendable {
        public var blockMinuten: Int
        public var vorlaufTage: Int
        public var eingangsFaktor: Double
        public var maxBloeckeProZielUndTag: Int
        /// Höchstens dieses Vielfache des gleichmäßigen Tagestempos pro Prüfung und Tag.
        public var tempoFaktor: Double

        public init(blockMinuten: Int = 45, vorlaufTage: Int = 28, eingangsFaktor: Double = 2,
                    maxBloeckeProZielUndTag: Int = 3, tempoFaktor: Double = 1.5) {
            self.blockMinuten = blockMinuten
            self.vorlaufTage = vorlaufTage
            self.eingangsFaktor = eingangsFaktor
            self.maxBloeckeProZielUndTag = maxBloeckeProZielUndTag
            self.tempoFaktor = tempoFaktor
        }
    }

    static let mindestBlock = 15

    public static func planen(
        ziele: [LernZiel],
        wochenplan: Wochenplan,
        ab start: Date,
        belegteMinuten: [Date: Int] = [:],
        kapazitaetsGrenzen: [Date: Int] = [:],
        optionen: Optionen = Optionen(),
        kalender: Calendar
    ) -> Lernplan {
        let heute = kalender.startOfDay(for: start)
        var rest: [String: Int] = [:]
        var pruefTag: [String: Date] = [:]
        var vorlauf: [String: Int] = [:]
        let durchschnittProTag = max(1, Double(wochenplan.summeProWoche) / 7)

        for ziel in ziele {
            rest[ziel.id] = ziel.restMinuten
            pruefTag[ziel.id] = kalender.startOfDay(for: ziel.pruefungstag)
            // Bei großem Aufwand früher beginnen: höchstens die Hälfte der Tageszeit pro Prüfung.
            let benoetigteTage = Int((Double(ziel.restMinuten) / (durchschnittProTag * 0.5)).rounded(.up))
            vorlauf[ziel.id] = max(optionen.vorlaufTage, benoetigteTage)
        }

        var geplant: [String: [Date: Int]] = [:]
        guard let letzterTag = pruefTag.values.max(), letzterTag > heute else {
            return Lernplan(einheiten: [], fehlendeMinuten: rest.filter { $0.value > 0 })
        }

        var tag = heute
        while tag < letzterTag {
            var kapazitaet = wochenplan.minuten(fuer: tag, kalender: kalender)
            if let grenze = kapazitaetsGrenzen[tag] { kapazitaet = min(kapazitaet, grenze) }
            kapazitaet -= belegteMinuten[tag] ?? 0
            var bloeckeHeute: [String: Int] = [:]
            var minutenHeute: [String: Int] = [:]
            // Gleichmäßiges Tagestempo je Prüfung: Restaufwand ÷ verbleibende Tage, mit Spielraum.
            var tageslimit: [String: Int] = [:]
            for ziel in ziele {
                guard let r = rest[ziel.id], r > 0, let pt = pruefTag[ziel.id], tag < pt else { continue }
                let tageBis = max(1, kalender.dateComponents([.day], from: tag, to: pt).day ?? 1)
                let tempo = Double(r) / Double(tageBis) * optionen.tempoFaktor
                let gerundet = Int((tempo / Double(mindestBlock)).rounded(.up)) * mindestBlock
                tageslimit[ziel.id] = max(optionen.blockMinuten, gerundet)
            }

            while kapazitaet >= mindestBlock {
                var bester: (id: String, wert: Double, pruefung: Date)?
                for ziel in ziele {
                    guard let r = rest[ziel.id], r > 0, let pt = pruefTag[ziel.id], tag < pt,
                          (bloeckeHeute[ziel.id] ?? 0) < optionen.maxBloeckeProZielUndTag,
                          (tageslimit[ziel.id] ?? 0) - (minutenHeute[ziel.id] ?? 0) >= mindestBlock else { continue }
                    let tageBis = kalender.dateComponents([.day], from: tag, to: pt).day ?? 0
                    guard tageBis <= vorlauf[ziel.id] ?? optionen.vorlaufTage else { continue }
                    var wert = Double(r) / Double(max(tageBis, 1)) * ziel.gewicht
                    if ziel.istEingangspruefung { wert *= optionen.eingangsFaktor }
                    if let b = bester {
                        if wert > b.wert || (wert == b.wert && (pt, ziel.id) < (b.pruefung, b.id)) {
                            bester = (ziel.id, wert, pt)
                        }
                    } else {
                        bester = (ziel.id, wert, pt)
                    }
                }
                guard let gewaehlt = bester, let r = rest[gewaehlt.id] else { break }
                let spielraum = (tageslimit[gewaehlt.id] ?? 0) - (minutenHeute[gewaehlt.id] ?? 0)
                let minuten = min(optionen.blockMinuten, kapazitaet, r, spielraum)
                rest[gewaehlt.id] = r - minuten
                kapazitaet -= minuten
                bloeckeHeute[gewaehlt.id, default: 0] += 1
                minutenHeute[gewaehlt.id, default: 0] += minuten
                geplant[gewaehlt.id, default: [:]][tag, default: 0] += minuten
            }

            guard let naechster = kalender.date(byAdding: .day, value: 1, to: tag) else { break }
            tag = kalender.startOfDay(for: naechster)
        }

        let einheiten = geplant
            .flatMap { id, tage in tage.map { GeplanteEinheit(zielID: id, tag: $0.key, minuten: $0.value) } }
            .sorted { ($0.tag, $0.zielID) < ($1.tag, $1.zielID) }
        return Lernplan(einheiten: einheiten, fehlendeMinuten: rest.filter { $0.value > 0 })
    }
}

public enum Dauer {
    /// "45 min", "2 h", "2 h 30 min".
    public static func text(minuten: Int) -> String {
        let h = minuten / 60
        let m = minuten % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }
}
