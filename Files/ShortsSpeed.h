#pragma once

#import <UIKit/UIKit.h>

void YMUpdateShortsSpeedButton(UIViewController *controller, NSString *title);

void YMUpdateShortsSpeedFromView(UIView *view, NSString *title);

void YMShortsRememberPlaybackRate(id player, float rate);
