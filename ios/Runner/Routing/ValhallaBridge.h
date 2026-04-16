#import <Foundation/Foundation.h>

/**
 * Objective-C bridge to allow Swift to communicate with the Valhalla C++ engine.
 */
@interface ValhallaBridge : NSObject

/**
 * Initializes the engine with the path to the valhalla.json config
 */
- (instancetype)initWithConfigPath:(NSString*)configPath;

/**
 * Requests a route and returns the result as a JSON string
 */
- (NSString*)requestRoute:(double)startLat 
                 startLng:(double)startLng 
                   endLat:(double)endLat 
                   endLng:(double)endLng 
                  profile:(NSString*)profile;

/**
 * Returns true if the engine is ready
 */
- (BOOL)isReady;

@end
