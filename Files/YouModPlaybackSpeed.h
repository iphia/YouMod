#pragma once

#import <Foundation/Foundation.h>
#include <math.h>

#define ShortsSpeedButton @"YouModShortsSpeedButton"

// Shared with the existing extended playback-speed picker.
static inline NSArray<NSNumber *> *YMPlaybackSpeedValues(void) {
    return @[@0.25f, @0.5f, @0.75f, @1.0f, @1.25f, @1.5f, @1.75f,
             @2.0f, @2.5f, @3.0f, @5.0f, @7.5f, @10.0f];
}

// Index zero disables automatic speed. Keep the mapping shared with Player.x.
static inline float YMDefaultPlaybackRateForIndex(NSInteger index) {
    NSArray<NSNumber *> *rates = @[@1.0f, @0.25f, @0.5f, @0.75f, @1.0f,
        @1.25f, @1.5f, @1.75f, @2.0f, @3.0f, @4.0f, @5.0f];
    return index > 0 && index < (NSInteger)rates.count ? rates[index].floatValue : 1.0f;
}

static inline float YMShortsToggleRate(float currentRate, NSInteger defaultIndex) {
    return fabsf(currentRate - 1.0f) < 0.01f ? YMDefaultPlaybackRateForIndex(defaultIndex) : 1.0f;
}
