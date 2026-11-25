import SwiftUI

/// Menüleisten-Befehle und Tastenkürzel (Mac und iPad mit Tastatur).
struct AppBefehle: Commands {
    @FocusedValue(\.navigationsAuswahl) private var auswahl

    var body: some Commands {
        CommandMenu("Gehe zu") {
            Button("Heute lernen") { auswahl?.wrappedValue = .heute }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(auswahl == nil)
            Button("Kalender") { auswahl?.wrappedValue = .kalender }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(auswahl == nil)
            Button("Dashboard & Analysen") { auswahl?.wrappedValue = .dashboard }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(auswahl == nil)
            Button("Voraussetzungen") { auswahl?.wrappedValue = .voraussetzungen }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(auswahl == nil)
            Divider()
            Button("Einstellungen") { auswahl?.wrappedValue = .einstellungen }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(auswahl == nil)
        }
    }
}
