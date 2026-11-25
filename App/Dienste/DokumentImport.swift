import Foundation
import SwiftData
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import CoreTransferable
import PharmaCore

/// Importiert Dateien als Vorlesungsunterlagen.
@MainActor
enum DokumentImport {
    static let erlaubteTypen: [UTType] = {
        var typen: [UTType] = [.pdf, .image, .audio, .presentation]
        for endung in ["pptx", "ppt", "key", "odp"] {
            if let typ = UTType(filenameExtension: endung) { typen.append(typ) }
        }
        return typen
    }()

    enum Fehler: LocalizedError {
        case nichtUnterstuetzt(String)
        case nichtLesbar(String)
        case beschaedigt(String)

        var errorDescription: String? {
            switch self {
            case .nichtUnterstuetzt(let name):
                return "„\(name)“ hat ein Format, das PharmaTutor nicht importieren kann. Unterstützt werden PDF, Bilder, PowerPoint/Keynote und Audio."
            case .nichtLesbar(let name):
                return "„\(name)“ konnte nicht gelesen werden. Ist die Datei bei Google Drive oder iCloud vollständig heruntergeladen?"
            case .beschaedigt(let name):
                return "„\(name)“ scheint beschädigt zu sein."
            }
        }
    }

    /// Importiert eine Datei. Bei Dateien aus dem Import-Dialog wird der Sandbox-Zugriff angefordert.
    @discardableResult
    static func importieren(url: URL, in lv: Lehrveranstaltung, kontext: ModelContext) throws -> Dokument {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let typ = DokumentTyp.typ(fuerEndung: url.pathExtension) else { throw Fehler.nichtUnterstuetzt(name) }

        var daten: Data
        do {
            daten = try Data(contentsOf: url)
        } catch {
            throw Fehler.nichtLesbar(name)
        }

        if typ == .scan {
            guard let bild = PlattformBild(data: daten), let pdf = PDFWerkzeuge.pdf(ausBildern: [bild]) else {
                throw Fehler.beschaedigt(name)
            }
            daten = pdf
        }
        if typ == .pdf, PDFDocument(data: daten) == nil {
            throw Fehler.beschaedigt(name)
        }

        let titel = url.deletingPathExtension().lastPathComponent
        return anlegen(titel: titel, dateiname: name, typ: typ, daten: daten, in: lv, kontext: kontext)
    }

    /// Legt ein Dokument an, liest Seitentexte und startet die Texterkennung.
    @discardableResult
    static func anlegen(titel: String, dateiname: String, typ: DokumentTyp, daten: Data,
                        in lv: Lehrveranstaltung, kontext: ModelContext) -> Dokument {
        let dokument = Dokument(titel: titel, dateiname: dateiname, typ: typ, daten: daten)
        kontext.insert(dokument)
        dokument.lehrveranstaltung = lv

        switch typ {
        case .pdf, .scan:
            if let pdf = PDFDocument(data: daten) {
                dokument.seitenzahl = pdf.pageCount
                for index in 0..<pdf.pageCount {
                    let seite = Seite(nummer: index, text: pdf.page(at: index)?.string ?? "")
                    kontext.insert(seite)
                    seite.dokument = dokument
                }
            }
            Task { await TexterkennungsDienst.seitenErkennen(dokument) }
        case .praesentation:
            if let folien = try? PptxText.folien(aus: daten) {
                dokument.seitenzahl = folien.count
                for (index, text) in folien.enumerated() {
                    let seite = Seite(nummer: index, text: text)
                    kontext.insert(seite)
                    seite.dokument = dokument
                }
            }
        case .audio:
            break
        }
        return dokument
    }

    /// Schreibt die Daten in eine temporäre Datei (für QuickLook und Audio).
    static func temporaereDatei(fuer dokument: Dokument) -> URL? {
        guard let daten = dokument.daten else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(dokument.kennung.uuidString)
            .appendingPathExtension(dokument.endung)
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try daten.write(to: url) } catch { return nil }
        }
        return url
    }
}

/// Per Drag & Drop empfangene Datei.
struct ImportDatei: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { empfangen in
            let ziel = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(empfangen.file.lastPathComponent)
            try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: empfangen.file, to: ziel)
            return ImportDatei(url: ziel)
        }
    }
}

/// PDF-Datei für den Export-Dialog.
struct PDFDatei: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var daten: Data

    init(daten: Data) {
        self.daten = daten
    }

    init(configuration: ReadConfiguration) throws {
        daten = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: daten)
    }
}
