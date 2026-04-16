#include "ValhallaWrapper.h"
#include <valhalla/tyr/actor.h>
#include <boost/property_tree/ptree.hpp>
#include <boost/property_tree/json_parser.hpp>

#include <memory>
#include <cstdio>
#include <sstream>

#define LOGD(fmt, ...) printf("ValhallaNative: " fmt "\n", ##__VA_ARGS__)
#define LOGE(fmt, ...) fprintf(stderr, "ValhallaNative ERROR: " fmt "\n", ##__VA_ARGS__)

ValhallaWrapper::ValhallaWrapper(const std::string& configPath) : ready(false) {
    try {
        LOGD("Initializing Valhalla actor (iOS) with config: %s", configPath.c_str());
        
        boost::property_tree::ptree config;
        boost::property_tree::read_json(configPath, config);
        
        // Create the actor
        actor = std::unique_ptr<valhalla::tyr::actor_t>(new valhalla::tyr::actor_t(config));
        ready = true;
        
        LOGD("Valhalla engine initialized successfully.");
    } catch (const std::exception& e) {
        LOGE("Failed to initialize Valhalla engine: %s", e.what());
    } catch (...) {
        LOGE("Unknown error initializing Valhalla engine.");
    }
}

ValhallaWrapper::~ValhallaWrapper() {}

bool ValhallaWrapper::isReady() const {
    return ready;
}

std::string ValhallaWrapper::getRoute(double startLat, double startLng, double endLat, double endLng, const std::string& profile) {
    if (!ready || !actor) {
        return "{\"error\": \"Valhalla engine not ready\"}";
    }

    try {
        // Build the request JSON with high precision for coordinates
        std::stringstream ss;
        ss.precision(10);
        ss << std::fixed;
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
        std::string result = actor->route(request);
        return result;

    } catch (const std::exception& e) {
        LOGE("Valhalla Routing Error: %s", e.what());
        return std::string("{\"error\": \"") + e.what() + "\"}";
    } catch (...) {
        LOGE("Unknown error during Valhalla routing.");
        return "{\"error\": \"Unknown internal error\"}";
    }
}
