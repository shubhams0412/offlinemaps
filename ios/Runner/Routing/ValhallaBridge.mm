#import "ValhallaBridge.h"
#include "ValhallaWrapper.h"

@implementation ValhallaBridge {
    ValhallaWrapper* _engine;
}

- (instancetype)initWithConfigPath:(NSString*)configPath {
    self = [super init];
    if (self) {
        // Initialize the C++ wrapper
        _engine = new ValhallaWrapper([configPath UTF8String]);
    }
    return self;
}

- (BOOL)isReady {
    return _engine && _engine->isReady();
}

- (NSString*)requestRoute:(double)startLat 
                 startLng:(double)startLng 
                   endLat:(double)endLat 
                   endLng:(double)endLng 
                  profile:(NSString*)profile {
    
    if (!_engine) return @"{\"error\": \"Engine not initialized\"}";
    
    // Call the C++ engine
    std::string result = _engine->getRoute(
        startLat, 
        startLng, 
        endLat, 
        endLng, 
        [profile UTF8String]
    );
    
    return [NSString stringWithUTF8String:result.c_str()];
}

- (void)dealloc {
    if (_engine) {
        delete _engine;
        _engine = nullptr;
    }
}

@end
