//
//  BenchmarkUtils.mm
//  StandardCyborgFusion
//
//  Created by eric on 2019-10-24.
//  Copyright © 2019 Standard Cyborg. All rights reserved.
//

#include "BenchmarkUtils.hpp"

#include <algorithm>
#include <functional>
#include <iomanip>
#include <numeric>
#include <string>
#include <vector>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <nlohmann/json.hpp>
#import <StandardCyborgFusion/StandardCyborgFusion.h>
#import <StandardCyborgFusion/SCOfflineReconstructionManager.h>
#import <StandardCyborgFusion/SCOfflineReconstructionManager_Private.h>
#import <standard_cyborg/io/ply/GeometryFileIO_PLY.hpp>
#import <UIKit/UIKit.h>

using namespace standard_cyborg;

// Not really geometry, but close enough
static const float kGammaCorrection = 1.0 / 2.2;

static inline float applyGammaCorrection(float x)
{
    return powf(x, kGammaCorrection);
}

struct ReconstructionMetadata {
    float meanRuntime;
    
    float positionChamferDistance;
    float normalChamferDistance;
    float colorChamferDistance;
    
    float averageICPIterations;
    int failedFrameCount;
    float averageCorrespondenceError;
    std::string testCase;
    SCPointCloud *pointCloud;
};

void meanStdDev(const std::vector<float> v, float &mean, float &stdDev)
{
    double sum = std::accumulate(v.begin(), v.end(), 0.0);
    mean = sum / v.size();
    
    std::vector<double> diff(v.size());
    std::transform(v.begin(), v.end(), diff.begin(), [mean](double x) { return x - mean; });
    double sq_sum = std::inner_product(diff.begin(), diff.end(), diff.begin(), 0.0);
    stdDev = std::sqrt(sq_sum / (v.size() - 1.0f));

    if (v.size() == 1) {
        stdDev = 0.0f;
    }
}

// calculate the chamfer distance between two point clouds.
// for more info, see the paper: "PCN: Point Completion Network"
void calcChamferDistance(const sc3d::Geometry &geo0,
                         const sc3d::Geometry &geo1,
                         float& positionChamferDistance,
                         float& colorChamferDistance,
                         float& normalChamferDistance)
{
    using namespace standard_cyborg::math;
    
    const std::vector<Vec3> &positions0 = geo0.getPositions();
    const std::vector<Vec3> &colors0 = geo0.getColors();
    const std::vector<Vec3> &normals0 = geo0.getNormals();
    
    const std::vector<Vec3> &positions1 = geo1.getPositions();
    const std::vector<Vec3> &colors1 = geo1.getColors();
    const std::vector<Vec3> &normals1 = geo1.getNormals();

    positionChamferDistance = 0.0f;
    colorChamferDistance = 0.0f;
    normalChamferDistance = 0.0f;

    for (int iv = 0; iv < geo0.vertexCount(); ++iv) {
        int iClosest = geo1.getClosestVertexIndex(positions0[iv]);
        float w = 1.0f / (float)geo0.vertexCount();
        
        positionChamferDistance += w * (positions0[iv] - positions1[iClosest]).norm();
        colorChamferDistance += w * (colors0[iv] - colors1[iClosest]).norm();
        normalChamferDistance += w * (Vec3::normalize(normals0[iv]) - Vec3::normalize(normals1[iClosest])).norm();
    }

    for (int iv = 0; iv < geo1.vertexCount(); ++iv) {
        int iClosest = geo0.getClosestVertexIndex(positions1[iv]);
        float w = (1.0f / (float)geo1.vertexCount());
        
        positionChamferDistance += w * (positions1[iv] - positions0[iClosest]).norm();
        colorChamferDistance += w * (colors1[iv] - colors0[iClosest]).norm();
        normalChamferDistance += w * (Vec3::normalize(normals1[iv]) - Vec3::normalize(normals0[iClosest])).norm();
    }
    
}


static bool MyWriteSurfelsToPLYFile(const Surfel *surfels,
                                    size_t surfelCount,
                                    Eigen::Vector3f gravity,
                                    std::string filename)
{
    FILE *file = fopen(filename.c_str(), "w");
    if (file == NULL) {
        return false;
    }

    fprintf(file, "ply\n");
    fprintf(file, "format ascii 1.0\n");
    fprintf(file, "comment StandardCyborgFusionMetadata { \"color_space\": \"sRGB\" }\n");
    fprintf(file, "element vertex %ld\n", surfelCount);
    fprintf(file, "property float x\n");
    fprintf(file, "property float y\n");
    fprintf(file, "property float z\n");
    fprintf(file, "property float nx\n");
    fprintf(file, "property float ny\n");
    fprintf(file, "property float nz\n");
    fprintf(file, "property uchar red\n");
    fprintf(file, "property uchar green\n");
    fprintf(file, "property uchar blue\n");
    fprintf(file, "property float surfel_radius\n");
    fprintf(file, "element face 0\n");
    fprintf(file, "property list uchar int vertex_indices\n");
    fprintf(file, "end_header\n");

    for (size_t i = 0; i < surfelCount; ++i) {
        const Surfel &surfel = surfels[i];
        Vector3f normal = surfel.normal;
        float surfelRadius = normal.norm();
        normal /= surfelRadius;

        fprintf(file, "%.8f %.8f %.8f %.8f %.8f %.8f %d %d %d %f\n",
                surfel.position.x(),
                surfel.position.y(),
                surfel.position.z(),
                normal.x(),
                normal.y(),
                normal.z(),
                (int)(applyGammaCorrection(surfel.color.x()) * 255.0f),
                (int)(applyGammaCorrection(surfel.color.y()) * 255.0f),
                (int)(applyGammaCorrection(surfel.color.z()) * 255.0f),
                surfelRadius);
    }

    fclose(file);

    return true;
}

static NSString *getGroundTruthPointCloudFilename(NSString *pointCloudsContainerDir, NSString *inputPath)
{
    NSString *theFileName = [inputPath lastPathComponent];

    if ([theFileName rangeOfString:@"/"].location != NSNotFound) {
        NSLog(@"Unhandled inputPath %@ with a forward slash. Shutting down.", inputPath);
        exit(1);
    }

    return [pointCloudsContainerDir stringByAppendingPathComponent:
                                        [theFileName stringByAppendingString:@".ply"]];
}

static SCOfflineReconstructionManager *reconstructHelper(
    NSString *inputPath,
    id<MTLDevice> metalDevice,
    float ICPDownsampleFraction,
    std::vector<float> &runtimes,
    PBFFinalStatistics& finalStatistics)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *inputDirectory = nil;
    NSArray *inputPaths = nil;
    
    inputDirectory = inputPath;
    inputPaths = [[fileManager contentsOfDirectoryAtPath:inputPath error:NULL]
                  sortedArrayUsingComparator:^(NSString *path1, NSString *path2) {
        return [path1 compare:path2];
    }];
    
    id<MTLCommandQueue> commandQueue = [metalDevice newCommandQueue];
    
    // Unfortunately, there's not a good way to get the number of *high-performance*
    // CPU cores on iOS, so we have to hard-code this for now
    int threadCount = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad ? 4 : 2;
    
    SCOfflineReconstructionManager *reconstruction = [[SCOfflineReconstructionManager alloc] initWithDevice:metalDevice
                                                                                               commandQueue:commandQueue
                                                                                             maxThreadCount:threadCount];

    if (ICPDownsampleFraction > 0.0) {
        [reconstruction setICPDownsampleFraction:0.2f];
    }
    
    NSString *motionDataPath = [inputDirectory stringByAppendingPathComponent:@"/motion-data.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:motionDataPath] == NO) {
        NSLog(@"No motion data found at \"%@\"\n", motionDataPath);
    } else {
        [reconstruction setMotionDataPath:motionDataPath];
    }
    
    for (NSString *file in inputPaths) {
        @autoreleasepool {
            if (![[file pathExtension] isEqualToString:@"ply"]) continue;
            if (![[file lastPathComponent] hasPrefix:@"frame-"]) continue;
            
            //std::cout << "Assimilating frame " << [file UTF8String] << std::endl;
            NSString *fullFilePath = [inputPath stringByAppendingPathComponent:file];
            
            SCAssimilatedFrameMetadata metadata = [reconstruction accumulateFromBPLYWithPath:fullFilePath];
            
            switch (metadata.result) {
                case SCAssimilatedFrameResultSucceeded:
                case SCAssimilatedFrameResultPoorTracking:
                    runtimes.push_back(metadata.assimilationTime);
                    
                    break;
                    
                case SCAssimilatedFrameResultLostTracking:
                case SCAssimilatedFrameResultFailed:
                    break;
            }
        }
    }

    finalStatistics = [reconstruction finalize];

    return reconstruction;
}

static void lazilyCreateGroundTruth(NSString *inputPath,
                                    id<MTLDevice> metalDevice,
                                    sc3d::Geometry &groundTruthPointCloudOut)
{
    NSError *error;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *groundTruthPointCloudsContainerDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"containerDir-point-clouds"];
    NSString *groundTruthPointCloudFilename = getGroundTruthPointCloudFilename(groundTruthPointCloudsContainerDir, inputPath);
    
    // Code useful for clearing the ground truth point cloud container directory cache
    // [[NSFileManager defaultManager] removeItemAtPath:groundTruthPointCloudsContainerDir error:nil];
    //exit(1);
    
    // Lazily create groundTruthPointCloudsContainerDir
    if (![fileManager fileExistsAtPath:groundTruthPointCloudsContainerDir]) {
        if (![fileManager createDirectoryAtPath:groundTruthPointCloudsContainerDir withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Couldn't create directory %@: %@",
                  groundTruthPointCloudsContainerDir,
                  [error localizedDescription]);
            return;
        }
    }
    
    if (![fileManager fileExistsAtPath:groundTruthPointCloudFilename]) {
        std::vector<float> runtimes;
        PBFFinalStatistics stats;
        SCOfflineReconstructionManager *reconstruction = reconstructHelper(inputPath, metalDevice, -1.0, runtimes, stats);
        
        const Surfels &surfels = [reconstruction surfels];
        size_t surfelCount = surfels.size();
        simd_float3 gravity = [reconstruction gravity];
        std::string plyPathString = std::string([groundTruthPointCloudFilename UTF8String]);
        assert(MyWriteSurfelsToPLYFile(surfels.data(),
                                       surfelCount,
                                       Vector3f(gravity.x, gravity.y, gravity.z),
                                       plyPathString));
        
        [reconstruction writePointCloudToPLYFile:groundTruthPointCloudFilename];
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:groundTruthPointCloudFilename] == NO) {
        NSLog(@"No ground truth point cloud found at \"%@\"\n", groundTruthPointCloudFilename);
        return;
    }
    
    io::ply::ReadGeometryFromPLYFile(groundTruthPointCloudOut, std::string([groundTruthPointCloudFilename UTF8String]));
}

static ReconstructionMetadata reconstruct(NSString *inputPath,
                                          id<MTLDevice> metalDevice)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // make sure the path actually exists.
    inputPath = [inputPath stringByStandardizingPath];
    {
        BOOL inputIsDirectory = NO;
        BOOL inputPathExists = inputPath == nil ? NO : [fileManager fileExistsAtPath:inputPath isDirectory:&inputIsDirectory];

        if (!inputPathExists || !inputIsDirectory) {
            std::cerr << "Input path does not exist at " << inputPath << std::endl;
            exit(1);
        }
    }
    
    sc3d::Geometry groundTruthPointCloud;
    lazilyCreateGroundTruth(inputPath, metalDevice, groundTruthPointCloud);
    
    std::vector<float> runtimes;
    PBFFinalStatistics finalStatistics;
    SCOfflineReconstructionManager *reconstruction = reconstructHelper(inputPath, metalDevice, -1.0f, runtimes, finalStatistics);
    
    SCPointCloud *pointCloud = [reconstruction buildPointCloud];
    sc3d::Geometry surfelsGeo;
    [pointCloud toGeometry:surfelsGeo];
    
    float positionChamferDistance;
    float colorChamferDistance;
    float normalChamferDistance;
    calcChamferDistance(surfelsGeo, groundTruthPointCloud,
                        positionChamferDistance, colorChamferDistance, normalChamferDistance);
    
    float meanRuntime;
    float stdDevRuntime;
    meanStdDev(runtimes, meanRuntime, stdDevRuntime);
    
    printf("Finished assimilating %d frames\n\tAverage runtime: %.6f s\n\tAverage ICP iterations: %.2f\n\tRejected frames: %d\n\taverageCorrespondenceError:%f\n",
           finalStatistics.mergedFrameCount,
           meanRuntime,
           finalStatistics.averageICPIterations,
           finalStatistics.failedFrameCount,
           finalStatistics.averageCorrespondenceError);
    
    ReconstructionMetadata metadata{
        meanRuntime,
        positionChamferDistance,
        normalChamferDistance,
        colorChamferDistance,
         
        (float)finalStatistics.averageICPIterations,
        (int)finalStatistics.failedFrameCount,
        (float)finalStatistics.averageCorrespondenceError,
        std::string([inputPath UTF8String]),
        pointCloud
    };
    
    return metadata;
}

std::string benchmarkAll(NSArray *allTestCases, void (^progressHandler)(int frameIndex, SCPointCloud *pointCloud))
{
    __block std::vector<ReconstructionMetadata> metadatas;
    
    id<MTLDevice> metalDevice = MTLCreateSystemDefaultDevice();
    
    [allTestCases enumerateObjectsUsingBlock:^(NSString *testCase, NSUInteger iTestCase, BOOL *stop) {
        NSLog(@"Running benchmark %d/%d: %@", (int)iTestCase + 1, (int)[allTestCases count], testCase);
        
        ReconstructionMetadata metadata = reconstruct(testCase, metalDevice);
        
        metadatas.push_back(metadata);
        
        progressHandler((int)iTestCase, metadata.pointCloud);
    }];
    
    std::vector<float> runtimes;
    std::vector<float> icpIterations;
    std::vector<float> failedFrameCounts;
    std::vector<float> averageCorrespondenceErrors;
    std::vector<float> positionChamferDistances;
    std::vector<float> colorChamferDistances;
    std::vector<float> normalChamferDistances;
    
    nlohmann::json json;
    
    for (int i = 0; i < metadatas.size(); ++i) {
        ReconstructionMetadata metadata = metadatas[i];
        
        runtimes.push_back(metadata.meanRuntime);
        icpIterations.push_back(metadata.averageICPIterations);
        failedFrameCounts.push_back((float)metadata.failedFrameCount);
        positionChamferDistances.push_back((float)metadata.positionChamferDistance);
        normalChamferDistances.push_back((float)metadata.normalChamferDistance);
        colorChamferDistances.push_back((float)metadata.colorChamferDistance);

        averageCorrespondenceErrors.push_back((float)metadata.averageCorrespondenceError);

        json["frameMetadatas"][i]["testCase"] = metadata.testCase;
        json["frameMetadatas"][i]["meanRuntime"] = metadata.meanRuntime;
        json["frameMetadatas"][i]["averageICPIterations"] = metadata.averageICPIterations;
        json["frameMetadatas"][i]["failedFrameCount"] = metadata.failedFrameCount;
        json["frameMetadatas"][i]["averageCorrespondenceError"] = metadata.averageCorrespondenceError;
        json["frameMetadatas"][i]["positionChamferDistance"] = metadata.positionChamferDistance;
        json["frameMetadatas"][i]["colorChamferDistance"] = metadata.colorChamferDistance;
        json["frameMetadatas"][i]["normalChamferDistance"] = metadata.normalChamferDistance;
    }
    
    {
        float mean;
        float stdDev;
        
        meanStdDev(runtimes, mean, stdDev);
        
        json["runtime"]["stdDev"] = stdDev;
        json["runtime"]["mean"] = mean;
    }
    
    {
        float mean;
        float stdDev;
        
        meanStdDev(positionChamferDistances, mean, stdDev);
        
        json["positionChamferDistance"]["stdDev"] = stdDev;
        json["positionChamferDistance"]["mean"] = mean;
    }
    
    {
        float mean;
        float stdDev;
        
        meanStdDev(normalChamferDistances, mean, stdDev);
        
        json["normalChamferDistance"]["stdDev"] = stdDev;
        json["normalChamferDistance"]["mean"] = mean;
    }
    
    {
        float mean;
        float stdDev;
        
        meanStdDev(colorChamferDistances, mean, stdDev);
        
        json["colorChamferDistance"]["stdDev"] = stdDev;
        json["colorChamferDistance"]["mean"] = mean;
    }
    
    {
        float mean;
        float stdDev;
        
        meanStdDev(icpIterations, mean, stdDev);
        
        json["icpIterations"]["stdDev"] = stdDev;
        json["icpIterations"]["mean"] = mean;
    }
    
    {
        float mean;
        float stdDev;
        
        meanStdDev(failedFrameCounts, mean, stdDev);
        
        json["failedFrameCounts"]["stdDev"] = stdDev;
        json["failedFrameCounts"]["mean"] = mean;
    }
    
    {
        float mean;
        float stdDev;
        
        meanStdDev(averageCorrespondenceErrors, mean, stdDev);
        
        json["averageCorrespondenceErrors"]["stdDev"] = stdDev;
        json["averageCorrespondenceErrors"]["mean"] = mean;
    }
    // averageCorrespondenceErrors
    
    json["GPU"] = std::string([[metalDevice name] UTF8String]);
    
    std::ostringstream os;
    
    os << std::setw(4) << json;
    
    return os.str();
}
