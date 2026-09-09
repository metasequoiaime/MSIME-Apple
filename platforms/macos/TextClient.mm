#import "TextClient.h"

void MSIMEApplyTransition(NSDictionary *transition, id<MSIMETextClient> client) {
    id commit = transition[@"commit"];
    if ([commit isKindOfClass:NSString.class]) [client insertText:commit replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    NSDictionary *view = transition[@"view"];
    if (![view isKindOfClass:NSDictionary.class]) return;
    NSString *editing = view[@"editing_text"];
    if (![editing isKindOfClass:NSString.class]) editing = @"";
    NSUInteger caret = MIN([view[@"caret_position"] unsignedIntegerValue], editing.length);
    [client setMarkedText:editing selectionRange:NSMakeRange(caret, 0) replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}
