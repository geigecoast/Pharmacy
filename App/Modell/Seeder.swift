import Foundation
import SwiftData
import PharmaCore

/// Lädt das vorgeladene Curriculum beim ersten Start in die Datenbank.
@MainActor
enum Seeder {
    static let versionsSchluessel = "curriculumVersion"

    static func ladeFallsNoetig(_ kontext: ModelContext) {
        let geladeneVersion = UserDefaults.standard.integer(forKey: versionsSchluessel)
        let anzahl = (try? kontext.fetchCount(FetchDescriptor<Semester>())) ?? 0
        guard geladeneVersion == 0, anzahl == 0 else { return }
        lade(in: kontext)
    }

    /// Löscht alle Studiendaten und lädt das Curriculum neu.
    static func zuruecksetzen(_ kontext: ModelContext) {
        do {
            try kontext.delete(model: Wiederholung.self)
            try kontext.delete(model: Fehlereintrag.self)
            try kontext.delete(model: QuizErgebnis.self)
            try kontext.delete(model: Karteikarte.self)
            try kontext.delete(model: Lerneinheit.self)
            try kontext.delete(model: Zeichnung.self)
            try kontext.delete(model: Markierung.self)
            try kontext.delete(model: Seite.self)
            try kontext.delete(model: Dokument.self)
            try kontext.delete(model: Teilpruefung.self)
            try kontext.delete(model: Frist.self)
            try kontext.delete(model: Lehrveranstaltung.self)
            try kontext.delete(model: Semester.self)
            try kontext.delete(model: Lernpfad.self)
            try kontext.delete(model: StoffgebietZuordnung.self)
            try kontext.save()
        } catch {
            assertionFailure("Zurücksetzen fehlgeschlagen: \(error)")
        }
        lade(in: kontext)
    }

    static func lade(in kontext: ModelContext) {
        var lernpfade: [String: Lernpfad] = [:]
        for pfad in Curriculum.lernpfade {
            let lp = Lernpfad(schluessel: pfad.schluessel, titel: pfad.titel)
            kontext.insert(lp)
            lernpfade[pfad.schluessel] = lp
        }

        var lvNachTeil: [String: Lehrveranstaltung] = [:]
        var offeneFristen: [(Frist, String)] = []

        for (sIndex, s) in Curriculum.semester.enumerated() {
            let semester = Semester(nummer: s.nummer, titel: s.titel, typ: s.typ, istAktuell: s.istAktuell, sortierung: sIndex)
            semester.vorlesungsbeginn = s.vorlesungsbeginn
            semester.vorlesungsende = s.vorlesungsende
            kontext.insert(semester)

            for (kIndex, k) in s.kurse.enumerated() {
                let lv = Lehrveranstaltung(lfdNr: k.lfdNr, bezeichnung: k.bezeichnung, lehrform: k.lehrform, sws: k.sws, sortierung: kIndex)
                lv.kurzname = k.kurzname
                lv.stoffgebiete = k.stoffgebiete
                lv.leistungsnachweis = k.leistungsnachweis
                lv.dozenten = k.dozenten
                lv.voraussetzungen = k.voraussetzungen
                lv.anmeldepflicht = k.anmeldepflicht
                lv.status = k.status
                lv.hinweis = k.hinweis
                lv.lernpfadTeil = k.lernpfadTeil
                kontext.insert(lv)
                lv.semester = semester
                if let schluessel = k.lernpfad { lv.lernpfad = lernpfade[schluessel] }

                for (tIndex, t) in k.teilpruefungen.enumerated() {
                    let tp = Teilpruefung(typ: t.typ, bezeichnung: t.bezeichnung, anmeldepflichtig: t.anmeldepflichtig,
                                          hinweis: t.hinweis, sortierung: tIndex)
                    kontext.insert(tp)
                    tp.lehrveranstaltung = lv
                }
                for teil in lv.lfdNrTeile { lvNachTeil[teil] = lv }
            }

            for f in s.fristen {
                let frist = Frist(titel: f.titel, art: f.art, datum: f.datum, hinweis: f.hinweis)
                kontext.insert(frist)
                frist.semester = semester
                if let nr = f.lfdNr { offeneFristen.append((frist, nr)) }
            }
        }

        // Fristen mit Veranstaltungen anderer Semester verknüpfen (z. B. Platzvergabe [76] im 6. Semester).
        for (frist, nr) in offeneFristen {
            frist.lehrveranstaltung = lvNachTeil[nr.lowercased()]
        }

        for gebiet in Stoffgebiet.allCases {
            kontext.insert(StoffgebietZuordnung(stoffgebiet: gebiet))
        }

        do {
            try kontext.save()
            UserDefaults.standard.set(Curriculum.version, forKey: versionsSchluessel)
        } catch {
            assertionFailure("Curriculum konnte nicht gespeichert werden: \(error)")
        }
    }
}
