import Foundation

/// Countdown-Texte und Fristberechnungen.
public enum Countdown {
    /// Ganze Kalendertage zwischen zwei Daten (negativ, wenn `ziel` in der Vergangenheit liegt).
    public static func tage(von start: Date = Date(), bis ziel: Date, kalender: Calendar = .current) -> Int {
        let a = kalender.startOfDay(for: start)
        let b = kalender.startOfDay(for: ziel)
        return kalender.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Kurzer deutscher Text: "heute", "morgen", "in 12 Tagen", "vor 3 Tagen".
    public static func text(tage: Int) -> String {
        switch tage {
        case 0: "heute"
        case 1: "morgen"
        case -1: "gestern"
        case 2...: "in \(tage) Tagen"
        default: "vor \(-tage) Tagen"
        }
    }
}

public enum Studienregeln {
    /// Mit der verbindlichen Anmeldung beginnt die 3-Semester-Frist (Näherung: 18 Monate).
    public static func dreiSemesterFristEnde(anmeldung: Date, kalender: Calendar = .current) -> Date {
        kalender.date(byAdding: .month, value: 18, to: anmeldung) ?? anmeldung
    }

    public static let anmeldeHinweis =
        "Verbindliche Anmeldung = Beginn der 3-Semester-Frist. Eine verspätete Anmeldung ist nicht möglich; unentschuldigtes Fehlen wird mit 5,0 bewertet."
}
