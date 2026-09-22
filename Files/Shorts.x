#import "Headers.h"
#import <objc/runtime.h>

// Enables shorts quality - works best with YTClassicVideoQuality
%hook YTHotConfig
- (BOOL)enableOmitAdvancedMenuInShortsVideoQualityPicker { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)enableShortsVideoQualityPicker { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableImmersiveLivePlayerVideoQuality { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableShortsPlayerVideoQuality { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableShortsPlayerVideoQualityRestartVideo { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableSimplerTitleInShortsVideoQualityPicker { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
%end

// Always show Shorts seekbar
%hook YTShortsPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return IS_ENABLED(ShowShortsSeekbar) ? NO : %orig; }
%end

%hook YTReelPlayerViewControllerSub
- (BOOL)shouldAlwaysEnablePlayerBar { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return IS_ENABLED(ShowShortsSeekbar) ? NO : %orig; }
%end

%hook YTColdConfig
- (BOOL)iosEnableVideoPlayerScrubber { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)mobileShortsTablnlinedExpandWatchOnDismiss { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
%end

static const void *YMShortsEndHandledKey = &YMShortsEndHandledKey;

static void YouModMakeAShortsAction(
    YTReelPlayerViewController *self,
    YTSingleVideoController *video,
    YTSingleVideoTime *time
) {
    NSInteger action = INTFORVAL(ShortsActionIndex);

    if (action == 0 || !video || !time)
        return;

    CGFloat duration = video.totalMediaTime;
    CGFloat current = time.time;

    if (!isfinite(duration) ||
        !isfinite(current) ||
        duration <= 0.0 ||
        current < 0.0) {
        return;
    }

    /*
     * 같은 쇼츠를 다시 처음부터 재생한 경우
     * 종료 처리 플래그를 초기화.
     */
    if (current < 0.5) {
        objc_setAssociatedObject(
            video,
            YMShortsEndHandledKey,
            @NO,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        return;
    }

    /*
     * 이미 이 재생에서 종료 동작을 실행했다면
     * 다시 실행하지 않음.
     */
    NSNumber *handled =
        objc_getAssociatedObject(video, YMShortsEndHandledKey);

    if (handled.boolValue)
        return;

    CGFloat remaining = duration - current;

    /*
     * 마지막 0.05초에서 종료 처리.
     *
     * 기존 floor() 방식은 최대 약 1초 일찍
     * 종료됐지만 이쪽은 약 50ms만 남기고 처리함.
     */
    const CGFloat tolerance = 0.05;

    if (remaining > tolerance)
        return;

    /*
     * YouTube에서 시간이 아주 조금 duration을
     * 넘어 보고되는 경우도 허용.
     */
    if (remaining < -0.25)
        return;

    /*
     * 동작을 먼저 처리 완료 상태로 만들어서
     * 연속으로 들어오는 time callback이
     * pause/next를 여러 번 실행하지 않도록 함.
     */
    objc_setAssociatedObject(
        video,
        YMShortsEndHandledKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    if (action == 1) {
        [self reelContentViewRequestsAdvanceToNextVideo:nil];

    } else if (action == 2) {
        [self reelContentViewRequestsPlayPauseToggle:nil];
    }
}

static BOOL isShortsOnlyOn = YES;
static BOOL isFullscreenEnabled = NO;

%hook YTReelPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return IS_ENABLED(ShowShortsSeekbar) ? NO : %orig; }
- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    YouModMakeAShortsAction(self, video, time);
}
- (void)loadPlayerBar {
    %orig;
    if ((isShortsOnlyOn && IS_ENABLED(ShortsOnly)) || (isFullscreenEnabled && IS_ENABLED(FullScreenShorts))) [[self valueForKey:@"_pivotBarProvider"] performSelector:@selector(hidePivotBar)];
    YTPlayerViewController *main = self.player;
    if (INTFORVAL(CaptionTrack) != 0) [main performSelector:@selector(YouModAutoCaptions) withObject:nil afterDelay:0.5];
    if (INTFORVAL(AutoSpeedIndex) != 0) [main performSelector:@selector(YouModSetAutoSpeed) withObject:nil afterDelay:0.5];
    if (INTFORVAL(AudioTrack) != 0) [self performSelector:@selector(YouModAutoAudioTrack:) withObject:main afterDelay:0.5];
}
%new
- (void)YouModAutoAudioTrack:(YTPlayerViewController *)pv {
    NSInteger selectedIndex = INTFORVAL(AudioTrackLangIndex);
    NSArray *langCodes = getAllSystemLanguageValues();
    NSString *userTargetLang = langCodes[selectedIndex];
    id switchcon = self.audioTrackController;
    NSArray *availableTracks = [switchcon valueForKey:@"_availableAudioTracks"];
    if (!availableTracks || availableTracks.count == 0) return;
    YTIAudioTrack *matchedTrack = nil;

    if (INTFORVAL(AudioTrack) == 1) {
        // Loop for all tracks
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasSuffix:@".4"]) {
                matchedTrack = track;
                break;
            }
        }
    } else if (INTFORVAL(AudioTrack) == 2) {
        // Loop for all tracks
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasPrefix:userTargetLang]) {
                matchedTrack = track;
                break;
            }
        }

        // Check if it's dubbed
        if (matchedTrack && [matchedTrack isAutoDubbed] && IS_ENABLED(NoDubbedAudioTrack)) matchedTrack = nil;

        if (!matchedTrack && IS_ENABLED(NoDubbedAudioTrack)) {
            for (YTIAudioTrack *track in availableTracks) {
                if ([track.id_p hasSuffix:@".4"]) {
                    matchedTrack = track;
                    break;
                }
            }
        }
    }

    // If found, change to it
    if (matchedTrack) {
        [pv setAudioTrack:matchedTrack source:0];
    }
}
%end

%hook YTReelTopBarView
- (void)didMoveToWindow {
    %orig;
    if (IS_ENABLED(HideShortsTopbar)) {
        if (self.superview) {
            [self removeFromSuperview];
        }
    } else if (IS_ENABLED(HideShortsSubbar)) {
        UIView *subbar = [self valueForKey:@"_pausedStateCarouselView"];
        if (subbar && subbar.superview) {
            [subbar removeFromSuperview];
        }
    }
}
%end

extern void YouModConfigureDownloadButton(_ASDisplayView *view);

static void YouModFilterShortsButtons(_ASDisplayView *self, NSString *iden) {
    NSDictionary *buttonsList = @{
        @"id.reel_like_button": @(IS_ENABLED(RemoveShortsLikeButton)),
        @"id.reel_like_toggled_button": @(IS_ENABLED(RemoveShortsLikeButton)),
        @"id.reel_comment_button": @(IS_ENABLED(RemoveShortsCommentButton)),
        @"id.reel_share_button": @(IS_ENABLED(RemoveShortsShareButton)),
        @"id.reel_remix_button" : @(IS_ENABLED(RemoveShortsRemixButton)),
        @"id.reel_pivot_button": @(IS_ENABLED(RemoveShortsSoundMetadataButton))
    };
    for (NSString *button in buttonsList) {
        if ([iden isEqualToString:button] && [buttonsList[button] boolValue]) {
            _ASDisplayView *mainView = (_ASDisplayView *)self.superview;
            ASDisplayNode *node = mainView.keepalive_node;
            for (_ASDisplayView *view in node.yogaChildren) {
                if ([[view description] containsString:button]) {
                    [node removeYogaChild:view];
                    [self removeFromSuperview];
                    break;
                }
            }
            break;
        }
    }
}

static void YouModFilterShortsPausedHeader(_ASDisplayView *self, NSString *iden) {
    NSDictionary *buttonsList = @{
        @"id.ui.shorts_paused_state.subscriptions_button": @(IS_ENABLED(RemoveShortsPausedSubButton)),
        @"id.ui.shorts_paused_state.live_button": @(IS_ENABLED(RemoveShortsPausedLiveButton)),
        @"id.ui.shorts_paused_state.lens_button": @(IS_ENABLED(RemoveShortsPausedLensButton)),
        @"id.ui.shorts_paused_state.trends_button" : @(IS_ENABLED(RemoveShortsPausedTrendsButton))
    };
    for (NSString *button in buttonsList) {
        if ([iden isEqualToString:button] && [buttonsList[button] boolValue]) {
            ASScrollView *mainView = (ASScrollView *)self.superview;
            ASDisplayNode *node = mainView.scrollNode;
            for (_ASDisplayView *view in node.yogaChildren) {
                if ([[view description] containsString:button]) {
                    [node removeYogaChild:view];
                    [self removeFromSuperview];
                    break;
                }
            }
            break;
        }
    }
}

static void YouModFilterShortsDisclosure(_ASDisplayView *self, NSString *iden) {
    if (![self.accessibilityIdentifier isEqualToString:@"eml.shorts-disclosures"] || !IS_ENABLED(RemoveShortsDisclosure)) return;
    _ASDisplayView *dpView = (_ASDisplayView *)self.superview;
    ASDisplayNode *node = dpView.keepalive_node;
    _ASDisplayView *maindpView = (_ASDisplayView *)dpView.superview;
    ASDisplayNode *mainNode = maindpView.keepalive_node;
    [mainNode removeYogaChild:node];
    [maindpView removeFromSuperview];
}

// _ASDisplayView filters
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    YouModConfigureDownloadButton(self);
    NSString *iden = self.accessibilityIdentifier;
    if (!iden || iden.length == 0) return;
    NSDictionary *elements = @{
        @"product_sticker.main_target": @(IS_ENABLED(HideShortsProducts)),
        @"product_sticker.secondary_target": @(IS_ENABLED(HideShortsProducts)),
        @"id.elements.components.suggested_action": @(IS_ENABLED(HideShortsRecbar))
    };
    if ([elements[iden] boolValue]) {
        [self removeFromSuperview];
        return;
    }
    if ([iden isEqualToString:@"eml.reel_sponsor_button"] && IS_ENABLED(RemoveChannelSponsorAll)) {
        [self.superview removeFromSuperview];
        return;
    }
    
    YouModFilterShortsButtons(self, iden);
    YouModFilterShortsPausedHeader(self, iden);
    YouModFilterShortsDisclosure(self, iden);
}
%end

%hook YTAppDelegate
- (void)appDidBecomeActive {
    %orig;
    if ((isFullscreenEnabled && IS_ENABLED(FullScreenShorts)) || (isShortsOnlyOn && IS_ENABLED(ShortsOnly))) {
        [[self valueForKey:@"_appViewController"] performSelector:@selector(hidePivotBar)];
    }
}
%end

%hook YTReelWatchPlaybackOverlayView
%property (nonatomic, retain) UIPinchGestureRecognizer *YouModFullscreenGesture;
- (void)didMoveToWindow {
    %orig;
    if (!IS_ENABLED(FullScreenShorts)) return;
    if (!self.YouModFullscreenGesture) {
        self.YouModFullscreenGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(YouModFullscrrenGestureHandler:)];
        self.YouModFullscreenGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
        [self.superview addGestureRecognizer:self.YouModFullscreenGesture];
    }
}
%new
- (void)YouModFullscrrenGestureHandler:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || (isShortsOnlyOn && IS_ENABLED(ShortsOnly))) return;
    UIViewController *appVC = [self valueForKey:@"_pivotBarProvider"];
    BOOL isTabBarHidden = [appVC performSelector:@selector(isPivotBarHidden)];
    if (gesture.scale > 1.0) {
        if (!isTabBarHidden) {
            [appVC performSelector:@selector(hidePivotBar)];
            [UIView animateWithDuration:0.3 animations:^{
                self.alpha = 0;
            }];
            isFullscreenEnabled = YES;
        }
    } else if (gesture.scale < 1.0) {
        if (isTabBarHidden) {
            [appVC performSelector:@selector(showPivotBar)];
            [UIView animateWithDuration:0.3 animations:^{
                self.alpha = 1;
            }];
            isFullscreenEnabled = NO;
        }
    }
}
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.YouModFullscreenGesture) {
        return YES;
    }
    return NO;
}
%end

%hook YTReelContentView
%property (nonatomic, retain) UILongPressGestureRecognizer *YouModExitShortsOnlyGesture;
- (void)setPlaybackView:(id)arg1 {
    %orig;
    self.playbackOverlay.alpha = !isFullscreenEnabled;
    if (!IS_ENABLED(ShortsOnly)) return;
    if (isShortsOnlyOn) {
        self.YouModExitShortsOnlyGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(YouModTurnOffShortsOnly:)];
        self.YouModExitShortsOnlyGesture.numberOfTouchesRequired = 2;
        self.YouModExitShortsOnlyGesture.minimumPressDuration = 0.5;
        self.YouModExitShortsOnlyGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
        [self addGestureRecognizer:self.YouModExitShortsOnlyGesture];
    }
}
%new
- (void)YouModTurnOffShortsOnly:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    isShortsOnlyOn = NO;
    UIView *parent = sbGetNotificationParent();
    [SBSkipNotificationView showSuccessInView:parent message:LOC(@"SHORTS_ONLY_DISABLED") duration:3.0];

    [[[[self valueForKey:@"_parentResponder"] valueForKey:@"_delegate"] valueForKey:@"_pivotBarProvider"] performSelector:@selector(showPivotBar)];
    [UIView animateWithDuration:0.3 animations:^{
        self.playbackOverlay.alpha = 1;
    }];
}
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.YouModExitShortsOnlyGesture && [otherGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.YouModExitShortsOnlyGesture) {
        return NO;
    }
    return YES;
}
%end
