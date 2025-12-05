-- ============================================================================
-- 3D Scanner App - Measurement Database Schema
-- Stores scan results, ground truth, and accuracy metrics
-- ============================================================================

-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- ============================================================================
-- Objects Table - Ground Truth Data
-- ============================================================================

CREATE TABLE IF NOT EXISTS objects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    material TEXT NOT NULL,

    -- Ground Truth Measurements
    true_volume_cm3 REAL NOT NULL,
    true_weight_g REAL NOT NULL,
    true_density_g_cm3 REAL NOT NULL,

    -- Optional dimensions
    true_length_cm REAL,
    true_width_cm REAL,
    true_height_cm REAL,

    -- Metadata
    description TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (true_volume_cm3 > 0),
    CHECK (true_weight_g > 0),
    CHECK (true_density_g_cm3 > 0)
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_objects_name ON objects(name);
CREATE INDEX IF NOT EXISTS idx_objects_category ON objects(category);

-- ============================================================================
-- Scans Table - Individual Scan Results
-- ============================================================================

CREATE TABLE IF NOT EXISTS scans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    object_id INTEGER,

    -- Scan Information
    scan_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scan_duration_seconds REAL,
    device_model TEXT DEFAULT 'iPhone 15 Pro',
    ios_version TEXT,

    -- Measured Values
    measured_volume_cm3 REAL NOT NULL,
    measured_weight_g REAL NOT NULL,
    measured_density_g_cm3 REAL NOT NULL,

    -- Point Cloud Stats
    point_count INTEGER,
    mesh_vertex_count INTEGER,
    mesh_face_count INTEGER,

    -- Quality Metrics
    confidence_score REAL DEFAULT 0.0,
    mesh_quality_score REAL DEFAULT 0.0,
    surface_completeness REAL DEFAULT 0.0,

    -- Processing Methods Used
    used_pcn_completion BOOLEAN DEFAULT 0,
    used_mesh_repair BOOLEAN DEFAULT 0,
    used_ai_detection BOOLEAN DEFAULT 0,

    -- Calibration
    calibration_method TEXT,
    scale_factor REAL DEFAULT 1.0,

    -- Metadata
    notes TEXT,

    -- Foreign Key
    FOREIGN KEY (object_id) REFERENCES objects(id) ON DELETE SET NULL,

    -- Constraints
    CHECK (measured_volume_cm3 > 0),
    CHECK (measured_weight_g > 0),
    CHECK (scan_duration_seconds >= 0),
    CHECK (confidence_score >= 0 AND confidence_score <= 1),
    CHECK (mesh_quality_score >= 0 AND mesh_quality_score <= 1)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_scans_object_id ON scans(object_id);
CREATE INDEX IF NOT EXISTS idx_scans_date ON scans(scan_date);
CREATE INDEX IF NOT EXISTS idx_scans_confidence ON scans(confidence_score);

-- ============================================================================
-- Accuracy Metrics View - Calculated Error Metrics
-- ============================================================================

CREATE VIEW IF NOT EXISTS scan_accuracy AS
SELECT
    s.id AS scan_id,
    s.scan_date,
    o.name AS object_name,
    o.category,
    o.material,

    -- Ground Truth
    o.true_volume_cm3,
    o.true_weight_g,
    o.true_density_g_cm3,

    -- Measured Values
    s.measured_volume_cm3,
    s.measured_weight_g,
    s.measured_density_g_cm3,

    -- Absolute Errors
    ABS(s.measured_volume_cm3 - o.true_volume_cm3) AS volume_error_cm3,
    ABS(s.measured_weight_g - o.true_weight_g) AS weight_error_g,
    ABS(s.measured_density_g_cm3 - o.true_density_g_cm3) AS density_error,

    -- Percentage Errors
    ROUND(ABS(s.measured_volume_cm3 - o.true_volume_cm3) / o.true_volume_cm3 * 100, 2) AS volume_error_percent,
    ROUND(ABS(s.measured_weight_g - o.true_weight_g) / o.true_weight_g * 100, 2) AS weight_error_percent,
    ROUND(ABS(s.measured_density_g_cm3 - o.true_density_g_cm3) / o.true_density_g_cm3 * 100, 2) AS density_error_percent,

    -- Quality Scores
    s.confidence_score,
    s.mesh_quality_score,
    s.surface_completeness,

    -- Point Cloud Info
    s.point_count,
    s.mesh_vertex_count,

    -- Processing Info
    s.used_pcn_completion,
    s.used_mesh_repair,
    s.used_ai_detection,
    s.scan_duration_seconds

FROM scans s
LEFT JOIN objects o ON s.object_id = o.id;

-- ============================================================================
-- Statistics View - Aggregate Performance Metrics
-- ============================================================================

CREATE VIEW IF NOT EXISTS overall_statistics AS
SELECT
    COUNT(*) AS total_scans,
    COUNT(DISTINCT object_id) AS unique_objects,

    -- Average Errors
    ROUND(AVG(ABS(measured_volume_cm3 - true_volume_cm3) / true_volume_cm3 * 100), 2) AS avg_volume_error_percent,
    ROUND(AVG(ABS(measured_weight_g - true_weight_g) / true_weight_g * 100), 2) AS avg_weight_error_percent,

    -- Best/Worst Performance
    ROUND(MIN(ABS(measured_volume_cm3 - true_volume_cm3) / true_volume_cm3 * 100), 2) AS best_volume_error_percent,
    ROUND(MAX(ABS(measured_volume_cm3 - true_volume_cm3) / true_volume_cm3 * 100), 2) AS worst_volume_error_percent,

    -- Quality Metrics
    ROUND(AVG(confidence_score), 2) AS avg_confidence,
    ROUND(AVG(mesh_quality_score), 2) AS avg_mesh_quality,

    -- Timing
    ROUND(AVG(scan_duration_seconds), 1) AS avg_scan_duration_sec

FROM scan_accuracy;

-- ============================================================================
-- Category Statistics View
-- ============================================================================

CREATE VIEW IF NOT EXISTS category_statistics AS
SELECT
    category,
    material,
    COUNT(*) AS scan_count,
    ROUND(AVG(ABS(measured_volume_cm3 - true_volume_cm3) / true_volume_cm3 * 100), 2) AS avg_volume_error_percent,
    ROUND(AVG(ABS(measured_weight_g - true_weight_g) / true_weight_g * 100), 2) AS avg_weight_error_percent,
    ROUND(AVG(confidence_score), 2) AS avg_confidence
FROM scan_accuracy
GROUP BY category, material
ORDER BY scan_count DESC;

-- ============================================================================
-- Sample Ground Truth Data
-- ============================================================================

-- Red Bull Can
INSERT OR IGNORE INTO objects (
    id, name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    1, 'Red Bull Can (250ml)', 'Beverage', 'Aluminum',
    250.0, 15.5, 2.70,
    5.3, 5.3, 12.0,
    'Standard Red Bull energy drink can, 250ml'
);

-- Apple (Medium)
INSERT OR IGNORE INTO objects (
    id, name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    2, 'Apple (Medium)', 'Food', 'Organic',
    180.0, 182.0, 1.01,
    7.5, 7.5, 7.0,
    'Medium-sized apple, approximately 180g'
);

-- iPhone 15 Pro
INSERT OR IGNORE INTO objects (
    id, name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    3, 'iPhone 15 Pro', 'Electronics', 'Titanium/Glass',
    100.0, 187.0, 1.87,
    14.67, 7.09, 0.83,
    'iPhone 15 Pro - Titanium frame with glass back'
);

-- Coffee Mug
INSERT OR IGNORE INTO objects (
    id, name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    4, 'Coffee Mug (Ceramic)', 'Household', 'Ceramic',
    350.0, 840.0, 2.40,
    8.5, 8.5, 10.0,
    'Standard ceramic coffee mug, 350ml capacity'
);

-- Wooden Block
INSERT OR IGNORE INTO objects (
    id, name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    5, 'Wooden Block (Pine)', 'Toy', 'Wood',
    125.0, 81.25, 0.65,
    5.0, 5.0, 5.0,
    'Pine wood cube, 5cm x 5cm x 5cm'
);

-- Water Bottle (Plastic)
INSERT OR IGNORE INTO objects (
    id, name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    6, 'Water Bottle (500ml)', 'Container', 'Plastic',
    500.0, 525.0, 1.05,
    6.5, 6.5, 20.0,
    'Standard plastic water bottle, 500ml PET'
);

-- Tennis Ball
INSERT OR IGNORE INTO objects (
    id, name, category, material,
    true_volume_cm3, true_weight_g, true_density_g_cm3,
    true_length_cm, true_width_cm, true_height_cm,
    description
) VALUES (
    7, 'Tennis Ball', 'Sports', 'Rubber',
    140.0, 58.0, 0.41,
    6.7, 6.7, 6.7,
    'Standard tennis ball, ITF approved'
);

-- ============================================================================
-- Helper Queries
-- ============================================================================

-- Query: Get latest scan results with accuracy
-- SELECT * FROM scan_accuracy ORDER BY scan_date DESC LIMIT 10;

-- Query: Get all scans for a specific object
-- SELECT * FROM scan_accuracy WHERE object_name = 'Red Bull Can (250ml)' ORDER BY scan_date;

-- Query: Get scans with error > 10%
-- SELECT * FROM scan_accuracy WHERE volume_error_percent > 10 ORDER BY volume_error_percent DESC;

-- Query: Average performance by material
-- SELECT material, COUNT(*) as scans, AVG(volume_error_percent) as avg_error
-- FROM scan_accuracy GROUP BY material;

-- Query: Best performing scans
-- SELECT object_name, MIN(volume_error_percent) as best_error
-- FROM scan_accuracy GROUP BY object_name ORDER BY best_error;

-- ============================================================================
-- End of Schema
-- ============================================================================
