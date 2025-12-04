# Quick Testing Guide - 3D Calibration System

## Pre-Flight Checklist

Before testing, verify:
- [ ] iPhone 15 Pro with LiDAR Scanner
- [ ] iOS 18.6 or later
- [ ] Xcode build succeeds without errors/warnings
- [ ] Standard credit card (85.6mm × 53.98mm)
- [ ] Flat, matte table surface
- [ ] Good room lighting

---

## Test 1: Successful Calibration (Happy Path)

**Setup:**
1. Place credit card flat on table (matte surface, not glossy)
2. Ensure good lighting (room lights on)
3. Clear area around card (no other objects nearby)

**Steps:**
1. Launch app
2. Navigate to calibration screen
3. Hold iPhone **30cm** above card (use ruler if unsure)
4. Keep iPhone **parallel** to table
5. Center card in guide frame
6. Hold **steady** for 10-15 seconds

**Expected Results:**
- ✅ Green guide frame appears when position is good
- ✅ Messages: "✅ Sample X/15 gespeichert! Noch Y..."
- ✅ Progress bar fills up (0% → 95%)
- ✅ After 15-20 samples: Success screen
- ✅ Success screen shows:
  - "Kalibrierung erfolgreich!"
  - Quality: "Exzellent" or "Sehr gut"
  - Genauigkeit: "±0.5mm" to "±2mm"
  - Messungen: "15" to "20"

**Console Log Check:**
```
🎯 Calibration started with Kreditkarte
   Mode: 3D PLANE-FITTING CALIBRATION (90%+ Success Rate)

✅ Valid calibration sample:
   Width: 85.7mm, Height: 54.1mm
   Calibration factor: 0.999
   Depth: 30.2cm
   Angle deviation: 2.3°
   Plane residual: 1.8mm
   Confidence: 0.92

📊 Collected 15/15 high-quality samples

✅ Final calibration computed:
   Samples used: 13 (from 15 collected)
   Calibration factor: 0.998
   Std deviation: 0.0082 (0.82%)
   Confidence: 0.92
```

**Success Criteria:**
- ✅ Calibration factor: 0.95 - 1.05
- ✅ Confidence: ≥ 0.85
- ✅ Std deviation: < 2%
- ✅ Time to complete: 10-20 seconds

---

## Test 2: Distance Validation (Too Close)

**Setup:**
1. Same as Test 1

**Steps:**
1. Start calibration
2. Hold iPhone only **20cm** above card (too close)
3. Observe feedback

**Expected Results:**
- ⚠️ Orange/red guide frame
- ⚠️ Message: "📏 Weiter weg! (20cm → 28-32cm, 10cm weiter)"
- ❌ No samples captured
- ❌ Progress bar stays at 0%

**Console Log Check:**
```
❌ Distance out of range: 20cm (ideal: 30cm ±2cm)
```

**Success Criteria:**
- ✅ App rejects frames that are too close
- ✅ Clear feedback message shown
- ✅ No bad samples added

---

## Test 3: Distance Validation (Too Far)

**Setup:**
1. Same as Test 1

**Steps:**
1. Start calibration
2. Hold iPhone **40cm** above card (too far)
3. Observe feedback

**Expected Results:**
- ⚠️ Orange/red guide frame
- ⚠️ Message: "📏 Näher! (40cm → 28-32cm, 10cm näher)"
- ❌ No samples captured

**Console Log Check:**
```
❌ Distance out of range: 40cm (ideal: 30cm ±2cm)
```

**Success Criteria:**
- ✅ App rejects frames that are too far
- ✅ Clear feedback message shown

---

## Test 4: Angle Validation (Tilted iPhone)

**Setup:**
1. Same as Test 1

**Steps:**
1. Start calibration
2. Hold iPhone at 30cm BUT **tilted** ~20° from horizontal
3. Observe feedback

**Expected Results:**
- ⚠️ Orange/red guide frame
- ⚠️ Message: "📐 iPhone parallel zum Tisch halten"
- ❌ No samples captured

**Console Log Check:**
```
❌ Card not perpendicular to camera: 15.2° (max: 5°)
```

**Success Criteria:**
- ✅ App rejects tilted frames
- ✅ Angle deviation correctly detected

---

## Test 5: Corner Occlusion (Card Partially Covered)

**Setup:**
1. Same as Test 1
2. **Cover one corner** of card with hand/object

**Steps:**
1. Start calibration
2. Hold position with corner covered
3. Observe behavior

**Expected Results:**
- ⚠️ Message may show "🔍 Suche Kreditkarte..." (if Vision can't detect)
- OR ❌ Sample silently rejected (if Vision detects but no depth at corner)
- ❌ No samples captured

**Console Log Check:**
```
❌ Failed to extract corner depths
```
OR
```
⚠️ No valid depth at corner (x, y)
```

**Success Criteria:**
- ✅ App doesn't accept samples with missing corners
- ✅ No crash or error dialog

---

## Test 6: Movement/Jitter (Unstable Hand)

**Setup:**
1. Same as Test 1

**Steps:**
1. Start calibration
2. Hold at correct distance/angle
3. **Move hand quickly** (shake iPhone)
4. Observe feedback

**Expected Results:**
- ⚠️ Message: "🤚 Ruhiger halten"
- ❌ No samples captured while moving
- ✅ Samples resume when hand stabilizes

**Console Log Check:**
```
(No specific log - samples just aren't created due to low quality score)
```

**Success Criteria:**
- ✅ App rejects frames with too much motion
- ✅ Feedback tells user to hold steady

---

## Test 7: Warped/Bent Card

**Setup:**
1. Same as Test 1
2. Use **bent or warped** credit card (or paper card)

**Steps:**
1. Start calibration
2. Hold at correct distance/angle
3. Observe behavior

**Expected Results:**
- ❌ No samples captured (plane residual too high)
- ⚠️ May show "Halte Position..." but never captures

**Console Log Check:**
```
❌ Plane residual too high: 5.2mm (max: 3mm)
```

**Success Criteria:**
- ✅ App rejects non-flat cards
- ✅ Ensures only rigid cards are used

---

## Test 8: Calibration Expiry (30-Day Limit)

**Setup:**
1. Complete successful calibration (Test 1)
2. Quit and reopen app

**Steps:**
1. **Manually modify timestamp** in UserDefaults:
   ```swift
   // Add this to CalibrationManager for testing:
   func setCalibrationTimestamp(_ date: Date) {
       UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "calibrationTimestamp")
   }

   // Call with old date:
   manager.setCalibrationTimestamp(Date().addingTimeInterval(-31 * 24 * 3600))
   ```

2. Check CalibrationStatusCard

**Expected Results:**
- ⚠️ CalibrationStatusCard shows "Abgelaufen - Neukalibrierung erforderlich"
- 🟠 Orange warning color
- 🔄 "Jetzt neu kalibrieren" button appears

**Console Log Check:**
```
⚠️ Calibration expired (age: 31 days, max: 30 days)
```

**Success Criteria:**
- ✅ Expired calibrations rejected
- ✅ UI prompts recalibration

---

## Test 9: Calibration Expiry Warning (25-30 Days)

**Setup:**
1. Complete successful calibration
2. Set timestamp to 26 days ago

**Expected Results:**
- ⚠️ CalibrationStatusCard shows orange age badge
- ⚠️ Warning: "Kalibrierung läuft in 4 Tagen ab"
- 🔵 "Erneuern" button appears

**Success Criteria:**
- ✅ Warning shown before expiry
- ✅ User can proactively recalibrate

---

## Test 10: Measurement Accuracy (Real-World Validation)

**Setup:**
1. Complete successful calibration
2. Have 3-5 objects with **known dimensions**:
   - Ruler (300mm)
   - Book (known width/height)
   - Box (known dimensions)
   - Phone (known dimensions)

**Steps:**
1. After calibration, go to scan mode
2. Scan each known object
3. Compare measured dimensions to real dimensions

**Expected Results:**
- ✅ Measurements within **±1-2%** of real dimensions
- ✅ Example: 300mm ruler measures 297-303mm
- ✅ Example: iPhone 15 Pro (146.6mm) measures 144-149mm

**Console Log Check:**
```
(Check measurement output in scan results)
```

**Success Criteria:**
- ✅ Accuracy ≤ ±2% for all objects
- ✅ Calibration factor was close to 1.0

**If accuracy is poor (> ±5%):**
- Recalibrate and check console logs
- Verify calibration factor is 0.95-1.05
- Verify confidence is ≥ 0.85
- Check if card dimensions are standard

---

## Regression Tests (Ensure Nothing Broke)

### Test 11: Vision Detection Still Works
- ✅ Rectangle detection works in various lighting
- ✅ Card detected when rotated (landscape/portrait)
- ✅ No false positives (doesn't detect non-cards)

### Test 12: LiDAR Depth Still Works
- ✅ Depth measurements are reasonable (0.2m - 0.5m range)
- ✅ Depth updates in real-time
- ✅ No lag or freezing

### Test 13: UI Responsiveness
- ✅ App doesn't freeze during calibration
- ✅ Progress bar updates smoothly
- ✅ Feedback messages update promptly
- ✅ Success screen appears within 1 second of completion

---

## Performance Tests

### Test 14: Frame Processing Speed
**Expected:**
- ✅ Vision detection runs every 2nd frame (~30 FPS)
- ✅ No noticeable lag in camera feed
- ✅ Phone doesn't overheat during calibration

### Test 15: Memory Usage
**Expected:**
- ✅ Memory usage < 200MB during calibration
- ✅ No memory leaks (use Xcode Instruments)
- ✅ Memory released after calibration completes

---

## Edge Case Tests

### Test 16: Multiple Calibrations in a Row
**Steps:**
1. Complete calibration
2. Immediately start another calibration
3. Complete 3-5 calibrations back-to-back

**Expected:**
- ✅ Each calibration works correctly
- ✅ No state corruption
- ✅ Latest calibration is saved

### Test 17: Calibration Interruption
**Steps:**
1. Start calibration
2. Collect 5-10 samples
3. Press "Abbrechen" (cancel)

**Expected:**
- ✅ Calibration stops cleanly
- ✅ No crash
- ✅ Previous calibration (if any) still valid

### Test 18: Background/Foreground
**Steps:**
1. Start calibration
2. Collect 5-10 samples
3. Press home button (background app)
4. Return to app

**Expected:**
- ✅ AR session resumes
- ✅ Calibration restarts (doesn't continue from 5/15)
- OR ✅ Calibration cancelled (shows start screen)

---

## Acceptance Criteria

For deployment, ALL of these must pass:

- [ ] **Test 1:** Successful calibration completes in 10-20 seconds
- [ ] **Test 2-6:** All validations correctly reject bad frames
- [ ] **Test 7:** Warped cards rejected (plane residual check works)
- [ ] **Test 8-9:** Calibration expiry works (30-day limit enforced)
- [ ] **Test 10:** Measurement accuracy ≤ ±2% on known objects
- [ ] **Test 11-13:** No regressions (existing features still work)
- [ ] **Test 14-15:** Performance acceptable (no lag/leaks)
- [ ] **Test 16-18:** Edge cases handled gracefully

**Success Rate Target:**
- ✅ 9 out of 10 calibrations succeed (90%+)
- ✅ When following instructions carefully

**If < 90% success rate:**
- Review console logs for rejection reasons
- Adjust thresholds in `ThreeDPlaneCalibrator.Config`
- Improve user feedback messages

---

## Debugging Checklist

If tests fail, check:

1. **Build Settings**
   - [ ] Target: iPhone 15 Pro
   - [ ] iOS Deployment Target: 18.6
   - [ ] Swift Language Version: 5.9+
   - [ ] No build warnings

2. **Permissions**
   - [ ] Camera permission granted
   - [ ] Info.plist has NSCameraUsageDescription

3. **Device Capabilities**
   - [ ] Device has LiDAR scanner
   - [ ] ARKit world tracking works
   - [ ] Scene depth available

4. **Console Logs**
   - [ ] No errors logged
   - [ ] Calibration samples show reasonable values
   - [ ] Calibration factor is 0.95-1.05

5. **Thresholds**
   - [ ] Review `ThreeDPlaneCalibrator.Config`
   - [ ] Adjust if too strict or too lenient
   - [ ] Document any changes made

---

## Reporting Results

After testing, document:

1. **Success Rate:**
   - X out of 10 calibrations succeeded
   - Common failure reasons (if any)

2. **Accuracy:**
   - Measured 5 known objects
   - Average error: ±X%
   - Calibration factor: X.XXX

3. **User Experience:**
   - Time to complete: X seconds
   - Feedback clarity: 1-5 rating
   - Difficulty level: Easy/Medium/Hard

4. **Issues Found:**
   - List any bugs or problems
   - Include console logs
   - Include steps to reproduce

5. **Recommendations:**
   - Threshold adjustments needed?
   - UI improvements needed?
   - Documentation clarifications needed?

---

## Quick Test Script (10 Minutes)

Minimum viable testing (if time-constrained):

1. ✅ Test 1: Happy path (successful calibration)
2. ✅ Test 2 OR 3: Distance validation
3. ✅ Test 10: Measure 1-2 known objects
4. ✅ Test 8: Check calibration expiry logic
5. ✅ Test 13: Verify UI responsiveness

**If all 5 pass:** System is probably working correctly
**If any fail:** Run full test suite to identify issues

---

## Contact

For questions or issues:
- Review `/3D/CALIBRATION_IMPROVEMENTS.md` for technical details
- Review `/3D/IMPLEMENTATION_SUMMARY.md` for architecture
- Check console logs for detailed error messages
- Verify device meets requirements (iPhone 15 Pro, iOS 18.6)

Good luck! 🚀
