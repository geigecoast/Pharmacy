import SwiftUI
import SwiftData
import PharmaCore

/// Fehlerjournal: falsche Antworten zum Wiederholen.
struct FehlerjournalAnsicht: View {
    var lv: Lehrveranstaltung?

    @Query(sort: \Fehlereintrag.datum, order: .reverse) private var alle: [Fehlereintrag]
    @Environment(\.dismiss) private var dismiss
    @State private var zeigeVerstandene = false
    @State private var wiederholen = false

    private var eintraege: [Fehlereintrag] {
        alle.filter { eintrag in
            (lv == nil || eintrag.lehrveranstaltung == lv) && (zeigeVerstandene || !eintrag.verstanden)
        }
    }

    private var offeneKarten: [Karteikarte] {
        var gesehen = Set<UUID>()
        return alle.filter { !$0.verstanden && (lv == nil || $0.lehrveranstaltung == lv) }
            .compactMap(\.karte)
            .filter { gesehen.insert($0.kennung).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fehlerjournal")
                            .font(Thema.display(44))
                            .foregroundStyle(Thema.tinte)
                        Text("Jede falsche Antwort landet hier automatisch. Wiederhole sie, bis du sie als verstanden markierst.")
                            .font(Thema.ui(14))
                            .foregroundStyle(Thema.tinteSekundaer)
                    }
                    HStack {
                        Toggle("Verstandene anzeigen", isOn: $zeigeVerstandene)
                            .font(Thema.ui(13))
                            .fixedSize()
                        Spacer()
                        if !offeneKarten.isEmpty {
                            Button("Fehler wiederholen (\(offeneKarten.count))") { wiederholen = true }
                                .buttonStyle(.plain)
                                .font(Thema.ui(13, .mittel))
                                .underline()
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Haarlinie(farbe: Thema.tinte)
                        if eintraege.isEmpty {
                            Text("Keine offenen Fehler. Sehr gut.")
                                .font(Thema.serif(22))
                                .foregroundStyle(Thema.tinte)
                                .padding(.vertical, 28)
                        }
                        ForEach(eintraege) { eintrag in
                            FehlerZeile(eintrag: eintrag)
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(40)
            }
            .background(Thema.flaeche)
            .navigationTitle("Fehlerjournal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $wiederholen) {
                QuizSitzung(modus: .themenquiz, pool: offeneKarten, lv: lv)
            }
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 600)
        #endif
    }
}

private struct FehlerZeile: View {
    @Bindable var eintrag: Fehlereintrag

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: eintrag.frage)
                .font(Thema.ui(15))
                .foregroundStyle(eintrag.verstanden ? Thema.tinteTertiaer : Thema.tinte)
            Text(verbatim: "Deine Antwort: \(eintrag.deineAntwort)")
                .font(Thema.ui(12))
                .foregroundStyle(Stoffgebiet.i.farbe)
            Text(verbatim: "Richtig: \(eintrag.richtigeAntwort)")
                .font(Thema.ui(12))
                .foregroundStyle(Thema.tinteSekundaer)
            HStack(spacing: 14) {
                Text(verbatim: [eintrag.datum.kurzesDatum, eintrag.herkunft, eintrag.thema,
                                eintrag.lehrveranstaltung.map { LfdNr.anzeige($0.lfdNr) } ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Thema.ui(11))
                    .foregroundStyle(Thema.tinteTertiaer)
                Spacer()
                Button("Erklär mir meinen Fehler") {}
                    .disabled(true)
                    .help("Der KI-Tutor erklärt Fehler ab Ausbaustufe e")
                Button(eintrag.verstanden ? "Wieder öffnen" : "Verstanden") { eintrag.verstanden.toggle() }
            }
            .buttonStyle(.plain)
            .font(Thema.ui(12))
            .underline()
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Haarlinie() }
    }
}
