import SwiftUI
import SwiftData
import PharmaCore

// MARK: - Monat

struct MonatsAnsicht: View {
    let stichtag: Date
    let eintraege: [Date: [KalenderEintrag]]
    let kalender: Calendar
    var tagGewaehlt: (Date) -> Void

    static let wochentagsKuerzel = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    /// 6 Wochen à 7 Tage, beginnend mit dem Montag vor dem Monatsersten.
    static func tage(fuer stichtag: Date, kalender: Calendar) -> [Date] {
        let monatsbeginn = kalender.dateInterval(of: .month, for: stichtag)?.start ?? stichtag
        let start = kalender.dateInterval(of: .weekOfYear, for: monatsbeginn)?.start ?? monatsbeginn
        return (0..<42).compactMap { kalender.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let tage = Self.tage(fuer: stichtag, kalender: kalender)
        let monat = kalender.component(.month, from: stichtag)
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Self.wochentagsKuerzel, id: \.self) { kuerzel in
                        Text(kuerzel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                    ForEach(tage, id: \.self) { tag in
                        MonatsZelle(tag: tag,
                                    imMonat: kalender.component(.month, from: tag) == monat,
                                    istHeute: kalender.isDateInToday(tag),
                                    eintraege: eintraege[kalender.startOfDay(for: tag)] ?? [])
                            .onTapGesture { tagGewaehlt(tag) }
                    }
                }
                .background(Color.secondary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: Layout.eckenradius))
            }
            .padding(Layout.abstand)
        }
    }
}

private struct MonatsZelle: View {
    let tag: Date
    let imMonat: Bool
    let istHeute: Bool
    let eintraege: [KalenderEintrag]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag.formatted(.dateTime.day().locale(.deutsch)))
                .font(.callout.weight(istHeute ? .bold : .regular))
                .foregroundStyle(istHeute ? Color.white : Color.primary)
                .frame(minWidth: 24, minHeight: 24)
                .background {
                    if istHeute { Circle().fill(Color.accentColor) }
                }
            ForEach(eintraege.prefix(3)) { eintrag in
                EintragsChip(eintrag: eintrag, kompakt: true)
            }
            if eintraege.count > 3 {
                Text("+\(eintraege.count - 3) weitere")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(4)
        .background(.background)
        .opacity(imMonat ? 1 : 0.45)
        .contentShape(Rectangle())
    }
}

// MARK: - Woche

struct WochenAnsicht: View {
    let stichtag: Date
    let eintraege: [Date: [KalenderEintrag]]
    let kalender: Calendar
    var tagGewaehlt: (Date) -> Void
    var verschieben: (UUID, Date) -> Void

    var body: some View {
        let start = kalender.dateInterval(of: .weekOfYear, for: stichtag)?.start ?? stichtag
        let tage = (0..<7).compactMap { kalender.date(byAdding: .day, value: $0, to: start) }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(tage, id: \.self) { tag in
                        WochenSpalte(tag: tag,
                                     istHeute: kalender.isDateInToday(tag),
                                     eintraege: eintraege[kalender.startOfDay(for: tag)] ?? [],
                                     tagGewaehlt: tagGewaehlt,
                                     verschieben: verschieben)
                    }
                }
                Text("Tipp: Lerneinheiten lassen sich per Drag & Drop auf einen anderen Tag verschieben.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Layout.abstand)
        }
    }
}

private struct WochenSpalte: View {
    let tag: Date
    let istHeute: Bool
    let eintraege: [KalenderEintrag]
    var tagGewaehlt: (Date) -> Void
    var verschieben: (UUID, Date) -> Void

    @State private var zielMarkiert = false

    private var lernminuten: Int {
        eintraege.compactMap(\.lerneinheit).reduce(0) { $0 + $1.dauerMinuten }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                tagGewaehlt(tag)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tag.formatted(.dateTime.weekday(.abbreviated).locale(.deutsch)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(tag.formatted(.dateTime.day().month(.abbreviated).locale(.deutsch)))
                        .font(.headline)
                        .foregroundStyle(istHeute ? Color.accentColor : Color.primary)
                    if lernminuten > 0 {
                        Text(verbatim: Dauer.text(minuten: lernminuten))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(eintraege) { eintrag in
                if let einheit = eintrag.lerneinheit {
                    EintragsChip(eintrag: eintrag)
                        .draggable(einheit.kennung.uuidString) {
                            EintragsChip(eintrag: eintrag).frame(width: 160)
                        }
                } else {
                    EintragsChip(eintrag: eintrag)
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Layout.eckenradius)
                .fill(zielMarkiert ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(istHeute ? 0.12 : 0.06))
        )
        .dropDestination(for: String.self) { elemente, _ in
            guard let text = elemente.first, let kennung = UUID(uuidString: text) else { return false }
            verschieben(kennung, tag)
            return true
        } isTargeted: { aktiv in
            zielMarkiert = aktiv
        }
    }
}

// MARK: - Tag

struct TagesAnsicht: View {
    let tag: Date
    let eintraege: [KalenderEintrag]
    @Binding var auswahl: Bereich?

    @Environment(\.modelContext) private var kontext
    @Query private var teilpruefungen: [Teilpruefung]

    private var planbar: [Teilpruefung] {
        teilpruefungen
            .filter { tp in
                guard let lv = tp.lehrveranstaltung, !lv.status.istAbgeschlossen, tp.ergebnis == .offen else { return false }
                return tp.typ != .praktischerTeil
            }
            .sorted { ($0.datum ?? .distantFuture) < ($1.datum ?? .distantFuture) }
    }

    var body: some View {
        List {
            Section {
                if eintraege.isEmpty {
                    Text("Keine Einträge an diesem Tag.")
                        .foregroundStyle(.secondary)
                }
                ForEach(eintraege) { eintrag in
                    if let einheit = eintrag.lerneinheit {
                        LerneinheitZeile(einheit: einheit)
                    } else {
                        TerminZeile(eintrag: eintrag) {
                            if let lv = eintrag.lehrveranstaltung { auswahl = .lehrveranstaltung(lv) }
                        }
                    }
                }
            } header: {
                Text(tag.datumMitWochentag)
            }

            Section {
                Menu {
                    ForEach(planbar) { tp in
                        Button(tp.titelMitLfdNr) { hinzufuegen(fuer: tp) }
                    }
                } label: {
                    Label("Lerneinheit hinzufügen", systemImage: "plus")
                }
                .disabled(planbar.isEmpty)
            } footer: {
                Text("Selbst angelegte oder verschobene Lerneinheiten bleiben beim Neuberechnen erhalten.")
            }
        }
    }

    private func hinzufuegen(fuer tp: Teilpruefung) {
        let einheit = Lerneinheit(tag: tag, dauerMinuten: 45, thema: tp.titelMitLfdNr, manuell: true)
        kontext.insert(einheit)
        einheit.teilpruefung = tp
        einheit.lehrveranstaltung = tp.lehrveranstaltung
    }
}

private struct TerminZeile: View {
    let eintrag: KalenderEintrag
    var oeffnen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: eintrag.symbol)
                .foregroundStyle(eintrag.farbe)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(eintrag.titel)
                    .fontWeight(.medium)
                    .strikethrough(eintrag.erledigt)
                if let uhrzeit = eintrag.uhrzeit {
                    Text(uhrzeit.formatted(.dateTime.hour().minute().locale(.deutsch)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !eintrag.detail.isEmpty {
                    Text(eintrag.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if eintrag.lehrveranstaltung != nil {
                Button("Öffnen", action: oeffnen)
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// Lerneinheit mit Abhaken, Dauer und Löschen.
struct LerneinheitZeile: View {
    @Bindable var einheit: Lerneinheit
    @Environment(\.modelContext) private var kontext

    var body: some View {
        HStack(spacing: 12) {
            Button {
                einheit.umschalten()
            } label: {
                Image(systemName: einheit.erledigt ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(einheit.erledigt ? Color.green : einheit.farbe)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(einheit.erledigt ? "Als offen markieren" : "Als erledigt markieren")

            VStack(alignment: .leading, spacing: 2) {
                Text(einheit.thema)
                    .strikethrough(einheit.erledigt)
                HStack(spacing: 6) {
                    if einheit.verpasst {
                        Label("verpasst", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    if einheit.manuell {
                        Label("selbst geplant", systemImage: "hand.point.up.left")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer()
            Stepper(value: Binding(
                get: { einheit.dauerMinuten },
                set: { neu in
                    einheit.dauerMinuten = neu
                    einheit.manuell = true
                }
            ), in: 15...480, step: 15) {
                Text(verbatim: Dauer.text(minuten: einheit.dauerMinuten))
                    .monospacedDigit()
            }
            .fixedSize()
            Button(role: .destructive) {
                kontext.delete(einheit)
            } label: {
                Label("Löschen", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }
}
