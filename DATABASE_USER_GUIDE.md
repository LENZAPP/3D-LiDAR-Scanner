# 📘 3D Scanner Database - Complete User Guide

**Database Name:** `3ddata.db`
**Location:** App Documents Folder
**Version:** 1.0
**Last Updated:** 2025-12-04

---

## 📋 TABLE OF CONTENTS

1. [Quick Start](#quick-start)
2. [Inserting Ground Truth Data](#inserting-ground-truth-data)
3. [Viewing Your Data](#viewing-your-data)
4. [Automatic Scan Logging](#automatic-scan-logging)
5. [Analyzing Results](#analyzing-results)
6. [Exporting Data](#exporting-data)
7. [SQL Queries](#sql-queries)
8. [Troubleshooting](#troubleshooting)

---

## 🚀 QUICK START

### Step 1: Find Your Database

The database is automatically created when you first run the app:

```
Location: App Documents/3ddata.db

On Simulator:
~/Library/Developer/CoreSimulator/Devices/[DEVICE_ID]/data/Containers/Data/Application/[APP_ID]/Documents/3ddata.db

On Device:
Files App → On My iPhone → 3D Scanner → 3ddata.db
```

### Step 2: Pre-loaded Test Objects

The database comes with 7 test objects ready to use:
- Red Bull Can (250ml)
- Apple (Medium)
- iPhone 15 Pro
- Coffee Mug (Ceramic)
- Wooden Block (Pine)
- Water Bottle (500ml)
- Tennis Ball

### Step 3: Start Scanning

Just scan any object! The results are automatically saved.

---

## 📝 INSERTING GROUND TRUTH DATA

Ground truth data = known measurements of real objects for testing accuracy.

### Method 1: Using the App (EASIEST)

**Step-by-Step:**

1. Open the app
2. Navigate to **"Scan Results"** tab
3. Scroll to **"Ground Truth Objects"** section
4. Tap **"Add Ground Truth Object"**
5. Fill in the form:

```
Name:        Red Bull Can (250ml)
Category:    Beverage
Material:    Aluminum

Volume:      250 cm³        (measure with water displacement)
Weight:      15.5 g         (weigh on scale)
Density:     2.70 g/cm³     (calculated: weight ÷ volume)

Dimensions (optional):
Length:      5.3 cm
Width:       5.3 cm
Height:      12.0 cm

Description: Standard Red Bull energy drink can
Notes:       Measured with graduated cylinder
```

6. Tap **"Save"**

**Done!** Your ground truth object is now in the database.

### Method 2: Using SQL

Open Terminal and run:

```bash
# Navigate to your database
cd ~/Desktop/3D_PROJEKT/3D

# Open database
sqlite3 scan_results_test.db

# Insert your object
INSERT INTO objects (
    name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    'My Custom Can',
    'Beverage',
    'Aluminum',
    250.0,
    15.5,
    2.70,
    5.3,
    5.3,
    12.0,
    'Custom test object measured 2025-12-04'
);

# Verify it was added
SELECT * FROM objects WHERE name = 'My Custom Can';
```

### Method 3: Using Swift Code

```swift
// In your Swift code
let object = GroundTruthObject(
    id: nil,
    name: "Coca Cola Can (330ml)",
    category: "Beverage",
    material: "Aluminum",
    trueVolume: 330.0,
    trueWeight: 20.5,
    trueDensity: 2.70,
    length: 6.0,
    width: 6.0,
    height: 12.3,
    description: "Standard Coca Cola can",
    notes: "Measured with precision scale"
)

Task {
    let database = ScanDatabaseManager.shared
    if let objectId = await database.addGroundTruthObject(object) {
        print("✅ Object added with ID: \(objectId)")
    }
}
```

---

## 👀 VIEWING YOUR DATA

### Method 1: In the App (RECOMMENDED)

**View Ground Truth Objects:**
1. Open app
2. Go to **"Scan Results"** tab
3. See **"Ground Truth Objects"** section
4. All your test objects are listed here

**View Scan Results:**
1. Go to **"Scan Results"** tab
2. See **"Recent Scans"** section
3. Shows last 20 scans with:
   - Date & time
   - Volume, weight, density
   - Confidence score
   - Which AI features were used

**View Statistics:**
1. See **"Overall Performance"** card at top
2. Shows:
   - Total scans
   - Average accuracy
   - Average scan duration
   - Confidence scores

**View Detailed Analytics:**
1. Scroll to **"Actions"** section
2. Tap **"Detailed Analytics"**
3. See:
   - Per-category performance
   - Material-specific accuracy
   - Trending data

### Method 2: Using Terminal

```bash
# Open database
sqlite3 ~/Desktop/3D_PROJEKT/3D/scan_results_test.db

# View all ground truth objects
SELECT id, name, category, true_volume_cm3, true_weight_g
FROM objects;

# View recent scans
SELECT
    scan_date,
    measured_volume_cm3,
    measured_weight_g,
    confidence_score
FROM scans
ORDER BY scan_date DESC
LIMIT 10;

# View accuracy for all scans
SELECT
    object_name,
    volume_error_percent,
    weight_error_percent,
    confidence_score
FROM scan_accuracy
ORDER BY scan_date DESC;
```

### Method 3: Export to Excel

1. In app, go to **"Scan Results"**
2. Scroll to **"Actions"**
3. Tap **"Export to CSV"**
4. Tap **"Share"**
5. Open in Excel, Numbers, or Google Sheets

---

## 🤖 AUTOMATIC SCAN LOGGING

**Good news:** Scan logging is **100% automatic**! You don't need to do anything.

### What Gets Logged Automatically

Every scan captures:

```
✅ Date & Time
✅ Volume (cm³)
✅ Weight (g)
✅ Density (g/cm³)
✅ Point Count
✅ Mesh Quality Score
✅ Confidence Score (0-100%)
✅ Scan Duration (seconds)
✅ Device Model (iPhone 15 Pro)
✅ iOS Version
✅ Processing Methods Used:
   - PCN Completion (yes/no)
   - Mesh Repair (yes/no)
   - AI Detection (yes/no)
✅ Calibration Method
✅ Scale Factor
```

### How It Works

1. **You scan an object**
2. **App calculates measurements**
3. **Automatically logs to database**
4. **If object matches ground truth:**
   - Calculates errors
   - Shows accuracy report
5. **Done!**

### Example: Scanning a Red Bull Can

```
1. You scan a Red Bull can
2. App measures: 248.5 cm³, 15.7g
3. Automatically finds ground truth: "Red Bull Can (250ml)"
4. Calculates errors:
   - Volume error: 0.60%
   - Weight error: 1.29%
5. Shows report in console:

📊 SCAN ACCURACY REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Object:      Red Bull Can (250ml)
Category:    Beverage
Material:    Aluminum

VOLUME
True:        250.00 cm³
Measured:    248.50 cm³
Error:       0.60% ✅

WEIGHT
True:        15.50 g
Measured:    15.70 g
Error:       1.29% ✅

QUALITY
Confidence:  85%
Points:      2048
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 📊 ANALYZING RESULTS

### Overall Statistics

**Via App:**
1. Go to "Scan Results"
2. See top card with:
   - Total Scans
   - Average Accuracy
   - Average Duration
   - Confidence Score

**Via SQL:**
```sql
SELECT * FROM overall_statistics;
```

**Shows:**
```
Total Scans:         42
Unique Objects:      7
Avg Volume Error:    3.45%
Avg Weight Error:    2.87%
Avg Confidence:      0.82
Avg Duration:        6.2 seconds
```

### Per-Object Accuracy

**Find best/worst performing objects:**

```sql
SELECT
    object_name,
    COUNT(*) as scan_count,
    AVG(volume_error_percent) as avg_volume_error,
    AVG(weight_error_percent) as avg_weight_error,
    AVG(confidence_score) as avg_confidence
FROM scan_accuracy
GROUP BY object_name
ORDER BY avg_volume_error;
```

**Example Output:**
```
object_name              scan_count  avg_volume_error  avg_weight_error  avg_confidence
Red Bull Can (250ml)     8           1.2%              1.5%              0.87
Apple (Medium)           5           4.3%              3.8%              0.75
iPhone 15 Pro            3           2.1%              2.4%              0.92
Tennis Ball              6           8.5%              7.2%              0.68
```

### Material Performance

**Which materials scan best?**

```sql
SELECT * FROM category_statistics;
```

**Or more detailed:**

```sql
SELECT
    material,
    COUNT(*) as scans,
    AVG(volume_error_percent) as avg_error,
    MIN(volume_error_percent) as best_scan,
    MAX(volume_error_percent) as worst_scan
FROM scan_accuracy
GROUP BY material
ORDER BY avg_error;
```

**Example Output:**
```
material    scans  avg_error  best_scan  worst_scan
Aluminum    12     1.8%       0.5%       4.2%
Ceramic     8      2.4%       1.1%       5.8%
Wood        6      3.2%       1.8%       6.5%
Plastic     15     3.8%       1.2%       9.1%
Rubber      7      7.5%       4.2%       12.8%
```

### Find Problem Scans

**Scans with error > 10%:**

```sql
SELECT
    scan_date,
    object_name,
    volume_error_percent,
    weight_error_percent,
    confidence_score,
    point_count
FROM scan_accuracy
WHERE volume_error_percent > 10
ORDER BY volume_error_percent DESC;
```

### Performance Over Time

**Are you getting better?**

```sql
SELECT
    DATE(scan_date) as date,
    COUNT(*) as scans,
    AVG(volume_error_percent) as avg_error,
    AVG(confidence_score) as avg_confidence,
    AVG(scan_duration_seconds) as avg_duration
FROM scan_accuracy
GROUP BY DATE(scan_date)
ORDER BY date DESC;
```

---

## 📤 EXPORTING DATA

### Export to CSV

**Via App (EASIEST):**

1. Open app
2. Go to **"Scan Results"**
3. Scroll to **"Actions"**
4. Tap **"Export to CSV"**
5. Choose:
   - **Share** → Send via AirDrop, Email, etc.
   - **Save to Files** → Save to iCloud Drive
   - **Open in Excel/Numbers**

**CSV Contains:**
```csv
Scan Date,Object,Category,Material,True Volume (cm³),Measured Volume (cm³),Volume Error %,True Weight (g),Measured Weight (g),Weight Error %,Confidence,Points
2025-12-04 18:30,Red Bull Can (250ml),Beverage,Aluminum,250.00,248.50,0.60,15.50,15.70,1.29,0.85,2048
2025-12-04 18:35,Apple (Medium),Food,Organic,180.00,183.20,1.78,182.00,179.50,1.37,0.78,1856
...
```

**Via SQL:**

```bash
# Export all scans
sqlite3 -header -csv ~/Desktop/3D_PROJEKT/3D/scan_results_test.db \
  "SELECT * FROM scan_accuracy ORDER BY scan_date DESC;" \
  > my_scan_results.csv

# Open in Excel
open my_scan_results.csv
```

### Export Specific Data

**Only successful scans (error < 5%):**

```sql
SELECT * FROM scan_accuracy
WHERE volume_error_percent < 5
ORDER BY scan_date DESC;
```

**Only specific object:**

```sql
SELECT * FROM scan_accuracy
WHERE object_name = 'Red Bull Can (250ml)'
ORDER BY scan_date DESC;
```

**Date range:**

```sql
SELECT * FROM scan_accuracy
WHERE scan_date BETWEEN '2025-12-01' AND '2025-12-31'
ORDER BY scan_date DESC;
```

---

## 🔍 SQL QUERIES REFERENCE

### Basic Queries

**View all objects:**
```sql
SELECT * FROM objects;
```

**View all scans:**
```sql
SELECT * FROM scans ORDER BY scan_date DESC;
```

**View scan accuracy:**
```sql
SELECT * FROM scan_accuracy ORDER BY scan_date DESC LIMIT 20;
```

**Count total scans:**
```sql
SELECT COUNT(*) as total_scans FROM scans;
```

### Advanced Queries

**Best scan for each object:**
```sql
SELECT
    object_name,
    MIN(volume_error_percent) as best_error,
    scan_date
FROM scan_accuracy
GROUP BY object_name
ORDER BY best_error;
```

**Average performance by day of week:**
```sql
SELECT
    CASE CAST(strftime('%w', scan_date) AS INTEGER)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END as day_of_week,
    COUNT(*) as scans,
    AVG(volume_error_percent) as avg_error
FROM scan_accuracy
GROUP BY strftime('%w', scan_date)
ORDER BY CAST(strftime('%w', scan_date) AS INTEGER);
```

**Scans using PCN vs not using PCN:**
```sql
SELECT
    used_pcn_completion,
    COUNT(*) as scans,
    AVG(volume_error_percent) as avg_error,
    AVG(confidence_score) as avg_confidence
FROM scans s
LEFT JOIN objects o ON s.object_id = o.id
GROUP BY used_pcn_completion;
```

**Impact of AI detection:**
```sql
SELECT
    used_ai_detection,
    COUNT(*) as scans,
    AVG(volume_error_percent) as avg_error,
    AVG(mesh_quality_score) as avg_quality
FROM scans s
LEFT JOIN objects o ON s.object_id = o.id
GROUP BY used_ai_detection;
```

### Updating Data

**Update ground truth:**
```sql
UPDATE objects
SET true_volume_cm3 = 252.0,
    true_weight_g = 15.8
WHERE name = 'Red Bull Can (250ml)';
```

**Add notes to scan:**
```sql
UPDATE scans
SET notes = 'Poor lighting conditions'
WHERE id = 42;
```

**Delete bad scan:**
```sql
DELETE FROM scans
WHERE id = 42;
```

### Data Maintenance

**Delete all scans (keep ground truth):**
```sql
DELETE FROM scans;
```

**Reset database (WARNING: deletes everything):**
```sql
DELETE FROM scans;
DELETE FROM objects;
VACUUM;
```

**Backup database:**
```bash
cp ~/Desktop/3D_PROJEKT/3D/scan_results_test.db \
   ~/Desktop/3D_PROJEKT/3D/scan_results_backup_$(date +%Y%m%d).db
```

---

## 🛠️ TROUBLESHOOTING

### Database Not Found

**Problem:** App says "Database not found"

**Solution:**
1. Delete app
2. Reinstall
3. Database will be created automatically on first launch

### No Ground Truth Objects

**Problem:** "No ground truth objects added yet"

**Solution:**
```bash
# Run initialization script
cd ~/Desktop/3D_PROJEKT/3D
./initialize_database.sh
```

Or add manually via app (Method 1 above).

### CSV Export Fails

**Problem:** "Export failed"

**Solution:**
1. Check storage space
2. Give app Files permission:
   - Settings → Privacy → Files → Enable for 3D Scanner
3. Try again

### Accuracy Not Showing

**Problem:** Scans save but no accuracy shown

**Reasons:**
- Object name doesn't match ground truth
- Ground truth object not in database

**Solution:**
1. Check object name spelling
2. Add ground truth object manually
3. Rescan

### Database Locked

**Problem:** "Database is locked"

**Solution:**
```bash
# Close all connections
sqlite3 ~/Desktop/3D_PROJEKT/3D/scan_results_test.db "PRAGMA wal_checkpoint(TRUNCATE);"
```

---

## 📚 COMPLETE EXAMPLE WORKFLOW

### Example: Testing Your Scanner Accuracy

**Goal:** Test how accurate your scanner is with a Red Bull can.

**Step 1: Measure Ground Truth**

```
1. Get a Red Bull can (250ml)
2. Measure volume:
   - Fill with water
   - Pour into measuring cup
   - Result: 250 ml = 250 cm³

3. Measure weight:
   - Empty can
   - Weigh on scale
   - Result: 15.5 g

4. Calculate density:
   - 15.5g ÷ 250cm³ = 0.062 g/cm³ (aluminum)
```

**Step 2: Add to Database**

Via app:
1. Tap "Add Ground Truth Object"
2. Enter:
   - Name: "Red Bull Can (250ml)"
   - Category: "Beverage"
   - Material: "Aluminum"
   - Volume: 250
   - Weight: 15.5
   - Density: 2.70 (for aluminum material)
3. Save

**Step 3: Scan the Can**

1. Open app
2. Place can on table
3. Start scan
4. Move camera around can
5. Complete scan
6. App automatically saves to database

**Step 4: View Results**

Console shows:
```
📊 SCAN ACCURACY REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Object:      Red Bull Can (250ml)
Category:    Beverage
Material:    Aluminum

VOLUME
True:        250.00 cm³
Measured:    248.50 cm³
Error:       0.60% ✅ Excellent!

WEIGHT
True:        15.50 g
Measured:    15.70 g
Error:       1.29% ✅ Very Good!

QUALITY
Confidence:  85%
Points:      2048
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 5: Scan Multiple Times**

1. Scan same can 5-10 times
2. View statistics:

```sql
SELECT
    COUNT(*) as scans,
    AVG(volume_error_percent) as avg_error,
    MIN(volume_error_percent) as best_error,
    MAX(volume_error_percent) as worst_error,
    AVG(confidence_score) as avg_confidence
FROM scan_accuracy
WHERE object_name = 'Red Bull Can (250ml)';
```

**Results:**
```
scans: 10
avg_error: 2.3%
best_error: 0.6%
worst_error: 4.8%
avg_confidence: 0.83
```

**Step 6: Improve**

If error > 5%:
1. Better lighting
2. Cleaner calibration
3. Slower scanning
4. Enable PCN
5. Enable mesh repair

**Step 7: Export Results**

1. Export to CSV
2. Create chart in Excel
3. Share with team

---

## 🎓 TIPS & BEST PRACTICES

### For Best Accuracy

1. **Good Lighting:** Scan in bright, even light
2. **Clean Calibration:** Use clean 1-Euro coin
3. **Slow Scanning:** Move camera slowly
4. **Multiple Scans:** Scan same object 3-5 times
5. **Use All Features:** Enable PCN, mesh repair, AI
6. **Clean Objects:** Remove labels, clean surface

### For Good Database Management

1. **Regular Backups:** Export CSV weekly
2. **Descriptive Names:** Use clear object names
3. **Add Notes:** Document special conditions
4. **Review Statistics:** Check performance monthly
5. **Clean Bad Data:** Delete obviously wrong scans

### For Research

1. **Consistent Conditions:** Same lighting, same location
2. **Document Everything:** Add notes to every scan
3. **Multiple Objects:** Test various materials
4. **Statistical Analysis:** Export to Excel/R/Python
5. **Track Improvements:** Monitor error trends

---

## 📞 QUICK REFERENCE CARD

```
DATABASE NAME:    3ddata.db
LOCATION:         App Documents/

TABLES:
- objects         Ground truth data
- scans           All scan results

VIEWS:
- scan_accuracy   Calculated errors
- overall_statistics    Performance metrics
- category_statistics   Per-material stats

COMMON COMMANDS:

View all objects:
  SELECT * FROM objects;

View recent scans:
  SELECT * FROM scan_accuracy
  ORDER BY scan_date DESC LIMIT 10;

Export to CSV:
  App → Scan Results → Export

Add ground truth:
  App → Scan Results → Add Object

View statistics:
  SELECT * FROM overall_statistics;
```

---

## ✅ CHECKLIST

**Before Scanning:**
- [ ] Ground truth objects added
- [ ] Database initialized
- [ ] App has Files permission

**After Scanning:**
- [ ] Check scan saved (view in app)
- [ ] Review accuracy report
- [ ] Export data (weekly)

**Maintenance:**
- [ ] Backup database (monthly)
- [ ] Review statistics (weekly)
- [ ] Clean bad scans (as needed)

---

**Generated:** 2025-12-04
**Version:** 1.0
**Database:** 3ddata.db
**Status:** ✅ Production Ready

---

**Need Help?**
- Review this guide
- Check console logs
- Test with pre-loaded objects first
- Export and review in Excel

**Happy Scanning!** 🎉
