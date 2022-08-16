//
//  SCPointCloud_Private.h
//  StandardCyborgFusion
//
//  Created by Ricky Reusser on 12/17/18.
//  Copyright © 2018 Standard Cyborg. All rights reserved.
//

#import <StandardCyborgFusion/SCPointCloud.h>

@interface SCPointCloud (Private)

- (instancetype)initWithSurfelData:(NSData *)data gravity:(simd_float3)gravity;

// TODO: Flesh these out, then expose them
- (void)lockForReading;
- (void)unlockForReading;
- (void)performWithReadLock:(dispatch_block_t)block;

@end

@interface SCPointCloud ()

@property (nonatomic) simd_float3x3 intrinsicMatrix;
@property (nonatomic) simd_float2 intrinsicMatrixReferenceDimensions;
@property (nonatomic) simd_float2 depthFrameSize;

@end
