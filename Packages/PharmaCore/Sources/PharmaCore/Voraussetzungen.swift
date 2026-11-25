import Foundation

/// Schlüssel einer Teilprüfung, z. B. Schriftliche Eingangsprüfung von [40].
public struct TeilpruefungSchluessel: Hashable, Codable, Sendable {
    public var lfdNr: String
    public var typ: TeilpruefungTyp

    public init(lfdNr: String, typ: TeilpruefungTyp) {
        self.lfdNr = lfdNr.lowercased()
        self.typ = typ
    }
}

/// Aktueller Studienstand, gegen den Voraussetzungen geprüft werden.
public struct StudienStand: Sendable, Equatable {
    public var bestandeneKurse: Set<String>
    public var teilgenommeneKurse: Set<String>
    public var bestandeneTeilpruefungen: Set<TeilpruefungSchluessel>
    public var zulassungen: Set<String>

    public init(
        bestandeneKurse: Set<String> = [],
        teilgenommeneKurse: Set<String> = [],
        bestandeneTeilpruefungen: Set<TeilpruefungSchluessel> = [],
        zulassungen: Set<String> = []
    ) {
        self.bestandeneKurse = Set(bestandeneKurse.map { $0.lowercased() })
        self.teilgenommeneKurse = Set(teilgenommeneKurse.map { $0.lowercased() })
        self.bestandeneTeilpruefungen = bestandeneTeilpruefungen
        self.zulassungen = Set(zulassungen.map { $0.lowercased() })
    }
}

/// Regel für die Zulassung zu einer Lehrveranstaltung.
public indirect enum VoraussetzungsRegel: Codable, Hashable, Sendable {
    case keine
    /// Lehrveranstaltung muss bestanden sein.
    case kurs(String)
    /// Teilnahme genügt (läuft oder bestanden).
    case teilnahme(String)
    /// Eine bestimmte Teilprüfung muss bestanden sein.
    case teilpruefung(lfdNr: String, typ: TeilpruefungTyp)
    /// Zulassung wie "Ph1" (1. Abschnitt der Pharmazeutischen Prüfung).
    case zulassung(String)
    case alle([VoraussetzungsRegel])
    case eine([VoraussetzungsRegel])
    /// Von den aufgeführten Bedingungen dürfen höchstens `n` fehlen.
    case hoechstensFehlend(Int, [VoraussetzungsRegel])

    // MARK: Beschreibung

    /// Lesbare deutsche Beschreibung der Regel.
    public var beschreibung: String {
        switch self {
        case .keine:
            return "Keine Voraussetzungen"
        case .kurs(let nr):
            return LfdNr.anzeige(nr)
        case .teilnahme(let nr):
            return "Teilnahme an \(LfdNr.anzeige(nr))"
        case .teilpruefung(let nr, let typ):
            return "\(typ.name) \(LfdNr.anzeige(nr))"
        case .zulassung(let name):
            return "Zulassung \(name)"
        case .alle(let regeln):
            return regeln.map { $0.beschreibungInKlammern(fuer: .alle) }.joined(separator: " + ")
        case .eine(let regeln):
            return regeln.map { $0.beschreibungInKlammern(fuer: .eine) }.joined(separator: " oder ")
        case .hoechstensFehlend(let n, let regeln):
            let liste = regeln.map(\.beschreibung).joined(separator: ", ")
            let anzahl = n == 1 ? "eine darf" : "höchstens \(n) dürfen"
            return "Von \(liste) \(anzahl) fehlen"
        }
    }

    private enum Verknuepfung { case alle, eine }

    private func beschreibungInKlammern(fuer aeussere: Verknuepfung) -> String {
        switch (self, aeussere) {
        case (.eine(let r), .alle) where r.count > 1: return "(\(beschreibung))"
        case (.alle(let r), .eine) where r.count > 1: return "(\(beschreibung))"
        case (.hoechstensFehlend, _): return "(\(beschreibung))"
        default: return beschreibung
        }
    }

    /// Alle Lfd. Nr., auf die diese Regel verweist (für den Voraussetzungs-Graphen).
    public var referenzierteKurse: Set<String> {
        switch self {
        case .keine, .zulassung: return []
        case .kurs(let nr), .teilnahme(let nr), .teilpruefung(let nr, _): return [nr.lowercased()]
        case .alle(let r), .eine(let r), .hoechstensFehlend(_, let r):
            return r.reduce(into: Set<String>()) { $0.formUnion($1.referenzierteKurse) }
        }
    }

    // MARK: Prüfung

    public func pruefe(_ stand: StudienStand) -> VoraussetzungsPruefung {
        switch self {
        case .keine:
            return .erfuellt
        case .kurs(let nr):
            return stand.bestandeneKurse.contains(nr.lowercased())
                ? .erfuellt
                : .fehlt("\(LfdNr.anzeige(nr)) bestanden")
        case .teilnahme(let nr):
            let n = nr.lowercased()
            return stand.teilgenommeneKurse.contains(n) || stand.bestandeneKurse.contains(n)
                ? .erfuellt
                : .fehlt("Teilnahme an \(LfdNr.anzeige(nr))")
        case .teilpruefung(let nr, let typ):
            return stand.bestandeneTeilpruefungen.contains(TeilpruefungSchluessel(lfdNr: nr, typ: typ))
                ? .erfuellt
                : .fehlt("\(typ.name) \(LfdNr.anzeige(nr)) bestanden")
        case .zulassung(let name):
            return stand.zulassungen.contains(name.lowercased())
                ? .erfuellt
                : .fehlt("Zulassung \(name)")
        case .alle(let regeln):
            let ergebnisse = regeln.map { $0.pruefe(stand) }
            return VoraussetzungsPruefung(
                erfuellt: ergebnisse.allSatisfy(\.erfuellt),
                fehlend: ergebnisse.flatMap(\.fehlend),
                hinweise: ergebnisse.flatMap(\.hinweise)
            )
        case .eine(let regeln):
            let ergebnisse = regeln.map { $0.pruefe(stand) }
            if let erfuellt = ergebnisse.first(where: \.erfuellt) {
                return VoraussetzungsPruefung(erfuellt: true, fehlend: [], hinweise: erfuellt.hinweise)
            }
            return .fehlt("Eine von: " + regeln.map(\.beschreibung).joined(separator: ", "))
        case .hoechstensFehlend(let n, let regeln):
            let ergebnisse = regeln.map { $0.pruefe(stand) }
            let fehlendeRegeln = zip(regeln, ergebnisse).filter { !$0.1.erfuellt }.map(\.0)
            let liste = fehlendeRegeln.map(\.beschreibung).joined(separator: ", ")
            if fehlendeRegeln.isEmpty {
                return .erfuellt
            } else if fehlendeRegeln.count <= n {
                return VoraussetzungsPruefung(
                    erfuellt: true,
                    fehlend: [],
                    hinweise: ["\(fehlendeRegeln.count) von \(regeln.count) fehlt noch (\(liste)) – erlaubt sind höchstens \(n)."]
                )
            } else {
                return .fehlt("Es fehlen \(fehlendeRegeln.count) von \(regeln.count) (\(liste)) – erlaubt sind höchstens \(n).")
            }
        }
    }

    // MARK: Speicherung

    public func alsDaten() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func aus(_ daten: Data?) -> VoraussetzungsRegel {
        guard let daten, let regel = try? JSONDecoder().decode(VoraussetzungsRegel.self, from: daten) else {
            return .keine
        }
        return regel
    }
}

/// Ergebnis einer Voraussetzungsprüfung.
public struct VoraussetzungsPruefung: Equatable, Sendable {
    public var erfuellt: Bool
    /// Was noch fehlt (bei nicht erfüllten Regeln).
    public var fehlend: [String]
    /// Zusätzliche Hinweise, z. B. "1 von 7 fehlt – erlaubt".
    public var hinweise: [String]

    public init(erfuellt: Bool, fehlend: [String], hinweise: [String]) {
        self.erfuellt = erfuellt
        self.fehlend = fehlend
        self.hinweise = hinweise
    }

    public static let erfuellt = VoraussetzungsPruefung(erfuellt: true, fehlend: [], hinweise: [])

    public static func fehlt(_ text: String) -> VoraussetzungsPruefung {
        VoraussetzungsPruefung(erfuellt: false, fehlend: [text], hinweise: [])
    }
}

/// Freigabezustand einer Lehrveranstaltung.
public enum Freigabe: Equatable, Sendable {
    case bestanden
    case freigeschaltet(hinweise: [String])
    case blockiert(fehlend: [String])

    public static func ermitteln(status: LVStatus, regel: VoraussetzungsRegel, stand: StudienStand) -> Freigabe {
        if status == .bestanden { return .bestanden }
        let pruefung = regel.pruefe(stand)
        return pruefung.erfuellt ? .freigeschaltet(hinweise: pruefung.hinweise) : .blockiert(fehlend: pruefung.fehlend)
    }

    public var name: String {
        switch self {
        case .bestanden: "Bestanden"
        case .freigeschaltet: "Freigeschaltet"
        case .blockiert: "Blockiert"
        }
    }

    public var symbol: String {
        switch self {
        case .bestanden: "checkmark.seal.fill"
        case .freigeschaltet: "lock.open.fill"
        case .blockiert: "lock.fill"
        }
    }
}
