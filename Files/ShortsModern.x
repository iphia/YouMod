#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ShortsSpeed.h"
#import "YouModPlaybackSpeed.h"

// Signatures verified from the user's YouTube 21.38.2 runtime dump.
// No fabricated superclass declaration for a private YouTube class is needed.
@protocol YMModernReel <NSObject>
- (id)player;
- (void)pause;
@end

@protocol YMModernReelPlayer <NSObject>
- (id)activeVideo;
- (NSString *)currentVideoID;
- (BOOL)isPlayingAd;
- (void)YouModSetAutoSpeed;
@end

#import "YouModShortsSession.h"

@implementation YMModernReelState
@end

static char YMModernReelStateKey;
extern NSBundle *YouModBundle(void);

static YMModernReelState *YMModernState(id owner) {
    YMModernReelState *state = objc_getAssociatedObject(owner, &YMModernReelStateKey);
    if (!state) {
        state = [YMModernReelState new];
        objc_setAssociatedObject(owner, &YMModernReelStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static id<YMModernReelPlayer> YMModernPlayer(id owner) {
    if (![owner respondsToSelector:@selector(player)]) return nil;
    id player = [(id<YMModernReel>)owner player];
    if (![player respondsToSelector:@selector(activeVideo)] ||
        ![player respondsToSelector:@selector(isPlayingAd)] ||
        [(id<YMModernReelPlayer>)player isPlayingAd]) return nil;
    return player;
}

static void YMModernRefresh(UIViewController *owner, BOOL applyDefault, id callbackVideo) {
    if (!NSThread.isMainThread || !owner.isViewLoaded) return;
    YMUpdateShortsSpeedButton(owner, [YouModBundle() localizedStringForKey:@"SHORTS_SPEED_BUTTON"
        value:@"Shorts playback speed" table:nil]);
    YMModernReelState *state = YMModernState(owner);
    if (!applyDefault || !state.visible || !owner.view.window) return;
    id<YMModernReelPlayer> player = YMModernPlayer(owner);
    id video = [player activeVideo];
    if (!player || !video || (callbackVideo && callbackVideo != video)) return;
    NSString *videoID = [player respondsToSelector:@selector(currentVideoID)] ? [player currentVideoID] : nil;
    if (![videoID isKindOfClass:NSString.class]) videoID = nil;
    NSInteger index = [NSUserDefaults.standardUserDefaults integerForKey:@"YouModAutoSpeedIndex"];
    if (![player respondsToSelector:@selector(YouModSetAutoSpeed)] ||
        !YMClaimShortsDefault(state, player, video, videoID, index)) return;
    // Once per player/video, preserving later manual speed selections.
    [player YouModSetAutoSpeed];
    YMUpdateShortsSpeedButton(owner, [YouModBundle() localizedStringForKey:@"SHORTS_SPEED_BUTTON"
        value:@"Shorts playback speed" table:nil]);
}

static BOOL YMModernShouldStop(id owner) {
    UIViewController *controller = (UIViewController *)owner;
    return [NSUserDefaults.standardUserDefaults integerForKey:@"YouModMakeAShortsAction"] == 2 &&
        YMModernState(owner).visible && controller.isViewLoaded && controller.view.window &&
        YMModernPlayer(owner) != nil && [owner respondsToSelector:@selector(pause)];
}

%hook YTReelContainerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    YMModernState(self).visible = YES;
    YMModernRefresh((UIViewController *)self, NO, nil);
}
- (void)viewDidLayoutSubviews {
    %orig;
    YMModernRefresh((UIViewController *)self, NO, nil);
}
- (void)pageDidEnter {
    %orig;
    YMModernState(self).visible = YES;
    YMModernRefresh((UIViewController *)self, YES, nil);
}
- (void)pageWillExit {
    YMModernState(self).visible = NO;
    %orig;
}
- (void)viewWillDisappear:(BOOL)animated {
    YMModernState(self).visible = NO;
    %orig;
}
- (void)loadPlayerBarAndShowIfNeeded {
    %orig;
    YMModernRefresh((UIViewController *)self, NO, nil);
}
- (void)playbackControllerDidActivateVideo:(id)video withPlayerResponse:(id)response {
    %orig;
    YMModernRefresh((UIViewController *)self, YES, video);
}
- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    YMModernRefresh((UIViewController *)self, YES, video);
}
- (BOOL)shouldAutoAdvance {
    if (YMModernShouldStop(self)) return NO;
    return %orig;
}
- (void)handleLoopBehavior {
    if (YMModernShouldStop(self)) {
        [(id<YMModernReel>)self pause];
        return;
    }
    %orig;
}
%end
