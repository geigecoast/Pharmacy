import Foundation
import Observation
import SwiftData
import PharmaCore
#if os(iOS)
import UIKit
#endif

/// Abgleich zwischen Mac und iPad über einen gemeinsamen Ordner (iCloud Drive, Google Drive …).
/// Siehe `Abgleich` in PharmaCore für die Entscheidungsregeln.
@MainActor
@Observable
final class AbgleichDienst {
    static let shared = AbgleichDienst()

    enum Fehler: LocalizedError {
        case keinOrdner
        case ordnerNichtErreichbar
        case wirdGeladen
        case unvollstaendig

        var errorDescription: String? {
            switch self {
            case .keinOrdner: "Es ist noch kein Abgleichsordner ausgewählt."
            case .ordnerNichtErreichbar: "Der Abgleichsordner ist nicht erreichbar. Wähle ihn in den Einstellungen erneut aus."
            case .wirdGeladen: "Der Stand des anderen Geräts wird noch heruntergeladen. Versuche es gleich noch einmal."
            case .unvollstaendig: "Der Stand des anderen Geräts ist noch nicht vollständig übertragen. Versuche es gleich noch einmal."
            }
        }
    }

    private enum Schluessel {
        static let lesezeichen = "abgleichLesezeichen"
        static let ordnerName = "abgleichOrdnerName"
        static let meinStand = "abgleichMeinStand"
        static let geaendert = "abgleichGeaendert"
        static let erledigt = "abgleichErledigt"
        static let letzter = "abgleichLetzter"
    }

    private let standard = UserDefaults.standard

    private(set) var ordnerName: String?
    private(set) var letzterAbgleich: Date?
    /// Eine Abgleichsfrage wird gerade angezeigt (nur ein Fenster fragt).
    var frageOffen = false
    /// In dieser Sitzung zurückgestellte Stände („Später“).
    private var zurueckgestellt: Set<UUID> = []
    private var ruheBis = Date.distantPast
    private var letzterExport = Date.distantPast

    private init() {
        ordnerName = standard.string(forKey: Schluessel.ordnerName)
        letzterAbgleich = standard.object(forKey: Schluessel.letzter) as? Date
    }

    var istEingerichtet: Bool { standard.data(forKey: Schluessel.lesezeichen) != nil }

    private var meinStandID: UUID? {
        get { standard.string(forKey: Schluessel.meinStand).flatMap(UUID.init(uuidString:)) }
        set { standard.set(newValue?.uuidString, forKey: Schluessel.meinStand) }
    }

    private(set) var lokalGeaendert: Bool {
        get { standard.object(forKey: Schluessel.geaendert) as? Bool ?? true }
        set { standard.set(newValue, forKey: Schluessel.geaendert) }
    }

    private var erledigt: Set<UUID> {
        get { Set((standard.stringArray(forKey: Schluessel.erledigt) ?? []).compactMap(UUID.init(uuidString:))) }
        set { standard.set(newValue.map(\.uuidString), forKey: Schluessel.erledigt) }
    }

    private func abgeglichen() {
        letzterAbgleich = Date()
        standard.set(letzterAbgleich, forKey: Schluessel.letzter)
    }

    // MARK: Lokale Änderungen

    /// Nach jedem Speichern aufrufen; automatische Änderungen (Lernplan, Abzeichen) vorher mit `ruhig()` ausblenden.
    func lokaleAenderung() {
        guard Date() >= ruheBis else { return }
        lokalGeaendert = true
    }

    /// Blendet Speichervorgänge der nächsten Sekunden aus (automatische Aktualisierungen).
    func ruhig(_ sekunden: TimeInterval = 1) {
        ruheBis = max(ruheBis, Date().addingTimeInterval(sekunden))
    }

    /// Nach dem Wiederherstellen einer Sicherung: Der Stand gilt als geändert.
    func nachWiederherstellung() {
        ruhig(3)
        lokalGeaendert = true
    }

    // MARK: Ordner

    func ordnerFestlegen(_ url: URL) throws {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let daten = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let daten = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        standard.set(daten, forKey: Schluessel.lesezeichen)
        standard.set(url.lastPathComponent, forKey: Schluessel.ordnerName)
        ordnerName = url.lastPathComponent
        // Neuer Ordner: eigener Stand muss einmal abgelegt werden.
        lokalGeaendert = true
    }

    func ordnerEntfernen() {
        standard.removeObject(forKey: Schluessel.lesezeichen)
        standard.removeObject(forKey: Schluessel.ordnerName)
        ordnerName = nil
    }

    private func mitOrdner<T>(_ arbeit: (URL) throws -> T) throws -> T {
        guard let daten = standard.data(forKey: Schluessel.lesezeichen) else { throw Fehler.keinOrdner }
        var veraltet = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: daten, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &veraltet)
        #else
        let url = try URL(resolvingBookmarkData: daten, options: [], relativeTo: nil, bookmarkDataIsStale: &veraltet)
        #endif
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        if veraltet { try? ordnerFestlegen(url) }
        guard FileManager.default.fileExists(atPath: url.path) else { throw Fehler.ordnerNichtErreichbar }
        return try arbeit(url)
    }

    private var dateiBasis: String { Abgleich.dateiname(geraetName: Geraet.name, geraetID: Geraet.id) }

    // MARK: Koordinierter Dateizugriff

    private static func schreiben(_ daten: Data, nach url: URL) throws {
        var koordinationsFehler: NSError?
        var schreibFehler: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &koordinationsFehler) { ziel in
            do { try daten.write(to: ziel, options: .atomic) } catch { schreibFehler = error }
        }
        if let fehler = koordinationsFehler ?? schreibFehler { throw fehler }
    }

    private static func lesen(_ url: URL) throws -> Data {
        var koordinationsFehler: NSError?
        var ergebnis: Result<Data, Error> = .failure(Fehler.unvollstaendig)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &koordinationsFehler) { quelle in
            ergebnis = Result { try Data(contentsOf: quelle) }
        }
        if let koordinationsFehler { throw koordinationsFehler }
        return try ergebnis.get()
    }

    // MARK: Ablegen

    /// Legt den aktuellen Stand im Ordner ab (nur bei Änderungen, höchstens einmal pro Minute).
    func ablegenFallsNoetig(kontext: ModelContext, speicher: URL) {
        guard istEingerichtet, lokalGeaendert, Date().timeIntervalSince(letzterExport) > 60 else { return }
        #if os(iOS)
        let aufgabe = UIApplication.shared.beginBackgroundTask(withName: "PharmaTutor-Abgleich")
        defer { UIApplication.shared.endBackgroundTask(aufgabe) }
        #endif
        try? ablegen(kontext: kontext, speicher: speicher)
    }

    func ablegen(kontext: ModelContext, speicher: URL) throws {
        let stand = Abgleich.Stand(basisID: meinStandID, geraetID: Geraet.id, geraetName: Geraet.name,
                                   erstelltAm: Date(), appVersion: Geraet.appVersion)
        ruhig(2)
        let daten = try SicherungsDienst.erstellen(kontext: kontext, speicher: speicher, stand: stand)
        let basis = dateiBasis
        try mitOrdner { ordner in
            try Self.schreiben(daten, nach: ordner.appending(path: basis + "." + Abgleich.dateiendung))
            try Self.schreiben(try stand.json(), nach: ordner.appending(path: basis + ".json"))
        }
        meinStandID = stand.id
        lokalGeaendert = false
        letzterExport = Date()
        abgeglichen()
    }

    // MARK: Prüfen und Übernehmen

    /// Liest die Beschreibungen der anderen Geräte und entscheidet, ob etwas zu tun ist.
    func pruefen() -> Abgleich.Entscheidung {
        guard istEingerichtet else { return .nichts }
        let fremde: [Abgleich.Stand] = (try? mitOrdner { ordner in
            let fm = FileManager.default
            let inhalte = try fm.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil, options: [])
            var staende: [Abgleich.Stand] = []
            for datei in inhalte {
                let name = datei.lastPathComponent
                if let ziel = Abgleich.icloudPlatzhalterZiel(name), ziel.hasPrefix(Abgleich.praefix) {
                    try? fm.startDownloadingUbiquitousItem(at: ordner.appending(path: ziel))
                    continue
                }
                guard name.hasPrefix(Abgleich.praefix), name.hasSuffix(".json"),
                      let daten = try? Self.lesen(datei),
                      let stand = try? Abgleich.Stand.aus(json: daten) else { continue }
                staende.append(stand)
            }
            return staende
        }) ?? []
        return Abgleich.entscheiden(fremde: fremde, eigeneGeraetID: Geraet.id, meinStandID: meinStandID,
                                    lokalGeaendert: lokalGeaendert, erledigt: erledigt.union(zurueckgestellt))
    }

    /// Ersetzt die lokalen Daten durch den Stand des anderen Geräts.
    func uebernehmen(_ stand: Abgleich.Stand, speicher: Datenspeicher) throws {
        let basis = Abgleich.dateiname(geraetName: stand.geraetName, geraetID: stand.geraetID)
        let daten: Data = try mitOrdner { ordner in
            let datei = ordner.appending(path: basis + "." + Abgleich.dateiendung)
            let platzhalter = ordner.appending(path: "." + basis + "." + Abgleich.dateiendung + ".icloud")
            if FileManager.default.fileExists(atPath: platzhalter.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: datei)
                throw Fehler.wirdGeladen
            }
            return try Self.lesen(datei)
        }
        let ergebnis = try SicherungsDienst.entpacken(daten)
        guard ergebnis.stand?.id == stand.id else {
            try? FileManager.default.removeItem(at: ergebnis.speicher.deletingLastPathComponent())
            throw Fehler.unvollstaendig
        }
        ruhig(5)
        try speicher.wechseln(zu: ergebnis.speicher)
        meinStandID = stand.id
        lokalGeaendert = false
        erledigt.insert(stand.id)
        abgeglichen()
    }

    /// Behält den lokalen Stand; er ersetzt beim nächsten Abgleich den des anderen Geräts.
    func behalten(_ stand: Abgleich.Stand, kontext: ModelContext, speicher: URL) throws {
        erledigt.insert(stand.id)
        meinStandID = stand.id
        lokalGeaendert = true
        try ablegen(kontext: kontext, speicher: speicher)
    }

    func spaeter(_ stand: Abgleich.Stand) {
        zurueckgestellt.insert(stand.id)
    }
}

extension Notification.Name {
    /// Bittet das Hauptfenster, den Abgleichsordner zu prüfen und ggf. nachzufragen.
    static let abgleichPruefen = Notification.Name("pharmatutor.abgleichPruefen")
}
