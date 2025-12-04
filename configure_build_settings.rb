#!/usr/bin/env ruby
#
# Configure Build Settings for Phase 2B
# Sets up C++17, Header Search Paths, Bridging Header, etc.
#

require 'xcodeproj'

puts "⚙️  Phase 2B Build Settings Configuration"
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

# Get build configurations
debug_config = target.build_configurations.find { |c| c.name == 'Debug' }
release_config = target.build_configurations.find { |c| c.name == 'Release' }

configs = [debug_config, release_config].compact

if configs.empty?
  puts "❌ No build configurations found!"
  exit 1
end

puts "📝 Configuring build settings for:"
configs.each { |c| puts "   • #{c.name}" }
puts ""

# Configure each build configuration
configs.each do |config|
  settings = config.build_settings

  # Header Search Paths
  puts "Setting Header Search Paths..."
  header_paths = [
    '$(PROJECT_DIR)/ThirdParty/PoissonRecon/Src',
    '$(PROJECT_DIR)/ThirdParty/MeshFix/include',
    '$(PROJECT_DIR)/3D/MeshRepair/Phase2B/ObjCBridge',
    '$(PROJECT_DIR)/3D/MeshRepair/Phase2B/CPP'
  ]

  existing_paths = settings['HEADER_SEARCH_PATHS'] || []
  existing_paths = [existing_paths] if existing_paths.is_a?(String)

  header_paths.each do |path|
    unless existing_paths.include?(path)
      existing_paths << path
      puts "  ✅ Added: #{path}"
    end
  end
  settings['HEADER_SEARCH_PATHS'] = existing_paths

  # C++ Language Standard
  puts "Setting C++ Language Standard to gnu++17..."
  settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++17'
  puts "  ✅ CLANG_CXX_LANGUAGE_STANDARD = gnu++17"

  # C++ Standard Library
  puts "Setting C++ Standard Library..."
  settings['CLANG_CXX_LIBRARY'] = 'libc++'
  puts "  ✅ CLANG_CXX_LIBRARY = libc++"

  # Enable C++ Exceptions
  puts "Enabling C++ Exceptions..."
  settings['GCC_ENABLE_CPP_EXCEPTIONS'] = 'YES'
  puts "  ✅ GCC_ENABLE_CPP_EXCEPTIONS = YES"

  # Enable C++ RTTI
  puts "Enabling C++ RTTI..."
  settings['GCC_ENABLE_CPP_RTTI'] = 'YES'
  puts "  ✅ GCC_ENABLE_CPP_RTTI = YES"

  # Bridging Header
  puts "Setting Objective-C Bridging Header..."
  settings['SWIFT_OBJC_BRIDGING_HEADER'] = '$(PROJECT_DIR)/3D/MeshRepair/Phase2B/ObjCBridge/3D-Bridging-Header.h'
  puts "  ✅ SWIFT_OBJC_BRIDGING_HEADER set"

  # C++ Compiler Flags (suppress PoissonRecon warnings)
  puts "Setting C++ Compiler Flags..."
  existing_flags = settings['OTHER_CPLUSPLUSFLAGS'] || ''
  existing_flags = [existing_flags] if existing_flags.is_a?(String)

  warning_flags = ['-Wno-unused-parameter', '-Wno-sign-compare', '-Wno-reorder']
  warning_flags.each do |flag|
    unless existing_flags.any? { |f| f.include?(flag) }
      existing_flags << flag
    end
  end
  settings['OTHER_CPLUSPLUSFLAGS'] = existing_flags.join(' ')
  puts "  ✅ OTHER_CPLUSPLUSFLAGS = #{existing_flags.join(' ')}"

  # Optimization Level (Debug: None, Release: Fast)
  if config.name == 'Debug'
    settings['GCC_OPTIMIZATION_LEVEL'] = '0'
    puts "  ✅ GCC_OPTIMIZATION_LEVEL = 0 (Debug)"
  else
    settings['GCC_OPTIMIZATION_LEVEL'] = 'fast'
    puts "  ✅ GCC_OPTIMIZATION_LEVEL = fast (Release)"
  end

  puts ""
end

puts "=" * 60
puts "💾 Saving project..."

# Save project
project.save

puts "✅ Project saved successfully!"
puts ""
puts "🎉 Build settings configured for Phase 2B!"
puts ""
puts "Configuration summary:"
puts "  ✅ Header Search Paths: 4 paths added"
puts "  ✅ C++ Standard: gnu++17"
puts "  ✅ C++ Library: libc++"
puts "  ✅ Exceptions & RTTI: Enabled"
puts "  ✅ Bridging Header: Set"
puts "  ✅ Warning Suppression: Configured"
puts ""
puts "Next steps:"
puts "1. Add PoissonRecon library files"
puts "2. Build project (⌘B)"
puts ""
