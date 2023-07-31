# StandardCyborgSDK

> A C++ SDK for 3D computer vision, paired with Cocoa frameworks for TrueDepth-based 3D scanning,
> meshing, and ML landmarking models + analysis for face, foot, and ear

## Introduction

A native (iOS/macOS) C++ library containing data structures, I/O, and algorithms,
as well as a Cocoa framework for iOS and Mac clients to use publicly.

This project generates [StandardCyborgFusion.framework](https://github.com/StandardCyborg/StandardCyborgCocoa)

This code was developed by the Standard Cyborg team, primarily in 2018 and the middle of 2019. Standard Cyborg powered applications for custom 3d smart glasses, football helmet fitting, custom medical glasses, shoe sizing, and more. Development was paused on this code when Standard Cyborg began working on horizontal tooling, versus developing specific applications. 

## License

This codebase is released under the MIT license, with the exception that commercial applications in the field of prosthetics are prohibited until Jan 1, 2023. 

See LICENSE file

## Installation

1. Make sure you have installed git lfs before cloning this repo
1. Run this shell command
```sh
$ ./install-dependencies.sh
```
1. Open `StandardCyborgSDK.xcworkspace` in Xcode

## Targets

- **StandardCyborgFusion**: iOS + macOS framework for 3D scanning and meshing using TrueDepth 
- **StandardCyborgFusionTests**: unit tests for the above
- **VisualTesterMac**: a macOS app for helping develop and test StandardCyborgFusion
- **VisualTesterMac**: ditto, but for iOS; also useful for on-device benchmarking
- **TrueDepthFusion**: an iOS app for exercising the StandardCyborgFusion framework
- **StandardCyborgAlgorithmsTestbed**: an iOS app for testing the SC C++ algorithms and data structures

## Development

For debugging via lldb in Xcode, it is recommended to install the [LLDB Eigen Data Formatter](https://github.com/tehrengruber/LLDB-Eigen-Data-Formatter).

Note on building with bitcode support: https://medium.com/@heitorburger/static-libraries-frameworks-and-bitcode-6d8f784478a9

## Deployment

To build StandardCyborgFusion.framework for public release:

1. Run `archive-build-standardcyborgfusion.sh`, which will both update the compiled copy in `../StandardCyborgCocoa/StandardCyborgFusion` and generate a .zip file for you to upload to the StandardCyborgFusion release in GitHub
1. Commit the updated StandardCyborgFusion/Info.plist (which now has a new version number)
1. Merge updated Info.plist commit into `main`
1. Tag this commit in the format `git tag v1.2.3-StandardCyborgFusion`

### Deploying StandardCyborgFusion to CocoaPods

1. Commit the changes with a nice public-facing message and a prefix of `StandardCyborgFusion: `, e.g. `StandardCyborgFusion: Adds SCMesh class`
1. Create a git tag for this commit in the format `v1.2.3-StandardCyborgFusion`
1. Push the commit and the tag `git push origin main`, `git push origin v1.2.3-StandardCyborgFusion`
1. Open this repo's releases on GitHub and draft a new release: https://github.com/StandardCyborg/StandardCyborgCocoa/releases/new
   a) For Tag version, specify the git tag you just created in step 2
   a) For Release title, use the commit message from step 1
   a) In "Attach binaries by dropping them here or selecting them", drag in the StandardCyborgFusion.framework.zip file that was generated inside `StandardCyborgSDK/build`.
   a) Publish release
1. Push to CocoaPods: `pod trunk push StandardCyborgFusion`

### Registering with CocoaPods

1. Register: pod trunk register someone@standardcyborg.com 'Your Name' --description='MacBook Pro 13 2019'
1. Click the link in your email
1. Get someone who has access to add you. `pod trunk add-owner StandardCyborgFusion jeff@standardcyborg.com`

### Integrating External CocoaPods

#### How To

##### Using https://github.com/StandardCyborg/SCCocoaPods

Our [SCCocoaPods](https://github.com/StandardCyborg/SCCocoaPods) private registry (which is just a github repo) provides the most scalable way for deploying common dependencies.

##### Using a local podspec

Sometimes you only want to use a dependency for a single project. In this scenario, CocoaPods supports local podspecs—
the podspec file is a file locally on disk rather than in a CocoaPods registry (as discussed above).
See for example [StandardCyborgFusion/PoissonRecon.podspec](StandardCyborgFusion/PoissonRecon.podspec),
which is a local dependency for the [StandardCyborgFusionOSX target](Podfile) of the SDK.

We use a mix of local Podspecs and registry-served Podspecs. Local podspecs are best for internal-only usage.

### Developing against the SDK locally

You may develop *locally* against the SDK as CocoaPod. For example, to develop a command line app which uses the SDK via local CocoaPods:

1. Clone [StandardCyborgCocoa](https://github.com/StandardCyborg/StandardCyborgCocoa) as a sibling directory to this repo
1. `cd StandardCyborgSDK`
1. Build the CocoaPod into `StandardCyborgCocoa/StandardCyborgFusion` by running `./archive-build-standardcyborgfusion.sh`
1. Create a new command line project in Xcode, for example, `FusionTest`
1. `cd /path/to/FusionTest`
1. `pod init`
1. Add to your podfile something like:
    ```ruby
    target 'FusionTest' do
      platform :osx, '11.0'

      use_frameworks!

      pod 'StandardCyborgFusion', path: '/path/to/your/StandardCyborgCocoa/StandardCyborgFusion'
    end
    ```
1. `pod install`
1. We need to be able to locate the headers, but local CocoaPods don't actually get copied into the `Pods` directory. You'll need to symlink the local CocoaPod directory into `Pods/`. For example from your project root, `ln -s /path/to/StandardCyborgCocoa/StandardCyborgFusion Pods/StandardCyborgFusion`
1. `open FusionTest.xcworkspace`
1. For some unknown reason, `Hardened Runtime` conflicts with the loading of our dynamic library. Open the `FusionTest` command line target settings and go to the `Signing & Capabilities` tab. Click the &times; next to `Hardened Runtime` to disable it.
1. Change the `main.m` extension to `main.mm` and add some code like the following:
    ```cpp
    #import <iostream>
    #import <StandardCyborgData/StandardCyborgData.hpp>

    int main(int argc, const char * argv[]) {
        StandardCyborg::Vec3 v {1, 2, 3};
        std::cout << "v = " << v << std::endl;
        return 0;
    }
    ```
1. Build and run!

