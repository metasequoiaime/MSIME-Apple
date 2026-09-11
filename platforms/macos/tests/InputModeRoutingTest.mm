#import "../InputModeRouting.h"
#import <AppKit/AppKit.h>
#include <cassert>
int main(){assert(msime::mac::ShouldToggleInputMode(true,kVK_Space,NSEventModifierFlagShift)); assert(!msime::mac::ShouldToggleInputMode(false,kVK_Space,NSEventModifierFlagShift)); assert(!msime::mac::ShouldToggleInputMode(true,kVK_Space,NSEventModifierFlagShift|NSEventModifierFlagCommand)); assert(msime::mac::ShouldPrepareInputSession(false)); assert(!msime::mac::ShouldPrepareInputSession(true));}
