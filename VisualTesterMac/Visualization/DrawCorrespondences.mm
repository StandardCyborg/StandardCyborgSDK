//
//  DrawCorrespondences.mm
//  VisualTesterMac
//
//  Created by Aaron Thompson on 9/17/18.
//  Copyright © 2018 Standard Cyborg. All rights reserved.
//

#import "DrawCorrespondences.hpp"
#import <simd/simd.h>
#import <GLKit/GLKMatrix4.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DrawCorrespondences {
    id<MTLDevice> _device;
    id<MTLLibrary> _library;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLBuffer> _sharedUniformsBuffer;
    id<MTLDepthStencilState> _depthStencilState;
}

struct Vertex {
    float position[3];
    float color;
};

struct SharedUniforms {
    matrix_float4x4 projection;
    matrix_float4x4 view;
    matrix_float4x4 model;
    
    SharedUniforms(matrix_float4x4 projectionIn, matrix_float4x4 viewIn, matrix_float4x4 modelIn) :
    projection(projectionIn),
    view(viewIn),
    model(modelIn)
    { }
};

// MARK: - MetalVisualization

- (instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library
{
    self = [super init];
    if (self) {
        _device = device;
        
        id<MTLFunction> vertexFunction = [library newFunctionWithName:@"DrawCorrespondencesVertex"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"DrawCorrespondencesFragment"];
        
        MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
        vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
        vertexDescriptor.attributes[0].offset = offsetof(Vertex, position);
        vertexDescriptor.attributes[1].format = MTLVertexFormatFloat;
        vertexDescriptor.attributes[1].offset = offsetof(Vertex, color);
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        vertexDescriptor.layouts[0].stride = sizeof(Vertex);
        
        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.vertexDescriptor = vertexDescriptor;
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        
        MTLDepthStencilDescriptor *depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
        depthStencilDescriptor.depthWriteEnabled = YES;
        _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
        
        NSError *error;
        _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if (_pipelineState == nil) { NSLog(@"Unable to create pipeline state: %@", error); }
        
        _sharedUniformsBuffer = [device newBufferWithLength:sizeof(SharedUniforms)
                                                    options:MTLResourceOptionCPUCacheModeWriteCombined];
        _sharedUniformsBuffer.label = @"DrawCorrespondences._sharedUniformsBuffer";
    }
    return self;
}

- (void)encodeCommandsWithDevice:(id<MTLDevice>)device
                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                         surfels:(const Surfels&)surfels
                       icpResult:(ICPResult&)icpResult
                      viewMatrix:(matrix_float4x4)viewMatrix
                projectionMatrix:(matrix_float4x4)projectionMatrix
                     intoTexture:(id<MTLTexture>)texture
                    depthTexture:(id<MTLTexture>)depthTexture
{
}

// MARK: - Private

- (id<MTLBuffer> _Nullable)_createVertexBufferFromSourceVertices:(std::shared_ptr<Eigen::Matrix3Xf>)sourceVertices
                                                  targetVertices:(std::shared_ptr<Eigen::Matrix3Xf>)targetVertices
                                                  getVertexCount:(size_t *)vertexCountOut
{
    size_t vertexCount = 0;
    id<MTLBuffer> result = nil;
    
    if (sourceVertices != nullptr && targetVertices != nullptr) {
        vertexCount = MIN(sourceVertices->cols(), targetVertices->cols());
    }
    
    if (vertexCount > 0) {
        Vertex vertices[vertexCount * 2];
        
        for (size_t i = 0; i < vertexCount; ++i) {
            Vector3f source = sourceVertices->col(i);
            Vector3f ref = targetVertices->col(i);
            vertices[i * 2 + 0] = { source.x(), source.y(), source.z(), 0 };
            vertices[i * 2 + 1] = { ref.x(), ref.y(), ref.z(), 1 };
        }
        
        result = [_device newBufferWithBytes:(void *)&vertices
                                      length:sizeof(Vertex) * vertexCount * 2
                                     options:MTLResourceCPUCacheModeWriteCombined];
    }
    
    *vertexCountOut = vertexCount * 2;
    return result;
}

- (void)_updateSharedUniformsBufferWithViewMatrix:(matrix_float4x4)view
                                 projectionMatrix:(matrix_float4x4)projection {
    matrix_float4x4 model = matrix_identity_float4x4;
    
    SharedUniforms sharedUniforms(projection, view, model);
    memcpy([_sharedUniformsBuffer contents], &sharedUniforms, sizeof(SharedUniforms));
}

@end

NS_ASSUME_NONNULL_END
