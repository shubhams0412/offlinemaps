#!/bin/bash

# setup_valhalla_deps.sh
# This script sets up the directory structure for Valhalla dependencies
# and provides instructions on where to obtain the necessary C++ headers.

PROJECT_ROOT=$(pwd)
CPP_INCLUDE_DIR="$PROJECT_ROOT/android/app/src/main/cpp/include"

echo "🚀 Setting up Valhalla dependencies for Android..."

# 1. Create directory structure
mkdir -p "$CPP_INCLUDE_DIR"
mkdir -p "$PROJECT_ROOT/android/app/src/main/jniLibs/arm64-v8a"

echo "✅ Created directories:"
echo "   - $CPP_INCLUDE_DIR"
echo "   - android/app/src/main/jniLibs/arm64-v8a"

# 2. Instructions for Headers
echo ""
echo "📦 STEP 1: DOWNLOAD HEADERS"
echo "You need the Boost and Valhalla header files. Since these are large, it is recommended to:"
echo "1. Download the latest Valhalla source: git clone https://github.com/valhalla/valhalla.git"
echo "2. Copy the contents of 'valhalla/' folder into '$CPP_INCLUDE_DIR/valhalla/'"
echo "3. Download Boost headers (v1.75+) and copy the 'boost/' folder into '$CPP_INCLUDE_DIR/boost/'"

# 3. Instructions for Binaries
echo ""
echo "💎 STEP 2: GET PRE-COMPILED BINARIES"
echo "For Android arm64-v8a, you can obtain 'libvalhalla.so' from:"
echo "1. The Valhalla Releases page (if available): https://github.com/valhalla/valhalla/releases"
echo "2. Compile via the official Android build script: https://github.com/valhalla/valhalla/tree/master/android"
echo "3. Extract from the MapLibre Navigation Android SDK (which uses Valhalla)."

echo ""
echo "🔧 Once the files are in place, your CMakeLists.txt is already configured to find them."
echo "Done!"
