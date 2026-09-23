#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/message.h>

static __weak id YMCurrentPostImageNode;
static const NSInteger YMPostImageButtonTag = 0x594D5049;

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


static UIViewController *YMOwningController(UIView *view) {
    UIResponder *responder = view;

    while (responder) {
        if ([responder isKindOfClass:UIViewController.class])
            return (UIViewController *)responder;

        responder = responder.nextResponder;
    }

    return nil;
}


static UIViewController *YMTopViewController(UIViewController *controller) {
    if (!controller)
        return nil;

    UIViewController *current = controller;

    while (YES) {
        if (current.presentedViewController) {
            current = current.presentedViewController;
            continue;
        }

        if ([current isKindOfClass:UINavigationController.class]) {
            UIViewController *visible =
                ((UINavigationController *)current).visibleViewController;

            if (visible && visible != current) {
                current = visible;
                continue;
            }
        }

        if ([current isKindOfClass:UITabBarController.class]) {
            UIViewController *selected =
                ((UITabBarController *)current).selectedViewController;

            if (selected && selected != current) {
                current = selected;
                continue;
            }
        }

        break;
    }

    return current;
}


static UIWindow *YMZoomWindowForNode(id node) {
    if (!node)
        return nil;

    UIWindow *window = nil;

    /*
     * YTImageZoomNode 자체가 사용하는 확대 이미지용 window.
     * 기존 UI에서는 이게 가장 정확함.
     */
    @try {
        id value = [node valueForKey:@"_zoomWindow"];

        if ([value isKindOfClass:UIWindow.class])
            window = value;
    }
    @catch (__unused NSException *exception) {
    }

    return window;
}


%hook YTImageZoomNode

- (void)didEnterVisibleState {
    /*
     * 피드에 게시물이 보였다는 이유만으로
     * 버튼을 만들면 안 됨.
     */
    %orig;
}


- (void)handleTapGesture:(id)gesture {
    id node = (id)self;

    SEL viewSelector = NSSelectorFromString(@"view");

    UIView *sourceView = nil;

    if ([node respondsToSelector:viewSelector]) {
        sourceView =
            ((id (*)(id, SEL))objc_msgSend)(
                node,
                viewSelector
            );
    }

    UIWindow *sourceWindow = sourceView.window;

    UIViewController *beforeController =
        YMOwningController(sourceView);

    /*
     * 먼저 YouTube가 원래 하던 이미지 열기를 실행.
     */
    %orig;

    /*
     * 뷰어 전환/zoom window 생성까지 아주 잠깐 기다림.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.15 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

        UIView *container = nil;

        /*
         * 1. 기존 YouTube 이미지 확대 UI
         */
        UIWindow *zoomWindow =
            YMZoomWindowForNode(node);

        if (zoomWindow &&
            !zoomWindow.hidden &&
            zoomWindow.alpha > 0.0) {

            container = zoomWindow;
        }

        /*
         * 2. 로그인 계정의 새로운 A/B 이미지 뷰어
         *
         * 별도 ViewController로 전환된 경우
         * 현재 화면 최상단 VC에 버튼을 붙임.
         */
        if (!container && sourceWindow) {

            UIViewController *top =
                YMTopViewController(
                    sourceWindow.rootViewController
                );

            if (top &&
                top.view.window &&
                top != beforeController) {

                container = top.view;
            }
        }

        /*
         * 3. 기존 YTKACE 방식의 뷰어도 지원.
         */
        if (!container && beforeController) {

            Class legacyViewer =
                NSClassFromString(
                    @"YTInterstitialElementsViewControllerImpl"
                );

            if (legacyViewer &&
                [beforeController
                    isKindOfClass:legacyViewer]) {

                container =
                    beforeController.view;
            }
        }

        /*
         * 뷰어가 실제로 열린 걸 확인하지 못했으면
         * 아무것도 만들지 않음.
         *
         * 따라서 메인 피드에는 버튼이 생기지 않음.
         */
        if (!container)
            return;

        YMCurrentPostImageNode = node;

        viewWithTag:YMPostImageButtonTag
        button.tag = YMPostImageButtonTag;

        UIButton *existing =
            (UIButton *)[container
                viewWithTag:buttonTag];

        if (existing) {
            existing.hidden = NO;

            [container
                bringSubviewToFront:existing];

            return;
        }

        UIButton *button =
            [UIButton
                buttonWithType:UIButtonTypeSystem];

        button.tag = buttonTag;

        UIImageSymbolConfiguration *config =
            [UIImageSymbolConfiguration
                configurationWithPointSize:18.0
                                    weight:
                    UIImageSymbolWeightSemibold];

        UIImage *icon =
            [UIImage
                systemImageNamed:
                    @"square.and.arrow.down"
                withConfiguration:config];

        [button
            setImage:icon
            forState:UIControlStateNormal];

        button.tintColor =
            UIColor.whiteColor;

        button.layer.shadowColor =
            UIColor.blackColor.CGColor;

        button.layer.shadowOpacity =
            0.6;

        button.layer.shadowRadius =
            3.0;

        button.layer.shadowOffset =
            CGSizeZero;

        button.translatesAutoresizingMaskIntoConstraints =
            NO;

        [button
            addTarget:
                [YMPostImageSaveTarget shared]
               action:
                @selector(saveTapped:)
     forControlEvents:
                UIControlEventTouchUpInside];

        [container addSubview:button];

        [container
            bringSubviewToFront:button];

        [NSLayoutConstraint
            activateConstraints:@[

            [button.leadingAnchor
                constraintEqualToAnchor:
                    container.leadingAnchor
                             constant:12.0],

            [button.topAnchor
                constraintEqualToAnchor:
                    container.safeAreaLayoutGuide.topAnchor
                             constant:60.0],

            [button.widthAnchor
                constraintEqualToConstant:44.0],

            [button.heightAnchor
                constraintEqualToConstant:44.0]
        ]];
    });
}

- (void)animateZoomEnd {
    %orig;

    YMCurrentPostImageNode = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class])
                continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows) {
                UIView *button =
                    [window viewWithTag:YMPostImageButtonTag];

                if (button)
                    [button removeFromSuperview];
            }
        }
    });
}

%end
