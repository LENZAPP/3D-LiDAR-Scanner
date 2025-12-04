//
//  MeshFixBridge.mm
//  3D
//
//  Objective-C++ implementation bridging Swift to C++ MeshFix
//

#import "MeshFixBridge.h"
#include "MeshFixWrapper.hpp"
#include <memory>
#include <vector>

@implementation MeshFixBridge

+ (MeshFixConfig)defaultConfig {
    MeshFixConfig config;
    config.maxHoleSize = 100;
    config.removeNonManifold = true;
    config.removeSmallComponents = true;
    config.minComponentSize = 10;
    config.verbose = true;
    return config;
}

+ (MeshFixResult*)repairMeshWithVertices:(const float*)vertices
                            vertexCount:(NSUInteger)vertexCount
                                indices:(const uint32_t*)indices
                             indexCount:(NSUInteger)indexCount
                                 config:(MeshFixConfig)config {

    @autoreleasepool {
        // Allocate result structure
        MeshFixResult* result = (MeshFixResult*)malloc(sizeof(MeshFixResult));
        memset(result, 0, sizeof(MeshFixResult));

        try {
            // Convert to C++ mesh data
            mesh::MeshData input;

            // Copy vertices
            input.vertices.reserve(vertexCount * 3);
            for (NSUInteger i = 0; i < vertexCount * 3; ++i) {
                input.vertices.push_back(vertices[i]);
            }

            // Copy indices
            input.indices.reserve(indexCount);
            for (NSUInteger i = 0; i < indexCount; ++i) {
                input.indices.push_back(indices[i]);
            }

            // Create C++ wrapper and config
            mesh::MeshFixWrapper wrapper;
            mesh::MeshFixWrapper::Configuration cppConfig;
            cppConfig.maxHoleSize = config.maxHoleSize;
            cppConfig.removeNonManifold = config.removeNonManifold;
            cppConfig.removeSmallComponents = config.removeSmallComponents;
            cppConfig.minComponentSize = config.minComponentSize;
            cppConfig.verbose = config.verbose;

            // Call C++ repair
            auto meshData = wrapper.repair(input, cppConfig);

            // Copy results to malloc'd buffers
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

            // Estimate holes filled (rough approximation)
            result->holesFilledCount = 0; // TODO: Track in MeshFixWrapper

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

+ (void)cleanupResult:(MeshFixResult*)result {
    if (result->vertices) {
        free(result->vertices);
        result->vertices = nullptr;
    }
    if (result->indices) {
        free(result->indices);
        result->indices = nullptr;
    }
    free(result);
}

@end
