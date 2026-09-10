#pragma once
#import <InputMethodKit/InputMethodKit.h>

// A bounded native selection snapshot. Unsupported or truncated host reads are
// rejected; only selected text is exposed to the writing service.
@interface MSIMEWritingSelection : NSObject
@property(nonatomic, readonly) NSString *text;
@property(nonatomic) BOOL valid;
+ (instancetype)capture:(id<IMKTextInput>)client;
- (BOOL)matches:(id<IMKTextInput>)client;
- (BOOL)replace:(NSString *)text client:(id<IMKTextInput>)client;
@end

@implementation MSIMEWritingSelection {
    id<IMKTextInput> _client;
    NSRange _range;
    NSRange _contextRange;
    NSString *_context;
    NSString *_text;
}
+ (instancetype)capture:(id<IMKTextInput>)client
{
    if (![(id)client respondsToSelector:@selector(selectedRange)] ||
        ![(id)client respondsToSelector:@selector(attributedSubstringFromRange:)]) return nil;
    const NSRange range = [client selectedRange];
    if (range.location == NSNotFound || range.length == 0 || range.length > 10000 ||
        range.location > NSUIntegerMax - range.length) return nil;
    NSString *text = [client attributedSubstringFromRange:range].string;
    if (text.length != range.length || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 16384) return nil;
    const NSUInteger before = MIN(range.location, 64UL);
    const NSRange contextRange = NSMakeRange(range.location - before, range.length + before);
    NSString *context = [client attributedSubstringFromRange:contextRange].string;
    if (context.length != contextRange.length) return nil;
    MSIMEWritingSelection *result = [MSIMEWritingSelection new];
    result->_client = client; result->_range = range; result->_contextRange = contextRange;
    result->_text = [text copy]; result->_context = [context copy]; result.valid = YES;
    return result;
}
- (NSString *)text { return _text; }
- (BOOL)matches:(id<IMKTextInput>)client
{
    return self.valid && client == _client && NSEqualRanges([client selectedRange], _range) &&
        [[client attributedSubstringFromRange:_contextRange].string isEqualToString:_context];
}
- (BOOL)replace:(NSString *)text client:(id<IMKTextInput>)client
{
    if (text.length == 0 || text.length > 10000 || ![self matches:client]) return NO;
    self.valid = NO;
    [client insertText:text replacementRange:_range];
    return YES;
}
@end
