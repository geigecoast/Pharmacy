import Foundation
import Observation
import SwiftData

/// Hält den ModelContainer und kann zur Laufzeit auf einen anderen Datenspeicher wechseln
/// (nach dem Wiederherstellen einer Sicherung oder dem Übernehmen eines Stands vom anderen Gerät).
@MainActor
@Observable
final class Datenspeicher {
    private(set) var container: ModelContainer?
    private(set) var fehlertext: String?
    /// Erhöht sich bei jedem Wechsel; Ansichten mit `.id(generation)` werden neu aufgebaut.
    private(set) var generation = 0
    private(set) var speicherURL: URL

    private static let schluessel = "aktiverDatenspeicher"

    /// Ursprünglicher Speicher (Standardort von SwiftData).
    static var standardURL: URL { URL.applicationSupportDirectory.appending(path: "default.store") }

    /// Ordner für wiederhergestellte bzw. übernommene Speicher.
    static var datenOrdner: URL {
        URL.applicationSupportDirectory.appending(path: "PharmaTutor-Daten", directoryHint: .isDirectory)
    }

    init() {
        let gemerkt = UserDefaults.standard.string(forKey: Self.schluessel).map { URL(fileURLWithPath: $0) }
        if let gemerkt, FileManager.default.fileExists(atPath: gemerkt.path) {
            speicherURL = gemerkt
        } else {
            speicherURL = Self.standardURL
        }
        do {
            container = try Self.oeffnen(speicherURL)
        } catch {
            fehlertext = error.localizedDescription
        }
        Self.aufraeumen(ausser: speicherURL)
    }

    static func oeffnen(_ url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema(Datenschema.modelle)
        let konfiguration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [konfiguration])
    }

    /// Wechselt auf einen neuen Speicher. Schlägt das Öffnen fehl, bleibt alles beim Alten.
    func wechseln(zu url: URL) throws {
        let neu = try Self.oeffnen(url)
        container = neu
        speicherURL = url
        fehlertext = nil
        generation += 1
        UserDefaults.standard.set(url.path, forKey: Self.schluessel)
    }

    /// Entfernt alte wiederhergestellte Speicher (der aktive bleibt). Läuft beim Start,
    /// wenn kein alter Container mehr geöffnet ist.
    private static func aufraeumen(ausser aktiv: URL) {
        let fm = FileManager.default
        guard let ordner = try? fm.contentsOfDirectory(at: datenOrdner, includingPropertiesForKeys: nil) else { return }
        let aktiverOrdner = aktiv.deletingLastPathComponent().standardizedFileURL
        for eintrag in ordner where eintrag.standardizedFileURL != aktiverOrdner {
            try? fm.removeItem(at: eintrag)
        }
    }

    /// Neuer, leerer Zielort für einen wiederhergestellten Speicher.
    static func neuerSpeicherOrt() -> URL {
        datenOrdner
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "PharmaTutor.store")
    }
}
