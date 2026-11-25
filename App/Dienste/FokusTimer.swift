import Foundation
import SwiftData
import UserNotifications
import PharmaCore

/// Fokus-Timer (Pomodoro): erfasst Lernzeit als Lernsitzung.
@MainActor
@Observable
final class FokusTimer {
    enum Phase { case bereit, fokus, pause }

    var phase: Phase = .bereit
    var laeuft = false
    var verbleibend: Int = 25 * 60
    var fokusMinuten = 25
    var pauseMinuten = 5
    var lehrveranstaltung: Lehrveranstaltung?
    var abgeschlosseneEinheiten = 0

    @ObservationIgnored private var aufgabe: Task<Void, Never>?
    @ObservationIgnored private var fokusBeginn: Date?
    @ObservationIgnored private var gelaufen: TimeInterval = 0
    @ObservationIgnored private var kontext: ModelContext?

    var anzeige: String {
        String(format: "%d:%02d", verbleibend / 60, verbleibend % 60)
    }

    func starten(kontext: ModelContext) {
        self.kontext = kontext
        if phase == .bereit {
            phase = .fokus
            verbleibend = fokusMinuten * 60
            gelaufen = 0
        }
        if phase == .fokus { fokusBeginn = Date() }
        laeuft = true
        aufgabe?.cancel()
        aufgabe = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.laeuft else { return }
                self.verbleibend -= 1
                if self.verbleibend <= 0 { self.phaseBeendet() }
            }
        }
    }

    func pausieren() {
        laeuft = false
        aufgabe?.cancel()
        if phase == .fokus, let beginn = fokusBeginn {
            gelaufen += Date().timeIntervalSince(beginn)
            fokusBeginn = nil
        }
    }

    /// Beendet den Timer; bereits gelernte Zeit (ab 1 Minute) wird gespeichert.
    func stoppen() {
        pausieren()
        if phase == .fokus { sitzungSpeichern() }
        phase = .bereit
        verbleibend = fokusMinuten * 60
    }

    private func phaseBeendet() {
        if phase == .fokus {
            if let beginn = fokusBeginn { gelaufen += Date().timeIntervalSince(beginn) }
            fokusBeginn = nil
            sitzungSpeichern()
            abgeschlosseneEinheiten += 1
            benachrichtigen("Fokus-Einheit geschafft", "Zeit für \(pauseMinuten) Minuten Pause.")
            phase = .pause
            verbleibend = pauseMinuten * 60
        } else {
            benachrichtigen("Pause vorbei", "Bereit für die nächste Fokus-Einheit?")
            laeuft = false
            aufgabe?.cancel()
            phase = .bereit
            verbleibend = fokusMinuten * 60
        }
    }

    private func sitzungSpeichern() {
        defer { gelaufen = 0 }
        guard gelaufen >= 60, let kontext else { return }
        let sitzung = Lernsitzung(start: Date().addingTimeInterval(-gelaufen), dauerSekunden: gelaufen)
        kontext.insert(sitzung)
        sitzung.lehrveranstaltung = lehrveranstaltung
    }

    private func benachrichtigen(_ titel: String, _ text: String) {
        let inhalt = UNMutableNotificationContent()
        inhalt.title = titel
        inhalt.body = text
        inhalt.sound = .default
        let anfrage = UNNotificationRequest(identifier: "pharmatutor.fokus.\(UUID().uuidString)", content: inhalt, trigger: nil)
        UNUserNotificationCenter.current().add(anfrage)
    }
}
