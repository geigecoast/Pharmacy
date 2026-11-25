import Foundation
import SwiftData
import PharmaCore

/// Lernserie, Punkte, Stufen und Abzeichen aus den gespeicherten Lerndaten.
@MainActor
enum GamificationDienst {
    struct Stand {
        var serie: Gamification.Serie
        var punkte: Int
        var stufe: Gamification.Stufe
        var statistik: Gamification.Statistik
        var minutenProTag: [Date: Double]
        var heuteMinuten: Int
        var tagesziel: Int
        var wocheMinuten: Int
        var wochenziel: Int
    }

    static var aktiv: Bool {
        UserDefaults.standard.object(forKey: EinstellungsSchluessel.gamificationAktiv) as? Bool ?? true
    }

    static var tagesziel: Int {
        max(5, Standardwerte.ganzzahl(EinstellungsSchluessel.tageszielMinuten, standard: Standardwerte.tageszielMinuten))
    }

    /// Eigenes Wochenziel oder die Summe der Lernzeiten aus dem Lernplan.
    static var wochenziel: Int {
        let eigenes = Standardwerte.ganzzahl(EinstellungsSchluessel.wochenzielMinuten, standard: 0)
        return eigenes > 0 ? eigenes : max(60, Standardwerte.wochenplan.summeProWoche)
    }

    static var ruhetagErlaubt: Bool {
        UserDefaults.standard.object(forKey: EinstellungsSchluessel.ruhetagErlaubt) as? Bool ?? true
    }

    static func stand(_ kontext: ModelContext, jetzt: Date = Date()) -> Stand {
        let kalender = Calendar.deutsch
        let minuten = AnalyseDienst.lernminuten(lv: nil, kontext: kontext)
        let ziel = tagesziel
        let serie = Gamification.serie(minutenProTag: minuten, tagesziel: ziel, ruhetagErlaubt: ruhetagErlaubt,
                                       heute: jetzt, kalender: kalender)
        let statistik = statistik(kontext, minuten: minuten, laengsteSerie: serie.laengste)
        let punkte = Gamification.punkte(statistik.aktivitaet)
        let heute = minuten[kalender.startOfDay(for: jetzt)] ?? 0
        let woche = AnalyseDienst.woche(minuten, um: jetzt).reduce(0, +)
        return Stand(serie: serie, punkte: punkte, stufe: Gamification.stufe(punkte: punkte), statistik: statistik,
                     minutenProTag: minuten, heuteMinuten: Int(heute.rounded()), tagesziel: ziel,
                     wocheMinuten: woche, wochenziel: wochenziel)
    }

    private static func alle<T: PersistentModel>(_ typ: T.Type, _ kontext: ModelContext) -> [T] {
        (try? kontext.fetch(FetchDescriptor<T>())) ?? []
    }

    static func statistik(_ kontext: ModelContext, minuten: [Date: Double], laengsteSerie: Int) -> Gamification.Statistik {
        var s = Gamification.Statistik()
        let kalender = Calendar.deutsch

        let quiz = alle(QuizErgebnis.self, kontext)
        let klausuren = alle(Probeklausur.self, kontext).filter { $0.abgegebenAm != nil }
        let fehler = alle(Fehlereintrag.self, kontext).filter(\.verstanden)
        // Nur Teilprüfungen ab dem Hauptstudium – das Grundstudium-Archiv zählt nicht.
        let teilpruefungen = alle(Teilpruefung.self, kontext).filter { tp in
            tp.ergebnis == .bestanden && tp.lehrveranstaltung?.semester?.typ != .archiv
        }

        s.aktivitaet = Gamification.Aktivitaet(
            lernminuten: Int(minuten.values.reduce(0, +).rounded()),
            wiederholungen: (try? kontext.fetchCount(FetchDescriptor<Wiederholung>())) ?? 0,
            quizRunden: quiz.count,
            probeklausuren: klausuren.count,
            fehlerVerstanden: fehler.count,
            teilpruefungenBestanden: teilpruefungen.count)
        s.laengsteSerie = laengsteSerie
        s.kartenErstellt = (try? kontext.fetchCount(FetchDescriptor<Karteikarte>())) ?? 0
        s.tutorFragen = alle(TutorNachricht.self, kontext).filter(\.vonNutzer).count
        s.besteProbeklausurProzent = klausuren.map(\.prozent).max()
        s.perfektesQuiz = quiz.contains { $0.fragen >= 10 && $0.richtig == $0.fragen }
        let sitzungen = alle(Lernsitzung.self, kontext).filter { $0.dauerSekunden >= 10 * 60 }
        s.fruehSitzung = sitzungen.contains { kalender.component(.hour, from: $0.start) < 7 }
        s.spaetSitzung = sitzungen.contains { kalender.component(.hour, from: $0.start) >= 23 }
        s.semesterKomplett = alle(Semester.self, kontext).contains { semester in
            guard semester.typ == .regulaer else { return false }
            let lvs = semester.lehrveranstaltungen ?? []
            return !lvs.isEmpty && lvs.allSatisfy { $0.status == .bestanden }
        }
        s.wochenMitZiel = Gamification.wochenMitZiel(minutenProTag: minuten, wochenziel: wochenziel, kalender: kalender)
        return s
    }

    /// Freigeschaltete Abzeichen mit Datum.
    static func erfolge(_ kontext: ModelContext) -> [String: Date] {
        var ergebnis: [String: Date] = [:]
        for erfolg in alle(Erfolg.self, kontext) {
            ergebnis[erfolg.kennung] = min(ergebnis[erfolg.kennung] ?? erfolg.erreichtAm, erfolg.erreichtAm)
        }
        return ergebnis
    }

    /// Speichert neu erreichte Abzeichen und gibt sie zurück.
    /// Beim allerersten Lauf werden bereits erfüllte Abzeichen still übernommen (keine Meldungsflut).
    @discardableResult
    static func pruefen(_ kontext: ModelContext) -> [Gamification.Abzeichen] {
        guard aktiv else { return [] }
        let statistik = stand(kontext).statistik
        let vorhanden = Set(erfolge(kontext).keys)
        let neu = Gamification.erreichteAbzeichen(statistik).filter { !vorhanden.contains($0.rawValue) }
        let standard = UserDefaults.standard
        let initialisiert = standard.bool(forKey: EinstellungsSchluessel.erfolgeInitialisiert)
        standard.set(true, forKey: EinstellungsSchluessel.erfolgeInitialisiert)
        guard !neu.isEmpty else { return [] }
        for abzeichen in neu {
            kontext.insert(Erfolg(kennung: abzeichen.rawValue))
        }
        try? kontext.save()
        return initialisiert ? neu : []
    }
}
