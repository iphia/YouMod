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
static void YMCollectViewStates(
    UIView *view,
    NSMutableDictionary<NSValue *, NSDictionary *> *states
) {
    if (!view)
        return;

    NSValue *key =
        [NSValue valueWithPointer:(__bridge const void *)view];

    CGRect frame = CGRectZero;

    if (view.window) {
        frame =
            [view convertRect:view.bounds
                       toView:view.window];
    }

    states[key] = @{
        @"hidden": @(view.hidden),
        @"alpha": @(view.alpha),
        @"frame": [NSValue valueWithCGRect:frame]
    };

    for (UIView *subview in view.subviews) {
        YMCollectViewStates(subview, states);
    }
}


static void YMFindChangedViews(
    UIView *view,
    NSDictionary<NSValue *, NSDictionary *> *before,
    UIWindow *window,
    NSMutableString *info
) {
    if (!view || !window)
        return;

    NSValue *key =
        [NSValue valueWithPointer:(__bridge const void *)view];

    NSDictionary *oldState =
        before[key];

    CGRect frame =
        [view convertRect:view.bounds
                   toView:window];

    CGFloat windowArea =
        window.bounds.size.width *
        window.bounds.size.height;

    CGFloat area =
        MAX(frame.size.width, 0) *
        MAX(frame.size.height, 0);

    CGFloat ratio =
        windowArea > 0 ? area / windowArea : 0;

    BOOL isNew =
        oldState == nil;

    BOOL becameVisible = NO;
    BOOL becameLarge = NO;

    if (oldState) {
        BOOL oldHidden =
            [oldState[@"hidden"] boolValue];

        CGFloat oldAlpha =
            [oldState[@"alpha"] doubleValue];

        CGRect oldFrame =
            [oldState[@"frame"] CGRectValue];

        CGFloat oldArea =
            MAX(oldFrame.size.width, 0) *
            MAX(oldFrame.size.height, 0);

        becameVisible =
            (oldHidden && !view.hidden) ||
            (oldAlpha < 0.05 && view.alpha >= 0.05);

        if (oldArea > 0) {
            becameLarge =
                area > oldArea * 3.0;
        }
    }

    /*
     * 화면의 10% 이상을 차지하는 뷰 중
     * 새로 생겼거나 크게 변한 것만 출력.
     */
    if (!view.hidden &&
        view.alpha > 0.05 &&
        ratio >= 0.10 &&
        (isNew || becameVisible || becameLarge)) {

        NSString *superName =
            view.superview
                ? NSStringFromClass(view.superview.class)
                : @"nil";

        [info appendFormat:
            @"VIEW\n"
             @"class: %@\n"
             @"super: %@\n"
             @"new: %@\n"
             @"visibleChanged: %@\n"
             @"largeChanged: %@\n"
             @"frame: %.1f %.1f %.1f %.1f\n"
             @"screenRatio: %.2f\n"
             @"subviews: %lu\n\n",
             NSStringFromClass(view.class),
             superName,
             isNew ? @"YES" : @"NO",
             becameVisible ? @"YES" : @"NO",
             becameLarge ? @"YES" : @"NO",
             frame.origin.x,
             frame.origin.y,
             frame.size.width,
             frame.size.height,
             ratio,
             (unsigned long)view.subviews.count];
    }

    for (UIView *subview in view.subviews) {
        YMFindChangedViews(
            subview,
            before,
            window,
            info
        );
    }
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

    SEL viewSelector =
        NSSelectorFromString(@"view");

    UIView *sourceView = nil;

    if ([node respondsToSelector:viewSelector]) {
        sourceView =
            ((id (*)(id, SEL))objc_msgSend)(
                node,
                viewSelector
            );
    }

    UIWindow *window =
        sourceView.window;

    if (!window) {
        %orig;
        return;
    }

    /*
     * 사진을 열기 직전의 전체 view 상태 저장.
     */
    NSMutableDictionary *before =
        [NSMutableDictionary dictionary];

    YMCollectViewStates(
        window,
        before
    );

    %orig;

    /*
     * 새 이미지 UI가 만들어질 시간을 기다림.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.5 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

        NSMutableString *info =
            [NSMutableString string];

        [info appendString:
            @"=== NEW / CHANGED LARGE VIEWS ===\n\n"];

        YMFindChangedViews(
            window,
            before,
            window,
            info
        );

        /*
         * YTImageZoomNode의 현재 부모 계층도 출력.
         */
        [info appendString:
            @"=== IMAGE NODE ANCESTORS ===\n\n"];

        UIView *current =
            sourceView;

        NSInteger depth = 0;

        while (current && depth < 15) {

            CGRect frame =
                [current convertRect:current.bounds
                              toView:window];

            [info appendFormat:
                @"%ld: %@\n"
                 @"frame: %.1f %.1f %.1f %.1f\n\n",
                 (long)depth,
                 NSStringFromClass(current.class),
                 frame.origin.x,
                 frame.origin.y,
                 frame.size.width,
                 frame.size.height];

            current =
                current.superview;

            depth++;
        }

        UIPasteboard.generalPasteboard.string =
            info;

        NSLog(
            @"[YouMod PostImage View Debug]\n%@",
            info
        );

        UILabel *label =
            [[UILabel alloc] init];

        label.text =
            @"View Debug 복사됨";

        label.textColor =
            UIColor.whiteColor;

        label.backgroundColor =
            [UIColor colorWithWhite:0
                              alpha:0.8];

        label.textAlignment =
            NSTextAlignmentCenter;

        label.layer.cornerRadius = 8;
        label.clipsToBounds = YES;

        label.translatesAutoresizingMaskIntoConstraints =
            NO;

        [window addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor
                constraintEqualToAnchor:
                    window.centerXAnchor],

            [label.bottomAnchor
                constraintEqualToAnchor:
                    window.safeAreaLayoutGuide.bottomAnchor
                             constant:-20],

            [label.widthAnchor
                constraintEqualToConstant:200],

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
