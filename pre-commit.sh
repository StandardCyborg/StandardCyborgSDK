#!/bin/bash

export PYTHONIOENCODING=utf-8
python3 deps/XcodeClangFormatWarnings/run-clang-format.py StandardCyborgFusion
python3 deps/XcodeClangFormatWarnings/run-clang-format.py StandardCyborgFusionTests
python3 deps/XcodeClangFormatWarnings/run-clang-format.py TrueDepthFusion
