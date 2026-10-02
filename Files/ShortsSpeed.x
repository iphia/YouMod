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
- (id)activeVideoPlayerOverlay;
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
@property (nonatomic, copy) void (^showMenu)(void);
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation YMShortsSpeedControl
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && self.showMenu) self.showMenu();
}
@end

static char YMShortsSpeedControlKey;
static char YMShortsLastRateKey;

void YMShortsRememberPlaybackRate(id player, float rate) {
    if (player && isfinite(rate) && rate > 0) {
        objc_setAssociatedObject(player, &YMShortsLastRateKey, @(rate), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static float YMShortsCurrentRate(id player) {
    float rate;
    if (YMReadPlaybackRate(player, &rate)) return rate;
    id<YMShortsSpeedOwner> owner = player;
    id video = [owner respondsToSelector:@selector(activeVideo)] ? [owner activeVideo] : nil;
    if (YMReadPlaybackRate(video, &rate)) return rate;
    id overlay = [owner respondsToSelector:@selector(activeVideoPlayerOverlay)] ? [owner activeVideoPlayerOverlay] : nil;
    if (YMReadPlaybackRate(overlay, &rate)) return rate;
    // Some Shorts versions expose no getter. Observe the existing setter hook
    // so automatic speed and menu selections still participate in the toggle.
    NSNumber *lastRate = objc_getAssociatedObject(player, &YMShortsLastRateKey);
    return lastRate ? lastRate.floatValue : YMDefaultPlaybackRateForIndex(
        [[NSUserDefaults standardUserDefaults] integerForKey:@"YouModAutoSpeedIndex"]);
}


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
        control.button.backgroundColor = UIColor.clearColor;
        [control.button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        control.button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        control.button.titleLabel.adjustsFontSizeToFitWidth = YES;
        control.button.titleLabel.minimumScaleFactor = 0.85;
        control.button.titleLabel.layer.masksToBounds = NO;
        control.button.titleLabel.layer.shadowColor = UIColor.blackColor.CGColor;
        control.button.titleLabel.layer.shadowOpacity = 0.85;
        control.button.titleLabel.layer.shadowRadius = 2.0;
        control.button.titleLabel.layer.shadowOffset = CGSizeMake(0, 1);
        // An explicit recognizer provides a public, configurable delay.
        // Cancellation prevents the same press from also toggling speed.
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
            initWithTarget:control action:@selector(handleLongPress:)];
        hold.minimumPressDuration = 0.30;
        hold.cancelsTouchesInView = YES;
        [control.button addGestureRecognizer:hold];
        extern NSBundle *YouModBundle(void);
        control.button.accessibilityHint = [YouModBundle() localizedStringForKey:@"SHORTS_SPEED_HINT"
            value:@"Tap to switch between default speed and 1x. Hold for speed options." table:nil];
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
    if (ready) {
        NSString *rateTitle = [NSString stringWithFormat:@"%gx", YMShortsCurrentRate(player)];
        [control.button setImage:nil forState:UIControlStateNormal];
        [control.button setTitle:rateTitle forState:UIControlStateNormal];
        control.button.accessibilityValue = rateTitle;
    } else {
        [control.button setTitle:nil forState:UIControlStateNormal];
        [control.button setImage:[UIImage systemImageNamed:@"speedometer"] forState:UIControlStateNormal];
        control.button.accessibilityValue = nil;
    }
    // Keep the button visible even if this YouTube version has not exposed a
    // usable player yet. This makes an unsupported path distinguishable from
    // a missing view hook, instead of silently removing the UI.
    if (control.showMenu && control.player == player && sameVideo &&
        control.video == video && control.button.tag == (ready ? 1 : 0)) return;
    control.button.tag = ready ? 1 : 0;
    control.video = video;
    control.player = player;
    control.videoID = videoID;
    __weak UIViewController *weakController = controller;
    __weak id weakPlayer = player;
    __weak id weakVideo = video;
    NSString *menuVideoID = [videoID copy];
    UIActionIdentifier toggleID = @"YouMod.Shorts.ToggleSpeed";
    [control.button removeActionForIdentifier:toggleID forControlEvents:UIControlEventPrimaryActionTriggered];
    __weak UIButton *weakButton = control.button;
    UIAction *toggle = [UIAction actionWithTitle:@"" image:nil identifier:toggleID
        handler:^(__kindof UIAction * __unused action) {
            UIViewController *owner = weakController;
            if (!owner.isViewLoaded || !owner.view.window ||
                ![[NSUserDefaults standardUserDefaults] boolForKey:ShortsSpeedButton]) return;
            id currentPlayer = YMShortsSpeedPlayer(owner);
            NSString *currentID = YMShortsSpeedVideoID(owner);
            BOOL sameVideoNow = menuVideoID.length > 0
                ? [menuVideoID isEqualToString:currentID]
                : (weakVideo && weakVideo == YMShortsVideoObject(owner));
            if (!ready || currentPlayer != weakPlayer || !sameVideoNow) return;
            NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:@"YouModAutoSpeedIndex"];
            float rate = YMShortsToggleRate(YMShortsCurrentRate(currentPlayer), index);
            if (YMApplyPlaybackRate(currentPlayer, rate)) {
                YMShortsRememberPlaybackRate(currentPlayer, rate);
                NSString *rateTitle = [NSString stringWithFormat:@"%gx", rate];
                [weakButton setTitle:rateTitle forState:UIControlStateNormal];
                weakButton.accessibilityValue = rateTitle;
            }
        }];
    [control.button addAction:toggle forControlEvents:UIControlEventPrimaryActionTriggered];
    control.showMenu = ^{
        UIViewController *presenter = weakController;
        UIButton *button = weakButton;
        if (!presenter.isViewLoaded || !presenter.view.window || !button.window ||
            presenter.presentedViewController ||
            ![[NSUserDefaults standardUserDefaults] boolForKey:ShortsSpeedButton]) return;
        id currentPlayer = YMShortsSpeedPlayer(presenter);
        NSString *currentID = YMShortsSpeedVideoID(presenter);
        BOOL sameVideoNow = menuVideoID.length > 0
            ? [menuVideoID isEqualToString:currentID]
            : (weakVideo && weakVideo == YMShortsVideoObject(presenter));
        if (ready && (currentPlayer != weakPlayer || !sameVideoNow)) return;
        extern NSBundle *YouModBundle(void);
        NSString *message = ready ? nil : [YouModBundle() localizedStringForKey:@"SHORTS_SPEED_UNAVAILABLE"
            value:@"Playback controls unavailable" table:nil];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:message
            preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *value in (ready ? YMPlaybackSpeedValues() : @[])) {
            float rate = value.floatValue;
            UIAlertAction *action = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%gx", rate]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *selectedAction) {
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
            if (YMApplyPlaybackRate(currentPlayer, rate)) {
                YMShortsRememberPlaybackRate(currentPlayer, rate);
                NSString *rateTitle = [NSString stringWithFormat:@"%gx", rate];
                [weakButton setTitle:rateTitle forState:UIControlStateNormal];
                weakButton.accessibilityValue = rateTitle;
            }
            }];
            [sheet addAction:action];
        }
        NSString *cancel = [YouModBundle() localizedStringForKey:@"CANCEL" value:@"Cancel" table:nil];
        [sheet addAction:[UIAlertAction actionWithTitle:cancel style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = button;
        sheet.popoverPresentationController.sourceRect = button.bounds;
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc]
            initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
        [presenter presentViewController:sheet animated:YES completion:nil];
    };
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
