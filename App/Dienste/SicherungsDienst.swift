import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers
import PharmaCore

/// Vollständige Sicherung aller Daten als eine Datei (.pharmatutor):
/// konsistente Kopie der Datenbank (SQLite-Backup) plus extern gespeicherte Dateien (PDFs, Bilder, Audio).
enum SicherungsDienst {
    enum Fehler: LocalizedError {
        case datenbank(String)
        case ungueltig
        case neuereVersion

        var errorDescription: String? {
            switch self {
            case .datenbank(let text): "Die Datenbank konnte nicht gesichert werden (\(text))."
            case .ungueltig: "Die Datei ist keine gültige PharmaTutor-Sicherung."
            case .neuereVersion: "Die Sicherung stammt von einer neueren PharmaTutor-Version. Bitte aktualisiere die App auf diesem Gerät."
            }
        }
    }

    private static let datenbankName = "datenbank.store"
    private static let standName = "stand.json"
    private static let externPraefix = "extern/"

    /// Ordner neben dem Speicher, in dem SwiftData große Daten ablegt („.<Name>_SUPPORT“).
    static func zusatzOrdner(fuer speicher: URL) -> URL {
        let name = speicher.deletingPathExtension().lastPathComponent
        return speicher.deletingLastPathComponent().appending(path: ".\(name)_SUPPORT", directoryHint: .isDirectory)
    }

    // MARK: Erstellen

    @MainActor
    static func erstellen(kontext: ModelContext, speicher: URL, stand: Abgleich.Stand) throws -> Data {
        try? kontext.save()
        let temp = FileManager.default.temporaryDirectory.appending(path: "sicherung-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: temp) }
        try datenbankKopieren(von: speicher, nach: temp)

        var eintraege: [(name: String, daten: Data)] = []
        eintraege.append((standName, try stand.json()))
        eintraege.append((datenbankName, try Data(contentsOf: temp)))

        let zusatz = zusatzOrdner(fuer: speicher)
        if let aufzaehlung = FileManager.default.enumerator(at: zusatz, includingPropertiesForKeys: [.isRegularFileKey]) {
            let basis = zusatz.standardizedFileURL.path
            for case let datei as URL in aufzaehlung {
                guard (try? datei.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let pfad = datei.standardizedFileURL.path
                guard pfad.hasPrefix(basis) else { continue }
                let relativ = String(pfad.dropFirst(basis.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                eintraege.append((externPraefix + relativ, try Data(contentsOf: datei)))
            }
        }
        return Zip.archiv(eintraege)
    }

    /// Konsistente Kopie über die SQLite-Backup-Schnittstelle (berücksichtigt das WAL-Journal).
    private static func datenbankKopieren(von quelle: URL, nach ziel: URL) throws {
        var quelleDB: OpaquePointer?
        var zielDB: OpaquePointer?
        defer {
            sqlite3_close(quelleDB)
            sqlite3_close(zielDB)
        }
        guard sqlite3_open_v2(quelle.path, &quelleDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let quelleDB else {
            throw Fehler.datenbank("Öffnen")
        }
        guard sqlite3_open(ziel.path, &zielDB) == SQLITE_OK, let zielDB else {
            throw Fehler.datenbank("Ziel")
        }
        guard let sicherung = sqlite3_backup_init(zielDB, "main", quelleDB, "main") else {
            throw Fehler.datenbank(String(cString: sqlite3_errmsg(zielDB)))
        }
        let ergebnis = sqlite3_backup_step(sicherung, -1)
        sqlite3_backup_finish(sicherung)
        guard ergebnis == SQLITE_DONE else { throw Fehler.datenbank("Code \(ergebnis)") }
        // Als eigenständige Datei ohne WAL ablegen.
        sqlite3_exec(zielDB, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
    }

    // MARK: Lesen und Wiederherstellen

    /// Liest nur die Beschreibung einer Sicherung.
    static func stand(aus daten: Data) throws -> Abgleich.Stand? {
        let eintraege = try Zip.eintraege(daten)
        return try eintraege[standName].map(Abgleich.Stand.aus(json:))
    }

    /// Entpackt die Sicherung an einen neuen Ort und gibt den Speicherpfad zurück.
    static func entpacken(_ daten: Data) throws -> (speicher: URL, stand: Abgleich.Stand?) {
        let eintraege: [String: Data]
        do {
            eintraege = try Zip.eintraege(daten)
        } catch {
            throw Fehler.ungueltig
        }
        guard let datenbank = eintraege[datenbankName] else { throw Fehler.ungueltig }
        let stand = try? eintraege[standName].map(Abgleich.Stand.aus(json:))
        if let stand, stand.schemaVersion > Abgleich.schemaVersion { throw Fehler.neuereVersion }

        let fm = FileManager.default
        let ziel = Datenspeicher.neuerSpeicherOrt()
        try fm.createDirectory(at: ziel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datenbank.write(to: ziel)
        let zusatz = zusatzOrdner(fuer: ziel)
        for (name, inhalt) in eintraege where name.hasPrefix(externPraefix) {
            let relativ = String(name.dropFirst(externPraefix.count))
            // Keine Pfade außerhalb des Zielordners zulassen.
            guard !relativ.isEmpty, !relativ.split(separator: "/").contains("..") else { continue }
            let datei = zusatz.appending(path: relativ)
            try fm.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
            try inhalt.write(to: datei)
        }
        return (ziel, stand)
    }
}

extension UTType {
    /// PharmaTutor-Sicherung (.pharmatutor).
    static var pharmatutorSicherung: UTType {
        UTType(filenameExtension: Abgleich.dateiendung, conformingTo: .data) ?? .data
    }
}

/// Geräte-Kennung und -Name für Sicherungen und Abgleich.
enum Geraet {
    private static let schluessel = "geraetID"

    static var id: UUID {
        if let text = UserDefaults.standard.string(forKey: schluessel), let id = UUID(uuidString: text) { return id }
        let neu = UUID()
        UserDefaults.standard.set(neu.uuidString, forKey: schluessel)
        return neu
    }

    static var name: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "iPad"
        #endif
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
}
