import Foundation

/// Hilfsfunktionen für laufende Nummern wie im QIS/LSF ("[43]", "[39+42]", "[67a+66]").
public enum LfdNr {
    /// Zerlegt eine Lfd. Nr. in ihre Teile: "[39+42]" → ["39", "42"].
    public static func teile(_ lfdNr: String) -> [String] {
        lfdNr
            .lowercased()
            .split(whereSeparator: { "+,;/ []".contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Anzeigeform mit eckigen Klammern: "39+42" → "[39+42]".
    public static func anzeige(_ lfdNr: String) -> String {
        let bereinigt = lfdNr.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        return "[\(bereinigt)]"
    }

    /// Erkennt Suchbegriffe wie "[43]", "43" oder "67a" und gibt den Teil zurück.
    public static func suchTeil(_ suchbegriff: String) -> String? {
        let bereinigt = suchbegriff
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard let erstes = bereinigt.first, erstes.isNumber else { return nil }
        let erlaubt = bereinigt.allSatisfy { $0.isNumber || ("a"..."z").contains(String($0)) }
        guard erlaubt, bereinigt.count <= 4 else { return nil }
        return bereinigt
    }

    /// Prüft, ob eine Veranstaltung zu einem Suchbegriff passt (Lfd. Nr. oder Bezeichnung).
    public static func passt(lfdNr: String, bezeichnung: String, suchbegriff: String) -> Bool {
        let begriff = suchbegriff.trimmingCharacters(in: .whitespaces)
        guard !begriff.isEmpty else { return true }
        if let teil = suchTeil(begriff) {
            if teile(lfdNr).contains(teil) { return true }
            // Teilweise Eingabe: "6" findet "62", "63", …, aber nur wenn keine Klammer gesetzt ist.
            if !begriff.contains("]") && teile(lfdNr).contains(where: { $0.hasPrefix(teil) }) { return true }
        }
        return bezeichnung.localizedStandardContains(begriff)
            || anzeige(lfdNr).localizedStandardContains(begriff)
    }
}
