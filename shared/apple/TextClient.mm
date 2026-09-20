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

NSUInteger MSIMEPreeditCaretPosition(NSString *editing, NSString *preedit, id position) {
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

NSString *MSIMETextClientFollowingCharacter(id<MSIMETextClient> client) {
    if (!client || ![client respondsToSelector:@selector(selectedRange)] ||
        ![client respondsToSelector:@selector(attributedSubstringFromRange:)]) return nil;
    NSRange selected = [client selectedRange];
    if (selected.location == NSNotFound || selected.length != 0) return nil;
    NSAttributedString *substring = [client attributedSubstringFromRange:NSMakeRange(selected.location, 1)];
    NSString *text = substring.string;
    return text.length == 1 ? [text substringWithRange:NSMakeRange(0, 1)] : nil;
}

uint32_t MSIMETextClientPrecedingUnicodeScalar(id<MSIMETextClient> client) {
    if (!client || ![client respondsToSelector:@selector(selectedRange)] ||
        ![client respondsToSelector:@selector(attributedSubstringFromRange:)]) return 0;
    NSRange selected = [client selectedRange];
    if (selected.location == NSNotFound || selected.length != 0 || selected.location == 0) return 0;
    NSUInteger start = selected.location - 1;
    NSAttributedString *one = [client attributedSubstringFromRange:NSMakeRange(start, 1)];
    NSString *text = one.string;
    if (!text.length) return 0;
    unichar tail = [text characterAtIndex:text.length - 1];
    if (tail >= 0xDC00 && tail <= 0xDFFF && start > 0) {
        NSAttributedString *pair = [client attributedSubstringFromRange:NSMakeRange(start - 1, 2)];
        NSString *pairText = pair.string;
        if (pairText.length == 2) {
            unichar high = [pairText characterAtIndex:0];
            if (high >= 0xD800 && high <= 0xDBFF)
                return CFStringGetLongCharacterForSurrogatePair(high, tail);
        }
    }
    return tail;
}

void MSIMEApplyTransitionWithPreeditStyle(NSDictionary *transition, id<MSIMETextClient> client,
                                          MSIMEInlinePreeditStyle style) {
    MSIMEApplyTransitionWithPendingClosing(transition, client, style, nil);
}

void MSIMEApplyTransitionWithPendingClosing(NSDictionary *transition, id<MSIMETextClient> client,
                                            MSIMEInlinePreeditStyle style, NSString *closing) {
    if (!closing.length) closing = nil;
    id commit = transition[@"commit"];
    // A commit ends the pair: the closing mark goes in with the text it was holding open, and the
    // caret lands after it, where the next character belongs.
    if ([commit isKindOfClass:NSString.class] && closing)
        commit = [(NSString *)commit stringByAppendingString:closing];
    if ([commit isKindOfClass:NSString.class]) [client insertText:commit replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    NSDictionary *view = transition[@"view"];
    if (![view isKindOfClass:NSDictionary.class]) return;
    NSString *editing = view[@"editing_text"];
    if (![editing isKindOfClass:NSString.class]) editing = @"";
    NSString *preedit = view[@"preedit"];
    if (![preedit isKindOfClass:NSString.class]) preedit = editing;
    id position = view[@"caret_position"];
    NSString *marked = preedit;
    NSUInteger caret = MSIMEPreeditCaretPosition(editing, preedit, position);
    if (style == MSIMEInlinePreeditStyleRaw) {
        marked = editing;
        caret = [position isKindOfClass:NSNumber.class]
            ? MIN([position unsignedIntegerValue], editing.length)
            : editing.length;
    } else if (style == MSIMEInlinePreeditStyleEmpty) {
        marked = @"";
        caret = 0;
    }
    // A phrase being put together out of several selections keeps the part already chosen in the
    // composition instead of sending it to the document. It leads the marked text and the caret
    // moves past it, the way the reference prepends word_for_creating_word to the reading and
    // offsets the display caret by its length. The runtime hands it over separately because
    // caret_position is an offset into the editing text in this host's own string unit.
    NSString *phrase = view[@"phrase_prefix"];
    if ([phrase isKindOfClass:NSString.class] && phrase.length && style != MSIMEInlinePreeditStyleEmpty) {
        marked = [phrase stringByAppendingString:marked];
        caret += phrase.length;
    }
    // While the pair is open the closing mark is the tail of the marked text, so it stays visible and
    // stays after the caret. A commit above has already consumed it.
    if (closing && ![commit isKindOfClass:NSString.class]) marked = [marked stringByAppendingString:closing];
    [client setMarkedText:marked selectionRange:NSMakeRange(caret, 0) replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}

void MSIMEApplyTransition(NSDictionary *transition, id<MSIMETextClient> client) {
    MSIMEApplyTransitionWithPreeditStyle(transition, client, MSIMEInlinePreeditStylePinyin);
}
