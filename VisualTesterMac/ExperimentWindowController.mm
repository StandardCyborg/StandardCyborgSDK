//
//  ExperimentViewController.m
//  VisualTesterMac
//
//  Created by Aaron Thompson on 6/10/19.
//  Copyright © 2019 Standard Cyborg. All rights reserved.
//

#import "ExperimentWindowController.h"
#import <iostream>
#import <string>
#import <SceneKit/SceneKit.h>
#import <standard_cyborg/sc3d/PerspectiveCamera.hpp>
#import <StandardCyborgFusion/GeometryHelpers.hpp>
#import <nlohmann/json.hpp>
#import <StandardCyborgFusion/PointCloudIO.hpp>
#import <StandardCyborgFusion/SCLandmark3D.h>
#import <StandardCyborgFusion/StandardCyborgFusion.h>

@implementation ExperimentWindowController {
    IBOutlet SCNView *_sceneView;
    IBOutlet NSStackView *_controlsStackView;
    NSArray *_buttons;
}

using namespace standard_cyborg;
using JSON = nlohmann::json;

- (void)configureExperiment
{
    NSButton *doSomething = [NSButton buttonWithTitle:@"Do Something" target:self action:@selector(doSomething)];
    [doSomething setKeyEquivalent:@"\n"];
    [self setButtons:@[doSomething]];
}

- (sc3d::PerspectiveCamera)readIntrinsicsFromFile:(NSString *)filename withExtension:(NSString *)extension
{
    NSString *intrinsicsData = [NSString stringWithContentsOfFile:intrinsicsPath encoding:NSUTF8StringEncoding error:nil];
    
    return PointCloudIO::PerspectiveCameraFromJSON(JSON::parse(std::string([intrinsicsData UTF8String]))["camera_intrinsics"]);
}

- (std::vector<simd_float4x4>)readExtrinsicsFromFile:(NSString *)filemname withExtension:(NSString *)extension
{
    NSString *extrinsicsPath = [[NSBundle mainBundle] pathForResource:@"extrinsics" ofType:@"json" inDirectory:@""];
    NSString *extrinsicsData = [NSString stringWithContentsOfFile:extrinsicsPath encoding:NSUTF8StringEncoding error:nil];
    
    auto extrinsics = JSON::parse(std::string([extrinsicsData UTF8String]))["extrinsicMatrices"];

    std::vector<simd_float4x4> extrinsicMatrices;
    
    for (auto it = extrinsics.begin(); it != extrinsics.end(); it++) {
        const std::vector<float>& m = *it;
        extrinsicMatrices.push_back(simd_float4x4({
            .columns[0] = {m[0], m[1], m[2], m[3]},
            .columns[1] = {m[4], m[5], m[6], m[7]},
            .columns[2] = {m[8], m[9], m[10], m[11]},
            .columns[3] = {m[12], m[13], m[14], m[15]}
        }));
    }
    
    return extrinsicMatrices;
}


// END YOUR CODE HERE

- (void)windowDidLoad
{
    _controlsStackView.wantsLayer = YES;
    _controlsStackView.layer.backgroundColor = [[NSColor darkGrayColor] CGColor];
    
    [self configureExperiment];
}

- (void)setButtons:(NSArray *)buttons
{
    for (NSButton *button in _buttons) {
        [_controlsStackView removeArrangedSubview:button];
    }
    
    _buttons = [buttons copy];
    
    for (NSButton *button in _buttons) {
        [_controlsStackView addArrangedSubview:button];
    }
}

@end

