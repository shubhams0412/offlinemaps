import Flutter
import Foundation

final class OfflineRoutingPlugin: NSObject, FlutterPlugin {
  private var valhalla: ValhallaBridge?
  private var activeConfigPath: String?
  private var isInitialized = false

  static let channelName = "com.example.offlinemaps/routing"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = OfflineRoutingPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      handleInit(call, result: result)
    case "isReady":
      result(isInitialized && (valhalla?.isReady() ?? false))
    case "getRoute":
      handleGetRoute(call, result: result)
    case "getStatus":
      result(statusPayload())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleInit(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let configPath = args["configPath"] as? String else {
      result(FlutterError(code: "invalid_params", message: "Missing configPath", details: nil))
      return
    }

    // Initialize Valhalla with the config file path
    valhalla = ValhallaBridge(configPath: configPath)
    activeConfigPath = configPath
    isInitialized = true
    
    NSLog("[ValhallaPlugin] Initialized with config: %@", configPath)
    result(true)
  }

  private func handleGetRoute(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let valhalla = valhalla, isInitialized else {
      result(FlutterError(code: "not_initialized", message: "Valhalla engine not initialized", details: nil))
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "getRoute expects a dictionary", details: nil))
      return
    }

    let sLat = (args["startLat"] as? NSNumber)?.doubleValue ?? 0
    let sLng = (args["startLng"] as? NSNumber)?.doubleValue ?? 0
    let eLat = (args["endLat"] as? NSNumber)?.doubleValue ?? 0
    let eLng = (args["endLng"] as? NSNumber)?.doubleValue ?? 0
    let profile = (args["profile"] as? String) ?? "auto"

    // Call the Objective-C++ bridge
    if let jsonResult = valhalla.requestRoute(sLat, startLng: sLng, endLat: eLat, endLng: eLng, profile: profile) {
      if jsonResult.contains("\"error\"") {
          result(FlutterError(code: "valhalla_error", message: jsonResult, details: nil))
      } else {
          result(jsonResult)
      }
    } else {
      result(FlutterError(code: "bridge_failure", message: "Failed to get response from bridge", details: nil))
    }
  }

  private func statusPayload() -> [String: Any] {
    [
      "isInitialized": isInitialized,
      "configPath": activeConfigPath ?? NSNull(),
      "engineReady": valhalla?.isReady() ?? false,
      "version": "Valhalla 3.x"
    ]
  }
}
