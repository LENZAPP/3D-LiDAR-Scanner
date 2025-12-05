#!/bin/bash

# Initialize Scan Results Database
# Creates database and populates with ground truth data

echo "📊 Initializing Scan Results Database"
echo "======================================"

# Database path
DB_PATH="$HOME/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Documents/scan_results.db"

# First, check if database_schema.sql exists
if [ ! -f "database_schema.sql" ]; then
    echo "❌ database_schema.sql not found"
    exit 1
fi

echo "✅ Found database schema"

# Create database in project directory for testing
TEST_DB="scan_results_test.db"

if [ -f "$TEST_DB" ]; then
    echo "🗑️  Removing existing test database..."
    rm "$TEST_DB"
fi

echo "📦 Creating database..."
sqlite3 "$TEST_DB" < database_schema.sql

if [ $? -eq 0 ]; then
    echo "✅ Database created successfully"
else
    echo "❌ Failed to create database"
    exit 1
fi

echo ""
echo "📊 Database Statistics:"
echo "----------------------"

# Count objects
OBJECT_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM objects;")
echo "Ground Truth Objects: $OBJECT_COUNT"

# Count scans
SCAN_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM scans;")
echo "Scans: $SCAN_COUNT"

echo ""
echo "📋 Ground Truth Objects:"
echo "----------------------"
sqlite3 -header -column "$TEST_DB" "SELECT id, name, category, material, true_volume_cm3, true_weight_g FROM objects;"

echo ""
echo "✅ Database initialized!"
echo ""
echo "📍 Database location: $TEST_DB"
echo ""
echo "🔧 To copy to iOS Simulator:"
echo "   1. Run the app in Simulator"
echo "   2. Find app's Documents directory"
echo "   3. Copy $TEST_DB to Documents/scan_results.db"
echo ""
echo "📱 To use on device:"
echo "   The app will create the database automatically on first launch"
echo ""
