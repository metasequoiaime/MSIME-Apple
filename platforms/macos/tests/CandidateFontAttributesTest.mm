#import "../CandidateFontSize.h"
#import <AppKit/AppKit.h>
#include <cassert>
int main(){@autoreleasepool{NSDictionary *a=metasequoia::mac::CandidatePanelAttributes(20); assert([a[NSFontAttributeName] isKindOfClass:NSFont.class]); assert(fabs([a[NSFontAttributeName] pointSize]-20.0)<0.01); assert([a[IMKCandidatesSendServerKeyEventFirst] boolValue]);}}
