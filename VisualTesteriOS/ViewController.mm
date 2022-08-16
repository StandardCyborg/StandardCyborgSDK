//
//  ViewController.mm
//  VisualTesteriOS
//
//  Created by Aaron Thompson on 8/11/18.
//  Copyright © 2018 Standard Cyborg. All rights reserved.
//

#import <SceneKit/SceneKit.h>
#import <StandardCyborgFusion/StandardCyborgFusion.h>
#import <nlohmann/json.hpp>

#import <cstdlib>
#import <fstream>
#import <iomanip>
#import <sstream>

#import "AppDelegate.h"
#import "BenchmarkUtils.hpp"
#import "ViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ViewController {
    __weak IBOutlet UILabel *_statusLabel;
    __weak IBOutlet SCNView *_sceneView;
    __weak IBOutlet UIButton *_playPauseButton;
    
    dispatch_semaphore_t _pauseSemaphore;
    BOOL _shouldSignalUnpause;
}

- (IBAction)playPause:(UIButton *)sender {
    BOOL wasPaused = [sender isSelected];
    
    [sender setSelected:!wasPaused];
    
    if (wasPaused && _shouldSignalUnpause) {
        _shouldSignalUnpause = NO;
        dispatch_semaphore_signal(_pauseSemaphore);
    }
}

// MARK: - UIViewController

- (void)viewDidLoad
{
    _pauseSemaphore = dispatch_semaphore_create(0);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    _statusLabel.text = @"Starting test";
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self _runBenchmarks];
    });
}

// MARK: - Internal

- (NSArray *)_allTestCasePathsInDirectory:(NSString *)testCasesPath
{
    NSMutableArray *allTestCases = [NSMutableArray array];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:testCasesPath] == NO) {
        NSLog(@"Cannot find test cases path %@", testCasesPath);
        exit(1);
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *inputPaths = [fileManager contentsOfDirectoryAtPath:testCasesPath error:NULL];
    
    for (NSString *filename in inputPaths) {
        NSString *fullPath = [testCasesPath stringByAppendingPathComponent:filename];
        
        BOOL isDirectory;
        [fileManager fileExistsAtPath:fullPath
                          isDirectory:&isDirectory];
        
        if (isDirectory) {
            [allTestCases addObject:fullPath];
        }
    }
    
    return allTestCases;
}

- (void)_runBenchmarksAtPath:(NSString *)testCasesPath
{
    NSArray *allTestCasePaths = [self _allTestCasePathsInDirectory:testCasesPath];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _statusLabel.text = [NSString stringWithFormat:@"Benchmarking %d test cases", (int)[allTestCasePaths count]];
    });
    
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    
    std::string jsonString = benchmarkAll(allTestCasePaths, ^(int frameIndex, SCPointCloud *pointCloud) {
        __block BOOL isPaused;
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _setPointCloudNode:[pointCloud buildPointCloudNode]];
            [_statusLabel setText:[NSString stringWithFormat:@"Benchmarking progress %d/%d", frameIndex + 1, (int)[allTestCasePaths count]]];
            
            isPaused = [_playPauseButton isSelected];
            _shouldSignalUnpause = isPaused;
        });
        
        if (isPaused) {
            dispatch_semaphore_wait(_pauseSemaphore, DISPATCH_TIME_FOREVER);
        }
    });
    
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    
    std::istringstream input(jsonString);
    nlohmann::json json;
    input >> json;
    
    for (int ii = 0; ii < json["frameMetadatas"].size(); ++ii) {
        std::string testCaseStr(json["frameMetadatas"][ii]["testCase"]);
        
        printf("%s: runtime: %f, icpIterations %f, failedFrameCounts: %d\naverageCorrespondenceError: %f\npositionChamferDistance: %f\nnormalChamferDistance: %f\ncolorChamferDistance: %f\n",
               testCaseStr.c_str(),
               (float)json["frameMetadatas"][ii]["meanRuntime"],
               (float)json["frameMetadatas"][ii]["averageICPIterations"],
               (int)json["frameMetadatas"][ii]["failedFrameCount"],
               (float)json["frameMetadatas"][ii]["averageCorrespondenceError"],
               (float)json["frameMetadatas"][ii]["positionChamferDistance"],
               (float)json["frameMetadatas"][ii]["normalChamferDistance"],
               (float)json["frameMetadatas"][ii]["colorChamferDistance"]
        );
    }
    
    printf("average stddev failedFrameCount %f +- %f\n",
           (float)json["failedFrameCounts"]["mean"],
           (float)json["failedFrameCounts"]["stdDev"]);
    
    printf("average stddev icpIteration %f +- %f\n",
           (float)json["icpIterations"]["mean"],
           (float)json["icpIterations"]["stdDev"]);
    
    printf("average stddev runtime %f +- %f\n",
           (float)json["runtime"]["mean"],
           (float)json["runtime"]["stdDev"]);
    
    printf("average stddev positionChamferDistance %f +- %f\n",
           (float)json["positionChamferDistance"]["mean"],
           (float)json["positionChamferDistance"]["stdDev"]);

    printf("average stddev normalChamferDistance %f +- %f\n",
           (float)json["normalChamferDistance"]["mean"],
           (float)json["normalChamferDistance"]["stdDev"]);
    
    printf("average stddev colorChamferDistance %f +- %f\n",
           (float)json["colorChamferDistance"]["mean"],
           (float)json["colorChamferDistance"]["stdDev"]);

    printf("average correspondence errors %f +- %f\n",
           (float)json["averageCorrespondenceErrors"]["mean"],
           (float)json["averageCorrespondenceErrors"]["stdDev"]);
    
    std::string gpuString(json["GPU"]);
    printf("GPU: %s\n", gpuString.c_str());
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timingString = [NSString stringWithFormat:@"Finished benchmarking in %f seconds", endTime - startTime];
        NSLog(@"%@", timingString);
        _statusLabel.text = timingString;
    });
}

- (NSString *)_directoryNameForKey:(NSString *)key
{
    return [key stringByReplacingOccurrencesOfString:@"/"
                                          withString:@"-$$-"];
}

- (void)_setPointCloudNode:(SCNNode *)node
{
    SCNNode *existing = [_sceneView.scene.rootNode childNodeWithName:@"PointCloud" recursively:NO];
    [existing removeFromParentNode];
    
    [node setName:@"PointCloud"];
    [node setTransform:SCNMatrix4MakeRotation(M_PI_2, 0, 0, 1)];
    [_sceneView.scene.rootNode addChildNode:node];
}

@end


NS_ASSUME_NONNULL_END
