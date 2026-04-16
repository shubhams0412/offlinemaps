#ifndef ValhallaWrapper_h
#define ValhallaWrapper_h

#include <string>
#include <memory>

// Forward declaration of Valhalla Actor
namespace valhalla {
    namespace tyr {
        class actor_t;
    }
}

/**
 * PRODUCTION-READY Valhalla Wrapper for iOS.
 */
class ValhallaWrapper {
public:
    ValhallaWrapper(const std::string& configPath);
    ~ValhallaWrapper();

    std::string getRoute(double startLat, double startLng, double endLat, double endLng, const std::string& profile);
    bool isReady() const;

private:
    std::unique_ptr<valhalla::tyr::actor_t> actor;
    bool ready;
};

#endif
