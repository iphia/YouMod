#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/message.h>


#pragma mark - Current Image

static __weak id YMCurrentPostImageNode;
static const NSInteger YMPostImageButtonTag = 0x594D5049;


#pragma mark - Original Image URL

static NSURL *YMOriginalPostImageURL(NSURL *url) {
    if (!url)
        return nil;

    NSString *text = url.absoluteString;

    if (!text.length)
        return url;

    /*
     * 일부 YouTube 커뮤니티 이미지 URL
     */
    NSRange crop =
        [text rangeOfString:@"c-fcrop"];

    if (crop.location != NSNotFound) {
        NSString *original =
            [[text substringToIndex:crop.location]
                stringByAppendingString:@"nd-v1"];

        NSURL *result =
            [NSURL URLWithString:original];

        return result ?: url;
    }

    /*
     * 일반 Google image URL
     *
     * ...=w123-h456-... 등을 =s0 로 변경
     */
    NSRange slash =
        [text rangeOfString:@"/"
                    options:NSBackwardsSearch];

    if (slash.location == NSNotFound)
        return url;

    NSRange eq =
        [text rangeOfString:@"="
                    options:NSBackwardsSearch
                      range:NSMakeRange(
                          slash.location,
                          text.length - slash.location
                      )];

    if (eq.location == NSNotFound)
        return url;

    NSString *original =
        [[text substringToIndex:eq.location]
            stringByAppendingString:@"=s0"];

    NSURL *result =
        [NSURL URLWithString:original];

    return result ?: url;
}


#pragma mark - Save To Photos

static void YMSavePostImageData(NSData *data) {
    if (!data.length)
        return;

    void (^saveBlock)(void) = ^{
        [[PHPhotoLibrary sharedPhotoLibrary]
            performChanges:^{

                PHAssetCreationRequest *request =
                    [PHAssetCreationRequest
                        creationRequestForAsset];

                [request
                    addResourceWithType:
                        PHAssetResourceTypePhoto
                                  data:data
                               options:nil];

            }
            completionHandler:^(BOOL success,
                                NSError *error) {

                if (success) {
                    NSLog(
                        @"[YouMod] Post image saved"
                    );
                } else {
                    NSLog(
                        @"[YouMod] Post image save error: %@",
                        error
                    );
                }
            }];
    };

    if (@available(iOS 14.0, *)) {

        [PHPhotoLibrary
            requestAuthorizationForAccessLevel:
                PHAccessLevelAddOnly
            handler:^(PHAuthorizationStatus status) {

                if (status ==
                        PHAuthorizationStatusAuthorized ||
                    status ==
                        PHAuthorizationStatusLimited) {

                    saveBlock();
                }
            }];

    } else {

        [PHPhotoLibrary
            requestAuthorization:^(
                PHAuthorizationStatus status
            ) {

                if (status ==
                    PHAuthorizationStatusAuthorized) {

                    saveBlock();
                }
            }];
    }
}


#pragma mark - Download Button Target

@interface YMPostImageSaveTarget : NSObject
+ (instancetype)shared;
- (void)saveTapped:(UIButton *)button;
@end


@implementation YMPostImageSaveTarget

+ (instancetype)shared {
    static YMPostImageSaveTarget *target;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        target =
            [[YMPostImageSaveTarget alloc] init];
    });

    return target;
}


- (void)saveTapped:(UIButton *)button {
    id node =
        YMCurrentPostImageNode;

    if (!node)
        return;

    SEL urlSelector =
        NSSelectorFromString(@"URL");

    if (![node
        respondsToSelector:urlSelector]) {
        return;
    }

    NSURL *url =
        ((id (*)(id, SEL))objc_msgSend)(
            node,
            urlSelector
        );

    url =
        YMOriginalPostImageURL(url);

    if (!url)
        return;

    button.enabled = NO;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithURL:url
            completionHandler:^(
                NSData *data,
                NSURLResponse *response,
                NSError *error
            ) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        button.enabled = YES;
                    }
                );

                if (error) {
                    NSLog(
                        @"[YouMod] Post image download error: %@",
                        error
                    );

                    return;
                }

                if (!data.length)
                    return;

                YMSavePostImageData(data);
            }];

    [task resume];
}

@end


#pragma mark - View Search

static UIView *YMFindVisibleSubviewOfClass(
    UIView *view,
    Class targetClass
) {
    if (!view || !targetClass)
        return nil;

    /*
     * 현재 화면에 실제로 표시 중인 것만 인정
     */
    if ([view isKindOfClass:targetClass] &&
        !view.hidden &&
        view.alpha > 0.01 &&
        view.window) {

        return view;
    }

    /*
     * 위에 올라온 뷰부터 찾기 위해 역순 검색
     */
    for (UIView *subview
         in [view.subviews reverseObjectEnumerator]) {

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
    UIView *current =
        view;

    while (current) {

        if ([current
            isKindOfClass:targetClass]) {

            return current;
        }

        current =
            current.superview;
    }

    return nil;
}


#pragma mark - Button

static void YMAddPostImageSaveButton(
    UIView *viewerRoot,
    id node
) {
    if (!viewerRoot || !node)
        return;

    YMCurrentPostImageNode =
        node;

    UIButton *existing =
        (UIButton *)[viewerRoot
            viewWithTag:
                YMPostImageButtonTag];

    if (existing) {
        existing.hidden = NO;
        existing.enabled = YES;

        [viewerRoot
            bringSubviewToFront:existing];

        return;
    }

    UIButton *button =
        [UIButton
            buttonWithType:
                UIButtonTypeSystem];

    button.tag =
        YMPostImageButtonTag;

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
        0.65;

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

    [viewerRoot
        addSubview:button];

    [viewerRoot
        bringSubviewToFront:button];

    [NSLayoutConstraint
        activateConstraints:@[

        [button.leadingAnchor
            constraintEqualToAnchor:
                viewerRoot.leadingAnchor
                         constant:12.0],

        [button.topAnchor
            constraintEqualToAnchor:
                viewerRoot.safeAreaLayoutGuide.topAnchor
                         constant:60.0],

        [button.widthAnchor
            constraintEqualToConstant:44.0],

        [button.heightAnchor
            constraintEqualToConstant:44.0]
    ]];
}


#pragma mark - YTImageZoomNode

%hook YTImageZoomNode

- (void)handleTapGesture:(id)gesture {
    id node =
        (id)self;

    SEL viewSelector =
        NSSelectorFromString(@"view");

    UIView *sourceView =
        nil;

    if ([node
        respondsToSelector:viewSelector]) {

        sourceView =
            ((id (*)(id, SEL))objc_msgSend)(
                node,
                viewSelector
            );
    }

    UIWindow *window =
        sourceView.window;

    /*
     * YouTube 원래 이미지 열기 동작
     */
    %orig;

    if (!window)
        return;

    /*
     * 로그인 후 새 게시물 뷰어는
     *
     * YTReelWatchRootView
     *   └ YTReelContainerView
     *       └ YTPostsContentPresenterView
     *
     * 구조로 생성됨.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                0.25 *
                NSEC_PER_SEC
            )
        ),
        dispatch_get_main_queue(),
        ^{

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

            /*
             * 현재 화면에서 실제로 보이는
             * 게시물 presenter 탐색
             */
            UIView *postsPresenter =
                YMFindVisibleSubviewOfClass(
                    window,
                    postsPresenterClass
                );

            if (!postsPresenter)
                return;

            /*
             * 게시물 presenter의 부모를 따라 올라가서
             * 전체화면 뷰어 루트 찾기
             */
            UIView *viewerRoot =
                YMFindAncestorOfClass(
                    postsPresenter,
                    reelRootClass
                );

            if (!viewerRoot)
                return;

            if (viewerRoot.hidden ||
                viewerRoot.alpha <= 0.01 ||
                !viewerRoot.window) {

                return;
            }

            /*
             * 버튼은 YTReelWatchRootView 안에 붙임.
             *
             * 따라서 게시물 뷰어에서 빠져나오면
             * viewerRoot와 함께 버튼도 사라짐.
             */
            YMAddPostImageSaveButton(
                viewerRoot,
                node
            );
        }
    );
}

%end
