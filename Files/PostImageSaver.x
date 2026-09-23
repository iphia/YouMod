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

    UIViewController *beforeController =
        YMOwningController(sourceView);

    %orig;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.5 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

        NSMutableString *info =
            [NSMutableString string];

        [info appendFormat:
            @"source VC: %@\n",
            beforeController
                ? NSStringFromClass(beforeController.class)
                : @"nil"];

        UIWindow *zoomWindow =
            YMZoomWindowForNode(node);

        [info appendFormat:
            @"zoomWindow: %@\n",
            zoomWindow
                ? NSStringFromClass(zoomWindow.class)
                : @"nil"];

        [info appendFormat:
            @"zoom root: %@\n\n",
            zoomWindow.rootViewController
                ? NSStringFromClass(
                    zoomWindow.rootViewController.class
                  )
                : @"nil"];

        NSInteger index = 0;

        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (![scene isKindOfClass:UIWindowScene.class])
                continue;

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows) {

                UIViewController *root =
                    window.rootViewController;

                UIViewController *top =
                    YMTopViewController(root);

                [info appendFormat:
                    @"WINDOW %ld\n"
                     @"class: %@\n"
                     @"hidden: %@\n"
                     @"level: %.1f\n"
                     @"root: %@\n"
                     @"top: %@\n\n",
                     (long)index,
                     NSStringFromClass(window.class),
                     window.hidden ? @"YES" : @"NO",
                     window.windowLevel,
                     root
                        ? NSStringFromClass(root.class)
                        : @"nil",
                     top
                        ? NSStringFromClass(top.class)
                        : @"nil"];

                index++;
            }
        }

        /*
         * 클립보드에 자동 복사
         */
        UIPasteboard.generalPasteboard.string = info;

        NSLog(@"[YouMod PostImage Debug]\n%@", info);

        /*
         * 화면에 '복사 완료' 표시
         */
        UIWindow *targetWindow = nil;

        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (![scene isKindOfClass:UIWindowScene.class])
                continue;

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden &&
                    window.alpha > 0 &&
                    window.windowLevel >= targetWindow.windowLevel) {

                    targetWindow = window;
                }
            }
        }

        if (!targetWindow)
            return;

        UILabel *label = [[UILabel alloc] init];

        label.text =
            @"Post Image Debug 복사됨";

        label.textColor =
            UIColor.whiteColor;

        label.backgroundColor =
            [UIColor colorWithWhite:0
                              alpha:0.75];

        label.textAlignment =
            NSTextAlignmentCenter;

        label.font =
            [UIFont systemFontOfSize:14
                             weight:UIFontWeightMedium];

        label.layer.cornerRadius = 8;
        label.clipsToBounds = YES;

        label.translatesAutoresizingMaskIntoConstraints =
            NO;

        [targetWindow addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor
                constraintEqualToAnchor:
                    targetWindow.centerXAnchor],

            [label.bottomAnchor
                constraintEqualToAnchor:
                    targetWindow.safeAreaLayoutGuide.bottomAnchor
                             constant:-20],

            [label.widthAnchor
                constraintEqualToConstant:220],

            [label.heightAnchor
                constraintEqualToConstant:40]
        ]];

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(2.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(), ^{

            [label removeFromSuperview];
        });
    });
}

%end
