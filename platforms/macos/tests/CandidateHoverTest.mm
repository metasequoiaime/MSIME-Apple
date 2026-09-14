#import <AppKit/AppKit.h>
#import "../CandidateChrome.h"

#include <cassert>

int main()
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:@"1  候选" target:nil action:nil];
        button.frame = NSMakeRect(0, 0, 160, 36);
        button.hoverColor = [NSColor colorWithSRGBRed:0.2 green:0.3 blue:0.4 alpha:0.5];
        [button updateTrackingAreas];
        assert(!button.candidateHovered);
        [button mouseEntered:(NSEvent *)[NSNull null]];
        assert(button.candidateHovered);
        [button mouseExited:(NSEvent *)[NSNull null]];
        assert(!button.candidateHovered);
        puts("Candidate hover tracking passed");
    }
    return 0;
}
