//
//  PoissonBridge.mm
//  3D
//
//  Objective-C++ implementation bridging Swift to C++
//

#import "PoissonBridge.h"
#include "PoissonWrapper.hpp"
#include <memory>
#include <vector>

@implementation PoissonBridge

+ (PoissonConfig)defaultConfig {
    PoissonConfig config;
    config.depth = 9;
    config.samplesPerNode = 1.5f;
    config.scale = 1.1f;
    config.enableDensityTrimming = true;
    config.trimPercentage = 0.05f;
    config.verbose = true;
    return config;
}

+ (PoissonResult*)reconstructSurfaceWithPoints:(const float*)points
                                       normals:(const float*)normals
                                    pointCount:(NSUInteger)count
                                        config:(PoissonConfig)config {

    @autoreleasepool {
        // Allocate result structure
        PoissonResult* result = (PoissonResult*)malloc(sizeof(PoissonResult));
        memset(result, 0, sizeof(PoissonResult));

        try {
            // Convert to C++ types
            mesh::OrientedPointCloud pointCloud;
            pointCloud.points.reserve(count);
            pointCloud.normals.reserve(count);

            for (NSUInteger i = 0; i < count; ++i) {
                mesh::Point3D point(
                    points[i * 3 + 0],
                    points[i * 3 + 1],
                    points[i * 3 + 2]
                );

                mesh::Point3D normal(
                    normals[i * 3 + 0],
                    normals[i * 3 + 1],
                    normals[i * 3 + 2]
                );

                pointCloud.addPoint(point, normal);
            }

            // Create C++ wrapper and config
            mesh::PoissonWrapper wrapper;
            mesh::PoissonWrapper::Configuration cppConfig;
            cppConfig.depth = config.depth;
            cppConfig.samplesPerNode = config.samplesPerNode;
            cppConfig.scale = config.scale;
            cppConfig.enableDensityTrimming = config.enableDensityTrimming;
            cppConfig.trimPercentage = config.trimPercentage;
            cppConfig.verbose = config.verbose;

            // Call C++ reconstruction
            auto meshData = wrapper.reconstruct(pointCloud, cppConfig);

            // Copy results to malloc'd buffers (ownership transfer to caller)
            result->vertexCount = meshData.vertexCount();
            result->indexCount = meshData.indices.size();

            if (!meshData.vertices.empty()) {
                result->vertices = (float*)malloc(meshData.vertices.size() * sizeof(float));
                memcpy(result->vertices, meshData.vertices.data(), meshData.vertices.size() * sizeof(float));
            }

            if (!meshData.indices.empty()) {
                result->indices = (uint32_t*)malloc(meshData.indices.size() * sizeof(uint32_t));
                memcpy(result->indices, meshData.indices.data(), meshData.indices.size() * sizeof(uint32_t));
            }

            if (!meshData.normals.empty()) {
                result->normals = (float*)malloc(meshData.normals.size() * sizeof(float));
                memcpy(result->normals, meshData.normals.data(), meshData.normals.size() * sizeof(float));
            }

            result->success = true;
            result->errorMessage = nil;

            return result;

        } catch (const std::exception& e) {
            result->success = false;
            result->errorMessage = [NSString stringWithUTF8String:e.what()];
            return result;
        }
    }
}

+ (void)cleanupResult:(PoissonResult*)result {
    if (result->vertices) {
        free(result->vertices);
        result->vertices = nullptr;
    }
    if (result->indices) {
        free(result->indices);
        result->indices = nullptr;
    }
    if (result->normals) {
        free(result->normals);
        result->normals = nullptr;
    }
    free(result);
}

@end
