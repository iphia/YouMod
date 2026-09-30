#import "ShortsSpeed.h"
#import "YouModPlaybackSpeed.h"
#import <objc/runtime.h>
#include <string.h>

// Local protocols describe messages, not private class inheritance. In
// particular, this file needs no YTReelPlayerViewControllerSub declaration.
@protocol YMShortsSpeedOwner <NSObject>
- (id)player;
- (NSString *)videoId;
@end

@protocol YMShortsSpeedPlayback <NSObject>
- (void)setPlaybackRate:(float)rate;
- (BOOL)isPlayingAd;
@end

@interface YMShortsSpeedControl : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, weak) id player;
@property (nonatomic, copy) NSString *videoID;
@end

@implementation YMShortsSpeedControl
@end

static char YMShortsSpeedControlKey;

static id<YMShortsSpeedPlayback> YMShortsSpeedPlayer(UIViewController *controller) {
    if (![controller respondsToSelector:@selector(player)]) return nil;
    id player = [(id<YMShortsSpeedOwner>)controller player];
    if (![player respondsToSelector:@selector(setPlaybackRate:)]) return nil;

    // A selector check alone cannot detect an incompatible scalar ABI.
    NSMethodSignature *signature = [player methodSignatureForSelector:@selector(setPlaybackRate:)];
    if (signature.numberOfArguments != 3 ||
        strcmp(signature.methodReturnType, @encode(void)) != 0 ||
        strcmp([signature getArgumentTypeAtIndex:2], @encode(float)) != 0) return nil;
    if ([player respondsToSelector:@selector(isPlayingAd)] &&
        [(id<YMShortsSpeedPlayback>)player isPlayingAd]) return nil;
    return player;
}

static NSString *YMShortsSpeedVideoID(UIViewController *controller) {
    if (![controller respondsToSelector:@selector(videoId)]) return nil;
    id videoID = [(id<YMShortsSpeedOwner>)controller videoId];
    return [videoID isKindOfClass:[NSString class]] ? videoID : nil;
}

void YMUpdateShortsSpeedButton(UIViewController *controller, NSString *title) {
    // Called from the reel's UI lifecycle and playback-time callback. Never
    // manipulate UIKit from a background playback callback or load an offscreen view.
    if (![NSThread isMainThread] || !controller.isViewLoaded) return;
    YMShortsSpeedControl *control = objc_getAssociatedObject(controller, &YMShortsSpeedControlKey);
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:ShortsSpeedButton];
    id player = enabled ? YMShortsSpeedPlayer(controller) : nil;
    NSString *videoID = enabled ? YMShortsSpeedVideoID(controller) : nil;
    if (!player || videoID.length == 0) {
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

    BOOL sameVideo = control.videoID == videoID || [control.videoID isEqualToString:videoID];
    if (control.button.menu && control.player == player && sameVideo) return;
    control.player = player;
    control.videoID = videoID;
    __weak UIViewController *weakController = controller;
    __weak id weakPlayer = player;
    NSString *menuVideoID = [videoID copy];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    for (NSNumber *value in YMPlaybackSpeedValues()) {
        float rate = value.floatValue;
        UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%gx", rate]
                                             image:nil identifier:nil handler:^(__kindof UIAction * __unused selectedAction) {
            UIViewController *owner = weakController;
            if (!owner.isViewLoaded || !owner.view.window ||
                ![[NSUserDefaults standardUserDefaults] boolForKey:ShortsSpeedButton]) return;
            id<YMShortsSpeedPlayback> currentPlayer = YMShortsSpeedPlayer(owner);
            NSString *currentID = YMShortsSpeedVideoID(owner);
            BOOL sameVideoNow = menuVideoID == currentID || [menuVideoID isEqualToString:currentID];
            // A menu left open while paging must not change a different reel.
            if (!currentPlayer || currentPlayer != weakPlayer || !sameVideoNow) return;
            [currentPlayer setPlaybackRate:rate];
        }];
        [actions addObject:action];
    }
    control.button.menu = [UIMenu menuWithTitle:title children:actions];
}
