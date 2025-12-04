# Kalibrierungs-Test Anleitung - 3D App

## 1. VORBEREITUNG

- [ ] iPhone mit LiDAR (iPhone 12 Pro oder neuer) bereit
- [ ] Kreditkarte oder EC-Karte (85.6 × 53.98 mm) verfügbar
- [ ] Flache, ebene Oberfläche (Tisch/Schreibtisch)
- [ ] Gutes Licht (keine direkten Schatten auf Karte)
- [ ] App geöffnet und Kalibrierungs-Screen aktiv
- [ ] Xcode Console offen für Debug-Logs
- [ ] Objektmessgerät oder Lineal für Genauigkeits-Tests

---

## 2. TEST 1: AR-INITIALISIERUNG

- [ ] App startet ohne Crashes
- [ ] AR-Kamera lädt (Live-Feed sichtbar)
- [ ] Status in Console: "ARSession started"
- [ ] LiDAR-Daten verfügbar: "LiDAR depth available" in Console
- [ ] Keine Fehler-Meldungen in Console

---

## 3. TEST 2: KREDITKARTEN-ERKENNUNG

- [ ] Karte in Kamera halten
- [ ] Vision Framework erkennt Rechteck (gelbter Rahmen sichtbar)
- [ ] Console zeigt: "Rectangle detected"
- [ ] Aspect Ratio akzeptiert (1.3 - 1.9 Range)
- [ ] Erkennung funktioniert auch bei leicht gedrehter Karte (Rotation ±30°)
- [ ] Karte erkannt bei verschiedenen Lichtverhältnissen

---

## 4. TEST 3: LIVE-DISTANZ-FEEDBACK

- [ ] Aktuelle Entfernung in cm angezeigt (z.B. "32cm")
- [ ] Feedback-Text ändert sich basierend auf Distanz:
  - [ ] "Näher ran" wenn > 35cm entfernt
  - [ ] "Weiter weg" wenn < 25cm entfernt
  - [ ] "Perfekt" wenn 25-35cm (grüner Status)
- [ ] Distanz-Wert aktualisiert sich Echtzeit (alle 100-200ms)
- [ ] Distanz-Balken (Progress-Ring) zeigt visuelle Rückmeldung
- [ ] Guidance-Text ist hilfreich und präzise

---

## 5. TEST 4: KALIBRIERUNGS-ABSCHLUSS

- [ ] App erkennt nach ~5 perfekten Frames (0,17s bei 30 FPS)
- [ ] ODER: Auto-Complete nach 8 guten Frames (statt 5 perfekten)
- [ ] Erfolgreiches Kalibrierungs-Ende:
  - [ ] Haptic Feedback (Vibration) spürbar
  - [ ] Kalibrierungs-Faktor angezeigt (z.B. "Factor: 0.95")
  - [ ] Faktor zwischen 0.8 - 1.2 (realistisch)
  - [ ] Keine Crashes beim Abschluss
- [ ] Success-Screen erscheint mit Ergebnis
- [ ] Console zeigt: "Calibration complete" mit Faktor

---

## 6. TEST 5: KALIBRIERUNGS-GENAUIGKEIT

**Test-Setup:**
- [ ] Bekanntes Objekt vorbereiten (z.B. 10cm lange Schachtel)
- [ ] Kalibrierungs-Faktor speichern (z.B. 0.95)
- [ ] Scan-Modus starten
- [ ] Objekt mit bekannter Länge scannen

**Messungen:**
- [ ] Gemessene Länge aufzeichnen (App zeigt Wert in cm)
- [ ] Mit Lineal vergleichen
- [ ] Fehler berechnen: |gemessen - real| / real × 100
  - [ ] Fehler < 10% = PASS
  - [ ] Fehler 10-15% = WARNING
  - [ ] Fehler > 15% = FAIL

**Beispiel:**
- Real: 10.0cm
- Gemessen: 9.8cm
- Fehler: 2% ✓ (PASS)

---

## 7. EDGE CASES TESTEN

- [ ] Reflexive Oberfläche (glänzende Karte)
  - [ ] Erkennung funktioniert
  - [ ] Falsche Distanzen? Nein
- [ ] Dunkle Umgebung
  - [ ] Erkennung schwach aber möglich
- [ ] Bewegung während Kalibrierung
  - [ ] App fordert Stabilität auf
  - [ ] Frame-Counter setzt zurück bei Bewegung
- [ ] Mehrere schnelle Kalibrierungen hintereinander
  - [ ] Keine Speicher-Lecks
  - [ ] Ergebnis konsistent

---

## 8. CONSOLE-LOGS PRÜFEN

Erwartete Meldungen:
```
ARSession started
LiDAR depth available
Rectangle detected: confidence 0.87
Distance: 32.4cm → Feedback: "Näher ran"
Distance: 28.5cm → Feedback: "Perfekt"
Perfect frame #1, #2, #3, #4, #5
Calibration complete: factor 0.95
```

Nicht erwünscht:
```
ERROR: AR Session failed
ERROR: Vision Framework crash
ERROR: LiDAR not available
ERROR: Depth measurement failed
```

---

## 9. BESTANDEN/NICHT BESTANDEN

**BESTANDEN wenn:**
- Alle Tests 1-5 grün ✓
- Kalibrierungs-Faktor 0.8-1.2
- Genauigkeit Test < 10% Fehler
- Keine Crashes
- Live-Feedback funktioniert

**NICHT BESTANDEN wenn:**
- AR-Session startet nicht
- Karte nie erkannt
- Faktor außerhalb 0.8-1.2
- Crashes bei Kalibrierungs-Ende
- Genauigkeit > 15% Fehler

---

## 10. TESTPROTOKOLLS-BEISPIEL

| Test | Status | Zeit | Faktor | Fehler | Notizen |
|------|--------|------|--------|--------|---------|
| Lauf 1 | PASS | 4.2s | 0.95 | 3% | Optimal |
| Lauf 2 | PASS | 5.1s | 0.92 | 4% | Gut |
| Lauf 3 | PASS | 3.8s | 0.98 | 2% | Schnell |
| Lauf 4 | WARN | 6.5s | 1.05 | 8% | Akzeptabel |

**Durchschnitt:** Factor 0.975, Fehler 4.25% ✓ PASS
