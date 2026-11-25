import SwiftUI
import SwiftData
import PharmaCore

/// Ein anzeigbarer Eintrag im Kalender (aus Teilprüfungen, Fristen und Lerneinheiten).
struct KalenderEintrag: Identifiable {
    enum Art: Int {
        case pruefung, praktikum, anmeldeschluss, frist, lerneinheit
    }

    let id: String
    let art: Art
    let titel: String
    let detail: String
    let farbe: Color
    let symbol: String
    let uhrzeit: Date?
    let lerneinheit: Lerneinheit?
    let lehrveranstaltung: Lehrveranstaltung?
    let erledigt: Bool
    let verpasst: Bool
}

@MainActor
enum KalenderQuelle {
    /// Einträge je Tagesbeginn im Zeitraum [von, bis).
    static func eintraege(
        teilpruefungen: [Teilpruefung],
        fristen: [Frist],
        lerneinheiten: [Lerneinheit],
        von: Date,
        bis: Date,
        kalender: Calendar
    ) -> [Date: [KalenderEintrag]] {
        var ergebnis: [Date: [KalenderEintrag]] = [:]

        func hinzufuegen(_ datum: Date, _ eintrag: KalenderEintrag) {
            let tag = kalender.startOfDay(for: datum)
            guard tag >= von, tag < bis else { return }
            ergebnis[tag, default: []].append(eintrag)
        }

        for tp in teilpruefungen {
            guard let datum = tp.datum, let lv = tp.lehrveranstaltung else { continue }
            let kennung = "tp-\(tp.persistentModelID.hashValue)"
            let erledigt = tp.ergebnis != .offen
            if tp.typ == .praktischerTeil, let ende = tp.ende, ende > datum {
                var tag = kalender.startOfDay(for: datum)
                let letzter = kalender.startOfDay(for: ende)
                while tag <= letzter {
                    hinzufuegen(tag, KalenderEintrag(
                        id: "\(kennung)-\(tag.timeIntervalSince1970)", art: .praktikum,
                        titel: tp.titelMitLfdNr, detail: lv.bezeichnung, farbe: lv.farbe, symbol: tp.typ.symbol,
                        uhrzeit: nil, lerneinheit: nil, lehrveranstaltung: lv, erledigt: erledigt, verpasst: false))
                    guard let naechster = kalender.date(byAdding: .day, value: 1, to: tag) else { break }
                    tag = naechster
                }
            } else {
                hinzufuegen(datum, KalenderEintrag(
                    id: kennung, art: tp.typ == .praktischerTeil ? .praktikum : .pruefung,
                    titel: tp.titelMitLfdNr, detail: lv.bezeichnung, farbe: lv.farbe, symbol: tp.typ.symbol,
                    uhrzeit: datum, lerneinheit: nil, lehrveranstaltung: lv, erledigt: erledigt, verpasst: false))
            }
            if tp.anmeldepflichtig, !tp.angemeldet, let schluss = tp.anmeldeschluss {
                hinzufuegen(schluss, KalenderEintrag(
                    id: "\(kennung)-anm", art: .anmeldeschluss,
                    titel: "Anmeldeschluss: \(tp.titelMitLfdNr)", detail: "QIS/LSF – verspätete Anmeldung nicht möglich",
                    farbe: .orange, symbol: "exclamationmark.triangle", uhrzeit: nil, lerneinheit: nil,
                    lehrveranstaltung: lv, erledigt: false, verpasst: false))
            }
        }

        for frist in fristen {
            guard let datum = frist.datum else { continue }
            hinzufuegen(datum, KalenderEintrag(
                id: "frist-\(frist.persistentModelID.hashValue)", art: .frist,
                titel: frist.titel, detail: frist.art.name, farbe: .orange, symbol: "calendar.badge.exclamationmark",
                uhrzeit: nil, lerneinheit: nil, lehrveranstaltung: frist.lehrveranstaltung,
                erledigt: frist.erledigt, verpasst: false))
        }

        for einheit in lerneinheiten {
            hinzufuegen(einheit.tag, KalenderEintrag(
                id: "le-\(einheit.kennung.uuidString)", art: .lerneinheit,
                titel: einheit.thema, detail: Dauer.text(minuten: einheit.dauerMinuten),
                farbe: einheit.farbe, symbol: einheit.erledigt ? "checkmark.circle.fill" : "book",
                uhrzeit: nil, lerneinheit: einheit, lehrveranstaltung: einheit.lehrveranstaltung,
                erledigt: einheit.erledigt, verpasst: einheit.verpasst))
        }

        for (tag, liste) in ergebnis {
            ergebnis[tag] = liste.sorted {
                ($0.art.rawValue, $0.uhrzeit ?? .distantPast, $0.titel) < ($1.art.rawValue, $1.uhrzeit ?? .distantPast, $1.titel)
            }
        }
        return ergebnis
    }
}

/// Kompakte Darstellung eines Eintrags.
struct EintragsChip: View {
    let eintrag: KalenderEintrag
    var kompakt = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: eintrag.symbol)
                .font(.caption)
                .foregroundStyle(eintrag.farbe)
            VStack(alignment: .leading, spacing: 1) {
                Text(eintrag.titel)
                    .font(.caption.weight(eintrag.art == .lerneinheit ? .regular : .semibold))
                    .strikethrough(eintrag.erledigt)
                    .lineLimit(kompakt ? 1 : 3)
                if !kompakt, !eintrag.detail.isEmpty {
                    Text(eintrag.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(kompakt ? 3 : 6)
        .background(eintrag.farbe.opacity(eintrag.art == .lerneinheit ? 0.10 : 0.20),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if eintrag.verpasst {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [3]))
            }
        }
        .opacity(eintrag.erledigt ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
