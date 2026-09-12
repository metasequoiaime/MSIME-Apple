#import "TextClient.h"

void MSIMEApplyTransition(NSDictionary *transition, id<MSIMETextClient> client) {
    id commit = transition[@"commit"];
    if ([commit isKindOfClass:NSString.class]) [client insertText:commit replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    NSDictionary *view = transition[@"view"];
    if (![view isKindOfClass:NSDictionary.class]) return;
    NSString *editing = view[@"editing_text"];
    if (![editing isKindOfClass:NSString.class]) editing = @"";
    NSString *preedit = view[@"preedit"];
    if (![preedit isKindOfClass:NSString.class]) preedit = editing;
    // Engine caret offsets address editing_text, not formatted display text.
    // Match the Apple host's end-caret policy when the display is transformed.
    NSUInteger caret = preedit.length;
    if ([preedit isEqual:editing]) {
        id position = view[@"caret_position"];
        caret = [position isKindOfClass:NSNumber.class] ? MIN([position unsignedIntegerValue], preedit.length) : preedit.length;
    }
    [client setMarkedText:preedit selectionRange:NSMakeRange(caret, 0) replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}
