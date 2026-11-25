import SwiftUI
import SwiftData
import PharmaCore

/// Verfügbare Lernzeit pro Wochentag und Planungsoptionen.
struct LernzeitenFelder: View {
    @AppStorage(EinstellungsSchluessel.lernzeiten) private var wochenplan: Wochenplan = .standard
    @AppStorage(EinstellungsSchluessel.vorlaufTage) private var vorlaufTage = Standardwerte.vorlaufTage
    @AppStorage(EinstellungsSchluessel.praktikumMinuten) private var praktikumMinuten = Standardwerte.praktikumMinuten

    var body: some View {
        Section {
            ForEach(0..<7, id: \.self) { index in
                Stepper(value: Binding(
                    get: { wochenplan.minuten[index] },
                    set: { neu in
                        var plan = wochenplan
                        plan.minuten[index] = neu
                        wochenplan = plan
                    }
                ), in: 0...600, step: 15) {
                    LabeledContent(Wochenplan.wochentage[index], value: Dauer.text(minuten: wochenplan.minuten[index]))
                }
            }
            LabeledContent("Pro Woche", value: Dauer.text(minuten: wochenplan.summeProWoche))
                .fontWeight(.semibold)
        } header: {
            Text("Verfügbare Lernzeit")
        }

        Section {
            Stepper(value: $vorlaufTage, in: 7...120, step: 7) {
                Text("Lernbeginn: \(vorlaufTage) Tage vor der Prüfung")
            }
            Stepper(value: $praktikumMinuten, in: 0...240, step: 15) {
                Text("Lernzeit während eines Blockpraktikums: \(Dauer.text(minuten: praktikumMinuten))")
            }
        } header: {
            Text("Planung")
        } footer: {
            Text("Bei großem Lernaufwand beginnt der Plan automatisch früher. Eingangsprüfungen, die ein Blockpraktikum freischalten, werden bevorzugt eingeplant.")
        }
    }
}

struct LernzeitenAnsicht: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var kontext

    var body: some View {
        NavigationStack {
            Form {
                LernzeitenFelder()
            }
            .formStyle(.grouped)
            .navigationTitle("Lernzeiten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        LernplanDienst.aktualisieren(kontext)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }
}
