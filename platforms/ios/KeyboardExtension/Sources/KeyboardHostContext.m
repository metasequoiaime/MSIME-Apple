#import "KeyboardHostContext.h"

@implementation KeyboardHostContext
+ (NSUUID *)documentIdentifierForProxy:(id<UITextDocumentProxy>)proxy
{
    return proxy.documentIdentifier;
}
@end
