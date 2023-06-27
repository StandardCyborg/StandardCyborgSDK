//
//  ViewController.mm
//  VisualTesterMac
//
//  Created by Aaron Thompson on 7/12/18.
//  Copyright © 2018 Standard Cyborg. All rights reserved.
//

#import <SceneKit/SceneKit.h>
#import <standard_cyborg/sc3d/Geometry.hpp>
#import <standard_cyborg/math/Mat3x4.hpp>
#import <standard_cyborg/math/Mat3x3.hpp>
#import <standard_cyborg/scene_graph/SceneGraph.hpp>
#import <StandardCyborgFusion/GeometryHelpers.hpp>
#import <StandardCyborgFusion/PointCloudIO.hpp>
#import <StandardCyborgFusion/SCOfflineReconstructionManager.h>
#import <StandardCyborgFusion/SCOfflineReconstructionManager_Private.h>
#import <StandardCyborgFusion/SCPointCloud+Geometry.h>
#import <StandardCyborgFusion/StandardCyborgFusion.h>
#import <StandardCyborgFusion/Surfel.hpp>
#import <standard_cyborg/io/gltf/SceneGraphFileIO_GLTF.hpp>
#import <stdlib.h>
#import <fstream>

#import "AppDelegate.h"
#import "CameraControl.h"
#import "ClearPass.hpp"
#import "DrawAxes.hpp"
#import "DrawCorrespondences.hpp"
#import "DrawPointCloud.hpp"
#import "DrawRawDepths.hpp"
#import "DrawSurfelIndexMap.hpp"
#import "EigenSceneKitHelpers.hpp"
#import "ViewController.h"
#import <nlohmann/json.hpp>

NS_ASSUME_NONNULL_BEGIN

using namespace standard_cyborg;

static SCNVector3 SurfelsBoundingBoxCenter(const Surfels& surfels);

@interface ViewController () <CameraControlDelegate, SCOfflineReconstructionManagerDelegate>
@end

@implementation ViewController
{
    IBOutlet __weak NSButton *_assimilateNextButton;
    __weak IBOutlet SCNView *sceneView;
    IBOutlet __weak NSButton *_assimilateAllButton;
    IBOutlet __weak NSButton *_resetButton;
    IBOutlet __weak NSButton *_openDirectoryButton;
    IBOutlet __weak NSTextField *_frameIndexField;
    
    IBOutlet __weak NSSliderCell *_icpPercentSlider;
    IBOutlet __weak NSSliderCell *_pbfMinDepthSlider;
    IBOutlet __weak NSSliderCell *_pbfMaxDepthSlider;
    
    IBOutlet __weak NSTextFieldCell *_icpPercentLabel;
    IBOutlet __weak NSTextFieldCell *_pbfMinDepthLabel;
    IBOutlet __weak NSTextFieldCell *_pbfMaxDepthLabel;
    
    dispatch_queue_t _processingQueue;
    NSOperation *_processingOperation;
    NSString *_dataDirectoryPath;
    NSInteger _nextFrameIndex;
    
    id<MTLDevice> _metalDevice;
    id<MTLCommandQueue> _algorithmCommandQueue;
    id<MTLCommandQueue> _visualizationCommandQueue;
    SCOfflineReconstructionManager *_reconstructionManager;
    
    NSMutableDictionary *_textureDebugWindowsByTitle;
    MetalVisualizationEngine *_visualizationEngine;
    DrawRawDepths *_drawRawDepths;
    DrawSurfelIndexMap *_drawSurfelIndexMap;
    CameraControl *_cameraControl;
    BOOL _hasCenter;
    ICPResult _lastICPResult;
    BOOL _drawsCorrespondences;
}

// MARK: - IBActions

- (IBAction)_openDirectory:(NSButton *)sender {
    NSOpenPanel *openDialog = [NSOpenPanel openPanel];
    [openDialog setCanChooseFiles:NO];
    [openDialog setAllowsMultipleSelection:NO];
    [openDialog setCanChooseDirectories:YES];
    
    if ([openDialog runModal] == NSModalResponseOK) {
        NSArray* dirs = [openDialog URLs];
        NSAssert([dirs count] == 1, @"You must select one directory");
        _dataDirectoryPath = [[dirs objectAtIndex:0] path];
        [[NSUserDefaults standardUserDefaults] setObject:_dataDirectoryPath forKey:@"LastDataPath"];
        [self _reset:nil];
    }
}

- (IBAction)_assimilateNext:(nullable id)sender
{
    if ([_processingOperation isExecuting]) { return; }
    
    [self _startProcessingWithContinuation:NO elapsedTime:0];
}

- (IBAction)_assimilateAll:(nullable id)sender
{
    if ([_processingOperation isExecuting]) { return; }
    
    [self _startProcessingWithContinuation:YES elapsedTime:0];
}

- (IBAction)_setPBFMinDepth:(NSSliderCell *)sender {
    [_reconstructionManager setMinDepth:[sender floatValue]];
    [self _updateUIControls];
}

- (IBAction)_setPBFMaxDepth:(NSSliderCell *)sender {
    [_reconstructionManager setMaxDepth:[sender floatValue]];
    [self _updateUIControls];
}

- (IBAction)_setICPDownsamplePercent:(NSSliderCell *)sender
{
    [_reconstructionManager setICPDownsampleFraction:[sender floatValue] / 100.0f];
    [self _updateUIControls];
}

- (IBAction)_reset:(nullable id)sender
{
    _nextFrameIndex = 0;
    _frameIndexField.integerValue = _nextFrameIndex;
    _hasCenter = NO;
    
    [self _resetPBFModel];
    [self _loadMotionData];

    //_lastICPResult.sourceVertices = nullptr;
    //_lastICPResult.targetVertices = nullptr;
    
    // Assimilate the first frame
    [self _startProcessingWithContinuation:NO elapsedTime:0];
}

- (IBAction)_exportUSDA:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:@"Export USDA"];
    [panel setNameFieldStringValue:@"Scan.usda"];
    [panel setAllowedFileTypes:@[@"usda"]];
    [panel setExtensionHidden:NO];
    [panel setShowsTagField:NO];
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        
        NSString *USDAPath = [[panel URL] path];
        
        [_reconstructionManager writePointCloudToUSDAFile:USDAPath];
    }];
}

- (IBAction)_exportPLY:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:@"Export PLY"];
    [panel setNameFieldStringValue:@"Scan.ply"];
    [panel setAllowedFileTypes:@[@"ply"]];
    [panel setExtensionHidden:NO];
    [panel setShowsTagField:NO];
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        
        NSString *PLYPath = [[panel URL] path];
        
        [_reconstructionManager writePointCloudToPLYFile:PLYPath];
    }];
}

- (IBAction)_exportPosesToJSON:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:@"Export Poses to JSON"];
    [panel setNameFieldStringValue:@"poses.json"];
    [panel setAllowedFileTypes:@[@"json"]];
    [panel setExtensionHidden:NO];
    [panel setShowsTagField:NO];
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        
        NSString *JSONPath = [[panel URL] path];
        
        const std::vector<PBFAssimilatedFrameMetadata> metadata = [_reconstructionManager assimilatedFrameMetadata];
        nlohmann::json poses;
        for (const PBFAssimilatedFrameMetadata& datum : metadata) {
            nlohmann::json pose;
            pose["merged"] = datum.isMerged;
            pose["timestamp"] = datum.timestamp;

            std::vector<std::vector<float>> rows;
            for (int i = 0; i < 3; i++) {
                std::vector<float> row;
                for (int j = 0; j < 4; j++) {
                    row.push_back(datum.viewMatrix(i, j));
                }
                rows.push_back(row);
            }
            
            pose["surfel_count"] = datum.surfelCount;
            pose["extrinsic_matrix"] = rows;
            
            poses["poses"].push_back(pose);
        }
        
        std::string path ([JSONPath UTF8String]);
        std::ofstream poseOutput(path);
        poseOutput << poses.dump(2);
        poseOutput.close();
    }];
}

- (IBAction)_exportScenegraph:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:@"Export Scenegraph"];
    [panel setNameFieldStringValue:@"scan.gltf"];
    [panel setAllowedFileTypes:@[@"gltf"]];
    [panel setExtensionHidden:NO];
    [panel setShowsTagField:NO];
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        
        NSString *GLTFPath = [[panel URL] path];
        
        sc3d::Geometry geometry {};
        SCPointCloud* pointCloud = [_reconstructionManager buildPointCloud];
        
        [pointCloud toGeometry:geometry];
        
        using namespace scene_graph;
        std::shared_ptr<Node> rootNode = std::make_shared<Node>("Root");
        std::shared_ptr<GeometryNode> geometryNode(new GeometryNode("Point cloud reconstruction"));
        std::shared_ptr<CoordinateFrameNode> axesNode (new CoordinateFrameNode("axes"));
        geometryNode->getGeometry().copy(geometry);
        rootNode->setTransform(toMat3x4([_reconstructionManager gravityAlignedAxes]).inverse());
        
        rootNode->appendChildren({geometryNode, axesNode});

        io::gltf::WriteSceneGraphToGltf({rootNode}, std::string([GLTFPath UTF8String]));
    }];
}

// MARK: - NSViewController

- (void)viewDidLoad
{
    _processingQueue = dispatch_queue_create("ICP", NULL);
    _textureDebugWindowsByTitle = [[NSMutableDictionary alloc] init];
    
    NSArray<id<MTLDevice>>* allDevices = MTLCopyAllDevices();
    _metalDevice = [allDevices lastObject];
    NSLog(@"GPU: %@", [_metalDevice name]);
    
    _algorithmCommandQueue = [_metalDevice newCommandQueue];
    _algorithmCommandQueue.label = @"ViewController._algorithmCommandQueue";
    
    _visualizationCommandQueue = [_metalDevice newCommandQueue];
    _visualizationCommandQueue.label = @"ViewController._visualizationCommandQueue";
    
    _reconstructionManager = [[SCOfflineReconstructionManager alloc] initWithDevice:_metalDevice
                                                                       commandQueue:_algorithmCommandQueue
                                                                     maxThreadCount:(int)[[NSProcessInfo processInfo] processorCount]];
  
    
    
    _reconstructionManager.delegate = self;
    
    id<MTLLibrary> library = [_metalDevice newDefaultLibrary];
    
    ClearPass *clearPass = [[ClearPass alloc] initWithDevice:_metalDevice library:library];
    DrawPointCloud *drawPointCloud = [[DrawPointCloud alloc] initWithDevice:_metalDevice library:library];
    DrawCorrespondences *drawCorrespondences = [[DrawCorrespondences alloc] initWithDevice:_metalDevice library:library];
    DrawAxes *drawAxes = [[DrawAxes alloc] initWithDevice:_metalDevice library:library];
    NSArray *visualizations = @[clearPass, drawPointCloud, drawAxes, drawCorrespondences];
    
    _visualizationEngine = [[MetalVisualizationEngine alloc] initWithDevice:_metalDevice
                                                               commandQueue:_visualizationCommandQueue
                                                                    library:library
                                                             visualizations:visualizations];
    _drawRawDepths = [[DrawRawDepths alloc] initWithDevice:_metalDevice
                                              commandQueue:_visualizationCommandQueue
                                                   library:library];
    _drawSurfelIndexMap = [[DrawSurfelIndexMap alloc] initWithDevice:_metalDevice
                                                        commandQueue:_visualizationCommandQueue
                                                             library:library];
    
    _cameraControl = [[CameraControl alloc] init];
    _cameraControl.delegate = self;
    
    NSString *lastDataPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastDataPath"];
    if ([lastDataPath length] > 0) {
        _dataDirectoryPath = lastDataPath;
        NSLog(@"Using previously opened data directory \"%@\"\n", lastDataPath);
        [self _reset:nil];
    }
    
    [self _updateUIControls];
}

// MARK: - CameraControlDelegate

- (void)cameraDidMove:(CameraControl *)control
{
    [self _redraw];
}

// MARK: - Internal

- (void)_loadMotionData
{
    NSLog(@"motion data");
    if ([[NSFileManager defaultManager] fileExistsAtPath:_dataDirectoryPath] == NO) {
        NSLog(@"No directory found at \"%@\"\n", _dataDirectoryPath);
        return;
    }
    
    NSString *filePath = [_dataDirectoryPath stringByAppendingFormat:@"/motion-data.json"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath] == NO) {
        NSLog(@"No file exists at path: \"%@\"\n", filePath);
        return;
    }
    [_reconstructionManager setMotionDataPath:filePath];
}

- (NSString * _Nullable)_loadNextFramePath
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:_dataDirectoryPath] == NO) {
        NSLog(@"No directory found at \"%@\"\n", _dataDirectoryPath);
        return nil;
    }
    
    ++_nextFrameIndex;
    
    NSString *filePath = [_dataDirectoryPath stringByAppendingFormat:@"/frame-%03d.ply", (int)(_nextFrameIndex)];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath] == NO) {
        NSLog(@"No file exists at path: \"%@\"\n", filePath);
        return nil;
    }
    
    _frameIndexField.integerValue = _nextFrameIndex;
    
    return filePath;
}

- (void)_startProcessingWithContinuation:(BOOL)assimilateNextOnCompletion elapsedTime:(NSTimeInterval)elapsedTime
{
    [_assimilateNextButton setEnabled:NO];
    [_assimilateAllButton setEnabled:NO];
    [_resetButton setEnabled:NO];
    
    // Load the next cloud from the queue
    NSString *nextFramePath = [self _loadNextFramePath];
    
    if (nextFramePath == nil) {
        [_reconstructionManager finalize];
        [self _finishedProcessing];
        NSLog(@"Completed %d frames in %.3f seconds (%.4f FPS)",
              (int)_nextFrameIndex, elapsedTime, _nextFrameIndex / elapsedTime);
        return;
    }
    
    __weak ViewController *weakSelf = self;
    
    dispatch_async(_processingQueue, ^{
        _processingOperation = [NSBlockOperation blockOperationWithBlock:^{
            __strong ViewController *strongSelf = weakSelf;
            if (strongSelf == nil) { return; }
            if ([strongSelf->_processingOperation isCancelled]) { return; }
            
            CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
            
            [strongSelf->_reconstructionManager accumulateFromBPLYWithPath:nextFramePath];

            CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf _finishedProcessing];
                
                if (assimilateNextOnCompletion) {
                    [weakSelf _startProcessingWithContinuation:YES elapsedTime:elapsedTime + endTime - startTime];
                } else {
                    NSLog(@"Completed 1 frame in %.3f seconds", endTime - startTime);
                }
            });
        }];
        
        [_processingOperation setName:@"ICP"];
        [_processingOperation setQualityOfService:NSQualityOfServiceUserInitiated];
        [_processingOperation start];
    });
}

- (void)_resetPBFModel
{
    [_reconstructionManager reset];
    
    [self _redraw];
}

- (void)_finishedProcessing
{
    //_lastICPResult.sourceVertices = nullptr;//
    //_lastICPResult.targetVertices = nullptr;
    
    [_assimilateNextButton setEnabled:YES];
    [_assimilateAllButton setEnabled:YES];
    [_resetButton setEnabled:YES];
    
    [self _redraw];
}

- (void)_updateUIControls
{
    [_pbfMinDepthLabel setStringValue:[NSString stringWithFormat:@"Min Depth: %.3f", [_reconstructionManager minDepth]]];
    [_pbfMinDepthSlider setFloatValue:_reconstructionManager.minDepth];
    
    [_pbfMaxDepthLabel setStringValue:[NSString stringWithFormat:@"Max Depth: %.3f", [_reconstructionManager maxDepth]]];
    [_pbfMaxDepthSlider setFloatValue:_reconstructionManager.maxDepth];
    
    float icpDownsamplePercentage = [_reconstructionManager icpDownsampleFraction] * 100.0f;
    [_icpPercentLabel setStringValue:[NSString stringWithFormat:@"ICP Percentage: %.1f", icpDownsamplePercentage]];
    [_icpPercentSlider setFloatValue:icpDownsamplePercentage];
}

- (id<CAMetalDrawable>)_nextDrawableForWindowWithTitle:(NSString *)title
                                                  size:(CGSize)size
                                         configuration:(void (^_Nullable)(NSWindow *))configuration
{
    NSWindow *window = _textureDebugWindowsByTitle[title];
    
    if (window == nil) {
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
        [view setWantsLayer:YES];
        
        CAMetalLayer *metalLayer = [[CAMetalLayer alloc] init];
        [metalLayer setBounds:view.bounds];
        [metalLayer setDevice:_metalDevice];
        [metalLayer setFramebufferOnly:NO];
        [view setLayer:metalLayer];
        
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(_textureDebugWindowsByTitle.count * view.bounds.size.width + 250,
                                                                  _textureDebugWindowsByTitle.count * view.bounds.size.height + 100,
                                                                  view.bounds.size.width,
                                                                  view.bounds.size.height)
                                             styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
        [window setTitle:title];
        [window setContentView:view];
        [window orderBack:nil];
        
        _textureDebugWindowsByTitle[title] = window;
        
        if (configuration != nil) { configuration(window); }
    } else {
        NSRect frame = window.frame;
        frame.size = size;
        [window setFrame:frame display:NO];
    }
    
    CAMetalLayer *metalLayer = (CAMetalLayer *)[[window contentView] layer];
    metalLayer.drawableSize = size;
    
    return [metalLayer nextDrawable];
}

- (void)_redraw
{
    const Surfels& surfels = [_reconstructionManager surfels];
    auto rawFrame = [_reconstructionManager lastRawFrame];
    CGSize rawFrameSize = rawFrame == nullptr ? CGSizeZero : CGSizeMake(rawFrame->width, rawFrame->height);
    const std::vector<uint32_t>& surfelIndexMap = [_reconstructionManager surfelIndexMap];
    id<MTLTexture> surfelIndexMapTexture = [_reconstructionManager surfelIndexMapTexture];
    CGSize surfelIndexMapSize = surfelIndexMapTexture == nil ? CGSizeMake(360, 240) : CGSizeMake(surfelIndexMapTexture.width, surfelIndexMapTexture.height);
    
    if (!_hasCenter && surfels.size() > 0) {
        SCNVector3 center = SurfelsBoundingBoxCenter(surfels);
        [_cameraControl setCenterX:center.x centerY:center.y centerZ:center.z];
        _hasCenter = YES;
    }
    
    id<CAMetalDrawable> drawable = [self _nextDrawableForWindowWithTitle:@"Point Cloud Debug"
                                                                    size:CGSizeMake(900, 900)
                                                           configuration:^(NSWindow *window) {
                                                               [_cameraControl installInView:window.contentView];
                                                           }];
    
    [_visualizationEngine renderSurfels:surfels
                              icpResult:_lastICPResult
                             viewMatrix:[_cameraControl viewMatrix]
                       projectionMatrix:[_cameraControl projectionMatrix]
                           intoDrawable:drawable];
    
    id<CAMetalDrawable> rawDepthsDrawable = [self _nextDrawableForWindowWithTitle:@"Raw Depths"
                                                                             size:rawFrameSize
                                                                    configuration:^(NSWindow *window){}];
    [_drawRawDepths draw:rawFrame into:rawDepthsDrawable];

    id<CAMetalDrawable> mapDrawable = [self _nextDrawableForWindowWithTitle:@"Surfel Index Map"
                                                                       size:surfelIndexMapSize
                                                              configuration:^(NSWindow *window){}];
    [_drawSurfelIndexMap draw:surfelIndexMap into:mapDrawable];
}

// MARK: - SCOfflineReconstructionManagerDelegate

- (void)reconstructionManager:(SCOfflineReconstructionManager *)manager didIterateICPWithResult:(ICPResult)result
{
    if (!_drawsCorrespondences) { return; }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _lastICPResult = result;

        [self _redraw];
    });
}

@end

static SCNVector3 SurfelsBoundingBoxCenter(const Surfels& surfels)
{
    float minX = FLT_MAX, maxX = -FLT_MAX;
    float minY = FLT_MAX, maxY = -FLT_MAX;
    float minZ = FLT_MAX, maxZ = -FLT_MAX;
    
    for (auto& surfel : surfels) {
        minX = MIN(surfel.position.x(), minX);
        maxX = MAX(surfel.position.x(), maxX);
        minY = MIN(surfel.position.y(), minY);
        maxY = MAX(surfel.position.y(), maxY);
        minZ = MIN(surfel.position.z(), minZ);
        maxZ = MAX(surfel.position.z(), maxZ);
    }
    
    float centerX = 0.5f * (maxX - minX) + minX;
    float centerY = 0.5f * (maxY - minY) + minY;
    float centerZ = 0.5f * (maxZ - minZ) + minZ;
    
    return SCNVector3Make(centerX, centerY, centerZ);
}

NS_ASSUME_NONNULL_END
