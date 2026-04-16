#include <jni.h>
#include <string>
#include <vector>
#include "ValhallaWrapper.h"

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_example_offlinemaps_routing_ValhallaManager_initNative(
        JNIEnv *env,
        jobject thiz,
        jstring config_path) {
    
    const char *path = env->GetStringUTFChars(config_path, nullptr);
    ValhallaWrapper *wrapper = new ValhallaWrapper(std::string(path));
    env->ReleaseStringUTFChars(config_path, path);
    
    if (wrapper->isReady()) {
        return reinterpret_cast<jlong>(wrapper);
    } else {
        delete wrapper;
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_com_example_offlinemaps_routing_ValhallaManager_destroyNative(
        JNIEnv *env,
        jobject thiz,
        jlong ptr) {
    
    if (ptr != 0) {
        ValhallaWrapper *wrapper = reinterpret_cast<ValhallaWrapper *>(ptr);
        delete wrapper;
    }
}

JNIEXPORT jstring JNICALL
Java_com_example_offlinemaps_routing_ValhallaManager_getRouteNative(
        JNIEnv *env,
        jobject thiz,
        jlong ptr,
        jdouble start_lat,
        jdouble start_lng,
        jdouble end_lat,
        jdouble end_lng,
        jstring profile) {
    
    if (ptr == 0) return env->NewStringUTF("{\"error\": \"Invalid Pointer\"}");
    
    ValhallaWrapper *wrapper = reinterpret_cast<ValhallaWrapper *>(ptr);
    const char *profile_str = env->GetStringUTFChars(profile, nullptr);
    
    std::string result = wrapper->getRoute(
            start_lat,
            start_lng,
            end_lat,
            end_lng,
            std::string(profile_str)
    );
    
    env->ReleaseStringUTFChars(profile, profile_str);
    return env->NewStringUTF(result.c_str());
}

}
