import Foundation
import Speech
import PharmaCore

/// Transkribiert Vorlesungsaufnahmen (Deutsch, nach Möglichkeit auf dem Gerät).
enum TranskriptionsDienst {
    enum Fehler: LocalizedError {
        case keineErlaubnis
        case nichtVerfuegbar

        var errorDescription: String? {
            switch self {
            case .keineErlaubnis:
                return "PharmaTutor darf keine Spracherkennung verwenden. Bitte erlaube sie in den Systemeinstellungen unter „Datenschutz & Sicherheit“."
            case .nichtVerfuegbar:
                return "Die deutsche Spracherkennung ist auf diesem Gerät gerade nicht verfügbar."
            }
        }
    }

    private final class Zustand: @unchecked Sendable {
        var beendet = false
    }

    static func transkribieren(url: URL) async throws -> [Transkriptabschnitt] {
        let status = await withCheckedContinuation { (fortsetzung: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { fortsetzung.resume(returning: $0) }
        }
        guard status == .authorized else { throw Fehler.keineErlaubnis }
        guard let erkenner = SFSpeechRecognizer(locale: Locale(identifier: "de-DE")), erkenner.isAvailable else {
            throw Fehler.nichtVerfuegbar
        }
        let anfrage = SFSpeechURLRecognitionRequest(url: url)
        anfrage.shouldReportPartialResults = false
        anfrage.addsPunctuation = true
        if erkenner.supportsOnDeviceRecognition {
            anfrage.requiresOnDeviceRecognition = true
        }

        let zustand = Zustand()
        return try await withCheckedThrowingContinuation { fortsetzung in
            erkenner.recognitionTask(with: anfrage) { ergebnis, fehler in
                guard !zustand.beendet else { return }
                if let fehler {
                    zustand.beendet = true
                    fortsetzung.resume(throwing: fehler)
                    return
                }
                guard let ergebnis, ergebnis.isFinal else { return }
                zustand.beendet = true
                let woerter = ergebnis.bestTranscription.segments.map { (zeit: $0.timestamp, text: $0.substring) }
                fortsetzung.resume(returning: Transkript.abschnitte(woerter: woerter))
            }
        }
    }
}
