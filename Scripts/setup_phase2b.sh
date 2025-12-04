#!/bin/bash

# Phase 2B Setup Script
# Downloads and configures PoissonRecon + MeshFix libraries

set -e  # Exit on error

PROJECT_ROOT="/Users/lenz/Desktop/3D_PROJEKT/3D"
THIRDPARTY_DIR="$PROJECT_ROOT/ThirdParty"

echo "🚀 Phase 2B Setup Starting..."
echo ""

# ============================================================
# 1. Download PoissonRecon
# ============================================================

echo "📦 Downloading PoissonRecon..."
cd "$THIRDPARTY_DIR/PoissonRecon"

if [ ! -d "PoissonRecon-master" ]; then
    curl -L "https://github.com/mkazhdan/PoissonRecon/archive/refs/heads/master.zip" -o poisson.zip
    unzip -q poisson.zip
    rm poisson.zip

    # Copy core files to Src/
    cp PoissonRecon-master/Src/*.h Src/ 2>/dev/null || true
    cp PoissonRecon-master/Src/*.inl Src/ 2>/dev/null || true
    cp PoissonRecon-master/Src/*.cpp Src/ 2>/dev/null || true

    echo "   ✅ PoissonRecon downloaded"
else
    echo "   ⏭️  PoissonRecon already downloaded"
fi

# ============================================================
# 2. Download MeshFix (Simplified - we'll use open3d-inspired approach)
# ============================================================

echo ""
echo "📦 Setting up MeshFix..."
cd "$THIRDPARTY_DIR/MeshFix"

# We'll create a simplified MeshFix wrapper based on common algorithms
# Instead of the full MeshFix library (which is complex),
# we'll implement essential hole-filling in pure C++

cat > include/meshfix.h << 'EOF'
// Simplified MeshFix header
// Basic topological repair functions

#pragma once
#include <vector>
#include <cstdint>

namespace meshfix {

struct Vec3 {
    float x, y, z;
    Vec3() : x(0), y(0), z(0) {}
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};

struct MeshData {
    std::vector<Vec3> vertices;
    std::vector<uint32_t> indices;  // Triangles: i0, i1, i2, ...
};

// Main repair function
MeshData repairMesh(const MeshData& input, int maxHoleSize = 100);

// Individual repair operations
void removeNonManifoldEdges(MeshData& mesh);
void fillHoles(MeshData& mesh, int maxHoleSize);
void removeSmallComponents(MeshData& mesh, int minVertices);
void removeSelfIntersections(MeshData& mesh);

} // namespace meshfix
EOF

echo "   ✅ MeshFix headers created"

# ============================================================
# 3. Create Xcode Build Configuration Guide
# ============================================================

echo ""
echo "📝 Creating Xcode configuration guide..."

cat > "$PROJECT_ROOT/Scripts/XCODE_SETUP.md" << 'EOF'
# Xcode Build Configuration for Phase 2B

## Required Build Settings

Add these to your Xcode target settings:

### 1. Header Search Paths
```
$(PROJECT_DIR)/ThirdParty/PoissonRecon/Src
$(PROJECT_DIR)/ThirdParty/MeshFix/include
$(PROJECT_DIR)/3D/MeshRepair/Phase2B/ObjCBridge
$(PROJECT_DIR)/3D/MeshRepair/Phase2B/CPP
```

### 2. C++ Language Settings
```
CLANG_CXX_LANGUAGE_STANDARD = gnu++17
CLANG_CXX_LIBRARY = libc++
GCC_ENABLE_CPP_EXCEPTIONS = YES
GCC_ENABLE_CPP_RTTI = YES
```

### 3. Optimization
```
GCC_OPTIMIZATION_LEVEL[config=Release] = -O3
GCC_OPTIMIZATION_LEVEL[config=Debug] = -O0
```

### 4. Architecture
```
VALID_ARCHS = arm64
ARCHS = arm64
```

### 5. Bridging Header
```
SWIFT_OBJC_BRIDGING_HEADER = $(PROJECT_DIR)/3D/MeshRepair/Phase2B/ObjCBridge/3D-Bridging-Header.h
```

### 6. Compiler Flags (Optional)
```
OTHER_CPLUSPLUSFLAGS = -ffast-math
```

## Adding Files to Xcode

1. Right-click on `3D` group in Xcode
2. Select "Add Files to '3D'..."
3. Select all files from:
   - `3D/MeshRepair/Phase2B/`
   - `ThirdParty/PoissonRecon/Src/`
   - `ThirdParty/MeshFix/`
4. Make sure "Add to targets" is checked for your app target
5. File types should be auto-detected:
   - `.swift` → Swift Source
   - `.mm` → Objective-C++ Source
   - `.cpp` → C++ Source
   - `.h/.hpp` → Headers (don't add to target)

## Verification

Build the project (⌘B). You should see:
- C++ files compiling
- Objective-C++ bridges compiling
- Swift files compiling
- No bridging header errors

If you see errors, check:
1. Header Search Paths are correct
2. Bridging header path is correct
3. All `.mm` and `.cpp` files are in "Compile Sources" build phase
4. C++ language standard is set to C++17 or later
EOF

echo "   ✅ Xcode configuration guide created"

# ============================================================
# 4. Summary
# ============================================================

echo ""
echo "=========================================="
echo "✅ Phase 2B Setup Complete!"
echo "=========================================="
echo ""
echo "📁 Directory Structure:"
echo "   $PROJECT_ROOT/3D/MeshRepair/Phase2B/"
echo "   $THIRDPARTY_DIR/PoissonRecon/"
echo "   $THIRDPARTY_DIR/MeshFix/"
echo ""
echo "📋 Next Steps:"
echo "   1. Run: open Scripts/XCODE_SETUP.md"
echo "   2. Configure Xcode build settings (see guide)"
echo "   3. Add C++ files to Xcode project"
echo "   4. Continue with Day 2 implementation"
echo ""
echo "🎯 Ready to implement C++ wrappers!"
echo ""
