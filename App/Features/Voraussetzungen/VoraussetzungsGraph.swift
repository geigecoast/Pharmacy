import SwiftUI
import PharmaCore

private struct KnotenSchluessel: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, neu in neu }
    }
}

/// Grafischer Voraussetzungs-Graph: Spalten je Semester, Kanten von Voraussetzung zu Veranstaltung.
struct VoraussetzungsGraph: View {
    let semester: [Semester]
    let stand: StudienStand
    var waehlen: (Lehrveranstaltung) -> Void

    private struct Kante: Hashable {
        let von: String
        let nach: String
        let art: Art
        let erfuellt: Bool

        enum Art { case pflicht, alternative, teilnahme, eineDarfFehlen }
    }

    private var alleLVs: [Lehrveranstaltung] { semester.flatMap(\.sortierteLehrveranstaltungen) }

    /// Lfd.-Nr.-Teil → Schlüssel des Knotens (volle Lfd. Nr.).
    private var knotenNachTeil: [String: String] {
        var ergebnis: [String: String] = [:]
        for lv in alleLVs {
            for teil in lv.lfdNrTeile { ergebnis[teil] = lv.lfdNr }
        }
        return ergebnis
    }

    private var kanten: [Kante] {
        let zuordnung = knotenNachTeil
        var ergebnis: [Kante] = []
        for lv in alleLVs {
            for kante in lv.voraussetzungen.kanten {
                guard let von = zuordnung[kante.lfdNr] else { continue }
                let art: Kante.Art
                let erfuellt: Bool
                switch kante.art {
                case .pflicht:
                    art = .pflicht
                    erfuellt = stand.bestandeneKurse.contains(kante.lfdNr)
                case .alternative:
                    art = .alternative
                    erfuellt = stand.bestandeneKurse.contains(kante.lfdNr)
                case .teilnahme:
                    art = .teilnahme
                    erfuellt = stand.teilgenommeneKurse.contains(kante.lfdNr) || stand.bestandeneKurse.contains(kante.lfdNr)
                case .eineDarfFehlen:
                    art = .eineDarfFehlen
                    erfuellt = stand.bestandeneKurse.contains(kante.lfdNr)
                case .teilpruefung:
                    art = .pflicht
                    erfuellt = stand.bestandeneTeilpruefungen.contains { $0.lfdNr == kante.lfdNr }
                }
                ergebnis.append(Kante(von: von, nach: lv.lfdNr, art: art, erfuellt: erfuellt))
            }
        }
        return Array(Set(ergebnis))
    }

    /// Nur Veranstaltungen, die mit einer Kante verbunden oder anmeldepflichtig sind.
    private func knoten(in semester: Semester) -> [Lehrveranstaltung] {
        let beteiligt = Set(kanten.flatMap { [$0.von, $0.nach] })
        return semester.sortierteLehrveranstaltungen.filter { beteiligt.contains($0.lfdNr) || $0.anmeldepflicht }
    }

    var body: some View {
        let alleKanten = kanten
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 56) {
                    ForEach(semester) { s in
                        VStack(alignment: .leading, spacing: 10) {
                            Kleintitel(text: LocalizedStringKey(s.titel))
                                .padding(.bottom, 4)
                            ForEach(knoten(in: s)) { lv in
                                knotenAnsicht(lv)
                                    .anchorPreference(key: KnotenSchluessel.self, value: .bounds) { [lv.lfdNr: $0] }
                            }
                        }
                        .frame(width: 210, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 24)
                .backgroundPreferenceValue(KnotenSchluessel.self) { anker in
                    GeometryReader { geo in
                        ForEach(alleKanten, id: \.self) { kante in
                            if let a = anker[kante.von], let b = anker[kante.nach] {
                                kantenPfad(von: geo[a], nach: geo[b])
                                    .stroke(kante.erfuellt ? Thema.tinte : Thema.rahmenStark,
                                            style: StrokeStyle(lineWidth: kante.erfuellt ? 1.3 : 1, lineCap: .round,
                                                               dash: strich(kante.art)))
                            }
                        }
                    }
                }
            }
            HStack(spacing: 18) {
                legende("Pflicht", strich: [])
                legende("eine von beiden", strich: [5, 3])
                legende("Teilnahme genügt", strich: [1.5, 3])
                legende("eine darf fehlen", strich: [8, 3, 1.5, 3])
                HStack(spacing: 6) {
                    Rectangle().fill(Thema.tinte).frame(width: 18, height: 1.3)
                    Text("erfüllt").font(Thema.ui(11)).foregroundStyle(Thema.tinteSekundaer)
                }
            }
        }
    }

    private func strich(_ art: Kante.Art) -> [CGFloat] {
        switch art {
        case .pflicht: []
        case .alternative: [5, 3]
        case .teilnahme: [1.5, 3]
        case .eineDarfFehlen: [8, 3, 1.5, 3]
        }
    }

    private func kantenPfad(von a: CGRect, nach b: CGRect) -> Path {
        var pfad = Path()
        let start = CGPoint(x: a.maxX, y: a.midY)
        let ende = CGPoint(x: b.minX, y: b.midY)
        // Kanten innerhalb einer Spalte: seitlich herumführen
        if abs(a.minX - b.minX) < 1 {
            let ausschlag = a.maxX + 28
            pfad.move(to: start)
            pfad.addCurve(to: CGPoint(x: b.maxX, y: b.midY), control1: CGPoint(x: ausschlag, y: start.y),
                          control2: CGPoint(x: ausschlag, y: b.midY))
            return pfad
        }
        let mitte = (start.x + ende.x) / 2
        pfad.move(to: start)
        pfad.addCurve(to: ende, control1: CGPoint(x: mitte, y: start.y), control2: CGPoint(x: mitte, y: ende.y))
        return pfad
    }

    private func knotenAnsicht(_ lv: Lehrveranstaltung) -> some View {
        let freigabe = Freigabe.ermitteln(status: lv.status, regel: lv.voraussetzungen, stand: stand)
        let blockiert: Bool = { if case .blockiert = freigabe { return true }; return false }()
        return Button {
            waehlen(lv)
        } label: {
            HStack(spacing: 8) {
                Punkt(farbe: lv.farbe)
                LfdNrText(text: LfdNr.anzeige(lv.lfdNr), groesse: 10)
                Text(verbatim: lv.anzeigename)
                    .font(Thema.ui(12))
                    .foregroundStyle(blockiert ? Thema.tinteTertiaer : Thema.tinte)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if freigabe == .bestanden {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Thema.tinteSekundaer)
                } else if blockiert {
                    Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(Thema.tinteTertiaer)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(freigabe == .bestanden ? Thema.flaecheGedaempft : Thema.flaeche, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(blockiert ? Thema.rahmenStark : Thema.tinte,
                                  style: StrokeStyle(lineWidth: 1, dash: blockiert ? [3, 2] : []))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(blockiert ? "Blockiert: \(lv.voraussetzungen.beschreibung)" : lv.bezeichnung)
    }

    private func legende(_ titel: LocalizedStringKey, strich: [CGFloat]) -> some View {
        HStack(spacing: 6) {
            Path { pfad in
                pfad.move(to: CGPoint(x: 0, y: 1))
                pfad.addLine(to: CGPoint(x: 22, y: 1))
            }
            .stroke(Thema.rahmenStark, style: StrokeStyle(lineWidth: 1.2, dash: strich))
            .frame(width: 22, height: 2)
            Text(titel).font(Thema.ui(11)).foregroundStyle(Thema.tinteSekundaer)
        }
    }
}
