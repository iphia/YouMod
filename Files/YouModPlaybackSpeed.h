#pragma once

#import <Foundation/Foundation.h>

#define ShortsSpeedButton @"YouModShortsSpeedButton"

// Shared with the existing extended playback-speed picker.
static inline NSArray<NSNumber *> *YMPlaybackSpeedValues(void) {
    return @[@0.25f, @0.5f, @0.75f, @1.0f, @1.25f, @1.5f, @1.75f,
             @2.0f, @2.5f, @3.0f, @5.0f, @7.5f, @10.0f];
}
