import Foundation
import SwiftData
import PharmaCore

/// Fehler der KI-Anbindung mit verständlichen deutschen Meldungen.
enum KIFehler: LocalizedError, Equatable {
    case keinSchluessel
    case keinInternet
    case ungueltigerSchluessel
    case ratenlimit
    case ueberlastet
    case abgelehnt
    case abgeschnitten
    case unlesbareAntwort
    case anfrage(String)
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .keinSchluessel:
            return "Kein API-Schlüssel hinterlegt. Trage deinen Claude-API-Schlüssel in den Einstellungen ein – alles andere funktioniert auch ohne."
        case .keinInternet:
            return "Keine Internetverbindung. Die KI-Funktionen sind gerade nicht verfügbar – der Rest der App funktioniert weiter."
        case .ungueltigerSchluessel:
            return "Der API-Schlüssel wurde abgelehnt. Bitte prüfe ihn in den Einstellungen."
        case .ratenlimit:
            return "Zu viele Anfragen in kurzer Zeit. Bitte versuche es in einer Minute erneut."
        case .ueberlastet:
            return "Der KI-Dienst ist gerade überlastet. Bitte versuche es gleich noch einmal."
        case .abgelehnt:
            return "Die KI hat diese Anfrage abgelehnt. Formuliere sie bitte anders."
        case .abgeschnitten:
            return "Die Antwort wurde abgeschnitten, weil sie zu lang wurde."
        case .unlesbareAntwort:
            return "Die Antwort der KI konnte nicht ausgewertet werden. Bitte versuche es erneut."
        case .anfrage(let meldung):
            return "Die Anfrage war ungültig: \(meldung)"
        case .server(let code):
            return "Der KI-Dienst hat einen Fehler gemeldet (Code \(code)). Bitte später erneut versuchen."
        }
    }
}

/// Austauschbare Schnittstelle zum KI-Anbieter.
protocol KIAnbieter {
    func antworten(_ anfrage: KIAnfrage) -> AsyncThrowingStream<KIEreignis, Error>
}

/// Claude-API über HTTPS mit Streaming (Server-Sent Events).
struct ClaudeAnbieter: KIAnbieter {
    func antworten(_ anfrage: KIAnfrage) -> AsyncThrowingStream<KIEreignis, Error> {
        AsyncThrowingStream { fortsetzung in
            let aufgabe = Task {
                do {
                    guard let schluessel = Schluesselbund.lesen(konto: Schluesselbund.claudeAPIKonto), !schluessel.isEmpty else {
                        throw KIFehler.keinSchluessel
                    }
                    var anforderung = URLRequest(url: ClaudeAPI.endpunkt)
                    anforderung.httpMethod = "POST"
                    anforderung.timeoutInterval = 600
                    for (feld, wert) in ClaudeAPI.kopfzeilen(schluessel: schluessel, modell: anfrage.modell) {
                        anforderung.setValue(wert, forHTTPHeaderField: feld)
                    }
                    anforderung.httpBody = try ClaudeAPI.koerper(anfrage)

                    let (bytes, antwort) = try await URLSession.shared.bytes(for: anforderung)
                    let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var daten = Data()
                        for try await byte in bytes {
                            daten.append(byte)
                            if daten.count > 65_536 { break }
                        }
                        throw Self.fehler(status: status, daten: daten)
                    }
                    var zerleger = SSEZerleger()
                    for try await zeile in bytes.lines {
                        for ereignis in zerleger.zeile(zeile) {
                            if case .fehler(let typ, let meldung) = ereignis {
                                throw typ == "overloaded_error" ? KIFehler.ueberlastet : KIFehler.anfrage(meldung)
                            }
                            fortsetzung.yield(ereignis)
                        }
                    }
                    fortsetzung.finish()
                } catch let fehler as URLError {
                    fortsetzung.finish(throwing: Self.netzfehler(fehler))
                } catch {
                    fortsetzung.finish(throwing: error)
                }
            }
            fortsetzung.onTermination = { _ in aufgabe.cancel() }
        }
    }

    static func fehler(status: Int, daten: Data) -> KIFehler {
        let meldung = ClaudeAPI.fehlermeldung(aus: daten)?.meldung ?? ""
        switch status {
        case 401, 403: return .ungueltigerSchluessel
        case 429: return .ratenlimit
        case 529, 503: return .ueberlastet
        case 400, 404, 413, 422: return .anfrage(meldung.isEmpty ? "Code \(status)" : meldung)
        default: return .server(status)
        }
    }

    static func netzfehler(_ fehler: URLError) -> Error {
        switch fehler.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff:
            return KIFehler.keinInternet
        case .cancelled:
            return CancellationError()
        default:
            return fehler
        }
    }
}

/// Zentrale Stelle für KI-Aufrufe; der Anbieter ist austauschbar.
@MainActor
enum KI {
    static var anbieter: KIAnbieter = ClaudeAnbieter()

    static var modell: String {
        UserDefaults.standard.string(forKey: EinstellungsSchluessel.kiModell) ?? ClaudeAPI.standardModell
    }

    static var istEingerichtet: Bool {
        Schluesselbund.lesen(konto: Schluesselbund.claudeAPIKonto)?.isEmpty == false
    }

    /// Sammelt eine vollständige Antwort (Text und Zitate).
    static func vollstaendig(_ anfrage: KIAnfrage, fortschritt: ((String) -> Void)? = nil) async throws -> (text: String, zitate: [KIZitat]) {
        var text = ""
        var zitate: [KIZitat] = []
        for try await ereignis in anbieter.antworten(anfrage) {
            switch ereignis {
            case .text(let teil):
                text += teil
                fortschritt?(text)
            case .zitat(let zitat):
                zitate.append(zitat)
            case .ende(let grund):
                if grund == "refusal" { throw KIFehler.abgelehnt }
                if grund == "max_tokens" && anfrage.schema != nil { throw KIFehler.abgeschnitten }
            case .fehler:
                break
            }
        }
        return (text, zitate)
    }

    /// Strukturierte Antwort (JSON-Schema) dekodieren.
    static func json<T: Decodable>(_ typ: T.Type, _ anfrage: KIAnfrage) async throws -> T {
        let (text, _) = try await vollstaendig(anfrage)
        guard let daten = text.data(using: .utf8), let wert = try? JSONDecoder().decode(T.self, from: daten) else {
            throw KIFehler.unlesbareAntwort
        }
        return wert
    }
}

/// Grundlage für alle Systemanweisungen.
enum KIAnweisungen {
    static let basis = """
    Du bist PharmaTutor, ein geduldiger, fachlich exakter Nachhilfelehrer für Pharmaziestudierende im Hauptstudium \
    (2. Abschnitt der Pharmazeutischen Prüfung, Goethe-Universität Frankfurt, Fachbereich 14).
    Antworte ausschließlich auf Deutsch und verwende korrekte deutsche pharmazeutische Fachsprache \
    (z. B. Arzneistoff, Arzneimittel, Ph. Eur., UAW, KI, WW, Gehaltsbestimmung, Grenzprüfung).
    Formatiere mit sparsamem Markdown: **fett** für Schlüsselbegriffe, kurze Listen mit „- “. Keine Tabellen, kein HTML.
    Wenn du dir bei etwas nicht sicher bist, sag das klar. Erfinde keine Quellen, Zahlen oder Monographie-Kapitel.
    """

    static func kontext(_ lv: Lehrveranstaltung?) -> String {
        guard let lv else { return "" }
        let gebiete = lv.stoffgebiete.map { "\($0.code) (\($0.name))" }.joined(separator: ", ")
        return """

        Lehrveranstaltung: \(LfdNr.anzeige(lv.lfdNr)) \(lv.bezeichnung) – \(lv.lehrform.name), Stoffgebiet \(gebiete)\
        \(lv.dozenten.isEmpty ? "" : ", Dozent:innen: " + lv.dozenten.joined(separator: ", ")).
        """
    }

    /// Feste Abschnitte am Ende jeder Erklärung.
    static let struktur = """

    Beende jede Erklärung mit genau diesen vier Abschnitten, jeweils als eigene Überschrift:
    ### Merksatz
    (ein einprägsamer Satz)
    ### Signalwörter
    (welche Schlüsselwörter in einer Klausurfrage welche Antwort verlangen, Form „„Signalwort“ → was zu antworten ist“)
    ### Typische Falle
    (der häufigste Denkfehler)
    ### In der Klausur
    (wie man die Frage in der Klausur vollständig beantwortet)
    """
}
