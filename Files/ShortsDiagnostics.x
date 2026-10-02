#import "ShortsDiagnostics.h"
#import <objc/runtime.h>

static NSTimer *YMDiagnosticTimer;
static NSMutableArray *YMDiagnosticSnapshots;
static NSMutableDictionary *YMDiagnosticEvents;
static NSUInteger YMDiagnosticTicks;
static NSDictionary *YMDiagnosticLastState;

void YMRecordShortsDiagnosticState(NSDictionary *state) {
    if (NSThread.isMainThread && YMDiagnosticTimer) YMDiagnosticLastState = [state copy];
}


static NSString *YMClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"nil";
}

// Class metadata only: no private getter invocation, ivar values, video IDs,
// account data, or persisted experiment configuration is read here.
static NSArray *YMShortsRuntimeMetadata(void) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in @[@"YTReelContainerViewController", @"YTShortsContentPresenter",
                             @"YTReelPlaybackView", @"YTReelWatchRootViewController",
                             @"YTReelPlayerViewController", @"YTShortsPlayerViewController",
                             @"YTReelPlayerViewControllerSub", @"YTPlayerViewController"]) {
        Class cls = NSClassFromString(name);
        if (!cls) {
            [result addObject:@{@"class": name, @"exists": @NO}];
            continue;
        }
        NSMutableArray *methods = [NSMutableArray array];
        NSMutableArray *ivars = [NSMutableArray array];
        NSMutableArray *properties = [NSMutableArray array];
        unsigned int count = 0;
        Method *list = class_copyMethodList(cls, &count);
        unsigned int methodCount = count;
        for (unsigned int i = 0; i < count && i < 400; i++) {
            const char *encoding = method_getTypeEncoding(list[i]);
            [methods addObject:@{@"selector": NSStringFromSelector(method_getName(list[i])),
                @"encoding": encoding ? @(encoding) : @""}];
        }
        free(list);
        Ivar *fields = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count && i < 150; i++) {
            const char *fieldName = ivar_getName(fields[i]);
            const char *type = ivar_getTypeEncoding(fields[i]);
            [ivars addObject:@{@"name": fieldName ? @(fieldName) : @"",
                @"encoding": type ? @(type) : @""}];
        }
        free(fields);
        objc_property_t *props = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count && i < 150; i++) {
            const char *propertyName = property_getName(props[i]);
            const char *attributes = property_getAttributes(props[i]);
            [properties addObject:@{@"name": propertyName ? @(propertyName) : @"",
                @"attributes": attributes ? @(attributes) : @""}];
        }
        free(props);
        const char *image = class_getImageName(cls);
        Class superclass = class_getSuperclass(cls);
        [result addObject:@{@"class": name, @"exists": @YES,
            @"superclass": superclass ? NSStringFromClass(superclass) : @"",
            @"imageName": image ? [@(image) lastPathComponent] : @"",
            @"methodCount": @(methodCount), @"methodsTruncated": @(methodCount > 400),
            @"methods": methods, @"ivars": ivars, @"properties": properties}];
    }
    return result;
}

static NSDictionary *YMShortsSettingsSnapshot(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"YouModShortsSpeedButton", @"YouModAutoSpeedIndex",
                            @"YouModMakeAShortsAction", @"YouModFullScreenShorts",
                            @"YouModShortsOnly", @"YouModHideShortsTopbar"]) {
        id value = [defaults objectForKey:key];
        values[key] = [value isKindOfClass:NSNumber.class] ? value : @"unset";
    }
    return values;
}

void YMRecordShortsDiagnostic(NSString *event, id owner) {
    if (!NSThread.isMainThread || !YMDiagnosticTimer) return;
    NSMutableDictionary *record = YMDiagnosticEvents[event];
    if (!record) {
        record = [NSMutableDictionary dictionary];
        YMDiagnosticEvents[event] = record;
    }
    record[@"count"] = @([record[@"count"] unsignedIntegerValue] + 1);
    record[@"lastClass"] = YMClassName(owner);
    record[@"lastTick"] = @(YMDiagnosticTicks);
    // Describe supported entry points without invoking a private getter.
    record[@"hasPlayerSelector"] = @([owner respondsToSelector:NSSelectorFromString(@"player")]);
    record[@"hasLoadPlayerBar"] = @([owner respondsToSelector:NSSelectorFromString(@"loadPlayerBar")]);
}

static void YMSampleShortsViews(void) {
    YMDiagnosticTicks++;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden) [queue addObject:window];
        }
    }
    NSUInteger windows = queue.count;
    NSMutableArray *matches = [NSMutableArray array];
    NSUInteger visited = 0;
    while (visited < queue.count && visited < 1200) {
        UIView *view = queue[visited++];
        NSString *name = YMClassName(view);
        BOOL button = [view.accessibilityIdentifier isEqualToString:@"YouMod.Shorts.Speed"];
        BOOL related = [name rangeOfString:@"shorts" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                       [name rangeOfString:@"reel" options:NSCaseInsensitiveSearch].location != NSNotFound;
        if ((button || related) && matches.count < 40) {
            NSMutableArray *ancestors = [NSMutableArray array];
            BOOL hidden = NO;
            CGFloat alpha = 1;
            UIView *parent = view;
            for (NSUInteger i = 0; parent && i < 24; i++, parent = parent.superview) {
                hidden |= parent.hidden;
                alpha *= parent.alpha;
                if (i < 8) [ancestors addObject:YMClassName(parent)];
            }
            NSMutableArray *controllers = [NSMutableArray array];
            UIResponder *responder = view;
            for (NSUInteger i = 0; responder && i < 40; i++, responder = responder.nextResponder) {
                if ([responder isKindOfClass:UIViewController.class]) {
                    NSMutableArray *classes = [NSMutableArray array];
                    Class cls = [responder class];
                    for (NSUInteger j = 0; cls && j < 5; j++, cls = class_getSuperclass(cls)) {
                        [classes addObject:NSStringFromClass(cls)];
                    }
                    [controllers addObject:classes];
                }
            }
            [matches addObject:@{@"viewClass": name, @"speedButton": @(button),
                @"frame": NSStringFromCGRect(view.frame), @"bounds": NSStringFromCGRect(view.bounds),
                @"hiddenByAncestor": @(hidden), @"combinedAlpha": @(alpha),
                @"ancestors": ancestors, @"controllers": controllers}];
        }
        // Breadth-first scan, bounded even on a very large feed.
        for (UIView *child in view.subviews) {
            if (queue.count >= 1200) break;
            [queue addObject:child];
        }
    }
    NSDictionary *snapshot = @{@"windows": @(windows), @"visited": @(visited),
        @"scanAtLimit": @(queue.count >= 1200), @"views": matches,
        @"settings": YMShortsSettingsSnapshot()};
    if (![YMDiagnosticSnapshots.lastObject isEqual:snapshot]) {
        [YMDiagnosticSnapshots addObject:snapshot];
        if (YMDiagnosticSnapshots.count > 12) [YMDiagnosticSnapshots removeObjectAtIndex:0];
    }
}

static void YMShowDiagnosticMessage(UIViewController *presenter, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Shorts 진단"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

void YMStartShortsDiagnostics(UIViewController *presenter) {
    [YMDiagnosticTimer invalidate];
    YMDiagnosticSnapshots = [NSMutableArray array];
    YMDiagnosticEvents = [NSMutableDictionary dictionary];
    YMDiagnosticTicks = 0;
    YMDiagnosticLastState = @{};
    YMDiagnosticTimer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        YMSampleShortsViews();
        if (YMDiagnosticTicks >= 180) {
            [timer invalidate];
            YMDiagnosticTimer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:YMDiagnosticTimer forMode:NSRunLoopCommonModes];
    YMShowDiagnosticMessage(presenter, @"문제가 있는 쇼츠 화면에서 10초 정도 재생하고 2~3개 영상을 넘긴 뒤, 이 설정으로 돌아와 ‘Shorts 진단 결과 복사’를 누르세요. 최대 3분 동안 화면 구조와 기능 호출 여부만 메모리에 기록합니다.");
}

void YMCopyShortsDiagnostics(UIViewController *presenter) {
    if (!YMDiagnosticSnapshots) {
        YMShowDiagnosticMessage(presenter, @"먼저 ‘Shorts 진단 시작’을 누르세요.");
        return;
    }
    [YMDiagnosticTimer invalidate];
    YMDiagnosticTimer = nil;
    NSDictionary *report = @{@"diagnosticVersion": @"v4-diag2", @"ticks": @(YMDiagnosticTicks),
        @"youtubeVersion": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"iosVersion": UIDevice.currentDevice.systemVersion,
        @"settings": YMShortsSettingsSnapshot(), @"events": YMDiagnosticEvents,
        @"lastPlaybackConnection": YMDiagnosticLastState ?: @{},
        @"snapshots": YMDiagnosticSnapshots, @"runtimeClasses": YMShortsRuntimeMetadata()};
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) {
        YMShowDiagnosticMessage(presenter, @"진단 결과 변환에 실패했습니다.");
        return;
    }
    UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    YMShowDiagnosticMessage(presenter, @"진단 결과를 복사했습니다. 대화창에 붙여넣어 주세요. 계정·영상 제목·영상 ID·시청 기록·전체 설정은 포함하지 않습니다.");
}
