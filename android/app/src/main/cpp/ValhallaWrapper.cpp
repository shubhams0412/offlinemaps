#include "ValhallaWrapper.h"
#include <boost/property_tree/ptree.hpp>
#include <boost/property_tree/json_parser.hpp>

#include <memory>
#include <android/log.h>
#include <cmath>
#include <sstream>

#define LOG_TAG "ValhallaNative"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#if !VALHALLA_STUB_MODE
#include <valhalla/tyr/actor.h>
#endif

#if VALHALLA_STUB_MODE
namespace {
static void encodePolyline6Value(double value, double last, std::string& out) {
    const int v = static_cast<int>(std::round((value - last) * 1e6));
    int encoded = (v << 1) ^ (v >> 31);
    while (encoded >= 0x20) {
        out += static_cast<char>((0x20 | (encoded & 0x1f)) + 63);
        encoded >>= 5;
    }
    out += static_cast<char>(encoded + 63);
}

static std::string encodePolyline6(double sLat, double sLng, double eLat, double eLng) {
    std::string out;
    encodePolyline6Value(sLat, 0.0, out);
    encodePolyline6Value(sLng, 0.0, out);
    encodePolyline6Value(eLat, sLat, out);
    encodePolyline6Value(eLng, sLng, out);
    return out;
}
} // namespace
#endif

void ValhallaWrapper::ActorDeleter::operator()(void* ptr) const {
#if VALHALLA_STUB_MODE
    (void)ptr;
#else
    delete reinterpret_cast<valhalla::tyr::actor_t*>(ptr);
#endif
}

ValhallaWrapper::ValhallaWrapper(const std::string& configPath) : ready(false) {
#if VALHALLA_STUB_MODE
    (void)configPath;
    LOGD("Initializing STUB Valhalla engine (no native routing library linked).");
    ready = true;
#else
    try {
        LOGD("Initializing real Valhalla engine with config: %s", configPath.c_str());
        
        // Load the config file
        long long max_cache_size = 100 * 1024 * 1024; // 100MB fallback
        
        boost::property_tree::ptree config;
        boost::property_tree::read_json(configPath, config);
        
        // Create the actor
        actor.reset(new valhalla::tyr::actor_t(config));
        ready = true;
        
        LOGD("Valhalla engine initialized successfully.");
    } catch (const std::exception& e) {
        LOGE("Failed to initialize Valhalla engine: %s", e.what());
    } catch (...) {
        LOGE("Unknown error initializing Valhalla engine.");
    }
#endif
}

ValhallaWrapper::~ValhallaWrapper() {
    // std::unique_ptr handles cleanup
}

bool ValhallaWrapper::isReady() const {
    return ready;
}

std::string ValhallaWrapper::getRoute(double startLat, double startLng, double endLat, double endLng, const std::string& profile) {
    if (!ready || !actor) {
#if VALHALLA_STUB_MODE
        // In stub mode we don't construct a real actor; treat readiness as sufficient.
        // (We still keep the actor pointer null so production-mode code paths don't run.)
#else
        return "{\"error\": \"Valhalla engine not ready\"}";
#endif
    }

#if VALHALLA_STUB_MODE
    (void)profile;
    const std::string shape = encodePolyline6(startLat, startLng, endLat, endLng);
    std::stringstream ss;
    ss << "{"
       << "\"trip\":{"
       << "\"summary\":{\"length\":1.5,\"time\":180},"
       << "\"legs\":[{\"shape\":\"" << shape << "\",\"maneuvers\":["
       << "{\"instruction\":\"Start journey\",\"length\":0.7,\"type\":1},"
       << "{\"instruction\":\"Arrived at destination\",\"length\":0.8,\"type\":15}"
       << "]}]"
       << "}"
       << "}";
    return ss.str();
#else
    auto* actorPtr = reinterpret_cast<valhalla::tyr::actor_t*>(actor.get());
    if (!actorPtr) {
        return "{\"error\": \"Valhalla engine not ready\"}";
    }

    try {
        // Build the request JSON
        std::stringstream ss;
        ss << "{"
           << "  \"locations\": ["
           << "    {\"lat\": " << startLat << ", \"lon\": " << startLng << ", \"type\": \"break\"},"
           << "    {\"lat\": " << endLat << ", \"lon\": " << endLng << ", \"type\": \"break\"}"
           << "  ],"
           << "  \"costing\": \"" << (profile == "auto" ? "auto" : profile) << "\","
           << "  \"directions_options\": {\"units\": \"kilometers\", \"shape_format\": \"polyline6\"}"
           << "}";

        std::string request = ss.str();
        LOGD("Valhalla Request: %s", request.c_str());

        // Perform the routing
        std::string result = actorPtr->route(request);
        return result;

    } catch (const std::exception& e) {
        LOGE("Valhalla Routing Error: %s", e.what());
        return std::string("{\"error\": \"") + e.what() + "\"}";
    } catch (...) {
        LOGE("Unknown error during Valhalla routing.");
        return "{\"error\": \"Unknown internal error\"}";
    }
#endif
}
