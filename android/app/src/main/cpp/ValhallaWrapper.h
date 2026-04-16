#ifndef ValhallaWrapper_h
#define ValhallaWrapper_h

#include <string>
#include <memory>

/**
 * PRODUCTION-READY Valhalla Wrapper.
 * This class directly interacts with the native Valhalla library.
 */
class ValhallaWrapper {
public:
    ValhallaWrapper(const std::string& configPath);
    ~ValhallaWrapper();

    std::string getRoute(double startLat, double startLng, double endLat, double endLng, const std::string& profile);
    bool isReady() const;

private:
    struct ActorDeleter {
        void operator()(void* ptr) const;
    };

    std::unique_ptr<void, ActorDeleter> actor;
    bool ready;
};

#endif
