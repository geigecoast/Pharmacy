import Foundation
import Security

/// Speichert Geheimnisse (z. B. den Claude-API-Schlüssel) im Schlüsselbund des Geräts.
enum Schluesselbund {
    static let dienst = "de.pharmatutor.app"
    static let claudeAPIKonto = "claude-api-key"

    enum Fehler: LocalizedError {
        case unerwarteterStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unerwarteterStatus(let status):
                return "Der Schlüsselbund hat den Vorgang abgelehnt (Code \(status))."
            }
        }
    }

    private static func basisAbfrage(konto: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: konto,
        ]
    }

    static func speichern(_ wert: String, konto: String) throws {
        let daten = Data(wert.utf8)
        let abfrage = basisAbfrage(konto: konto)
        let aktualisierung: [String: Any] = [kSecValueData as String: daten]
        var status = SecItemUpdate(abfrage as CFDictionary, aktualisierung as CFDictionary)
        if status == errSecItemNotFound {
            var neu = abfrage
            neu[kSecValueData as String] = daten
            neu[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(neu as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Fehler.unerwarteterStatus(status) }
    }

    static func lesen(konto: String) -> String? {
        var abfrage = basisAbfrage(konto: konto)
        abfrage[kSecReturnData as String] = true
        abfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        guard SecItemCopyMatching(abfrage as CFDictionary, &ergebnis) == errSecSuccess,
              let daten = ergebnis as? Data else { return nil }
        return String(data: daten, encoding: .utf8)
    }

    static func loeschen(konto: String) {
        _ = SecItemDelete(basisAbfrage(konto: konto) as CFDictionary)
    }
}
