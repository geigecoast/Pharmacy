# PharmaTutor

Native Lern-App für das Pharmaziestudium (Staatsexamen, Goethe-Universität Frankfurt, FB 14) – für macOS 15+ und iPadOS 18+ aus einer gemeinsamen SwiftUI-Codebasis. Die App ist vollständig deutschsprachig.

## Projekt öffnen

Das Xcode-Projekt wird mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) aus `project.yml` erzeugt:

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open PharmaTutor.xcodeproj
```

Danach in Xcode unter *Signing & Capabilities* dein (kostenloses) Personal Team auswählen und als Ziel **My Mac** oder einen **iPad-Simulator** bzw. dein iPad wählen.

> Hinweis: Mit einem kostenlosen Apple-Account laufen selbst installierte Apps auf dem iPad 7 Tage; danach erneut aus Xcode installieren. CloudKit/iCloud-Sync ist ohne bezahlten Developer Account nicht möglich – die Synchronisierung zwischen Mac und iPad wird in Ausbaustufe (i) anders gelöst.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `App/` | Multiplatform-App (SwiftUI, SwiftData) |
| `App/Modell/` | SwiftData-Modelle, Seed des Curriculums, Studienstand |
| `App/Features/` | Bildschirme (Heute, Semester, Lehrveranstaltung, Voraussetzungen, Staatsexamen, Einstellungen, Einführung) |
| `Packages/PharmaCore/` | Reine Fachlogik ohne UI: Stammdaten, Curriculum, Voraussetzungsregeln, Fristen – mit Tests |
| `.github/workflows/build.yml` | CI: Tests, Build für macOS und iPad-Simulator (Warnungen = Fehler), Starttest der Mac-App mit Bildschirmfotos |

## Tests

```bash
swift test --package-path Packages/PharmaCore
```

## Ausbaustufen

- [x] (a) App-Gerüst, Semester-Navigation, Datenmodell, Curriculum
- [x] (b) Kalender + Lernplan
- [x] (c) Vorlesungen + Annotation
- [x] (d) Karteikarten + FSRS + Quiz
- [x] (e) Tutor
- [x] (f) Altklausuren-Analyse + Probeklausuren
- [x] (g) Analysen + Dashboard
- [x] (h) Gamification: Lernserie mit Tagesziel und Ruhetag, Punkte und Stufen, Abzeichen, Wochenziel, Lernkalender
- [ ] (i) Sync + Feinschliff
