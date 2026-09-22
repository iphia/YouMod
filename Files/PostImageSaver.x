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


%hook YTImageZoomNode

- (void)didEnterVisibleState {
    %orig;

    id node = (id)self;
    YMCurrentPostImageNode = node;

    dispatch_async(dispatch_get_main_queue(), ^{
        SEL viewSelector = NSSelectorFromString(@"view");

        if (![node respondsToSelector:viewSelector])
            return;

        UIView *view =
            ((id (*)(id, SEL))objc_msgSend)(
                node,
                viewSelector);

        if (!view || !view.window)
            return;

        UIViewController *controller =
            YMOwningController(view);

        /*
         * 예전에는 여기서
         * YTInterstitialElementsViewControllerImpl인지 검사했는데,
         * A/B UI 대응을 위해 제거.
         */

        UIView *container = controller.view;

        /*
         * 컨트롤러를 못 찾더라도 window에 붙여서
         * 최대한 동작하도록 fallback.
         */
        if (!container)
            container = view.window;

        if (!container)
            return;

        const NSInteger buttonTag = 0x594D5049;

        UIButton *existing =
            (UIButton *)[container viewWithTag:buttonTag];

        if (existing) {
            existing.hidden = NO;
            [container bringSubviewToFront:existing];
            return;
        }

        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.tag = buttonTag;

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

        button.layer.shadowColor = UIColor.blackColor.CGColor;
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

%end
