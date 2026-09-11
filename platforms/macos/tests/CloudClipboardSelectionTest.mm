#import "../CloudClipboardWindowController.h"
#import "../CloudClipboardClient.h"
#include <cassert>

static NSMutableArray *pending;
static NSString *removedID;
void MSIMEFetchCloudClipboard(NSString *, NSString *, MSIMECloudClipboardCompletion completion) {
    [pending addObject:[completion copy]];
}
void MSIMEAddCloudClipboard(NSString *, NSString *, MSIMECloudClipboardCompletion) {}
void MSIMERemoveCloudClipboard(NSString *itemID, NSString *, MSIMECloudClipboardCompletion) {
    removedID = itemID;
}
@interface MSIMECloudClipboardWindowController (Testing)
- (void)deleteItem:(id)sender;
- (void)refresh:(id)sender;
@end
@interface HiddenClipboardController : MSIMECloudClipboardWindowController
@end
@implementation HiddenClipboardController
- (void)showWindow:(id)sender { (void)sender; }
@end
static void Complete(NSUInteger index, NSArray *items) {
    MSIMECloudClipboardCompletion completion = pending[index];
    completion([NSJSONSerialization dataWithJSONObject:@{@"items":items} options:0 error:nil], 200, nil);
}
int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        pending = [NSMutableArray array];
        HiddenClipboardController *controller = [HiddenClipboardController new];
        [controller showWithToken:@"synthetic-session"];
        NSArray *entries = @[@{@"id":@"first", @"text":@"sample"},
                             @{@"id":@"second", @"text":@"sample"},
                             @{@"id":@"unicode", @"text":@"\U0001F332test"}];
        Complete(0, entries);
        NSTextView *items = [controller valueForKey:@"items"];
        assert([items.string isEqualToString:@"sample\n\nsample\n\n\U0001F332test\n\n"]);
        [controller deleteItem:nil];
        assert(removedID == nil);
        items.selectedRange = NSMakeRange(8, 6);
        [controller deleteItem:nil];
        assert([removedID isEqualToString:@"second"]);
        removedID = nil;
        items.selectedRange = NSMakeRange(4, 6);
        [controller deleteItem:nil];
        assert(removedID == nil);
        items.selectedRange = NSMakeRange(6, 2);
        [controller deleteItem:nil];
        assert(removedID == nil);
        items.selectedRange = NSMakeRange(16, 2);
        [controller deleteItem:nil];
        assert([removedID isEqualToString:@"unicode"]);
        removedID = nil;
        [controller refresh:nil];
        [controller deleteItem:nil];
        assert(removedID == nil);
        [controller showWithToken:@"synthetic-other-session"];
        Complete(2, @[@{@"id":@"new", @"text":@"new sample"}]);
        Complete(1, entries);
        items = [controller valueForKey:@"items"];
        assert([items.string isEqualToString:@"new sample\n\n"]);
        [controller refresh:nil];
        Complete(3, @[@{@"text":@"missing-id"}, @42, NSNull.null]);
        assert([items.string isEqualToString:@"暂无云端历史"]);
        [controller deleteItem:nil];
        assert(removedID == nil);
        [controller refresh:nil];
        MSIMECloudClipboardCompletion failed = pending[4];
        failed(nil, 200, nil);
        assert(items.string.length == 0);
        assert([[[controller valueForKey:@"status"] stringValue] isEqualToString:@"刷新失败"]);
    }
}
