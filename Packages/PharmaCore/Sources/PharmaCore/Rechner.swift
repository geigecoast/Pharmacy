import Foundation

/// Rechenhilfen für Analytik und Rezeptur.
public enum Analytikrechner {
    /// Gehalt in Prozent aus einer Titration nach Ph. Eur.
    /// - Parameters:
    ///   - verbrauchML: Verbrauch an Maßlösung in ml (abzüglich Blindwert).
    ///   - faktor: Titer/Faktor der Maßlösung (z. B. 1,002).
    ///   - aequivalentMG: „1 ml Maßlösung entspricht … mg Substanz“.
    ///   - einwaageMG: Einwaage in mg.
    ///   - blindwertML: Verbrauch im Blindversuch (wird abgezogen).
    public static func gehaltProzent(verbrauchML: Double, faktor: Double, aequivalentMG: Double,
                                     einwaageMG: Double, blindwertML: Double = 0) -> Double? {
        guard einwaageMG > 0, faktor > 0 else { return nil }
        let netto = verbrauchML - blindwertML
        return netto * faktor * aequivalentMG / einwaageMG * 100
    }

    /// Erwarteter Verbrauch in ml für einen Sollgehalt (z. B. 100 %).
    public static func sollverbrauchML(einwaageMG: Double, sollProzent: Double, faktor: Double, aequivalentMG: Double) -> Double? {
        guard aequivalentMG > 0, faktor > 0 else { return nil }
        return einwaageMG * sollProzent / 100 / (faktor * aequivalentMG)
    }

    /// Äquivalentmasse in mg pro ml Maßlösung: Molarität × molare Masse ÷ stöchiometrischer Faktor (z).
    public static func aequivalentMG(molaritaet: Double, molareMasse: Double, z: Double = 1) -> Double? {
        guard z > 0 else { return nil }
        return molaritaet * molareMasse / z
    }
}

public enum Konzentrationsrechner {
    /// Verdünnung c1·V1 = c2·V2 – gibt den fehlenden Wert zurück (genau einer muss nil sein).
    public static func verduennung(c1: Double?, v1: Double?, c2: Double?, v2: Double?) -> Double? {
        switch (c1, v1, c2, v2) {
        case (nil, let v1?, let c2?, let v2?) where v1 > 0: return c2 * v2 / v1
        case (let c1?, nil, let c2?, let v2?) where c1 > 0: return c2 * v2 / c1
        case (let c1?, let v1?, nil, let v2?) where v2 > 0: return c1 * v1 / v2
        case (let c1?, let v1?, let c2?, nil) where c2 > 0: return c1 * v1 / c2
        default: return nil
        }
    }

    /// Masse in mg für eine Lösung: c (mol/l) × V (ml) × M (g/mol).
    public static func masseMG(molaritaet: Double, volumenML: Double, molareMasse: Double) -> Double {
        molaritaet * volumenML * molareMasse
    }

    /// Molarität (mol/l) aus Masse (mg), Volumen (ml) und molarer Masse (g/mol).
    public static func molaritaet(masseMG: Double, volumenML: Double, molareMasse: Double) -> Double? {
        guard volumenML > 0, molareMasse > 0 else { return nil }
        return masseMG / (volumenML * molareMasse)
    }

    /// Prozent (m/V): g Substanz pro 100 ml.
    public static func prozentMV(masseG: Double, volumenML: Double) -> Double? {
        guard volumenML > 0 else { return nil }
        return masseG / volumenML * 100
    }
}

/// Zahlen deutsch formatieren und einlesen („1,5“).
public enum Dezimal {
    public static func lesen(_ text: String) -> Double? {
        let bereinigt = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return bereinigt.isEmpty ? nil : Double(bereinigt)
    }

    public static func text(_ wert: Double, stellen: Int = 2) -> String {
        let format = NumberFormatter()
        format.locale = Locale(identifier: "de_DE")
        format.numberStyle = .decimal
        format.minimumFractionDigits = 0
        format.maximumFractionDigits = stellen
        return format.string(from: NSNumber(value: wert)) ?? "\(wert)"
    }
}
