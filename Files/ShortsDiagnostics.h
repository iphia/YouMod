#pragma once
#import <UIKit/UIKit.h>
void YMStartShortsDiagnostics(UIViewController *presenter);
void YMCopyShortsDiagnostics(UIViewController *presenter);
void YMRecordShortsDiagnostic(NSString *event, id owner);

void YMRecordShortsDiagnosticState(NSDictionary *state);
