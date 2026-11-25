import SwiftUI
import SwiftData
import PharmaCore

enum KalenderModus: String, CaseIterable, Identifiable {
    case monat, woche, tag

    var id: String { rawValue }

    var titel: LocalizedStringKey {
        switch self {
        case .monat: "Monat"
        case .woche: "Woche"
        case .tag: "Tag"
        }
    }

    var komponente: Calendar.Component {
        switch self {
        case .monat: .month
        case .woche: .weekOfYear
        case .tag: .day
        }
    }
}

struct KalenderAnsicht: View {
    @Binding var auswahl: Bereich?

    @Environment(\.modelContext) private var kontext
    @Query private var teilpruefungen: [Teilpruefung]
    @Query private var fristen: [Frist]
    @Query private var lerneinheiten: [Lerneinheit]
    @SceneStorage("kalenderModus") private var modus: KalenderModus = .monat
    @AppStorage(EinstellungsSchluessel.lernplanWarnungen) private var warnungen = ""
    @AppStorage(EinstellungsSchluessel.kalenderLerneinheitenExport) private var lerneinheitenExportieren = true

    @State private var stichtag = Date()
    @State private var zeigeLernzeiten = false
    @State private var meldung: String?
    @State private var gleichtAb = false

    private let kalender = Calendar.deutsch

    var body: some View {
        let zeitraum = sichtbarerZeitraum
        let daten = KalenderQuelle.eintraege(teilpruefungen: teilpruefungen, fristen: fristen, lerneinheiten: lerneinheiten,
                                             von: zeitraum.start, bis: zeitraum.end, kalender: kalender)
        VStack(spacing: 0) {
            kopfzeile
            hinweise
            switch modus {
            case .monat:
                MonatsAnsicht(stichtag: stichtag, eintraege: daten, kalender: kalender) { tag in
                    stichtag = tag
                    modus = .tag
                }
            case .woche:
                WochenAnsicht(stichtag: stichtag, eintraege: daten, kalender: kalender,
                              tagGewaehlt: { tag in
                                  stichtag = tag
                                  modus = .tag
                              },
                              verschieben: verschieben)
            case .tag:
                TagesAnsicht(tag: kalender.startOfDay(for: stichtag),
                             eintraege: daten[kalender.startOfDay(for: stichtag)] ?? [],
                             auswahl: $auswahl)
            }
        }
        .background(Thema.flaeche)
        .navigationTitle("Kalender")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        meldung = LernplanDienst.aktualisieren(kontext).meldung
                    } label: {
                        Label("Lernplan neu berechnen", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        zeigeLernzeiten = true
                    } label: {
                        Label("Lernzeiten festlegen …", systemImage: "clock")
                    }
                    Divider()
                    Button {
                        abgleichen()
                    } label: {
                        Label("Mit Systemkalender abgleichen", systemImage: "calendar.badge.plus")
                    }
                    .disabled(gleichtAb)
                } label: {
                    Label("Lernplan", systemImage: "list.bullet.clipboard")
                }
            }
        }
        .sheet(isPresented: $zeigeLernzeiten) {
            LernzeitenAnsicht()
        }
    }

    // MARK: Kopfzeile

    private var kopfzeile: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                titelText
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    ForEach(KalenderModus.allCases) { m in
                        if m != .monat {
                            Text(verbatim: "·").foregroundStyle(Thema.tinteTertiaer)
                        }
                        Button {
                            modus = m
                        } label: {
                            Text(m.titel)
                                .foregroundStyle(modus == m ? Thema.tinte : Thema.tinteSekundaer)
                                .underline(modus == m)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(Thema.ui(12))
                HStack(spacing: 14) {
                    Button {
                        blaettern(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .accessibilityLabel("Zurück")
                    Button("Heute") { stichtag = Date() }
                        .keyboardShortcut("t", modifiers: .command)
                    Button {
                        blaettern(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .accessibilityLabel("Weiter")
                }
                .buttonStyle(.plain)
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteSekundaer)
            }
            .padding(.bottom, 18)
            Haarlinie(farbe: Thema.tinte)
        }
        .padding(.horizontal, Thema.randAussen)
        .padding(.top, 40)
    }

    /// „Dezember 2026“ – Jahr in Grau; Woche/Tag mit eigenem Titel.
    @ViewBuilder
    private var titelText: some View {
        switch modus {
        case .monat:
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(verbatim: stichtag.formatted(.dateTime.month(.wide).locale(.deutsch)))
                    .foregroundStyle(Thema.tinte)
                Text(verbatim: stichtag.formatted(.dateTime.year().locale(.deutsch)))
                    .foregroundStyle(Thema.tinteTertiaer)
            }
            .font(Thema.display(52))
        case .woche, .tag:
            Text(verbatim: zeitraumTitel)
                .font(Thema.display(40))
                .foregroundStyle(Thema.tinte)
        }
    }

    @ViewBuilder
    private var hinweise: some View {
        let liste = warnungen.split(separator: "\n").map(String.init)
        if meldung != nil || !liste.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let meldung {
                    HStack {
                        Text(verbatim: meldung)
                        Spacer()
                        Button {
                            self.meldung = nil
                        } label: {
                            Label("Ausblenden", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(liste, id: \.self) { warnung in
                    Text(verbatim: warnung)
                        .foregroundStyle(Stoffgebiet.i.farbe)
                }
            }
            .font(Thema.ui(12))
            .padding(.horizontal, Thema.randAussen)
            .padding(.top, 12)
        }
    }

    // MARK: Zeitraum

    private var sichtbarerZeitraum: DateInterval {
        switch modus {
        case .monat:
            let tage = MonatsAnsicht.tage(fuer: stichtag, kalender: kalender)
            let start = tage.first ?? stichtag
            let ende = kalender.date(byAdding: .day, value: 1, to: tage.last ?? stichtag) ?? stichtag
            return DateInterval(start: start, end: ende)
        case .woche:
            return kalender.dateInterval(of: .weekOfYear, for: stichtag) ?? DateInterval(start: stichtag, duration: 7 * 86_400)
        case .tag:
            return kalender.dateInterval(of: .day, for: stichtag) ?? DateInterval(start: stichtag, duration: 86_400)
        }
    }

    private var zeitraumTitel: String {
        switch modus {
        case .monat:
            return stichtag.formatted(.dateTime.month(.wide).year().locale(.deutsch))
        case .woche:
            let woche = kalender.component(.weekOfYear, from: stichtag)
            let intervall = sichtbarerZeitraum
            let ende = kalender.date(byAdding: .day, value: -1, to: intervall.end) ?? intervall.end
            return "KW \(woche) · \(intervall.start.formatted(.dateTime.day().month(.abbreviated).locale(.deutsch))) – \(ende.kurzesDatum)"
        case .tag:
            return stichtag.datumMitWochentag
        }
    }

    private func blaettern(_ richtung: Int) {
        if let neu = kalender.date(byAdding: modus.komponente, value: richtung, to: stichtag) {
            stichtag = neu
        }
    }

    // MARK: Aktionen

    private func verschieben(_ kennung: UUID, nach tag: Date) {
        guard let einheit = lerneinheiten.first(where: { $0.kennung == kennung }) else { return }
        einheit.tag = kalender.startOfDay(for: tag)
        einheit.manuell = true
    }

    private func abgleichen() {
        gleichtAb = true
        Task {
            do {
                let anzahl = try await SystemkalenderDienst.shared.abgleichen(kontext, mitLerneinheiten: lerneinheitenExportieren)
                meldung = "\(anzahl) Termine in den Kalender „\(SystemkalenderDienst.kalenderName)“ übertragen."
            } catch {
                meldung = error.localizedDescription
            }
            gleichtAb = false
        }
    }
}
