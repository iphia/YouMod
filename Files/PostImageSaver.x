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

    YMCurrentPostImageNode = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self respondsToSelector:@selector(view)])
            return;

        UIView *view =
            ((id (*)(id, SEL))objc_msgSend)(
                self,
                @selector(view));

        if (!view.window)
            return;

        UIViewController *controller =
            YMOwningController(view);

        Class viewerClass =
            NSClassFromString(
                @"YTInterstitialElementsViewControllerImpl");

        if (!controller ||
            !viewerClass ||
            ![controller isKindOfClass:viewerClass])
            return;

        const NSInteger buttonTag = 0x594D5049;

        UIButton *existing =
            (UIButton *)[controller.view
                viewWithTag:buttonTag];

        if (existing) {
            existing.hidden = NO;
            return;
        }

        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.tag = buttonTag;

        UIImageSymbolConfiguration *config =
            [UIImageSymbolConfiguration
                configurationWithPointSize:18
                                    weight:UIImageSymbolWeightSemibold];

        UIImage *icon =
            [UIImage
                systemImageNamed:@"square.and.arrow.down"
                withConfiguration:config];

        [button setImage:icon
                forState:UIControlStateNormal];

        button.tintColor = UIColor.whiteColor;

        button.translatesAutoresizingMaskIntoConstraints = NO;

        [button
            addTarget:[YMPostImageSaveTarget shared]
               action:@selector(saveTapped:)
     forControlEvents:UIControlEventTouchUpInside];

        [controller.view addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [button.leadingAnchor
                constraintEqualToAnchor:
                    controller.view.leadingAnchor
                             constant:12],

            [button.topAnchor
                constraintEqualToAnchor:
                    controller.view.safeAreaLayoutGuide.topAnchor
                             constant:8],

            [button.widthAnchor
                constraintEqualToConstant:44],

            [button.heightAnchor
                constraintEqualToConstant:44]
        ]];
    });
}

%end
