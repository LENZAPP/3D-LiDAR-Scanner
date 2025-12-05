#!/usr/bin/env ruby
require 'xcodeproj'

project_path = '3D.xcodeproj'

puts "🔧 Adding Database files to Xcode project..."

# Open project
project = Xcodeproj::Project.open(project_path)

# Find main target
target = project.targets.find { |t| t.name == '3D' }

unless target
  puts "❌ Target '3D' not found"
  exit 1
end

# Create Database group if it doesn't exist
database_group = project.main_group.find_subpath('3D/Database', true)
database_group.set_source_tree('SOURCE_ROOT')

files_to_add = [
  '3D/Database/ScanDatabaseManager.swift',
  '3D/Database/ScanResultsView.swift',
  '3D/Database/ScanResultLogger.swift'
]

files_to_add.each do |file_path|
  # Check if file already exists in project
  existing = project.files.find { |f| f.path == file_path }

  if existing
    puts "✅ #{File.basename(file_path)} already in project"
  else
    # Add file to project
    file_ref = database_group.new_file(file_path)

    # Add to compile sources
    target.source_build_phase.add_file_reference(file_ref)

    puts "✅ Added #{File.basename(file_path)}"
  end
end

# Add database_schema.sql as resource
schema_file = 'database_schema.sql'
existing_schema = project.files.find { |f| f.path == schema_file }

if existing_schema
  puts "✅ database_schema.sql already in project"
else
  schema_ref = database_group.new_file(schema_file)
  target.resources_build_phase.add_file_reference(schema_ref)
  puts "✅ Added database_schema.sql as resource"
end

# Save project
project.save

puts "💾 Project saved"
puts "✅ Done! Database files added to Xcode project."
