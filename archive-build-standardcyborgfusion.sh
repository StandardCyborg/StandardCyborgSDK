#!/usr/bin/env bash

# Exit on first error, unset variable, or pipe failure
set -euo pipefail

if [ ! -d "../StandardCyborgCocoa" ]; then echo "Need a checkout of StandardCyborgCocoa"; exit 1; fi

# Read and update the framework version
current_version_string=`plutil -p StandardCyborgFusion/Info.plist | grep CFBundleShortVersionString`
current_version=`echo "$current_version_string" | sed -E 's/.+=> \"([0-9\.]+)\"$/\1/g'`

echo "What version number do you deem this build? The current version is $current_version (leave empty to use the same version)"
read new_version
if [ -z $new_version ]; then
    new_version="$current_version"
fi

echo "Updating version number to $new_version"
plutil -replace CFBundleShortVersionString -string "$new_version" StandardCyborgFusion/Info.plist
sed -i '' -E "s/  s.version(.+) = '([0-9\.]+)'/  s.version\1 = '$new_version'/g" "../StandardCyborgCocoa/StandardCyborgFusion/StandardCyborgFusion.podspec"


# Now we build StandardCyborgFusion for OSX, iOS, and the simulator.  Notes:
#  * `-derivedDataPath` for iOS and simulator is how to best get the .framework we desire; we use
#     `-archivePath` for OSX because for whatever reason `-derivedDataPath` doesn't give us the same
#     output structure for OSX (and actually includes a broken simlink and no compiled library).
#  * This was set up with a lot of trial and error and it's not at all clear if this is the best
#     solution.  Don't change SYMROOT because then the Pods won't build for some reason.
#  * Note we're using a different StandardCyborgFusionOSX scheme for OSX; this scheme (and target)
#     is basically identical to StandardCyborgFusion, except we need a separate one because of how
#     cocoapods work (must be either iOS or OSX not both).

echo
echo
echo "Building StandardCyborgFusion for macOS"
echo
xcodebuild archive -workspace StandardCyborgSDK.xcworkspace -scheme StandardCyborgFusionOSX -configuration Release -sdk macosx -archivePath build/StandardCyborgFusion-osx | xcpretty

echo
echo "Building StandardCyborgFusion for iOS"
echo
xcodebuild archive -workspace StandardCyborgSDK.xcworkspace -scheme StandardCyborgFusion -configuration Release -sdk iphoneos -archivePath build/StandardCyborgFusion-ios | xcpretty

echo
echo "Building StandardCyborgFusion for iOS simulator"
echo
# NOTE: only building the x86_64 slice for simulator because the simulator on M1 Macs can use the iOS arm64 slice
xcodebuild archive -workspace StandardCyborgSDK.xcworkspace -scheme StandardCyborgFusion -configuration Release -sdk iphonesimulator -archivePath build/StandardCyborgFusion-simulator | xcpretty

echo
echo
echo "Creating universal binary for device and simulator architectures..."
pushd "build" &>/dev/null
  # Create the directories
  mkdir -p osx ios

  # Remove existing
  if test -d "ios/StandardCyborgFusion.framework"; then rm -r "ios/StandardCyborgFusion.framework"; fi
  if test -d "osx/StandardCyborgFusion.framework"; then rm -r "osx/StandardCyborgFusion.framework"; fi

  # Copy build products into the appropriate locations
  osx_root="StandardCyborgFusion-osx.xcarchive/Products/Library/Frameworks/"
  cp -R "$osx_root/StandardCyborgFusion.framework/" "osx/StandardCyborgFusion.framework"

  ios_root="StandardCyborgFusion-ios.xcarchive/Products/Library/Frameworks/"
  cp -R "$ios_root/StandardCyborgFusion.framework" "ios/StandardCyborgFusion.framework"

  sim_root="StandardCyborgFusion-simulator.xcarchive/Products/Library/Frameworks/"

  # Ensure private headers are stripped
  if test -d "osx/StandardCyborgFusion.framework/Versions/A/PrivateHeaders"; then
    echo "ERROR: private headers were not stripped from the built Mac framework!"
    exit
  fi
  if test -d "ios/StandardCyborgFusion.framework/PrivateHeaders"; then
    echo "ERROR: private headers were not stripped from the built iOS framework!"
    exit
  fi

  # Ensure ML models are not published
  if compgen -G "osx/StandardCyborgFusion.framework/Versions/A/Resources/*.mlmodel*" >/dev/null; then
    echo "ERROR: mlmodelc directories were not stripped from the built Mac framework!"
    exit
  fi
  if compgen -G "ios/StandardCyborgFusion.framework/*.mlmodel*" >/dev/null; then
    echo "ERROR: mlmodelc directories were not stripped from the built iOS framework!"
    exit
  fi
  
  if test -d "StandardCyborgFusion.xcframework"; then
    rm -r "StandardCyborgFusion.xcframework"
  fi

  # This creates a combined xcframework that includes binaries for iOS device, simulator, and macOS
  xcrun xcodebuild -create-xcframework \
    -framework "$ios_root/StandardCyborgFusion.framework" \
    -framework "$sim_root/StandardCyborgFusion.framework" \
    -framework "$osx_root/StandardCyborgFusion.framework" \
    -output "StandardCyborgFusion.xcframework"

  # Copy files into StandardCyborgCocoa
  echo "Updating StandardCyborgCocoa"
  rm -rf "../../StandardCyborgCocoa/StandardCyborgFusion/StandardCyborgFusion.xcframework"
  cp -R "StandardCyborgFusion.xcframework" "../../StandardCyborgCocoa/StandardCyborgFusion/"

  echo "Creating zipped version for upload to GitHub release..."
  cp "../../StandardCyborgCocoa/StandardCyborgFusion/LICENSE" .

  tar -czf "StandardCyborgFusion.xcframework.tar.gz" "StandardCyborgFusion.xcframework" "LICENSE"
popd &>/dev/null

echo "Finished building StandardCyborgFusion-$new_version"
echo "Recommended:"
echo "git tag StandardCyborgFusion-$new_version"
