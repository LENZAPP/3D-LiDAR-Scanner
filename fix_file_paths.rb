#!/usr/bin/env ruby
#
# Fix duplicate file paths in Xcode project
#

require 'xcodeproj'

puts "🔧 Fixing File Paths in Xcode Project"
puts "=" * 60

PROJECT_PATH = '3D.xcodeproj'

# Open project
project = Xcodeproj::Project.open(PROJECT_PATH)

puts "✅ Opened project: #{PROJECT_PATH}"
puts ""

# Find all file references with problematic paths
fixed_count = 0

project.files.each do |file_ref|
  next unless file_ref.path

  # Check if path starts with "3D/MeshRepair"
  if file_ref.path.start_with?('3D/MeshRepair/')
    old_path = file_ref.path
    new_path = old_path.sub('3D/', '')

    file_ref.path = new_path

    puts "✅ Fixed: #{File.basename(old_path)}"
    puts "   Old: #{old_path}"
    puts "   New: #{new_path}"
    puts ""

    fixed_count += 1
  end
end

puts "=" * 60
puts "Fixed #{fixed_count} file references"
puts ""

if fixed_count > 0
  puts "💾 Saving project..."
  project.save
  puts "✅ Project saved!"
else
  puts "No fixes needed"
end

puts ""
