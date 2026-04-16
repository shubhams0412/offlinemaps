#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VALHALLA_DIR="${PROJECT_ROOT}/third_party/valhalla"
VCPKG_DIR="${PROJECT_ROOT}/third_party/vcpkg"
IOS_CMAKE_DIR="${PROJECT_ROOT}/third_party/ios-cmake"
OUT_DIR="${PROJECT_ROOT}/ios/valhalla"

DEVICE_BUILD_DIR="${PROJECT_ROOT}/build/valhalla-ios-device"
SIM_BUILD_DIR="${PROJECT_ROOT}/build/valhalla-ios-sim"
VCPKG_INSTALL_DIR="${PROJECT_ROOT}/build/vcpkg-installed-ios"
VCPKG_BUILDTREES_DIR="${PROJECT_ROOT}/build/vcpkg-buildtrees-ios"
VCPKG_PACKAGES_DIR="${PROJECT_ROOT}/build/vcpkg-packages-ios"
VCPKG_DOWNLOADS_DIR="${PROJECT_ROOT}/build/vcpkg-downloads"
# Ensure system build tools are in path (brew, etc)
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
# Add vcpkg host tools (pkgconf, etc)
export PATH="${PROJECT_ROOT}/build/vcpkg-installed-ios/arm64-osx/tools/pkgconf:${PATH}"
export PATH="${PROJECT_ROOT}/build/vcpkg-installed-ios/arm64-osx/bin:${PATH}"

echo "== Valhalla iOS build =="
echo "Project: ${PROJECT_ROOT}"
echo "Output:  ${OUT_DIR}/Valhalla.xcframework"
echo ""

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd cmake
need_cmd xcodebuild
need_cmd python3
need_cmd libtool

mkdir -p "${PROJECT_ROOT}/third_party" "${PROJECT_ROOT}/build" "${OUT_DIR}"
mkdir -p "${VCPKG_INSTALL_DIR}" "${VCPKG_BUILDTREES_DIR}" "${VCPKG_PACKAGES_DIR}" "${VCPKG_DOWNLOADS_DIR}"

if [[ ! -d "${VALHALLA_DIR}/.git" ]]; then
  echo "Cloning Valhalla into ${VALHALLA_DIR} ..."
  git clone --depth 1 https://github.com/valhalla/valhalla.git "${VALHALLA_DIR}"
fi

if [[ ! -d "${IOS_CMAKE_DIR}/.git" ]]; then
  echo "Cloning ios-cmake toolchain into ${IOS_CMAKE_DIR} ..."
  git clone --depth 1 https://github.com/leetal/ios-cmake.git "${IOS_CMAKE_DIR}"
fi

if [[ ! -d "${VCPKG_DIR}/.git" ]]; then
  echo "Cloning vcpkg into ${VCPKG_DIR} ..."
  git clone --depth 1 https://github.com/microsoft/vcpkg.git "${VCPKG_DIR}"
fi

echo ""
echo "Bootstrapping vcpkg..."
"${VCPKG_DIR}/bootstrap-vcpkg.sh" -disableMetrics

echo ""
echo "Installing dependencies via vcpkg (this can take a while)..."
echo "If you hit build errors, you may need to add/remove ports depending on the Valhalla version."
echo "Note: Installing the vcpkg 'boost' meta-port is extremely large; we install only the common boost libs Valhalla needs."

# Common Valhalla deps (may vary with Valhalla version / build options).
DEPS=(
  boost-filesystem
  boost-program-options
  boost-algorithm
  boost-foreach
  boost-format
  boost-geometry
  boost-heap
  boost-optional
  boost-property-tree
  boost-range
  boost-tokenizer
  boost-system
  boost-thread
  boost-regex
  boost-date-time
  boost-chrono
  boost-iostreams
  boost-serialization


  protobuf
  sqlite3
  zlib
  curl
  lz4
)

for triplet in arm64-ios arm64-ios-simulator; do
  echo "vcpkg install ${DEPS[*]/%/:$triplet} ..."
  "${VCPKG_DIR}/vcpkg" install ${DEPS[@]/%/:$triplet} \
    --x-install-root "${VCPKG_INSTALL_DIR}" \
    --x-buildtrees-root "${VCPKG_BUILDTREES_DIR}" \
    --x-packages-root "${VCPKG_PACKAGES_DIR}" \
    --downloads-root "${VCPKG_DOWNLOADS_DIR}" \
    --clean-buildtrees-after-build \
    --clean-packages-after-build
done

TOOLCHAIN="${IOS_CMAKE_DIR}/ios.toolchain.cmake"
if [[ ! -f "${TOOLCHAIN}" ]]; then
  echo "ios-cmake toolchain not found at: ${TOOLCHAIN}" >&2
  exit 1
fi

common_cmake_args=(
  -DCMAKE_TOOLCHAIN_FILE="${VCPKG_DIR}/scripts/buildsystems/vcpkg.cmake"
  -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE="${TOOLCHAIN}"
  -DVCPKG_INSTALLED_DIR="${VCPKG_INSTALL_DIR}"
  -DVCPKG_MANIFEST_MODE=OFF
  -DDEPLOYMENT_TARGET=17.0
  -DCMAKE_CXX_STANDARD=20
  -DCMAKE_CXX_STANDARD_REQUIRED=ON
  -DBUILD_SHARED_LIBS=OFF
  -DENABLE_SERVICES=OFF
  -DENABLE_TOOLS=OFF
  -DENABLE_TESTS=OFF
  -DENABLE_PYTHON_BINDINGS=OFF
  -DENABLE_DATA_TOOLS=OFF
  -DLOGGING_LEVEL=NONE
  -DENABLE_SINGLE_FILES_WERROR=OFF
  -DPKG_CONFIG_EXECUTABLE="${PROJECT_ROOT}/build/vcpkg-installed-ios/arm64-osx/tools/pkgconf/pkgconf"
)

echo ""
echo "Configuring device build..."
cmake -S "${VALHALLA_DIR}" -B "${DEVICE_BUILD_DIR}" \
  -DPLATFORM=OS64 \
  -DVCPKG_TARGET_TRIPLET=arm64-ios \
  "${common_cmake_args[@]}"

echo "Building device..."
cmake --build "${DEVICE_BUILD_DIR}" --config Release

echo ""
echo "Configuring simulator build..."
cmake -S "${VALHALLA_DIR}" -B "${SIM_BUILD_DIR}" \
  -DPLATFORM=SIMULATORARM64 \
  -DVCPKG_TARGET_TRIPLET=arm64-ios-simulator \
  "${common_cmake_args[@]}"

echo "Building simulator..."
cmake --build "${SIM_BUILD_DIR}" --config Release

echo ""
echo "Locating built libraries..."
DEVICE_LIB="$(find "${DEVICE_BUILD_DIR}" -name 'libvalhalla*.a' -maxdepth 5 | head -n 1 || true)"
SIM_LIB="$(find "${SIM_BUILD_DIR}" -name 'libvalhalla*.a' -maxdepth 5 | head -n 1 || true)"

if [[ -z "${DEVICE_LIB}" || -z "${SIM_LIB}" ]]; then
  echo "Could not find Valhalla static library artifacts." >&2
  echo "Searched for: libvalhalla*.a under:" >&2
  echo "  - ${DEVICE_BUILD_DIR}" >&2
  echo "  - ${SIM_BUILD_DIR}" >&2
  echo "" >&2
  echo "Tip: open the Valhalla CMake output and check the actual target/library names." >&2
  exit 1
fi

echo "Device lib: ${DEVICE_LIB}"
echo "Sim lib:    ${SIM_LIB}"

echo ""
echo "Creating combined static libraries (Valhalla + vcpkg deps)..."
DEVICE_DEPS_DIR="${VCPKG_INSTALL_DIR}/arm64-ios/lib"
SIM_DEPS_DIR="${VCPKG_INSTALL_DIR}/arm64-ios-simulator/lib"

if [[ ! -d "${DEVICE_DEPS_DIR}" || ! -d "${SIM_DEPS_DIR}" ]]; then
  echo "vcpkg lib directories not found:" >&2
  echo "  - ${DEVICE_DEPS_DIR}" >&2
  echo "  - ${SIM_DEPS_DIR}" >&2
  exit 1
fi

DEVICE_COMBINED_LIB="${DEVICE_BUILD_DIR}/libValhallaAll.a"
SIM_COMBINED_LIB="${SIM_BUILD_DIR}/libValhallaAll.a"

# Merge Valhalla + *all* vcpkg static libs for the triplet to keep the CocoaPod simple.
# (The pod will still need to link a few Apple system frameworks; see Valhalla.podspec if needed.)
libtool -static -o "${DEVICE_COMBINED_LIB}" "${DEVICE_LIB}" "${DEVICE_DEPS_DIR}"/*.a
libtool -static -o "${SIM_COMBINED_LIB}" "${SIM_LIB}" "${SIM_DEPS_DIR}"/*.a

echo "Device combined lib: ${DEVICE_COMBINED_LIB}"
echo "Sim combined lib:    ${SIM_COMBINED_LIB}"

HEADERS_DIR="${VALHALLA_DIR}"
if [[ ! -d "${HEADERS_DIR}/valhalla" ]]; then
  echo "Headers folder not found at ${HEADERS_DIR}/valhalla" >&2
  exit 1
fi

echo ""
echo "Creating XCFramework..."
rm -rf "${OUT_DIR}/Valhalla.xcframework"
xcodebuild -create-xcframework \
  -library "${DEVICE_COMBINED_LIB}" -headers "${HEADERS_DIR}" \
  -library "${SIM_COMBINED_LIB}" -headers "${HEADERS_DIR}" \
  -output "${OUT_DIR}/Valhalla.xcframework"

echo ""
echo "✅ Done."
echo "Generated: ${OUT_DIR}/Valhalla.xcframework"
echo ""
echo "Next:"
echo "  cd ios && pod install"
echo "  flutter clean && flutter run"
