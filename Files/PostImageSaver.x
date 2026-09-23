#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/message.h>

static __weak id YMCurrentPostImageNode;

static NSURL *YMOriginalPostImageURL(NSURL *url) {
    if (!url) return nil;

    NSString *text = url.absoluteString;

    NSRange crop = [text rangeOfString:@"c-fcrop"];
    if (crop.location != NSNotFound) {
        NSString *original =
            [[text substringToIndex:crop.location]
                stringByAppendingString:@"nd-v1"];

        return [NSURL URLWithString:original] ?: url;
    }

    NSRange slash =
        [text rangeOfString:@"/" options:NSBackwardsSearch];

    if (slash.location == NSNotFound)
        return url;

    NSRange eq =
        [text rangeOfString:@"="
                    options:NSBackwardsSearch
                      range:NSMakeRange(
                          slash.location,
                          text.length - slash.location)];

    if (eq.location == NSNotFound)
        return url;

    NSString *original =
        [[text substringToIndex:eq.location]
            stringByAppendingString:@"=s0"];

    return [NSURL URLWithString:original] ?: url;
}

static void YMSavePostImageData(NSData *data) {
    if (!data.length) return;

    void (^save)(void) = ^{
        [[PHPhotoLibrary sharedPhotoLibrary]
            performChanges:^{
                PHAssetCreationRequest *request =
                    [PHAssetCreationRequest creationRequestForAsset];

                [request addResourceWithType:PHAssetResourceTypePhoto
                                        data:data
                                     options:nil];
            }
            completionHandler:^(BOOL success, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        NSLog(@"[YouMod] Post image saved");
                    } else {
                        NSLog(@"[YouMod] Post image save error: %@", error);
                    }
                });
            }];
    };

    if (@available(iOS 14.0, *)) {
        [PHPhotoLibrary
            requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
            handler:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized ||
                    status == PHAuthorizationStatusLimited) {
                    save();
                }
            }];
    } else {
        [PHPhotoLibrary
            requestAuthorization:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized)
                    save();
            }];
    }
}

@interface YMPostImageSaveTarget : NSObject
+ (instancetype)shared;
- (void)saveTapped:(UIButton *)button;
@end

@implementation YMPostImageSaveTarget

+ (instancetype)shared {
    static YMPostImageSaveTarget *target;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        target = [YMPostImageSaveTarget new];
    });

    return target;
}

- (void)saveTapped:(UIButton *)button {
    id node = YMCurrentPostImageNode;

    if (!node) return;

    SEL urlSelector = NSSelectorFromString(@"URL");

    if (![node respondsToSelector:urlSelector])
        return;

    NSURL *url =
        ((id (*)(id, SEL))objc_msgSend)(node, urlSelector);

    url = YMOriginalPostImageURL(url);

    if (!url) return;

    button.enabled = NO;

    [[[NSURLSession sharedSession]
        dataTaskWithURL:url
        completionHandler:^(NSData *data,
                            NSURLResponse *response,
                            NSError *error) {

            dispatch_async(dispatch_get_main_queue(), ^{
                button.enabled = YES;
            });

            if (data.length)
                YMSavePostImageData(data);

        }] resume];
}

@end

static const NSInteger YMPostImageButtonTag = 0x594D5049;


#pragma mark - Common

static UIViewController *YMOwningController(UIView *view) {
    UIResponder *responder = view;

    while (responder) {
        if ([responder isKindOfClass:UIViewController.class])
            return (UIViewController *)responder;

        responder = responder.nextResponder;
    }

    return nil;
}


static UIView *YMFindVisibleSubviewOfClass(
    UIView *view,
    Class targetClass
) {
    if (!view || !targetClass)
        return nil;

    if ([view isKindOfClass:targetClass] &&
        !view.hidden &&
        view.alpha > 0.01 &&
        view.window) {

        return view;
    }

    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIView *found =
            YMFindVisibleSubviewOfClass(
                subview,
                targetClass
            );

        if (found)
            return found;
    }

    return nil;
}


static UIView *YMFindAncestorOfClass(
    UIView *view,
    Class targetClass
) {
    UIView *current = view;

    while (current) {
        if ([current isKindOfClass:targetClass])
            return current;

        current = current.superview;
    }

    return nil;
}


#pragma mark - Button

static void YMAddPostImageButton(
    UIView *container,
    id node,
    CGFloat topOffset
) {
    if (!container || !node)
        return;

    /*
     * 원래 다운로드 방식 그대로
     */
    YMCurrentPostImageNode = node;

    UIButton *existing =
        (UIButton *)[container
            viewWithTag:YMPostImageButtonTag];

    if (existing) {
        existing.hidden = NO;
        existing.enabled = YES;

        [container bringSubviewToFront:existing];
        return;
    }

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.tag = YMPostImageButtonTag;

    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration
            configurationWithPointSize:18.0
                                weight:UIImageSymbolWeightSemibold];

    UIImage *icon =
        [UIImage
            systemImageNamed:@"square.and.arrow.down"
            withConfiguration:config];

    [button setImage:icon
            forState:UIControlStateNormal];

    button.tintColor = UIColor.whiteColor;

    button.layer.shadowColor =
        UIColor.blackColor.CGColor;

    button.layer.shadowOpacity = 0.6;
    button.layer.shadowRadius = 3.0;
    button.layer.shadowOffset = CGSizeZero;

    button.translatesAutoresizingMaskIntoConstraints = NO;

    [button
        addTarget:[YMPostImageSaveTarget shared]
           action:@selector(saveTapped:)
 forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:button];
    [container bringSubviewToFront:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor
            constraintEqualToAnchor:container.leadingAnchor
                         constant:12.0],

        [button.topAnchor
            constraintEqualToAnchor:
                container.safeAreaLayoutGuide.topAnchor
                         constant:topOffset],

        [button.widthAnchor
            constraintEqualToConstant:44.0],

        [button.heightAnchor
            constraintEqualToConstant:44.0]
    ]];
}


#pragma mark - New UI

static void YMTryAttachNewPostImageButton(
    UIWindow *window,
    id node,
    NSInteger attempt
) {
    if (!window || !node)
        return;

    Class postsPresenterClass =
        NSClassFromString(
            @"YTPostsContentPresenterView"
        );

    Class reelRootClass =
        NSClassFromString(
            @"YTReelWatchRootView"
        );

    if (!postsPresenterClass ||
        !reelRootClass) {
        return;
    }

    UIView *postsPresenter =
        YMFindVisibleSubviewOfClass(
            window,
            postsPresenterClass
        );

    if (postsPresenter) {

        UIView *viewerRoot =
            YMFindAncestorOfClass(
                postsPresenter,
                reelRootClass
            );

        if (viewerRoot &&
            !viewerRoot.hidden &&
            viewerRoot.alpha > 0.01 &&
            viewerRoot.window) {

            /*
             * 로그인 상태의 새 게시물 UI
             */
            YMAddPostImageButton(
                viewerRoot,
                node,
                60.0
            );

            return;
        }
    }

    /*
     * 생성 타이밍 차이 대비
     */
    if (attempt >= 6)
        return;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.15 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

        YMTryAttachNewPostImageButton(
            window,
            node,
            attempt + 1
        );
    });
}


#pragma mark - Hooks

%hook YTImageZoomNode


/*
 * 구형 UI
 *
 * 로그아웃 상태 등에서 기존 YTKACE 방식 사용.
 */
- (void)didEnterVisibleState {
    %orig;

    id node = (id)self;

    dispatch_async(
        dispatch_get_main_queue(), ^{

        SEL viewSelector =
            NSSelectorFromString(@"view");

        if (![node respondsToSelector:viewSelector])
            return;

        UIView *view =
            ((id (*)(id, SEL))objc_msgSend)(
                node,
                viewSelector
            );

        if (!view.window)
            return;

        UIViewController *owner =
            YMOwningController(view);

        if (!owner || !owner.view)
            return;

        Class legacyViewer =
            NSClassFromString(
                @"YTInterstitialElementsViewControllerImpl"
            );

        /*
         * 이 조건 때문에 메인 피드에는 버튼이 안 뜸.
         */
        if (!legacyViewer ||
            ![owner isKindOfClass:legacyViewer]) {

            return;
        }

        YMAddPostImageButton(
            owner.view,
            node,
            8.0
        );
    });
}


/*
 * 신형 UI
 *
 * 로그인 상태의 새 게시물 뷰어.
 */
- (void)handleTapGesture:(id)gesture {
    id node = (id)self;

    SEL viewSelector =
        NSSelectorFromString(@"view");

    UIView *view = nil;

    if ([node respondsToSelector:viewSelector]) {
        view =
            ((id (*)(id, SEL))objc_msgSend)(
                node,
                viewSelector
            );
    }

    UIWindow *window =
        view.window;

    /*
     * YouTube 원래 동작
     */
    %orig;

    if (!window)
        return;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.10 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

        YMTryAttachNewPostImageButton(
            window,
            node,
            0
        );
    });
}

%end    YMFindAncestorOfClass(
                postsPresenter,
                reelRootClass
            );

        if (viewerRoot &&
            !viewerRoot.hidden &&
            viewerRoot.alpha > 0.01 &&
            viewerRoot.window) {

            /*
             * 원래 코드와 똑같이 현재 YTImageZoomNode를 저장.
             * 다운로드 로직은 전혀 변경하지 않음.
             */
            YMCurrentPostImageNode = node;

            YMAddPostImageButton(
                viewerRoot
            );

            return;
        }
    }

    /*
     * 뷰어 생성 타이밍이 조금 늦을 수 있으므로
     * 최대 약 1초 동안 재시도.
     */
    if (attempt >= 6)
        return;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.15 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

        YMTryAttachPostImageButton(
            window,
            node,
            attempt + 1
        );
    });
}


%hook YTImageZoomNode

- (void)handleTapGesture:(id)gesture {
    id node = (id)self;

    SEL viewSelector =
        NSSelectorFromString(@"view");

    UIView *view = nil;

    if ([node respondsToSelector:viewSelector]) {
        view =
            ((id (*)(id, SEL))objc_msgSend)(
                node,
                viewSelector
            );
    }

    UIWindow *window =
        view.window;

    /*
     * YouTube 원래 동작
     */
    %orig;

    if (!window)
        return;

    /*
     * 새 게시물 전체화면 UI가 생긴 뒤
     * 거기에 버튼만 붙임.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.10 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

        YMTryAttachPostImageButton(
            window,
            node,
            0
        );
    });
}

%end
