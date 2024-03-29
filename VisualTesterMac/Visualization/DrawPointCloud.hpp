//
//  DrawPointCloud.hpp
//  VisualTesterMac
//
//  Created by Ricky Reusser on 8/31/18.
//  Copyright © 2018 Standard Cyborg. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MetalVisualizationEngine.hpp"

@interface DrawPointCloud : NSObject <MetalVisualization>

@property (nonatomic) BOOL colorByNormals;

@end
