cmake_minimum_required(VERSION 3.22.1)
project("valhalla-jni")

set(CMAKE_CXX_STANDARD 20)

# 🛠️ STUB_MODE: Enable this to compile without real Valhalla binaries
# Set to OFF when you add libvalhalla.so to jniLibs
option(VALHALLA_STUB_MODE "Build with stub headers and no external linking" ON)

include_directories(
    .
    include
    ../../../../../native_include
    ../../../../../native_include/include
)

add_library(
    valhalla-jni
    SHARED
    valhalla-jni.cpp
    ValhallaWrapper.cpp
)

find_library(log-lib log)

# Auto-switch to production when a prebuilt Valhalla .so is present for the current ABI.
set(VALHALLA_JNI_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")
set(VALHALLA_SO "${VALHALLA_JNI_LIB_DIR}/libvalhalla.so")
if(VALHALLA_STUB_MODE AND EXISTS "${VALHALLA_SO}")
    message("✅ Found ${VALHALLA_SO} — switching to PRODUCTION MODE for ${ANDROID_ABI}.")
    set(VALHALLA_STUB_MODE OFF)
endif()

target_compile_definitions(valhalla-jni PRIVATE VALHALLA_STUB_MODE=$<BOOL:${VALHALLA_STUB_MODE}>)

if(VALHALLA_STUB_MODE)
    message("⚠️ Building in STUB MODE. No real Valhalla libraries will be linked.")
    target_link_libraries(
        valhalla-jni
        ${log-lib}
    )
else()
    message("🚀 Building in PRODUCTION MODE. Linking real Valhalla libraries.")
    if(NOT EXISTS "${VALHALLA_SO}")
        message(FATAL_ERROR "VALHALLA_STUB_MODE=OFF but libvalhalla.so was not found at: ${VALHALLA_SO}")
    endif()

    add_library(valhalla SHARED IMPORTED)
    set_target_properties(valhalla PROPERTIES IMPORTED_LOCATION "${VALHALLA_SO}")

    target_link_libraries(
        valhalla-jni
        valhalla
        ${log-lib}
    )
endif()
