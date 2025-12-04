//
//  MeshFixBridge.h
//  3D
//
//  Objective-C bridge for MeshFix topological repair
//  Pure C/Objective-C header (Swift-compatible, no C++)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Result structure for MeshFix repair (C-compatible)
typedef struct {
    float* _Nullable vertices;      // Flat array: [x0,y0,z0, x1,y1,z1, ...]
    uint32_t* _Nullable indices;    // Triangle indices: [i0,i1,i2, ...]
    NSUInteger vertexCount;
    NSUInteger indexCount;
    int holesFilledCount;
    bool success;
    NSString* _Nullable errorMessage;
} MeshFixResult;

/// Configuration for MeshFix
typedef struct {
    int maxHoleSize;                // Maximum hole size to fill (edges)
    bool removeNonManifold;         // Remove non-manifold edges
    bool removeSmallComponents;     // Remove disconnected components
    int minComponentSize;           // Minimum vertices in component
    bool verbose;                   // Print debug info
} MeshFixConfig;

/// Objective-C++ Bridge for MeshFix
@interface MeshFixBridge : NSObject

/// Repair mesh topology
+ (MeshFixResult* _Nullable)repairMeshWithVertices:(const float* _Nonnull)vertices
                                      vertexCount:(NSUInteger)vertexCount
                                          indices:(const uint32_t* _Nonnull)indices
                                       indexCount:(NSUInteger)indexCount
                                           config:(MeshFixConfig)config;

/// Clean up malloc'd memory from MeshFixResult
+ (void)cleanupResult:(MeshFixResult* _Nonnull)result;

/// Create default configuration
+ (MeshFixConfig)defaultConfig;

@end

NS_ASSUME_NONNULL_END
