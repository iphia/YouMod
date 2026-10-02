#pragma once
#import <Foundation/Foundation.h>

@interface YMModernReelState : NSObject
@property (nonatomic) BOOL visible;
@property (nonatomic) BOOL appliedDefault;
@property (nonatomic, weak) id player;
@property (nonatomic, weak) id video;
@property (nonatomic, copy) NSString *videoID;
@end

// Claim exactly one default-speed application for a playback identity.
// The caller has already checked active visibility, ad state, callback identity,
// and setter availability. No selected rate is persisted or overwritten here.
static inline BOOL YMClaimShortsDefault(YMModernReelState *state, id player,
                                        id video, NSString *videoID, NSInteger index) {
    if (!player || !video) return NO;
    BOOL sameIdentity = videoID.length > 0 && state.videoID.length > 0
        ? [state.videoID isEqualToString:videoID] : state.video == video;
    if (state.player != player || !sameIdentity) {
        state.player = player;
        state.video = video;
        state.videoID = videoID;
        state.appliedDefault = NO;
    }
    if (state.appliedDefault || index <= 0 || index >= 12) return NO;
    state.appliedDefault = YES;
    return YES;
}
