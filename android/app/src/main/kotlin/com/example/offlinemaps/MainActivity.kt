package com.example.offlinemaps

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.offlinemaps/routing"
    private val valhallaManager = com.example.offlinemaps.routing.ValhallaManager()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    val configPath = call.argument<String>("configPath")
                    if (configPath != null) {
                        val success = valhallaManager.init(configPath)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Config path is null", null)
                    }
                }
                "getRoute" -> {
                    val sLat = call.argument<Double>("startLat") ?: 0.0
                    val sLng = call.argument<Double>("startLng") ?: 0.0
                    val eLat = call.argument<Double>("endLat") ?: 0.0
                    val eLng = call.argument<Double>("endLng") ?: 0.0
                    val profile = call.argument<String>("profile") ?: "auto"
                    
                    val jsonResponse = valhallaManager.getRoute(sLat, sLng, eLat, eLng, profile)
                    if (!jsonResponse.contains("\"error\"")) {
                        result.success(jsonResponse)
                    } else {
                        result.error("VALHALLA_ERROR", jsonResponse, null)
                    }
                }
                "isReady" -> {
                    result.success(valhallaManager.isReady()) 
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        valhallaManager.dispose()
        super.onDestroy()
    }
}