#import <Foundation/Foundation.h>

@protocol MSIMETextClient <NSObject>
- (void)insertText:(id)text replacementRange:(NSRange)range;
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement;
@end

/// Render ASCII editing text so Engine's byte caret maps exactly to UTF-16.
void MSIMEApplyTransition(NSDictionary *transition, id<MSIMETextClient> client);
