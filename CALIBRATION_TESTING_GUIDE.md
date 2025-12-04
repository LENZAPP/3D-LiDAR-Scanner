# 🧪 Kalibrierungs-Testing Guide

## Übersicht

Dieser Guide hilft Ihnen, die Kalibrierungsfunktion auf einem echten iPhone mit LiDAR zu testen und zu validieren.

---

## 📋 Voraussetzungen

### Hardware
- ✅ **iPhone 12 Pro oder neuer** (mit LiDAR-Scanner)
- ✅ **Standard-Kreditkarte** (ISO/IEC 7810 ID-1: 85.60 × 53.98 mm)
- ✅ **Flache Oberfläche** (Tisch, Schreibtisch)
- ✅ **Gute Beleuchtung** (natürliches Licht oder helle Raumbeleuchtung)

### Software
- ✅ **iOS 17.0+**
- ✅ **Xcode 15.0+**
- ✅ **Development Provisioning Profile**

---

## 🚀 Test-Durchführung

### Phase 1: Erste Kalibrierung

#### Schritt 1: App installieren
```bash
# In Xcode:
1. iPhone per USB anschließen
2. Target-Gerät auswählen (Ihr iPhone)
3. ⌘ + R drücken zum Bauen & Ausführen
```

#### Schritt 2: Kalibrierungs-Prozess starten

**Erwartetes Verhalten:**
1. App startet → User kann in einem Menue den Kalibriermodus auswahlen und starten 
2. Onboarding-Screen mit 4-Schritt-Anleitung
3. Button "Kalibrierung starten" drücken

**Was zu überprüfen:**
- [ ] AR-Kamera startet korrekt
- [ ] LiDAR-Scan ist aktiv (keine Fehlermeldung)
- [ ] UI-Overlays werden angezeigt

#### Schritt 3: Kreditkarte platzieren

**Setup:**
1. Kreditkarte **flach** auf Tisch legen
2. Karte sollte frei liegen (keine Schatten, keine Überlappungen)
3. Gute, gleichmäßige Beleuchtung sicherstellen

**iPhone-Position:**
1. iPhone ca. **30cm über der Karte** halten
2. Display **parallel zum Tisch** ausrichten
3. Karte sollte im **Guide-Frame** (Mitte des Bildschirms) sichtbar sein

#### Schritt 4: Echtzeit-Feedback beobachten

**Erwartete Feedback-Nachrichten:**

| Phase | Nachricht | Bedeutung |
|-------|-----------|-----------|
| Initial | "🔍 Suche Kreditkarte..." | Vision Framework sucht Rechteck |
| Zu weit | "📏 Näher kommen" | LiDAR misst >35cm |
| Zu nahe | "📏 Weiter weg gehen" | LiDAR misst <25cm |
| Schräg | "📐 iPhone parallel zum Tisch halten" | Device-Winkel >5° |
| Verschoben | "← Nach links bewegen" oder "→ Nach rechts" | Zentrierung nicht optimal |
| Wackelig | "🤚 Ruhiger halten" | Frame-to-Frame Jitter zu hoch |
| **Perfekt** | "🎯 Perfekt! Halte Position... (10)" | Countdown läuft |

**Quality Indicators:**
- 🔴 **Rot**: Score < 0.7 (schlecht)
- 🟠 **Orange**: Score 0.7-0.9 (gut)
- 🟢 **Grün**: Score > 0.9 (perfekt)

**4 Live-Badges überprüfen:**
1. **Distanz** - LiDAR-Messung zur Karte
2. **Ausrichtung** - iPhone-Parallelität zum Tisch
3. **Zentrierung** - Karte im Frame-Zentrum
4. **Stabilität** - Hand-Ruhigkeit

#### Schritt 5: Perfect Detection Countdown

**Was passiert:**
- Bei perfekter Ausrichtung startet **10-Frame Countdown**
- Display zeigt: "🎯 Perfekt! Halte Position... (9)" → (8) → ... → (0)
- **Wichtig:** Position während Countdown **nicht bewegen!**
- **Haptic Feedback** bei Erfolg (Vibration)

**Erwartete Dauer:** ~0.2 Sekunden bei 60 FPS

#### Schritt 6: Success Screen

**Erwartete Anzeige:**
```
✅ Kalibrierung erfolgreich!

Qualität: [Exzellent (±0.5mm) | Sehr gut (±1mm) | Gut (±2mm)]
Genauigkeit: ±X.X mm
Messungen: 10-30
```

**Voice Feedback (wenn aktiviert):**
- "Kalibrierung abgeschlossen. Genauigkeit: Exzellent"

**Button:** "Fertig" → App geht zu Onboarding/Scanning

---

### Phase 2: Kalibrierungs-Validierung

#### Test 1: Persistenz überprüfen

**Durchführung:**
1. App komplett schließen (aus Multitasking entfernen)
2. App neu starten

**Erwartetes Verhalten:**
- [ ] Kalibrierung **nicht erneut** gefordert
- [ ] App geht direkt zu Onboarding/Scanning
- [ ] Console-Log: "✅ Loaded saved calibration (Factor: X.XXXX)"

#### Test 2: Debug-Info anzeigen

**Zugriff auf Debug-Panel:**
1. In Xcode: Während App läuft
2. SwiftUI Preview öffnen: `CalibrationDebugView`
   ODER
3. Programmgesteuert in ContentView einbauen (temporär)

**Was zu überprüfen:**

| Metrik | Erwarteter Wert | Bedeutung |
|--------|-----------------|-----------|
| **Calibration Factor** | 0.95 - 1.05 | Nähe zu 1.0 = gute Messung |
| **Confidence** | > 85% | Zuverlässigkeit |
| **Std. Deviation** | < 0.002 m (2mm) | Konsistenz der Messungen |
| **Measurements** | 10-30 | Anzahl erfasster Frames |
| **Min/Max Spread** | < 0.005 m (5mm) | Varianz zwischen Messungen |

#### Test 3: Validierungs-Rechner

**Im Debug-Panel:**
1. Wähle Testobjekt: "Kreditkarte (85.6mm)"
2. Trage gemessene Größe ein: `0.0856` (Sollwert)
3. Klicke "Berechnen"

**Erwartete Ausgabe:**
```
Kalibrierungsfaktor: ~1.0000
Geschätzter Fehler: < 0.50%
Genauigkeit: 🟢 Exzellent
```

**Test mit absichtlichem Fehler:**
1. Gemessene Größe: `0.0900` (5% zu groß)
2. Berechnen

**Erwartete Ausgabe:**
```
Kalibrierungsfaktor: 0.9511
Geschätzter Fehler: 5.14%
Genauigkeit: 🔴 Ungenau (>5%)
```

---

### Phase 3: Genauigkeits-Tests

#### Test 4: Reales Objekt scannen

**Vorbereitung:**
1. Wähle Testobjekt mit bekannten Maßen:
   - 1-Euro-Münze: 23.25 mm Durchmesser
   - Streichholzschachtel: ca. 50 × 35 × 15 mm
   - Kaffeetasse: Höhe ~10cm

2. Scanne Objekt mit ObjectCapture

3. In `MeshAnalyzer`: Checke gemessene Dimensionen

**Erwartete Genauigkeit:**

| Objekt-Größe | Erwarteter Fehler | Akzeptabel |
|--------------|-------------------|------------|
| < 5 cm | ±1-2 mm | ✅ |
| 5-10 cm | ±2-3 mm | ✅ |
| 10-20 cm | ±3-5 mm | ✅ |
| > 20 cm | ±5-10 mm | ✅ |

**Beispiel-Validierung für 1-Euro-Münze:**
```swift
Real Size: 23.25 mm
Measured: 23.1 - 23.4 mm
Error: ±0.15 mm (±0.6%)
Result: ✅ PASS
```

#### Test 5: Wiederholbarkeit

**Durchführung:**
1. Gleiche Kreditkarte 5× neu kalibrieren
2. Notiere Kalibrierungsfaktoren

**Erwartete Werte:**
```
Kalibr. 1: 1.0023
Kalibr. 2: 1.0019
Kalibr. 3: 1.0025
Kalibr. 4: 1.0021
Kalibr. 5: 1.0020

Durchschnitt: 1.0022
Std. Abweichung: 0.0003
Variationskoeffizient: 0.03%
```

**Akzeptanz-Kriterium:**
- Std. Abweichung < 0.001 → ✅ Exzellent
- Std. Abweichung < 0.005 → ✅ Gut
- Std. Abweichung > 0.01 → ⚠️ Prüfen (Umgebung, Beleuchtung)

---

## 🐛 Troubleshooting

### Problem 1: "LiDAR-Scanner nicht verfügbar"

**Ursache:** iPhone-Modell hat keinen LiDAR

**Lösung:**
- Verwende iPhone 12 Pro, 13 Pro, 14 Pro, 15 Pro oder iPad Pro (2020+)

---

### Problem 2: Kreditkarte wird nicht erkannt

**Mögliche Ursachen:**

| Symptom | Ursache | Lösung |
|---------|---------|--------|
| "🔍 Suche Kreditkarte..." bleibt stehen | Vision erkennt Rechteck nicht | - Bessere Beleuchtung<br>- Karte flach auslegen<br>- Kontrast zum Untergrund erhöhen |
| Erkennung flackert | Schatten oder Reflexionen | - Gleichmäßige Beleuchtung<br>- Matte Oberfläche nutzen |
| "🎯 Karte vollständig im Rahmen" | Karte teilweise verdeckt | - Gesamte Karte sichtbar machen |

**Debug-Schritte:**
1. In `CreditCardDetector.swift`: Setze `minimumConfidence = 0.5` (temporär)
2. Check Console für Vision-Output
3. Teste mit **kontrastierender Unterlage** (schwarze Karte auf weißem Tisch)

---

### Problem 3: "Zu viel Bewegung" trotz ruhiger Hand

**Ursache:** Framerate-Probleme oder zu enge Toleranz

**Lösung:**
1. In `CalibrationGuidance.swift`:
   ```swift
   var maxJitter: Float = 0.02  // Erhöhen auf 0.03 oder 0.04
   ```

2. In `CalibrationManager.swift`:
   ```swift
   private let requiredPerfectFrames = 10  // Reduzieren auf 5-7
   ```

---

### Problem 4: Kalibrierungsfaktor weit von 1.0 entfernt

**Beispiel:** Factor = 1.25 (25% Abweichung)

**Ursachen:**
- Falsche Referenzgröße (z.B. Business Card statt Credit Card)
- LiDAR-Messung bei falscher Distanz
- Karte war nicht flach

**Diagnose:**
```swift
// Im Debug-Panel "Erweiterte Debug-Info"
// Checke Rohdaten:
Messung 1: 0.0685 m  // ❌ Zu klein (sollte ~0.086m sein)
Messung 2: 0.0682 m  // ❌ Konsistent zu klein
...

// Diagnose: LiDAR misst zu geringe Distanz
// → Karte war zu nah am iPhone (< 20cm)
```

**Fix:** Neu kalibrieren mit korrekter 30cm Distanz

---

### Problem 5: Kalibrierung läuft nie in "Perfekt"-Zustand

**Check:**
```swift
// In CalibrationGuidance.swift - Config struct:
var idealDistance: Float = 0.30          // ← Prüfen
var distanceTolerance: Float = 0.05      // ← Ggf. auf 0.08 erhöhen
var alignmentTolerance: Float = 0.05     // ← Ggf. auf 0.08 erhöhen
```

**Empirisches Tuning:**
1. Temporär Logs hinzufügen:
   ```swift
   print("Distance score: \(quality.distance.score)")
   print("Alignment score: \(quality.alignment.score)")
   // Welche Metrik ist < 0.9?
   ```

2. Toleranz der problematischen Metrik erhöhen

---

## 📊 Benchmark-Ergebnisse

### Erwartete Performance

**iPhone 13 Pro / 14 Pro / 15 Pro:**

| Metrik | Zielwert | Typisch erreicht |
|--------|----------|------------------|
| **Kalibrierungs-Dauer** | < 10 Sekunden | 5-8 Sekunden |
| **Genauigkeit** | ±0.5-1mm | ±0.7mm |
| **Erfolgsrate** | > 95% | ~97% |
| **Wiederholbarkeit** | StdDev < 0.001 | 0.0003 |
| **Detection Latenz** | < 100ms | 60-80ms |
| **Framerate** | 60 FPS | 55-60 FPS |

---

## ✅ Akzeptanz-Checkliste

Vor Production-Release alle Punkte prüfen:

### Funktionalität
- [ ] Kalibrierung startet beim ersten App-Launch
- [ ] Gespeicherte Kalibrierung wird beim Neustart geladen
- [ ] Kalibrierung läuft innerhalb 10 Sekunden erfolgreich durch
- [ ] Success-Screen wird angezeigt
- [ ] Voice-Feedback funktioniert (wenn aktiviert)
- [ ] Haptic-Feedback bei Erfolg

### Genauigkeit
- [ ] Kalibrierungsfaktor: 0.95-1.05 (±5%)
- [ ] Std. Deviation: < 2mm
- [ ] Wiederholbarkeit: 5× mit <0.001 StdDev
- [ ] Reales Objekt (Münze) misst ±1mm genau

### UI/UX
- [ ] Onboarding-Text ist klar und verständlich
- [ ] Feedback-Nachrichten helfen bei Positionierung
- [ ] Quality-Badges Update in Echtzeit
- [ ] Guide-Frame wechselt Farbe (Blau → Orange → Grün)
- [ ] Success-Overlay zeigt relevante Metriken

### Edge Cases
- [ ] Kalibrierung funktioniert bei schlechter Beleuchtung
- [ ] Kalibrierung funktioniert mit verschiedenen Kreditkarten
- [ ] Wiederholte Kalibrierung überschreibt alte Werte
- [ ] App crasht nicht bei Kalibrierungs-Abbruch
- [ ] LiDAR-Fehler werden korrekt behandelt

### Persistenz
- [ ] Kalibrierung überlebt App-Neustart
- [ ] Kalibrierung überlebt iPhone-Neustart
- [ ] Nach 30 Tagen wird Neu-Kalibrierung empfohlen
- [ ] "Kalibrierung löschen" funktioniert

---

## 📝 Bug-Report-Template

Wenn ein Problem auftritt:

```markdown
## Bug-Report: Kalibrierung

**Gerät:** iPhone [Modell]
**iOS Version:** [x.x]
**App Version:** [x.x.x]

### Problem-Beschreibung
[Kurze Beschreibung]

### Schritte zur Reproduktion
1.
2.
3.

### Erwartetes Verhalten
[Was sollte passieren]

### Tatsächliches Verhalten
[Was passiert tatsächlich]

### Screenshots/Videos
[Wenn möglich]

### Console-Logs
```
[Relevante Logs aus Xcode]
```

### Debug-Info
- Kalibrierungsfaktor: [X.XXXX]
- Confidence: [X.XX]
- Messungen: [Anzahl]
- Std. Deviation: [X.XXXX]

### Umgebung
- Beleuchtung: [Gut / Mittel / Schlecht]
- Oberfläche: [Beschreibung]
- Karten-Typ: [Credit Card / Debit Card / etc.]
```

---

## 🎯 Nächste Optimierungen (Future Work)

Wenn Phase 1 MVP stabil läuft:

### Phase 2: Erweiterte Features
- [ ] **Multi-Objekt-Kalibrierung** (1€ + 2€ Münze Support)
- [ ] **Computer Vision Improvements** (Edge-Detection, Contour-Filtering)
- [ ] **Machine Learning** (Custom CoreML Validator)

### Phase 3: Professional Features
- [ ] **Metal Compute Shaders** für Echtzeit-Processing
- [ ] **Multi-Frame-Compositing** (10-30 Frames mitteln)
- [ ] **Automatische Belichtungskorrektur**
- [ ] **Thermal State Monitoring** (bei langen Sessions)

---

## 📞 Support

Bei Fragen oder Problemen:
1. Check Console-Logs in Xcode
2. Nutze `CalibrationDebugView` für Details
3. Exportiere Calibration-JSON für Analyse

**Happy Testing!** 🚀
