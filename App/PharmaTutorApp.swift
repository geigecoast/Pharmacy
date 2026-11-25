import SwiftUI
import SwiftData

@main
struct PharmaTutorApp: App {
    @State private var speicher: Datenspeicher

    init() {
        Thema.schriftenRegistrieren()
        _speicher = State(initialValue: Datenspeicher())
    }

    var body: some Scene {
        WindowGroup {
            if let container = speicher.container {
                HauptAnsicht()
                    .id(speicher.generation)
                    .modelContainer(container)
                    .environment(speicher)
                    .environment(\.locale, .deutsch)
                    .erscheinungsbild()
            } else {
                DatenbankFehlerAnsicht(details: speicher.fehlertext)
            }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif
        .commands {
            SidebarCommands()
            InspectorCommands()
            AppBefehle()
        }

        WindowGroup("Lehrveranstaltung", id: LVFenster.fensterID, for: PersistentIdentifier.self) { $id in
            if let container = speicher.container {
                LVFenster(id: id)
                    .id(speicher.generation)
                    .modelContainer(container)
                    .environment(speicher)
                    .environment(\.locale, .deutsch)
                    .erscheinungsbild()
            }
        }

        WindowGroup("Unterlage", id: DokumentFenster.fensterID, for: PersistentIdentifier.self) { $id in
            if let container = speicher.container {
                DokumentFenster(id: id)
                    .id(speicher.generation)
                    .modelContainer(container)
                    .environment(speicher)
                    .environment(\.locale, .deutsch)
                    .erscheinungsbild()
            }
        }

        #if os(macOS)
        Settings {
            if let container = speicher.container {
                NavigationStack {
                    EinstellungenAnsicht()
                }
                .id(speicher.generation)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 560)
                .modelContainer(container)
                .environment(speicher)
                .environment(\.locale, .deutsch)
            }
        }
        #endif
    }
}

/// Erscheinungsbild aus den Einstellungen (System, Hell, Dunkel).
private struct Erscheinungsbild: ViewModifier {
    @AppStorage(EinstellungsSchluessel.erscheinungsbild) private var wahl = "system"

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(wahl == "hell" ? .light : (wahl == "dunkel" ? .dark : nil))
            .tint(Thema.tinte)
    }
}

extension View {
    func erscheinungsbild() -> some View { modifier(Erscheinungsbild()) }
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
