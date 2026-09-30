#import "ShortsSpeed.h"
#import "YouModPlaybackSpeed.h"
#import <objc/runtime.h>
#import "YouModPlaybackRate.h"

// Local protocols describe messages, not private class inheritance. In
// particular, this file needs no YTReelPlayerViewControllerSub declaration.
@protocol YMShortsSpeedOwner <NSObject>
- (id)player;
- (NSString *)videoId;
- (NSString *)currentVideoID;
- (id)currentVideo;
- (id)activeVideo;
@end

@protocol YMShortsSpeedPlayback <NSObject>
- (void)setPlaybackRate:(float)rate;
- (BOOL)isPlayingAd;
@end

@interface YMShortsSpeedControl : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, weak) id player;
@property (nonatomic, copy) NSString *videoID;
@property (nonatomic, weak) id video;
@end

@implementation YMShortsSpeedControl
@end

static char YMShortsSpeedControlKey;

static id<YMShortsSpeedPlayback> YMShortsSpeedPlayer(UIViewController *controller) {
    if (![controller respondsToSelector:@selector(player)]) return nil;
    id player = [(id<YMShortsSpeedOwner>)controller player];
    if (![player respondsToSelector:@selector(setPlaybackRate:)]) return nil;

    if ([player respondsToSelector:@selector(isPlayingAd)] &&
        [(id<YMShortsSpeedPlayback>)player isPlayingAd]) return nil;
    return player;
}

static NSString *YMShortsSpeedVideoID(UIViewController *controller) {
    id<YMShortsSpeedOwner> owner = (id)controller;
    id videoID = [owner respondsToSelector:@selector(videoId)] ? [owner videoId] : nil;
    id<YMShortsSpeedOwner> player = [owner respondsToSelector:@selector(player)] ? [owner player] : nil;
    if (![videoID isKindOfClass:[NSString class]] || [videoID length] == 0) {
        videoID = [player respondsToSelector:@selector(currentVideoID)] ? [player currentVideoID] : nil;
    }
    return [videoID isKindOfClass:[NSString class]] ? videoID : nil;
}

static id YMShortsVideoObject(UIViewController *controller) {
    id<YMShortsSpeedOwner> owner = (id)controller;
    id video = [owner respondsToSelector:@selector(currentVideo)] ? [owner currentVideo] : nil;
    id<YMShortsSpeedOwner> player = [owner respondsToSelector:@selector(player)] ? [owner player] : nil;
    return video ?: ([player respondsToSelector:@selector(activeVideo)] ? [player activeVideo] : nil);
}

void YMUpdateShortsSpeedButton(UIViewController *controller, NSString *title) {
    // Called from the reel's UI lifecycle and playback-time callback. Never
    // manipulate UIKit from a background playback callback or load an offscreen view.
    if (![NSThread isMainThread]) {
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{
            YMUpdateShortsSpeedButton(weakController, title);
        });
        return;
    }
    if (!controller.isViewLoaded) return;
    YMShortsSpeedControl *control = objc_getAssociatedObject(controller, &YMShortsSpeedControlKey);
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:ShortsSpeedButton];
    id player = enabled ? YMShortsSpeedPlayer(controller) : nil;
    NSString *videoID = enabled ? YMShortsSpeedVideoID(controller) : nil;
    if (!enabled) {
        [control.button removeFromSuperview];
        objc_setAssociatedObject(controller, &YMShortsSpeedControlKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    UIView *view = controller.view;
    if (!control) {
        control = [YMShortsSpeedControl new];
        control.button = [UIButton buttonWithType:UIButtonTypeSystem];
        control.button.accessibilityIdentifier = @"YouMod.Shorts.Speed";
        control.button.accessibilityLabel = title;
        [control.button setImage:[UIImage systemImageNamed:@"speedometer"] forState:UIControlStateNormal];
        control.button.tintColor = UIColor.whiteColor;
        control.button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        control.button.layer.cornerRadius = 22;
        control.button.showsMenuAsPrimaryAction = YES;
        objc_setAssociatedObject(controller, &YMShortsSpeedControlKey, control, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (control.button.superview != view) {
        [control.button removeFromSuperview];
        [view addSubview:control.button];
    }
    // Below the native top bar, away from the right-hand Shorts action rail.
    // Only the 44-point button intercepts touches; no pan recognizer is added.
    UIEdgeInsets insets = view.safeAreaInsets;
    control.button.frame = CGRectMake(insets.left + 12, insets.top + 64, 44, 44);
    [view bringSubviewToFront:control.button];

    id video = YMShortsVideoObject(controller);
    BOOL sameVideo = control.videoID == videoID || [control.videoID isEqualToString:videoID];
    BOOL ready = YMShortsRateSignature(player) && (videoID.length > 0 || video);
    // Keep the button visible even if this YouTube version has not exposed a
    // usable player yet. This makes an unsupported path distinguishable from
    // a missing view hook, instead of silently removing the UI.
    if (control.button.menu && control.player == player && sameVideo &&
        control.video == video && control.button.tag == (ready ? 1 : 0)) return;
    control.button.tag = ready ? 1 : 0;
    control.video = video;
    control.player = player;
    control.videoID = videoID;
    __weak UIViewController *weakController = controller;
    __weak id weakPlayer = player;
    __weak id weakVideo = video;
    NSString *menuVideoID = [videoID copy];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    if (!ready) {
        extern NSBundle *YouModBundle(void);
        NSString *message = [YouModBundle() localizedStringForKey:@"SHORTS_SPEED_UNAVAILABLE"
            value:@"Playback controls unavailable" table:nil];
        UIAction *unavailable = [UIAction actionWithTitle:message image:nil identifier:nil
            handler:^(__kindof UIAction * __unused action) {}];
        unavailable.attributes = UIMenuElementAttributesDisabled;
        [actions addObject:unavailable];
    }
    for (NSNumber *value in (ready ? YMPlaybackSpeedValues() : @[])) {
        float rate = value.floatValue;
        UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%gx", rate]
                                             image:nil identifier:nil handler:^(__kindof UIAction * __unused selectedAction) {
            UIViewController *owner = weakController;
            if (!owner.isViewLoaded || !owner.view.window ||
                ![[NSUserDefaults standardUserDefaults] boolForKey:ShortsSpeedButton]) return;
            id<YMShortsSpeedPlayback> currentPlayer = YMShortsSpeedPlayer(owner);
            NSString *currentID = YMShortsSpeedVideoID(owner);
            BOOL sameVideoNow = menuVideoID.length > 0
                ? [menuVideoID isEqualToString:currentID]
                : (weakVideo && weakVideo == YMShortsVideoObject(owner));
            // A menu left open while paging must not change a different reel.
            if (!currentPlayer || currentPlayer != weakPlayer || !sameVideoNow) return;
            YMApplyPlaybackRate(currentPlayer, rate);
        }];
        [actions addObject:action];
    }
    control.button.menu = [UIMenu menuWithTitle:title children:actions];
}

void YMUpdateShortsSpeedFromView(UIView *view, NSString *title) {
    if (!view.window) return;
    Class reelClass = NSClassFromString(@"YTReelPlayerViewController");
    for (UIResponder *responder = view; responder; responder = responder.nextResponder) {
        if (reelClass && [responder isKindOfClass:reelClass]) {
            YMUpdateShortsSpeedButton((UIViewController *)responder, title);
            return;
        }
    }
}
