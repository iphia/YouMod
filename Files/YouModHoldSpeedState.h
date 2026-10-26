#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Transient state: never export or reuse a hold lock in another player/video.
@interface YMHoldSpeedState : NSObject
@property (nonatomic, weak) id video;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL appliedDefaultSpeed;
@property (nonatomic) BOOL applyingDefaultSpeed;
@property (nonatomic) BOOL locked;
@property (nonatomic) BOOL initialLock;
@property (nonatomic) BOOL pendingToggle;
@property (nonatomic) CGFloat startY;
@property (nonatomic) float normalRate;
@end

static inline YMHoldSpeedState *YMHoldState(id player, id video) {
    static char key;
    YMHoldSpeedState *state = objc_getAssociatedObject(player, &key);
    if (!state || state.video != video) {
        state = [YMHoldSpeedState new];
        state.video = video;
        state.normalRate = 1.0f;
        objc_setAssociatedObject(player, &key, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static inline BOOL YMFinishHold(YMHoldSpeedState *state, BOOL ended, BOOL allowLock) {
    state.locked = allowLock && (ended && state.pendingToggle
        ? !state.initialLock : state.initialLock);
    state.active = NO;
    state.pendingToggle = NO;
    return state.locked;
}
