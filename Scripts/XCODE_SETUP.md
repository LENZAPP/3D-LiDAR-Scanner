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
