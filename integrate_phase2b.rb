#!/usr/bin/env ruby
#
# Phase 2B Xcode Integration Script
# Adds all Phase 2B files to Xcode project using xcodeproj gem
#

require 'xcodeproj'

puts "🔧 Phase 2B Xcode Integration Script"
puts "=" * 60

PROJECT_PATH = '3D.xcodeproj'
TARGET_NAME = '3D'

# Open project
project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }

if target.nil?
  puts "❌ Target '#{TARGET_NAME}' not found!"
  exit 1
end

puts "✅ Opened project: #{PROJECT_PATH}"
puts "✅ Found target: #{TARGET_NAME}"
puts ""

# Get main group
main_group = project.main_group['3D']
if main_group.nil?
  puts "❌ Main group '3D' not found!"
  exit 1
end

# Find or create MeshRepair group
mesh_repair_group = main_group['MeshRepair']
if mesh_repair_group.nil?
  puts "Creating MeshRepair group..."
  mesh_repair_group = main_group.new_group('MeshRepair', '3D/MeshRepair')
end

# Find or create Phase2B group
phase2b_group = mesh_repair_group['Phase2B']
if phase2b_group.nil?
  puts "Creating Phase2B group..."
  phase2b_group = mesh_repair_group.new_group('Phase2B', '3D/MeshRepair/Phase2B')
end

# Find or create Shared group
shared_group = mesh_repair_group['Shared']
if shared_group.nil?
  puts "Creating Shared group..."
  shared_group = mesh_repair_group.new_group('Shared', '3D/MeshRepair/Shared')
end

puts "✅ Group structure ready"
puts ""

# Helper function to add files
def add_files_to_group(project, target, group, files, file_type)
  added_count = 0

  files.each do |file_path|
    next unless File.exist?(file_path)

    file_name = File.basename(file_path)

    # Check if file already in group
    existing = group.files.find { |f| f.path == file_name }
    if existing
      puts "  ⏭️  Skipping (already exists): #{file_name}"
      next
    end

    # Add file reference
    file_ref = group.new_file(file_path)

    # Add to compile sources if needed
    if file_type == :source
      target.add_file_references([file_ref])
      puts "  ✅ Added to sources: #{file_name}"
    else
      puts "  ✅ Added to project: #{file_name}"
    end

    added_count += 1
  end

  added_count
end

# Swift files in Shared
puts "📁 Adding Shared Swift files..."
shared_swift_files = [
  '3D/MeshRepair/Shared/MeshRepairError.swift',
  '3D/MeshRepair/Shared/MeshRepairResult.swift'
]
add_files_to_group(project, target, shared_group, shared_swift_files, :source)

# Create subgroups for Phase2B
cpp_group = phase2b_group['CPP']
if cpp_group.nil?
  cpp_group = phase2b_group.new_group('CPP', '3D/MeshRepair/Phase2B/CPP')
end

objc_group = phase2b_group['ObjCBridge']
if objc_group.nil?
  objc_group = phase2b_group.new_group('ObjCBridge', '3D/MeshRepair/Phase2B/ObjCBridge')
end

swift_group = phase2b_group['Swift']
if swift_group.nil?
  swift_group = phase2b_group.new_group('Swift', '3D/MeshRepair/Phase2B/Swift')
end

puts ""
puts "📁 Adding Phase2B C++ files..."
cpp_files = [
  '3D/MeshRepair/Phase2B/CPP/MeshTypes.hpp',
  '3D/MeshRepair/Phase2B/CPP/PoissonWrapper.hpp',
  '3D/MeshRepair/Phase2B/CPP/PoissonWrapper.cpp',
  '3D/MeshRepair/Phase2B/CPP/PointCloudStreamAdapter.hpp',
  '3D/MeshRepair/Phase2B/CPP/MeshFixWrapper.hpp',
  '3D/MeshRepair/Phase2B/CPP/MeshFixWrapper.cpp'
]

# Add headers (no compilation)
cpp_headers = cpp_files.select { |f| f.end_with?('.hpp') }
add_files_to_group(project, target, cpp_group, cpp_headers, :header)

# Add source files (compile)
cpp_sources = cpp_files.select { |f| f.end_with?('.cpp') }
add_files_to_group(project, target, cpp_group, cpp_sources, :source)

puts ""
puts "📁 Adding Phase2B Objective-C++ bridge files..."
objc_files = [
  '3D/MeshRepair/Phase2B/ObjCBridge/3D-Bridging-Header.h',
  '3D/MeshRepair/Phase2B/ObjCBridge/PoissonBridge.h',
  '3D/MeshRepair/Phase2B/ObjCBridge/PoissonBridge.mm',
  '3D/MeshRepair/Phase2B/ObjCBridge/MeshFixBridge.h',
  '3D/MeshRepair/Phase2B/ObjCBridge/MeshFixBridge.mm'
]

# Add headers (no compilation)
objc_headers = objc_files.select { |f| f.end_with?('.h') }
add_files_to_group(project, target, objc_group, objc_headers, :header)

# Add .mm files (compile)
objc_sources = objc_files.select { |f| f.end_with?('.mm') }
add_files_to_group(project, target, objc_group, objc_sources, :source)

puts ""
puts "📁 Adding Phase2B Swift files..."
swift_files = [
  '3D/MeshRepair/Phase2B/Swift/NormalEstimator.swift',
  '3D/MeshRepair/Phase2B/Swift/TaubinSmoother.swift',
  '3D/MeshRepair/Phase2B/Swift/PoissonMeshRepair.swift'
]
add_files_to_group(project, target, swift_group, swift_files, :source)

puts ""
puts "=" * 60
puts "💾 Saving project..."

# Save project
project.save

puts "✅ Project saved successfully!"
puts ""
puts "🎉 Phase 2B files added to Xcode project!"
puts ""
puts "Next steps:"
puts "1. Configure Build Settings (run configure_build_settings.rb)"
puts "2. Build project (⌘B)"
puts "3. Run on device (⌘R)"
puts ""
