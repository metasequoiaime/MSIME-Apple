#import "TextClient.h"

static BOOL MSIMEPreeditSeparator(unichar character) {
    return character == '\'' || character == ' ';
}

static NSString *MSIMEPreeditLetters(NSString *text) {
    NSMutableString *letters = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar character = [text characterAtIndex:i];
        if (MSIMEPreeditSeparator(character)) continue;
        if (!((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z'))) return nil;
        [letters appendString:[text substringWithRange:NSMakeRange(i, 1)]];
    }
    return letters;
}

static NSUInteger MSIMEPreeditCaret(NSString *editing, NSString *preedit, id position) {
    if (![position isKindOfClass:NSNumber.class]) return preedit.length;
    NSUInteger rawCaret = MIN([position unsignedIntegerValue], editing.length);
    if ([preedit isEqual:editing]) return rawCaret;
    // Only map lossless separator formatting. Expanded shuangpin, converted words
    // and corrections need an Engine-provided offset map, not host-side guesses.
    NSString *letters = MSIMEPreeditLetters(editing);
    if (!letters.length || ![letters isEqual:MSIMEPreeditLetters(preedit)]) return preedit.length;
    if (rawCaret == editing.length) return preedit.length;
    NSUInteger remaining = 0;
    for (NSUInteger i = 0; i < rawCaret; ++i)
        if (!MSIMEPreeditSeparator([editing characterAtIndex:i])) ++remaining;
    NSUInteger displayCaret = 0;
    while (displayCaret < preedit.length && remaining) {
        if (!MSIMEPreeditSeparator([preedit characterAtIndex:displayCaret])) --remaining;
        ++displayCaret;
    }
    // Preserve the two sides of an explicitly typed syllable separator, matching
    // Windows GetPreeditWithCaretMarker at the pinned product reference.
    if (rawCaret && MSIMEPreeditSeparator([editing characterAtIndex:rawCaret - 1]))
        while (displayCaret < preedit.length && MSIMEPreeditSeparator([preedit characterAtIndex:displayCaret])) ++displayCaret;
    return displayCaret;
}

void MSIMEApplyTransition(NSDictionary *transition, id<MSIMETextClient> client) {
    id commit = transition[@"commit"];
    if ([commit isKindOfClass:NSString.class]) [client insertText:commit replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    NSDictionary *view = transition[@"view"];
    if (![view isKindOfClass:NSDictionary.class]) return;
    NSString *editing = view[@"editing_text"];
    if (![editing isKindOfClass:NSString.class]) editing = @"";
    NSString *preedit = view[@"preedit"];
    if (![preedit isKindOfClass:NSString.class]) preedit = editing;
    NSUInteger caret = MSIMEPreeditCaret(editing, preedit, view[@"caret_position"]);
    [client setMarkedText:preedit selectionRange:NSMakeRange(caret, 0) replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}
