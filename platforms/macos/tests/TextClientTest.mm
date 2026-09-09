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
    }
    return 0;
}
