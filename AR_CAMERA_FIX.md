# AR Camera Feed Fix - Black Screen Issue

## Problem

When starting calibration, the AR camera feed was not displaying - only a black screen was visible behind the UI elements.

## Root Cause

The issue was caused by **two separate ARSession instances** that were not connected:

1. **ARSCNView's Session**: Created in `ARViewContainerForCalibration.makeUIView()` but never configured or started
2. **CalibrationManager's Session**: Created independently in `setupARSession()` and started, but not connected to the visible ARSCNView

Result: The ARSCNView displayed a black screen because its session was never started, while CalibrationManager's session ran in the background (invisible).

## Solution

Modified the architecture to use a **single ARSession** - the one owned by ARSCNView:

### Changes Made

#### 1. CalibrationViewAR.swift (Line 87-95)

**Before:**
```swift
func makeUIView(context: Context) -> ARSCNView {
    let arView = ARSCNView(frame: .zero)
    arView.session.delegate = context.coordinator
    return arView  // Session never started!
}
```

**After:**
```swift
func makeUIView(context: Context) -> ARSCNView {
    let arView = ARSCNView(frame: .zero)
    arView.session.delegate = context.coordinator

    // Pass the ARSession to the manager
    manager.setARSession(arView.session)

    return arView
}
```

#### 2. CalibrationManager.swift (Line 83-88)

**Added new method:**
```swift
// MARK: - AR Session Management

/// Set the AR session from the ARSCNView
func setARSession(_ session: ARSession) {
    self.arSession = session
}
```

#### 3. CalibrationManager.swift (Line 135-156)

**Before:**
```swift
private func setupARSession() {
    arSession = ARSession()  // Creates NEW session
    arSession?.delegate = self

    let configuration = ARWorldTrackingConfiguration()
    configuration.sceneReconstruction = .meshWithClassification
    configuration.frameSemantics = .sceneDepth

    arSession?.run(configuration)
}
```

**After:**
```swift
private func setupARSession() {
    // Use the ARSession provided by ARSCNView
    guard let arSession = arSession else {
        print("⚠️ ARSession not set - call setARSession() first")
        state = .failed(.lidarUnavailable)
        return
    }

    guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
        state = .failed(.lidarUnavailable)
        return
    }

    let configuration = ARWorldTrackingConfiguration()
    configuration.sceneReconstruction = .meshWithClassification
    configuration.frameSemantics = .sceneDepth

    // Run configuration on the EXISTING session
    arSession.run(configuration)

    print("✅ AR Session configured and running")
}
```

#### 4. CalibrationManager.swift (Line 158-161)

**Updated cleanup:**
```swift
private func stopARSession() {
    // Pause the AR session (but don't nil it since we don't own it)
    arSession?.pause()
}
```

## How It Works Now

1. **ARViewContainerForCalibration** creates ARSCNView with its native ARSession
2. Immediately passes this session to CalibrationManager via `setARSession()`
3. When user clicks "Kalibrierung starten", `startCalibration()` is called
4. `setupARSession()` configures and runs the **existing** ARSession (not a new one)
5. Camera feed displays correctly because the visible ARSCNView and the running ARSession are now the **same instance**

## Expected Behavior After Fix

✅ Onboarding screen displays correctly
✅ User clicks "Kalibrierung starten"
✅ **AR camera feed is visible** (previously black)
✅ Blue guide frame overlays the camera feed
✅ Feedback messages appear at top
✅ Progress bar shows at bottom
✅ Credit card detection starts working

## Testing Steps

1. Build and run on iPhone with LiDAR (iPhone 12 Pro or newer)
2. Grant camera permissions when prompted
3. Complete onboarding steps
4. Click "Kalibrierung starten"
5. **Verify camera feed is visible** - should show live camera view
6. Place credit card on table
7. Follow on-screen guidance for calibration

## Technical Details

### Architecture Pattern
This follows the proper iOS pattern for ARKit + SwiftUI integration:
- UIViewRepresentable wraps ARSCNView
- ARSession is owned by the ARSCNView (UIKit)
- Manager classes receive a reference to the session (don't create their own)
- Single source of truth for AR state

### Why This Fix Works
- ARSCNView automatically displays what its `session` sees
- By configuring the view's own session (instead of a separate one), the view displays the camera feed
- All AR frames flow through the same session delegate chain
- No duplicate AR sessions competing for camera access

## Build Status

✅ **Build Succeeded** (verified 2025-11-22)

No errors or warnings related to AR session management.
