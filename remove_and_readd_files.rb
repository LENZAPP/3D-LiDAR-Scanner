#!/usr/bin/env ruby
#
# Remove Phase2B files and re-add them with correct paths
#

require 'xcodeproj'

puts "🔧 Re-adding Phase 2B Files with Correct Paths"
puts "=" * 60

PROJECT_PATH = '3D.xcodeproj'
TARGET_NAME = '3D'

# Open project
project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }

puts "✅ Opened project"
puts ""

# Get main group
main_group = project.main_group['3D']
mesh_repair_group = main_group['MeshRepair']

# Remove Phase2B and Shared groups if they exist
if mesh_repair_group
  puts "🗑️  Removing old MeshRepair groups..."

  ['Phase2B', 'Shared'].each do |group_name|
    if group = mesh_repair_group[group_name]
      # Remove all file references
      group.recursive_children.each do |child|
        if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
          target.source_build_phase.files.each do |build_file|
            if build_file.file_ref == child
              target.source_build_phase.files.delete(build_file)
            end
          end
        end
      end

      group.clear
      mesh_repair_group.children.delete(group)
      puts "  ✅ Removed #{group_name}"
    end
  end

  puts ""
end

# Now add files with correct absolute paths
puts "📁 Adding files with absolute paths..."

# Create groups
phase2b_group = mesh_repair_group.new_group('Phase2B')
shared_group = mesh_repair_group.new_group('Shared')

cpp_group = phase2b_group.new_group('CPP')
objc_group = phase2b_group.new_group('ObjCBridge')
swift_group = phase2b_group.new_group('Swift')

# Define files with absolute paths
base_path = '/Users/lenz/Desktop/3D_PROJEKT/3D/3D'

files_to_add = [
  # Shared
  {group: shared_group, path: "#{base_path}/MeshRepair/Shared/MeshRepairError.swift", compile: true},
  {group: shared_group, path: "#{base_path}/MeshRepair/Shared/MeshRepairResult.swift", compile: true},

  # CPP
  {group: cpp_group, path: "#{base_path}/MeshRepair/Phase2B/CPP/MeshTypes.hpp", compile: false},
  {group: cpp_group, path: "#{base_path}/MeshRepair/Phase2B/CPP/PoissonWrapper.hpp", compile: false},
  {group: cpp_group, path: "#{base_path}/MeshRepair/Phase2B/CPP/PoissonWrapper.cpp", compile: true},
  {group: cpp_group, path: "#{base_path}/MeshRepair/Phase2B/CPP/PointCloudStreamAdapter.hpp", compile: false},
  {group: cpp_group, path: "#{base_path}/MeshRepair/Phase2B/CPP/MeshFixWrapper.hpp", compile: false},
  {group: cpp_group, path: "#{base_path}/MeshRepair/Phase2B/CPP/MeshFixWrapper.cpp", compile: true},

  # ObjC++
  {group: objc_group, path: "#{base_path}/MeshRepair/Phase2B/ObjCBridge/3D-Bridging-Header.h", compile: false},
  {group: objc_group, path: "#{base_path}/MeshRepair/Phase2B/ObjCBridge/PoissonBridge.h", compile: false},
  {group: objc_group, path: "#{base_path}/MeshRepair/Phase2B/ObjCBridge/PoissonBridge.mm", compile: true},
  {group: objc_group, path: "#{base_path}/MeshRepair/Phase2B/ObjCBridge/MeshFixBridge.h", compile: false},
  {group: objc_group, path: "#{base_path}/MeshRepair/Phase2B/ObjCBridge/MeshFixBridge.mm", compile: true},

  # Swift
  {group: swift_group, path: "#{base_path}/MeshRepair/Phase2B/Swift/NormalEstimator.swift", compile: true},
  {group: swift_group, path: "#{base_path}/MeshRepair/Phase2B/Swift/TaubinSmoother.swift", compile: true},
  {group: swift_group, path: "#{base_path}/MeshRepair/Phase2B/Swift/PoissonMeshRepair.swift", compile: true},
]

files_to_add.each do |file_info|
  if File.exist?(file_info[:path])
    # Add file with absolute path
    file_ref = file_info[:group].new_file(file_info[:path])

    # Set source tree to absolute
    file_ref.source_tree = '<absolute>'

    # Add to build phase if should compile
    if file_info[:compile]
      target.add_file_references([file_ref])
      puts "  ✅ Added (compile): #{File.basename(file_info[:path])}"
    else
      puts "  ✅ Added (header): #{File.basename(file_info[:path])}"
    end
  else
    puts "  ⚠️  File not found: #{file_info[:path]}"
  end
end

puts ""
puts "=" * 60
puts "💾 Saving project..."

project.save

puts "✅ Project saved!"
puts ""
puts "🎉 Files re-added with correct absolute paths!"
puts ""
