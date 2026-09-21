#import <Foundation/Foundation.h>

@protocol MSIMETextClient <NSObject>
- (void)insertText:(id)text replacementRange:(NSRange)range;
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement;
@optional
// NSTextInputClient-compatible context queries. Hosts that cannot expose
// document context may omit these; callers must treat the result as unknown.
- (NSRange)selectedRange;
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range;
@end

typedef NS_ENUM(NSInteger, MSIMEInlinePreeditStyle) {
    MSIMEInlinePreeditStyleRaw,
    MSIMEInlinePreeditStylePinyin,
    MSIMEInlinePreeditStyleEmpty,
};

void MSIMEApplyTransition(NSDictionary *transition, id<MSIMETextClient> client);
/// Applies a transition using the shared inline preedit display preference.
/// The legacy entry point above remains the pinyin-display default for callers
/// that do not consume shared preferences yet.
void MSIMEApplyTransitionWithPreeditStyle(NSDictionary *transition, id<MSIMETextClient> client,
                                          MSIMEInlinePreeditStyle style);
/// The same, carrying a closing mark the host owes the document.
///
/// Paired punctuation puts the caret between the two marks, and IMK has no way to move a client's
/// insertion point. The opening mark is committed as usual and the closing one rides in the marked
/// text after the caret until the composition ends, so what the user sees is `（|）` and then
/// `（你好|）`. Passing nil is the ordinary case and behaves exactly as the call above.
void MSIMEApplyTransitionWithPendingClosing(NSDictionary *transition, id<MSIMETextClient> client,
                                            MSIMEInlinePreeditStyle style, NSString *closing);
// UTF-16 display offset shared by marked text and the candidate preedit row.
NSUInteger MSIMEPreeditCaretPosition(NSString *editing, NSString *preedit, id position);

// Returns the single UTF-16 character immediately following the selection,
// or nil when the host cannot safely expose document context.
NSString * MSIMETextClientFollowingCharacter(id<MSIMETextClient> client);
/// Returns the Unicode scalar immediately preceding the selection, or zero when
/// the host cannot safely expose document context.
uint32_t MSIMETextClientPrecedingUnicodeScalar(id<MSIMETextClient> client);
