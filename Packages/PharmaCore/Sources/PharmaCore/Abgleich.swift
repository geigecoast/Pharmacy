import Foundation

/// Abgleich zwischen Geräten über einen gemeinsamen Ordner (iCloud Drive, Google Drive …).
///
/// Jedes Gerät legt dort seinen vollständigen Stand als Sicherung ab (eine Datei pro Gerät)
/// und daneben eine kleine Beschreibung (`Stand`). Ein Gerät übernimmt einen fremden Stand
/// ohne Rückfrage-Konflikt nur, wenn es selbst seit dem letzten Abgleich nichts geändert hat
/// und der fremde Stand auf dem eigenen aufbaut. Sonst entscheidet die Nutzerin.
public enum Abgleich {
    /// Version des Datenschemas; ein Gerät übernimmt keine Stände eines neueren Schemas.
    public static let schemaVersion = 1
    public static let dateiendung = "pharmatutor"
    public static let praefix = "PharmaTutor-"

    public struct Stand: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        /// Stand, auf dem dieser aufbaut (zuletzt übernommener oder eigener vorheriger Stand).
        public var basisID: UUID?
        public var geraetID: UUID
        public var geraetName: String
        public var erstelltAm: Date
        public var appVersion: String
        public var schemaVersion: Int

        public init(id: UUID = UUID(), basisID: UUID?, geraetID: UUID, geraetName: String, erstelltAm: Date,
                    appVersion: String, schemaVersion: Int = Abgleich.schemaVersion) {
            self.id = id
            self.basisID = basisID
            self.geraetID = geraetID
            self.geraetName = geraetName
            self.erstelltAm = erstelltAm
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }

        public func json() throws -> Data {
            let kodierer = JSONEncoder()
            kodierer.dateEncodingStrategy = .iso8601
            kodierer.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try kodierer.encode(self)
        }

        public static func aus(json: Data) throws -> Stand {
            let dekodierer = JSONDecoder()
            dekodierer.dateDecodingStrategy = .iso8601
            return try dekodierer.decode(Stand.self, from: json)
        }
    }

    public enum Entscheidung: Equatable, Sendable {
        case nichts
        /// Der fremde Stand baut auf dem eigenen auf, lokal wurde nichts geändert.
        case uebernehmen(Stand)
        /// Beide Seiten haben sich verändert – die Nutzerin entscheidet.
        case konflikt(Stand)
        /// Der neueste fremde Stand stammt von einer neueren App-Version.
        case neuereVersion(Stand)
    }

    /// Entscheidet, was mit den fremden Ständen im Abgleichsordner geschehen soll.
    /// - Parameters:
    ///   - meinStandID: ID des Stands, dem die lokalen Daten entsprechen (zuletzt exportiert oder übernommen).
    ///   - lokalGeaendert: Seitdem wurde lokal etwas geändert.
    ///   - erledigt: Fremde Stände, die bereits übernommen oder bewusst verworfen wurden.
    public static func entscheiden(fremde: [Stand], eigeneGeraetID: UUID, meinStandID: UUID?,
                                   lokalGeaendert: Bool, erledigt: Set<UUID>) -> Entscheidung {
        let kandidaten = fremde.filter { stand in
            stand.geraetID != eigeneGeraetID && stand.id != meinStandID && !erledigt.contains(stand.id)
        }
        guard let neuester = kandidaten.max(by: { $0.erstelltAm < $1.erstelltAm }) else { return .nichts }
        if neuester.schemaVersion > schemaVersion { return .neuereVersion(neuester) }
        if !lokalGeaendert && (meinStandID == nil || neuester.basisID == meinStandID) {
            return .uebernehmen(neuester)
        }
        return .konflikt(neuester)
    }

    /// Dateiname ohne Endung für ein Gerät, z. B. „PharmaTutor-Mac-1A2B3C4D“.
    public static func dateiname(geraetName: String, geraetID: UUID) -> String {
        let erlaubt = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let name = geraetName.unicodeScalars
            .map { erlaubt.contains($0) ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let kurz = String(geraetID.uuidString.prefix(8))
        return praefix + (name.isEmpty ? "Geraet" : name) + "-" + kurz
    }

    /// iCloud-Platzhalter „.Name.icloud“ → „Name“ (nil, wenn kein Platzhalter).
    public static func icloudPlatzhalterZiel(_ dateiname: String) -> String? {
        guard dateiname.hasPrefix("."), dateiname.hasSuffix(".icloud"), dateiname.count > 8 else { return nil }
        return String(dateiname.dropFirst().dropLast(".icloud".count))
    }
}
