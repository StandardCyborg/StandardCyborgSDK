#!/usr/bin/env bash

set -euo pipefail

## Git submodules

git submodule update --init

## Utils

function homebrewInstall() {
    local formula=$1
    brew list $formula &>/dev/null || brew install $formula
}

## Homebrew packages

if ! [ "$(command -v brew)" ]; then
    echo "Please install Homebrew: https://brew.sh/"
    exit 1
fi

homebrewInstall cmake
homebrewInstall swiftlint
homebrewInstall ccache
homebrewInstall clang-format
homebrewInstall git-lfs
homebrewInstall libiconv

## CocoaPods #################################################################

if ! [ "$(command -v pod)" ]; then
    echo "CocoaPods is required to continue. Please install CocoaPods by"
    echo "running `sudo gem install cocoapods`."
    echo "See more: https://cocoapods.org/"
    exit 1
fi

if ! test -e .git/hooks/pre-commit; then
    pushd .git/hooks &>/dev/null
    echo "Installing git pre-commit hook"
    ln -s ../../pre-commit.sh pre-commit
    popd &>/dev/null
fi

pod install

echo "Finished installing and updating dependencies"
echo "Please open StandardCyborgSDK.xcworkspace"

