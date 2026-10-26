#import <Foundation/Foundation.h>
#include <assert.h>

// Keep the user's actual preferences untouched.
static NSString *testSuiteName;
@interface YMTestDefaults : NSUserDefaults
+ (YMTestDefaults *)standardUserDefaults;
@end
@implementation YMTestDefaults
+ (YMTestDefaults *)standardUserDefaults {
    static NSUserDefaults *defaults;
    if (!defaults) {
        testSuiteName = [@"YouMod.SpeedTests." stringByAppendingString:NSUUID.UUID.UUIDString];
        defaults = [[NSUserDefaults alloc] initWithSuiteName:testSuiteName];
    }
    return (id)defaults;
}
@end
#define NSUserDefaults YMTestDefaults
#import "YouModPlaybackSpeed.h"
#import "YouModShortsSession.h"
#import "YouModHoldSpeedState.h"
@implementation YMModernReelState
@end
@implementation YMHoldSpeedState
@end

// The runner inserts the actual Player.x methods here, replacing only Logos %orig.
static const NSInteger UIGestureRecognizerStateBegan = 1;
static const NSInteger UIGestureRecognizerStateChanged = 2;
@interface YMTestGesture : NSObject
@property NSInteger state;
@end
@implementation YMTestGesture
@end
#define AutoSpeedIndex @"YouModAutoSpeedIndex"
#define INTFORVAL(key) [NSUserDefaults.standardUserDefaults integerForKey:key]
@interface YMTestPlayer : NSObject
@property (strong) id activeVideo;
@property BOOL isPlayingAd;
@property (strong) YMTestGesture *YouModHoldGesture;
@property float rate;
- (void)setPlaybackRate:(float)rate;
- (void)YouModSetAutoSpeed;
@end
@implementation YMTestPlayer
// PLAYER_METHODS
@end

int main(void) {
    @autoreleasepool {
        NSUserDefaults *prefs = (id)NSUserDefaults.standardUserDefaults;
        float expected[] = {1, .25, .5, .75, 1, 1.25, 1.5, 1.75, 2, 3, 4, 5};
        for (NSInteger i = 0; i < 12; i++) assert(YMDefaultPlaybackRateForIndex(i) == expected[i]);
        assert(YMDefaultPlaybackRateForIndex(12) == 1);
        assert(YMDefaultPlaybackRateForIndex(13) == 1);
        [prefs setInteger:12 forKey:AutoSpeedIndex];
        YMTestPlayer *player = [YMTestPlayer new];
        player.activeVideo = [NSObject new];
        [player YouModSetAutoSpeed];
        assert(player.rate == 1);
        [player setPlaybackRate:1.75];
        assert(YMDefaultPlaybackRateForIndex(12) == 1.75);
        player.activeVideo = [NSObject new];
        [player setPlaybackRate:1]; // Startup reset must not erase the last speed.
        assert(YMDefaultPlaybackRateForIndex(12) == 1.75);
        [player YouModSetAutoSpeed];
        assert(player.rate == 1.75);
        YMTestPlayer *reopened = [YMTestPlayer new];
        reopened.activeVideo = [NSObject new];
        [reopened YouModSetAutoSpeed];
        assert(reopened.rate == 1.75);
        player.isPlayingAd = YES;
        [player setPlaybackRate:1];
        [player YouModSetAutoSpeed];
        assert(player.rate == 1 && YMDefaultPlaybackRateForIndex(12) == 1.75);
        player.isPlayingAd = NO;
        YMHoldSpeedState *hold = YMHoldState(player, player.activeVideo);
        hold.active = YES;
        [player setPlaybackRate:2];
        hold.active = NO;
        hold.locked = YES;
        [player setPlaybackRate:2];
        assert(YMDefaultPlaybackRateForIndex(12) == 1.75);
        hold.locked = NO;
        [player setPlaybackRate:1];
        assert(YMDefaultPlaybackRateForIndex(12) == 1);
        for (NSNumber *bad in @[@0, @-1, @(NAN), @(INFINITY)]) YMRememberLastPlaybackRate(bad.floatValue);
        assert(YMDefaultPlaybackRateForIndex(12) == 1);
        [prefs setFloat:NAN forKey:YMLastPlaybackRateKey];
        assert(YMDefaultPlaybackRateForIndex(12) == 1);
        YMRememberLastPlaybackRate(2.5);
        [prefs setInteger:6 forKey:AutoSpeedIndex];
        [player YouModSetAutoSpeed];
        [player setPlaybackRate:3];
        assert(YMDefaultPlaybackRateForIndex(12) == 2.5);
        assert(YMDefaultPlaybackRateForIndex(6) == 1.5);
        YMModernReelState *shorts = [YMModernReelState new];
        assert(YMClaimShortsDefault(shorts, player, player.activeVideo, @"one", 12));
        assert(!YMClaimShortsDefault(shorts, player, player.activeVideo, @"one", 12));
        assert(YMClaimShortsDefault(shorts, player, player.activeVideo, @"two", 12));
        assert(!YMClaimShortsDefault(shorts, player, player.activeVideo, @"three", 13));
        [prefs removePersistentDomainForName:testSuiteName];
        puts("PASS: fixed indexes, last speed, startup resets, new players, ads, holds, invalid values, Shorts");
    }
}
