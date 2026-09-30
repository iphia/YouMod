#pragma once
#import <Foundation/Foundation.h>
#include <string.h>

// Accept the two scalar encodings seen in playback APIs without an ABI cast.
static inline NSMethodSignature *YMShortsRateSignature(id player) {
    NSMethodSignature *signature = [player methodSignatureForSelector:@selector(setPlaybackRate:)];
    if (signature.numberOfArguments != 3 ||
        strcmp(signature.methodReturnType, @encode(void)) != 0) return nil;
    const char *type = [signature getArgumentTypeAtIndex:2];
    return (strcmp(type, @encode(float)) == 0 || strcmp(type, @encode(double)) == 0) ? signature : nil;
}

static inline BOOL YMApplyPlaybackRate(id player, float rate) {
    if (![player respondsToSelector:@selector(setPlaybackRate:)]) return NO;
    NSMethodSignature *signature = YMShortsRateSignature(player);
    if (!signature) return NO;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = player;
    invocation.selector = @selector(setPlaybackRate:);
    if (strcmp([signature getArgumentTypeAtIndex:2], @encode(float)) == 0) {
        [invocation setArgument:&rate atIndex:2];
    } else {
        double value = rate;
        [invocation setArgument:&value atIndex:2];
    }
    [invocation invoke];
    return YES;
}
