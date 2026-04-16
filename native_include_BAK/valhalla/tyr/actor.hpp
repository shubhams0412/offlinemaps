#ifndef VALHALLA_TYR_ACTOR_HPP
#define VALHALLA_TYR_ACTOR_HPP

// This repository currently ships Valhalla headers as *stubs* for iOS builds.
// If you want real offline routing on iOS, you must build and link the actual
// Valhalla library (and remove/replace these stubs).
#define VALHALLA_HEADERS_STUB 1

#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <boost/property_tree/ptree.hpp>

namespace valhalla {
namespace tyr {

class actor_t {
public:
    actor_t(const boost::property_tree::ptree& config) {}

    std::string route(const std::string& request) {
        // STUB LOGIC: Try to extract coordinates for a "Real-Feeling" mock
        // We'll return a straight line between the points
        
        double sLat = 0, sLng = 0, eLat = 0, eLng = 0;
        
        // Simple manual parsing for the stub
        size_t locsPos = request.find("\"locations\":");
        if (locsPos != std::string::npos) {
            auto parseCoord = [&](const std::string& key, size_t start) {
                size_t pos = request.find(key, start);
                if (pos == std::string::npos) return 0.0;
                return std::stod(request.substr(pos + key.length() + 2));
            };
            
            sLat = parseCoord("\"lat\"", locsPos);
            sLng = parseCoord("\"lon\"", locsPos);
            
            size_t secondLoc = request.find("{", request.find("}", locsPos));
            if (secondLoc != std::string::npos) {
                eLat = parseCoord("\"lat\"", secondLoc);
                eLng = parseCoord("\"lon\"", secondLoc);
            }
        }

        std::string shape = encodePolyline6(sLat, sLng, eLat, eLng);

        std::stringstream ss;
        ss << "{\n"
           << "  \"trip\": {\n"
           << "    \"summary\": { \"length\": 1.5, \"time\": 180 },\n"
           << "    \"legs\": [{\n"
           << "      \"shape\": \"" << shape << "\",\n"
           << "      \"maneuvers\": [\n"
           << "        { \"instruction\": \"Start journey\", \"length\": 0.7, \"type\": 1 },\n"
           << "        { \"instruction\": \"Arrived at destination\", \"length\": 0.8, \"type\": 15 }\n"
           << "      ]\n"
           << "    }]\n"
           << "  }\n"
           << "}";
        return ss.str();
    }

private:
    std::string encodePolyline6(double sLat, double sLng, double eLat, double eLng) {
        std::string res;
        encodeValue(sLat, res, 0);
        encodeValue(sLng, res, 0);
        encodeValue(eLat, res, sLat);
        encodeValue(eLng, res, sLng);
        return res;
    }

    void encodeValue(double val, std::string& res, double last) {
        int v = static_cast<int>(std::round((val - last) * 1e6));
        int value = (v << 1) ^ (v >> 31);
        while (value >= 0x20) {
            res += static_cast<char>((0x20 | (value & 0x1f)) + 63);
            value >>= 5;
        }
        res += static_cast<char>(value + 63);
    }
};

} // namespace tyr
} // namespace valhalla

#endif
