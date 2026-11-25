import Foundation

/// Bewertung nach dem Aufdecken einer Karte.
public enum Bewertung: Int, Codable, CaseIterable, Identifiable, Sendable {
    case nochmal = 1
    case schwer = 2
    case gut = 3
    case einfach = 4

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .nochmal: "Nochmal"
        case .schwer: "Schwer"
        case .gut: "Gut"
        case .einfach: "Einfach"
        }
    }

    /// Tastenkürzel 1–4.
    public var taste: Character { Character(String(rawValue)) }
}

public enum KartenZustand: Int, Codable, Sendable {
    case neu = 0
    case lernen = 1
    case wiederholen = 2
    case neuLernen = 3

    public var name: String {
        switch self {
        case .neu: "Neu"
        case .lernen: "Lernen"
        case .wiederholen: "Wiederholen"
        case .neuLernen: "Neu lernen"
        }
    }
}

/// Lernstand einer Karte für die Planung.
public struct KartenStand: Codable, Equatable, Sendable {
    public var zustand: KartenZustand
    public var stabilitaet: Double
    public var schwierigkeit: Double
    public var faellig: Date
    public var letzteWiederholung: Date?
    public var wiederholungen: Int
    public var fehlschlaege: Int
    public var intervallTage: Int

    public init(zustand: KartenZustand = .neu, stabilitaet: Double = 0, schwierigkeit: Double = 0, faellig: Date,
                letzteWiederholung: Date? = nil, wiederholungen: Int = 0, fehlschlaege: Int = 0, intervallTage: Int = 0) {
        self.zustand = zustand
        self.stabilitaet = stabilitaet
        self.schwierigkeit = schwierigkeit
        self.faellig = faellig
        self.letzteWiederholung = letzteWiederholung
        self.wiederholungen = wiederholungen
        self.fehlschlaege = fehlschlaege
        self.intervallTage = intervallTage
    }

    public static func neu(_ jetzt: Date = Date()) -> KartenStand { KartenStand(faellig: jetzt) }
}

/// FSRS-5 (Free Spaced Repetition Scheduler) mit Standardparametern.
public struct FSRS: Sendable {
    public static let standardGewichte: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]

    static let zerfall = -0.5
    static let faktor = 19.0 / 81.0

    public var w: [Double]
    /// Gewünschte Behaltensquote beim nächsten Abruf.
    public var zielBehalten: Double
    public var maxIntervallTage: Int

    public init(w: [Double] = FSRS.standardGewichte, zielBehalten: Double = 0.9, maxIntervallTage: Int = 36_500) {
        self.w = w
        self.zielBehalten = zielBehalten
        self.maxIntervallTage = maxIntervallTage
    }

    // MARK: Grundformeln

    /// Abrufwahrscheinlichkeit nach `tage` Tagen bei Stabilität `s`.
    public static func abrufbarkeit(tage: Double, stabilitaet s: Double) -> Double {
        guard s > 0 else { return 0 }
        return pow(1 + faktor * max(0, tage) / s, zerfall)
    }

    public func abrufbarkeit(_ stand: KartenStand, jetzt: Date) -> Double {
        guard stand.zustand != .neu, let letzte = stand.letzteWiederholung else { return 0 }
        return Self.abrufbarkeit(tage: jetzt.timeIntervalSince(letzte) / 86_400, stabilitaet: stand.stabilitaet)
    }

    func intervall(_ s: Double) -> Int {
        let roh = s / Self.faktor * (pow(zielBehalten, 1 / Self.zerfall) - 1)
        return min(max(Int(roh.rounded()), 1), maxIntervallTage)
    }

    func startStabilitaet(_ g: Bewertung) -> Double { max(w[g.rawValue - 1], 0.1) }

    func startSchwierigkeit(_ g: Bewertung) -> Double {
        klemme(w[4] - exp(w[5] * Double(g.rawValue - 1)) + 1)
    }

    func naechsteSchwierigkeit(_ d: Double, _ g: Bewertung) -> Double {
        let delta = -w[6] * Double(g.rawValue - 3)
        let gedaempft = d + delta * (10 - d) / 9
        return klemme(w[7] * startSchwierigkeit(.einfach) + (1 - w[7]) * gedaempft)
    }

    func stabilitaetNachErfolg(_ d: Double, _ s: Double, _ r: Double, _ g: Bewertung) -> Double {
        let schwerStrafe = g == .schwer ? w[15] : 1
        let einfachBonus = g == .einfach ? w[16] : 1
        return s * (exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * schwerStrafe * einfachBonus + 1)
    }

    func stabilitaetNachVergessen(_ d: Double, _ s: Double, _ r: Double) -> Double {
        let neu = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r))
        return min(neu, s)
    }

    func kurzzeitStabilitaet(_ s: Double, _ g: Bewertung) -> Double {
        s * exp(w[17] * (Double(g.rawValue) - 3 + w[18]))
    }

    private func klemme(_ d: Double) -> Double { min(max(d, 1), 10) }

    // MARK: Planung

    /// Neuer Lernstand nach einer Bewertung.
    public func planen(_ stand: KartenStand, _ g: Bewertung, jetzt: Date) -> KartenStand {
        var neu = stand
        neu.letzteWiederholung = jetzt
        neu.wiederholungen += 1

        func inMinuten(_ m: Double) -> Date { jetzt.addingTimeInterval(m * 60) }
        func inTagen(_ t: Int) -> Date { jetzt.addingTimeInterval(Double(t) * 86_400) }

        switch stand.zustand {
        case .neu:
            neu.schwierigkeit = startSchwierigkeit(g)
            neu.stabilitaet = startStabilitaet(g)
            switch g {
            case .nochmal: neu.zustand = .lernen; neu.faellig = inMinuten(1); neu.intervallTage = 0
            case .schwer: neu.zustand = .lernen; neu.faellig = inMinuten(5); neu.intervallTage = 0
            case .gut: neu.zustand = .lernen; neu.faellig = inMinuten(10); neu.intervallTage = 0
            case .einfach:
                neu.zustand = .wiederholen
                neu.intervallTage = intervall(neu.stabilitaet)
                neu.faellig = inTagen(neu.intervallTage)
            }

        case .lernen, .neuLernen:
            neu.schwierigkeit = naechsteSchwierigkeit(stand.schwierigkeit, g)
            switch g {
            case .nochmal:
                neu.stabilitaet = kurzzeitStabilitaet(stand.stabilitaet, g)
                neu.faellig = inMinuten(5); neu.intervallTage = 0
            case .schwer:
                neu.stabilitaet = kurzzeitStabilitaet(stand.stabilitaet, g)
                neu.faellig = inMinuten(10); neu.intervallTage = 0
            case .gut:
                neu.stabilitaet = kurzzeitStabilitaet(stand.stabilitaet, .gut)
                neu.zustand = .wiederholen
                neu.intervallTage = intervall(neu.stabilitaet)
                neu.faellig = inTagen(neu.intervallTage)
            case .einfach:
                let gutS = kurzzeitStabilitaet(stand.stabilitaet, .gut)
                let einfachS = kurzzeitStabilitaet(stand.stabilitaet, .einfach)
                neu.stabilitaet = einfachS
                neu.zustand = .wiederholen
                neu.intervallTage = max(intervall(einfachS), intervall(gutS) + 1)
                neu.faellig = inTagen(neu.intervallTage)
            }

        case .wiederholen:
            let r = abrufbarkeit(stand, jetzt: jetzt)
            let d = stand.schwierigkeit
            let s = stand.stabilitaet
            neu.schwierigkeit = naechsteSchwierigkeit(d, g)
            if g == .nochmal {
                neu.stabilitaet = stabilitaetNachVergessen(d, s, r)
                neu.zustand = .neuLernen
                neu.fehlschlaege += 1
                neu.intervallTage = 0
                neu.faellig = inMinuten(5)
            } else {
                let schwerS = stabilitaetNachErfolg(d, s, r, .schwer)
                let gutS = stabilitaetNachErfolg(d, s, r, .gut)
                let einfachS = stabilitaetNachErfolg(d, s, r, .einfach)
                var schwerI = intervall(schwerS)
                var gutI = intervall(gutS)
                schwerI = min(schwerI, gutI)
                gutI = max(gutI, schwerI + 1)
                let einfachI = max(intervall(einfachS), gutI + 1)
                switch g {
                case .schwer: neu.stabilitaet = schwerS; neu.intervallTage = schwerI
                case .gut: neu.stabilitaet = gutS; neu.intervallTage = gutI
                default: neu.stabilitaet = einfachS; neu.intervallTage = einfachI
                }
                neu.faellig = inTagen(neu.intervallTage)
            }
        }
        return neu
    }

    /// Vorschau aller vier Bewertungen (für die Beschriftung der Knöpfe).
    public func vorschau(_ stand: KartenStand, jetzt: Date) -> [Bewertung: KartenStand] {
        Dictionary(uniqueKeysWithValues: Bewertung.allCases.map { ($0, planen(stand, $0, jetzt: jetzt)) })
    }

    /// Kurztext für den Abstand bis zur nächsten Fälligkeit: „<1 min“, „10 min“, „3 T“, „2 Mon.“.
    public static func abstandText(von jetzt: Date, bis faellig: Date) -> String {
        let sekunden = faellig.timeIntervalSince(jetzt)
        let minuten = sekunden / 60
        if minuten < 1 { return "<1 min" }
        if minuten < 60 { return "\(Int(minuten.rounded())) min" }
        let stunden = minuten / 60
        if stunden < 24 { return "\(Int(stunden.rounded())) h" }
        let tage = stunden / 24
        if tage < 31 { return "\(Int(tage.rounded())) T" }
        if tage < 365 { return "\(Int((tage / 30).rounded())) Mon." }
        let jahre = (tage / 365 * 10).rounded() / 10
        return "\(String(jahre).replacingOccurrences(of: ".", with: ",")) J."
    }
}
