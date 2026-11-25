import SwiftUI
import SwiftData

@main
struct PharmaTutorApp: App {
    private let container: ModelContainer?
    private let fehlertext: String?

    init() {
        do {
            let schema = Schema(Datenschema.modelle)
            let konfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [konfiguration])
            fehlertext = nil
        } catch {
            container = nil
            fehlertext = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                HauptAnsicht()
                    .modelContainer(container)
                    .environment(\.locale, .deutsch)
            } else {
                DatenbankFehlerAnsicht(details: fehlertext)
            }
        }
        .commands {
            SidebarCommands()
            InspectorCommands()
            AppBefehle()
        }

        WindowGroup("Lehrveranstaltung", id: LVFenster.fensterID, for: PersistentIdentifier.self) { $id in
            if let container {
                LVFenster(id: id)
                    .modelContainer(container)
                    .environment(\.locale, .deutsch)
            }
        }

        #if os(macOS)
        Settings {
            if let container {
                NavigationStack {
                    EinstellungenAnsicht()
                }
                .frame(minWidth: 520, idealWidth: 560, minHeight: 560)
                .modelContainer(container)
                .environment(\.locale, .deutsch)
            }
        }
        #endif
    }
}

extension Locale {
    /// Die App ist ausschließlich deutschsprachig.
    static let deutsch = Locale(identifier: "de_DE")
}

struct DatenbankFehlerAnsicht: View {
    let details: String?

    var body: some View {
        ContentUnavailableView {
            Label("Datenbank konnte nicht geöffnet werden", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Bitte starte PharmaTutor neu. Wenn das Problem bleibt, hilft ein Neustart des Geräts.")
            if let details {
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
