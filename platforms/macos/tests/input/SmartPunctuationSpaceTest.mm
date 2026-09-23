#import "../../src/input/InputController.mm"
#import "../settings/TestPreferenceSuite.h"

#include <cassert>
#include <cstdio>

// A document the controller can read back, which is what the conversion depends on: it re-reads the mark
// before rewriting it rather than trusting what it believes it committed.
@interface SpaceConvertClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *document;
@property(nonatomic) NSRange selection;
@property(nonatomic) NSUInteger replacements;
@end

@implementation SpaceConvertClient
- (NSRange)selectedRange { return self.selection; }
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range {
    if (range.location == NSNotFound || range.location > self.document.length ||
        range.length > self.document.length - range.location)
        return nil;
    return [[NSAttributedString alloc] initWithString:[self.document substringWithRange:range]];
}
- (void)insertText:(id)text replacementRange:(NSRange)range {
    if (![text isKindOfClass:NSString.class]) return;
    ++self.replacements;
    NSRange target = range.location == NSNotFound ? self.selection : range;
    self.document = [self.document stringByReplacingCharactersInRange:target withString:text];
    self.selection = NSMakeRange(target.location + [text length], 0);
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement {
    (void)text; (void)selection; (void)replacement;
}
@end

@interface SpaceConvertController : MSIMEInputController
@end
@implementation SpaceConvertController
- (void)ensureAppearance {}
@end

static NSEvent *KeyWithFlags(NSString *characters, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                        windowNumber:0 context:nil characters:characters
     charactersIgnoringModifiers:characters isARepeat:NO keyCode:0];
}
static NSEvent *Key(NSString *characters) { return KeyWithFlags(characters, 0); }

// Arm the controller the way a committed Chinese mark does, without running the Engine.
static void Arm(SpaceConvertController *controller, unichar mark, id client) {
    [controller setValue:@(mark) forKey:@"spaceConvertMark"];
    [controller setValue:client forKey:@"spaceConvertClient"];
}

static SpaceConvertClient *ClientWith(NSString *document) {
    SpaceConvertClient *client = [SpaceConvertClient new];
    client.document = document;
    client.selection = NSMakeRange(document.length, 0);
    return client;
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *suite = [@"msime.smart.space." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *appearance = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        // The whole family is off in the source, so both the parent switch and the space rewrite have to be asked for before anything rewrites text.
        assert(!appearance.smartPunctuation && !appearance.smartPunctuationSpaceConvert);

        SpaceConvertController *controller = [SpaceConvertController alloc];
        [controller setValue:appearance forKey:@"appearance"];
        [controller setValue:@{@"editing_text" : @"", @"candidates" : @[]} forKey:@"view"];

        // Disabled: the arm is dropped and the mark the user saw land stays put.
        SpaceConvertClient *client = ClientWith(@"测试，");
        Arm(controller, ',', client);
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:client]);
        assert([client.document isEqual:@"测试，"] && client.replacements == 0);

        appearance.smartPunctuation = YES;
        appearance.smartPunctuationSpaceConvert = YES;
        assert(appearance.smartPunctuation && appearance.smartPunctuationSpaceConvert);

        // Shift is part of typing several mapped marks, not a competing chord. Prove the real key path
        // arms one of the newly covered marks before Engine commits its Chinese form.
        SpaceConvertClient *shifted = ClientWith(@"abc");
        assert(![controller handleSmartPunctuation:KeyWithFlags(@"!", NSEventModifierFlagShift) client:shifted]);
        shifted.document = @"abc！";
        shifted.selection = NSMakeRange(4, 0);
        assert([controller convertSmartPunctuationSpace:Key(@" ") client:shifted]);
        assert([shifted.document isEqual:@"abc!"] && shifted.replacements == 1);

        // Enabled: every standalone Chinese mark from the source mapping becomes its ASCII form. The
        // space is the gesture and is consumed; it is not document content after a successful rewrite.
        for (NSString *pair in @[ @",，", @".。", @":：", @"!！", @"?？", @";；", @"/、",
                                  @"\"“", @"\"”", @"'‘", @"'’", @"[【", @"]】", @"<《",
                                  @">》", @"(（", @")）" ]) {
            const unichar ascii = [pair characterAtIndex:0];
            SpaceConvertClient *editor = ClientWith([@"abc" stringByAppendingString:[pair substringFromIndex:1]]);
            Arm(controller, ascii, editor);
            assert([controller convertSmartPunctuationSpace:Key(@" ") client:editor]);
            NSString *expected = [@"abc" stringByAppendingString:[NSString stringWithCharacters:&ascii length:1]];
            assert([editor.document isEqual:expected]);
            assert(editor.replacements == 1);
        }

        // One space only. A second finds nothing armed and leaves the ASCII mark alone.
        SpaceConvertClient *once = ClientWith(@"abc，");
        Arm(controller, ',', once);
        assert([controller convertSmartPunctuationSpace:Key(@" ") client:once]);
        assert([once.document isEqual:@"abc,"]);
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:once]);
        assert([once.document isEqual:@"abc,"] && once.replacements == 1);

        // Any other key disarms: the conversion is for the space that immediately follows the mark.
        SpaceConvertClient *interrupted = ClientWith(@"abc，");
        Arm(controller, ',', interrupted);
        assert(![controller convertSmartPunctuationSpace:Key(@"x") client:interrupted]);
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:interrupted]);
        assert([interrupted.document isEqual:@"abc，"] && interrupted.replacements == 0);

        // A space in a different editor must not rewrite anything: the arm belongs to one client.
        SpaceConvertClient *armed = ClientWith(@"abc，");
        SpaceConvertClient *other = ClientWith(@"other，");
        Arm(controller, ',', armed);
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:other]);
        assert([armed.document isEqual:@"abc，"] && [other.document isEqual:@"other，"]);
        assert(armed.replacements == 0 && other.replacements == 0);

        // The document is authoritative. If the mark is no longer there - the user moved the caret, or
        // something else edited - nothing is rewritten.
        SpaceConvertClient *moved = ClientWith(@"abc，def");
        Arm(controller, ',', moved);
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:moved]);
        assert([moved.document isEqual:@"abc，def"] && moved.replacements == 0);

        // A composition owns the keyboard; the mark behind it is not this feature's to touch.
        [controller setValue:@{@"editing_text" : @"ni", @"candidates" : @[]} forKey:@"view"];
        SpaceConvertClient *composing = ClientWith(@"abc，");
        Arm(controller, ',', composing);
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:composing]);
        assert([composing.document isEqual:@"abc，"] && composing.replacements == 0);
        [controller setValue:@{@"editing_text" : @"", @"candidates" : @[]} forKey:@"view"];

        // Full-width mode owns the punctuation form and does not run the ASCII conversion gesture.
        appearance.fullWidthInput = YES;
        SpaceConvertClient *wide = ClientWith(@"abc\u3002");
        Arm(controller, '.', wide);
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:wide]);
        assert([wide.document isEqual:@"abc\u3002"] && wide.replacements == 0);
        appearance.fullWidthInput = NO;

        // An auto-completed pair sits around the caret. Rewriting only its left half would produce a
        // mixed pair, so the gesture is disabled while the host owns a pending closing mark.
        SpaceConvertClient *paired = ClientWith(@"abc（");
        Arm(controller, '(', paired);
        [controller setValue:@"）" forKey:@"pendingPairedClosing"];
        assert(![controller convertSmartPunctuationSpace:Key(@" ") client:paired]);
        assert([paired.document isEqual:@"abc（"] && paired.replacements == 0);
        [controller setValue:nil forKey:@"pendingPairedClosing"];

        MSIMERemoveTestPreferenceSuite(defaults, suite);
    }
    std::puts("macOS smart punctuation space conversion passed.");
    return 0;
}
