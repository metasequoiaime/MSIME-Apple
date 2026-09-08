#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface KeyboardHostContext : NSObject
// UIKit may return nil before connecting to a host even though the proxy protocol declares a
// nonnull identifier. Preserve that nil here rather than trapping during Swift UUID bridging.
+ (nullable NSUUID *)documentIdentifierForProxy:(id<UITextDocumentProxy>)proxy NS_SWIFT_NAME(documentIdentifier(for:));
@end
NS_ASSUME_NONNULL_END
