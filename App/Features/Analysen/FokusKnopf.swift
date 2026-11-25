import SwiftUI
import SwiftData
import PharmaCore

/// Werkzeugleisten-Knopf für den Fokus-Timer (Pomodoro).
struct FokusKnopf: View {
    var lv: Lehrveranstaltung?
    @Environment(FokusTimer.self) private var timer
    @State private var zeige = false

    var body: some View {
        Button {
            zeige.toggle()
        } label: {
            if timer.phase == .bereit {
                Label("Fokus", systemImage: "timer")
            } else {
                Label(timer.anzeige, systemImage: timer.phase == .pause ? "cup.and.saucer" : "timer")
                    .monospacedDigit()
            }
        }
        .help("Fokus-Timer: erfasst deine Lernzeit für die Analysen")
        .popover(isPresented: $zeige, arrowEdge: .bottom) {
            FokusPanel(lv: lv)
        }
    }
}

private struct FokusPanel: View {
    var lv: Lehrveranstaltung?
    @Environment(FokusTimer.self) private var timer
    @Environment(\.modelContext) private var kontext
    @Query(sort: \Lehrveranstaltung.lfdNr) private var alleLVs: [Lehrveranstaltung]

    private var phasenText: LocalizedStringKey {
        switch timer.phase {
        case .bereit: "Fokus-Timer"
        case .fokus: timer.laeuft ? "Fokus läuft" : "Fokus pausiert"
        case .pause: "Pause"
        }
    }

    var body: some View {
        @Bindable var timer = timer
        VStack(alignment: .leading, spacing: 18) {
            Kleintitel(text: phasenText)
            Text(verbatim: timer.anzeige)
                .font(Thema.display(60))
                .monospacedDigit()
                .foregroundStyle(Thema.tinte)
            if timer.phase == .bereit {
                Picker("Lehrveranstaltung", selection: $timer.lehrveranstaltung) {
                    Text("Ohne Zuordnung").tag(Lehrveranstaltung?.none)
                    ForEach(alleLVs.filter { $0.semester?.istAktuell == true || $0 == lv }) { eintrag in
                        Text(verbatim: "\(LfdNr.anzeige(eintrag.lfdNr)) \(eintrag.anzeigename)").tag(Lehrveranstaltung?.some(eintrag))
                    }
                }
                Stepper(value: $timer.fokusMinuten, in: 10...90, step: 5) {
                    Text("Fokus: \(timer.fokusMinuten) min")
                }
                .onChange(of: timer.fokusMinuten) { _, neu in timer.verbleibend = neu * 60 }
                Stepper(value: $timer.pauseMinuten, in: 3...30) {
                    Text("Pause: \(timer.pauseMinuten) min")
                }
            } else if let zugeordnet = timer.lehrveranstaltung {
                Text(verbatim: "\(LfdNr.anzeige(zugeordnet.lfdNr)) \(zugeordnet.anzeigename)")
                    .font(Thema.ui(13))
                    .foregroundStyle(Thema.tinteSekundaer)
            }
            HStack(spacing: 10) {
                if timer.laeuft {
                    knopf("Pausieren", gefuellt: true) { timer.pausieren() }
                } else {
                    knopf(timer.phase == .bereit ? "Starten" : "Fortsetzen", gefuellt: true) {
                        if timer.phase == .bereit, timer.lehrveranstaltung == nil { timer.lehrveranstaltung = lv }
                        timer.starten(kontext: kontext)
                    }
                }
                if timer.phase != .bereit {
                    knopf("Beenden", gefuellt: false) { timer.stoppen() }
                }
            }
            if timer.abgeschlosseneEinheiten > 0 {
                Text("\(timer.abgeschlosseneEinheiten) Fokus-Einheiten in dieser Sitzung")
                    .font(Thema.ui(11))
                    .foregroundStyle(Thema.tinteTertiaer)
            }
            Text("Die Lernzeit fließt in Analysen, Dashboard und Lernserie ein.")
                .font(Thema.ui(11))
                .foregroundStyle(Thema.tinteTertiaer)
        }
        .font(Thema.ui(13))
        .padding(24)
        .frame(width: 320)
        .onAppear {
            if timer.phase == .bereit, timer.lehrveranstaltung == nil { timer.lehrveranstaltung = lv }
        }
    }

    private func knopf(_ titel: LocalizedStringKey, gefuellt: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(titel)
                .font(Thema.ui(13, .mittel))
                .foregroundStyle(gefuellt ? Thema.tinteInvers : Thema.tinte)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(gefuellt ? Thema.tinte : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Thema.tinte))
        }
        .buttonStyle(.plain)
    }
}
