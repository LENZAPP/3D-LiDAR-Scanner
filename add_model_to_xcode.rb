#!/usr/bin/env ruby
require 'xcodeproj'

project_path = '3D.xcodeproj'
model_path = 'PointCloudCompletion.mlpackage'

puts "🔧 Adding PCN model to Xcode project..."
puts "   Project: #{project_path}"
puts "   Model:   #{model_path}"

# Open project
project = Xcodeproj::Project.open(project_path)

# Find main target
target = project.targets.find { |t| t.name == '3D' }

unless target
  puts "❌ Target '3D' not found"
  exit 1
end

# Check if model already exists
existing = project.files.find { |f| f.path == model_path }

if existing
  puts "✅ Model already in project"
else
  # Add model file to project
  file_ref = project.new_file(model_path)

  # Add to Resources build phase
  target.resources_build_phase.add_file_reference(file_ref)

  puts "✅ Model added to project"
end

# Save project
project.save

puts "💾 Project saved"
puts "✅ Done! Build the project to compile the model."
