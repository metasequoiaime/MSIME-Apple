#import "TextClient.h"
#include <cassert>

@interface FakeTextClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *committed;
@property(nonatomic, copy) NSString *marked;
@property(nonatomic) NSRange selection;
@end
@implementation FakeTextClient
- (void)insertText:(id)text replacementRange:(NSRange)range { assert(range.location == NSNotFound); self.committed = text; }
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement { assert(replacement.location == NSNotFound); self.marked = text; self.selection = selection; }
@end

int main() {
    @autoreleasepool {
        FakeTextClient *client = [FakeTextClient new];
        MSIMEApplyTransition(@{@"commit": @"你好", @"view": @{@"editing_text": @"shi", @"caret_position": @1}}, client);
        assert([client.committed isEqual:@"你好"]);
        assert([client.marked isEqual:@"shi"] && client.selection.location == 1);
        MSIMEApplyTransition(@{@"commit": NSNull.null, @"view": @{@"editing_text": @"", @"caret_position": @5}}, client);
        assert([client.committed isEqual:@"你好"] && client.marked.length == 0 && client.selection.location == 0);
        // Shuangpin full-pinyin display must not expose the raw key sequence.
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"b;", @"preedit": @"bing", @"caret_position": @2}}, client);
        assert([client.marked isEqual:@"bing"] && client.selection.location == 4);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"nihao", @"preedit": @"ni hao", @"caret_position": @2}}, client);
        assert([client.marked isEqual:@"ni hao"] && client.selection.location == 6);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"shi", @"preedit": @"shi", @"caret_position": @1}}, client);
        assert([client.marked isEqual:@"shi"] && client.selection.location == 1);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"x", @"preedit": @"😀", @"caret_position": @1}}, client);
        assert([client.marked isEqual:@"😀"] && client.selection.location == 2);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"shi", @"preedit": NSNull.null, @"caret_position": NSNull.null}}, client);
        assert([client.marked isEqual:@"shi"] && client.selection.location == 3);
        MSIMEApplyTransition(@{@"commit": @"合成", @"view": @{@"editing_text": @"", @"preedit": @"", @"caret_position": @0}}, client);
        assert([client.committed isEqual:@"合成"] && client.marked.length == 0 && client.selection.location == 0);
    }
    return 0;
}
