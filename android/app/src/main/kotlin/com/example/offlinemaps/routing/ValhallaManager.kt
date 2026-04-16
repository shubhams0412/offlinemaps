package com.example.offlinemaps.routing

import android.util.Log
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Android bridge for the Valhalla C++ routing engine.
 * Uses JNI to call high-performance native routing code.
 */
class ValhallaManager {
    private var nativePtr: Long = 0
    private var isInitialized = false

    companion object {
        init {
            try {
                // Load the native Valhalla library
                System.loadLibrary("valhalla-jni")
            } catch (e: Exception) {
                Log.e("ValhallaManager", "Failed to load native library: ${e.message}")
            }
        }
    }

    /**
     * Initializes the engine with the absolute path to valhalla.json
     */
    fun init(configPath: String): Boolean {
        if (nativePtr != 0L) {
            destroyNative(nativePtr)
        }
        
        nativePtr = initNative(configPath)
        isInitialized = nativePtr != 0L
        
        Log.d("ValhallaManager", "Initialized with config: $configPath (ptr: $nativePtr)")
        return isInitialized
    }

    fun isReady(): Boolean = isInitialized

    /**
     * Executes a routing query through JNI
     */
    fun getRoute(
        startLat: Double,
        startLng: Double,
        endLat: Double,
        endLng: Double,
        profile: String
    ): String {
        if (!isInitialized) return "{\"error\": \"Not initialized\"}"
        
        return getRouteNative(nativePtr, startLat, startLng, endLat, endLng, profile)
    }

    fun dispose() {
        if (nativePtr != 0L) {
            destroyNative(nativePtr)
            nativePtr = 0L
            isInitialized = false
        }
    }

    // Native JNI methods
    private external fun initNative(configPath: String): Long
    private external fun destroyNative(ptr: Long)
    private external fun getRouteNative(
        ptr: Long,
        startLat: Double,
        startLng: Double,
        endLat: Double,
        endLng: Double,
        profile: String
    ): String
}
