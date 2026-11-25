import Foundation
#if canImport(SQLite3)
import SQLite3
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Erzeugt ein Anki-Paket (.apkg) im klassischen Format (Schema 11), das Anki importieren kann.
public enum AnkiPaket {
    public struct Notiz: Sendable {
        public enum Art: Sendable { case basis, lueckentext }
        public var art: Art
        /// Felder als HTML: Basis = [Vorderseite, Rückseite], Lückentext = [Text mit {{c1::…}}, Extra].
        public var felder: [String]
        public var schlagwoerter: [String]

        public init(art: Art, felder: [String], schlagwoerter: [String] = []) {
            self.art = art
            self.felder = felder
            self.schlagwoerter = schlagwoerter
        }
    }

    public enum Fehler: Error {
        case nichtVerfuegbar
        case datenbank(String)
    }

    /// - Parameters:
    ///   - stapel: Name des Anki-Stapels, z. B. „PharmaTutor::[43] Arzneistoffanalytik“.
    ///   - medien: Dateiname → Inhalt (z. B. Bilder, auf die per `<img src="…">` verwiesen wird).
    public static func erstellen(stapel: String, notizen: [Notiz], medien: [String: Data] = [:], jetzt: Date = Date()) throws -> Data {
        #if canImport(SQLite3)
        let pfad = FileManager.default.temporaryDirectory.appendingPathComponent("anki-\(UUID().uuidString).anki2").path
        defer { try? FileManager.default.removeItem(atPath: pfad) }

        var db: OpaquePointer?
        guard sqlite3_open(pfad, &db) == SQLITE_OK, let db else { throw Fehler.datenbank("Öffnen fehlgeschlagen") }
        var geschlossen = false
        defer { if !geschlossen { sqlite3_close(db) } }

        func ausfuehren(_ sql: String) throws {
            var meldung: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &meldung) != SQLITE_OK {
                let text = meldung.map { String(cString: $0) } ?? "unbekannt"
                sqlite3_free(meldung)
                throw Fehler.datenbank(text)
            }
        }

        try ausfuehren("""
        CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null, ver integer not null, dty integer not null, usn integer not null, ls integer not null, conf text not null, models text not null, decks text not null, dconf text not null, tags text not null);
        CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null, usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null, flags integer not null, data text not null);
        CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null, mod integer not null, usn integer not null, type integer not null, queue integer not null, due integer not null, ivl integer not null, factor integer not null, reps integer not null, lapses integer not null, left integer not null, odue integer not null, odid integer not null, flags integer not null, data text not null);
        CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null, ease integer not null, ivl integer not null, lastIvl integer not null, factor integer not null, time integer not null, type integer not null);
        CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
        CREATE INDEX ix_notes_usn on notes (usn);
        CREATE INDEX ix_cards_usn on cards (usn);
        CREATE INDEX ix_revlog_usn on revlog (usn);
        CREATE INDEX ix_cards_nid on cards (nid);
        CREATE INDEX ix_cards_sched on cards (did, queue, due);
        CREATE INDEX ix_revlog_cid on revlog (cid);
        CREATE INDEX ix_notes_csum on notes (csum);
        """)

        let sekunden = Int64(jetzt.timeIntervalSince1970)
        let ms = sekunden * 1000
        let basisID = ms
        let lueckeID = ms + 1
        let stapelID = ms + 2

        let modelle: [String: Any] = [
            String(basisID): modell(id: basisID, name: "PharmaTutor Basis", typ: 0, stapel: stapelID, sekunden: sekunden,
                                    felder: ["Vorderseite", "Rückseite"],
                                    vorlage: ["name": "Karte 1", "ord": 0, "qfmt": "{{Vorderseite}}",
                                              "afmt": "{{FrontSide}}<hr id=answer>{{Rückseite}}",
                                              "did": NSNull(), "bqfmt": "", "bafmt": ""]),
            String(lueckeID): modell(id: lueckeID, name: "PharmaTutor Lückentext", typ: 1, stapel: stapelID, sekunden: sekunden,
                                     felder: ["Text", "Extra"],
                                     vorlage: ["name": "Lückentext", "ord": 0, "qfmt": "{{cloze:Text}}",
                                               "afmt": "{{cloze:Text}}<br>{{Extra}}",
                                               "did": NSNull(), "bqfmt": "", "bafmt": ""]),
        ]
        let stapelEintrag: ([String: Any]) = [
            "id": stapelID, "name": stapel, "desc": "Exportiert aus PharmaTutor", "mod": sekunden, "usn": -1,
            "collapsed": false, "browserCollapsed": false, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0],
            "timeToday": [0, 0], "dyn": 0, "conf": 1, "extendNew": 10, "extendRev": 50,
        ]
        var standardStapel = stapelEintrag
        standardStapel["id"] = 1
        standardStapel["name"] = "Default"
        let stapelJSON: [String: Any] = ["1": standardStapel, String(stapelID): stapelEintrag]
        let dconf: [String: Any] = ["1": [
            "id": 1, "name": "Default", "mod": 0, "usn": 0, "maxTaken": 60, "timer": 0, "autoplay": true, "replayq": true, "dyn": false,
            "new": ["delays": [1, 10], "ints": [1, 4, 7], "initialFactor": 2500, "order": 1, "perDay": 20, "bury": false],
            "rev": ["perDay": 200, "ease4": 1.3, "ivlFct": 1, "maxIvl": 36500, "bury": false, "hardFactor": 1.2],
            "lapse": ["delays": [10], "mult": 0, "minInt": 1, "leechFails": 8, "leechAction": 0],
        ]]
        let conf: [String: Any] = [
            "nextPos": notizen.count + 1, "estTimes": true, "activeDecks": [1], "sortType": "noteFld", "timeLim": 0,
            "sortBackwards": false, "addToCur": true, "curDeck": 1, "newBury": true, "newSpread": 0, "dueCounts": true,
            "curModel": String(basisID), "collapseTime": 1200,
        ]

        try einfuegen(db, "INSERT INTO col VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')", [
            .zahl(sekunden), .zahl(ms), .zahl(ms), .text(json(conf)), .text(json(modelle)), .text(json(stapelJSON)), .text(json(dconf)),
        ])

        for (index, notiz) in notizen.enumerated() {
            let notizID = ms + 10 + Int64(index) * 2
            let kartenID = notizID + 1
            let modellID = notiz.art == .basis ? basisID : lueckeID
            let felder = notiz.felder.joined(separator: "\u{1F}")
            let sortierfeld = ohneHTML(notiz.felder.first ?? "")
            let schlagwoerter = notiz.schlagwoerter.isEmpty ? "" : " " + notiz.schlagwoerter.map { $0.replacingOccurrences(of: " ", with: "_") }.joined(separator: " ") + " "
            try einfuegen(db, "INSERT INTO notes VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, '')", [
                .zahl(notizID), .text(guid()), .zahl(modellID), .zahl(sekunden), .text(schlagwoerter), .text(felder),
                .text(sortierfeld), .zahl(pruefsumme(sortierfeld)),
            ])
            try einfuegen(db, "INSERT INTO cards VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, '')", [
                .zahl(kartenID), .zahl(notizID), .zahl(stapelID), .zahl(sekunden), .zahl(Int64(index + 1)),
            ])
        }
        sqlite3_close(db)
        geschlossen = true
        let datenbank = try Data(contentsOf: URL(fileURLWithPath: pfad))

        var eintraege: [(name: String, daten: Data)] = [("collection.anki2", datenbank)]
        var medienliste: [String: String] = [:]
        for (index, (name, inhalt)) in medien.sorted(by: { $0.key < $1.key }).enumerated() {
            medienliste[String(index)] = name
            eintraege.append((String(index), inhalt))
        }
        eintraege.append(("media", Data(json(medienliste).utf8)))
        return Zip.archiv(eintraege)
        #else
        throw Fehler.nichtVerfuegbar
        #endif
    }

    // MARK: Hilfen

    private static func modell(id: Int64, name: String, typ: Int, stapel: Int64, sekunden: Int64,
                               felder: [String], vorlage: [String: Any]) -> [String: Any] {
        [
            "id": id, "name": name, "type": typ, "mod": sekunden, "usn": -1, "sortf": 0, "did": stapel,
            "tmpls": [vorlage],
            "flds": felder.enumerated().map { index, feld in
                ["name": feld, "ord": index, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": [String]()] as [String: Any]
            },
            "css": ".card { font-family: -apple-system, Helvetica, Arial; font-size: 20px; text-align: center; color: #111; background: #fff; }\n.cloze { font-weight: bold; color: #7f5aa6; }",
            "latexPre": "\\documentclass[12pt]{article}\n\\special{papersize=3in,5in}\n\\usepackage[utf8]{inputenc}\n\\usepackage{amssymb,amsmath}\n\\pagestyle{empty}\n\\setlength{\\parindent}{0in}\n\\begin{document}\n",
            "latexPost": "\\end{document}",
            "tags": [String](), "vers": [String](), "req": [[0, "any", [0]]],
        ]
    }

    private static func json(_ objekt: Any) -> String {
        guard let daten = try? JSONSerialization.data(withJSONObject: objekt, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: daten, as: UTF8.self)
    }

    static func ohneHTML(_ text: String) -> String {
        var ergebnis = ""
        var inTag = false
        for zeichen in text {
            if zeichen == "<" { inTag = true; continue }
            if zeichen == ">" { inTag = false; continue }
            if !inTag { ergebnis.append(zeichen) }
        }
        return ergebnis
    }

    /// Anki: erste 8 Hex-Stellen des SHA-1 des Sortierfelds.
    static func pruefsumme(_ text: String) -> Int64 {
        #if canImport(CryptoKit)
        let hash = Insecure.SHA1.hash(data: Data(text.utf8))
        let bytes = Array(hash.prefix(4))
        return Int64(bytes[0]) << 24 | Int64(bytes[1]) << 16 | Int64(bytes[2]) << 8 | Int64(bytes[3])
        #else
        return 0
        #endif
    }

    private static func guid() -> String {
        let zeichen = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~")
        return String((0..<10).map { _ in zeichen[Int.random(in: 0..<zeichen.count)] })
    }

    #if canImport(SQLite3)
    private enum Wert {
        case zahl(Int64)
        case text(String)
    }

    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    private static func einfuegen(_ db: OpaquePointer, _ sql: String, _ werte: [Wert]) throws {
        var anweisung: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &anweisung, nil) == SQLITE_OK else {
            throw Fehler.datenbank(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(anweisung) }
        for (index, wert) in werte.enumerated() {
            let position = Int32(index + 1)
            switch wert {
            case .zahl(let zahl): sqlite3_bind_int64(anweisung, position, zahl)
            case .text(let text): sqlite3_bind_text(anweisung, position, text, -1, transient)
            }
        }
        guard sqlite3_step(anweisung) == SQLITE_DONE else {
            throw Fehler.datenbank(String(cString: sqlite3_errmsg(db)))
        }
    }
    #endif
}
