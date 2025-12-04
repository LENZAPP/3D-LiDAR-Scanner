//
//  PoissonBridge.h
//  3D
//
//  Objective-C bridge for Poisson Surface Reconstruction
//  Pure C/Objective-C header (Swift-compatible, no C++)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Result structure for Poisson reconstruction (C-compatible)
typedef struct {
    float* _Nullable vertices;      // Flat array: [x0,y0,z0, x1,y1,z1, ...]
    uint32_t* _Nullable indices;    // Triangle indices: [i0,i1,i2, ...]
    float* _Nullable normals;       // Per-vertex normals (optional)
    NSUInteger vertexCount;
    NSUInteger indexCount;
    bool success;
    NSString* _Nullable errorMessage;
} PoissonResult;

/// Configuration for Poisson reconstruction
typedef struct {
    int depth;                      // Octree depth (8-10)
    float samplesPerNode;           // Samples per node
    float scale;                    // Point weight scale
    bool enableDensityTrimming;     // Trim low-density regions
    float trimPercentage;           // Trim percentage
    bool verbose;                   // Print debug info
} PoissonConfig;

/// Objective-C++ Bridge for Poisson Surface Reconstruction
@interface PoissonBridge : NSObject

/// Reconstruct surface from oriented point cloud
+ (PoissonResult* _Nullable)reconstructSurfaceWithPoints:(const float* _Nonnull)points
                                                 normals:(const float* _Nonnull)normals
                                              pointCount:(NSUInteger)count
                                                  config:(PoissonConfig)config;

/// Clean up malloc'd memory from PoissonResult
+ (void)cleanupResult:(PoissonResult* _Nonnull)result;

/// Create default configuration
+ (PoissonConfig)defaultConfig;

@end

NS_ASSUME_NONNULL_END
