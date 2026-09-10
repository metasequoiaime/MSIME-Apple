#import <UIKit/UIKit.h>
#import "../../shared/apple/MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "../../crates/host-api/include/msime_client.h"

@interface MSIMEKeyboardViewController : UIInputViewController <MSIMETextClient>
@property(nonatomic, strong) MSIMEClientSession *session;
@end

@implementation MSIMEKeyboardViewController

- (NSDictionary *)runtimeOptions {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-options" ofType:@"json"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.session = [[MSIMEClientSession alloc] initWithOptions:[self runtimeOptions] error:nil];
    [self apply:[self.session setFocused:YES error:nil]];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self apply:[self.session setFocused:NO error:nil]];
    [super viewWillDisappear:animated];
}

- (void)textWillChange:(id<UITextInput>)textInput {
    [super textWillChange:textInput];
}

- (void)textDidChange:(id<UITextInput>)textInput {
    [super textDidChange:textInput];
}

- (void)insertText:(id)text replacementRange:(NSRange)range {
    (void)range;
    [self.textDocumentProxy insertText:text];
}

- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)range {
    (void)range;
    [self.textDocumentProxy setMarkedText:text selectedRange:selection];
}

- (void)apply:(NSDictionary *)transition {
    if (transition) MSIMEApplyTransition(transition, self);
}

- (void)handleCharacter:(NSString *)character {
    if (character.length != 1) return;
    [self apply:[self.session typeASCII:(uint8_t)[character characterAtIndex:0] shift:NO error:nil]];
}

- (void)deleteBackward {
    [self apply:[self.session command:MSIME_BACKSPACE error:nil]];
}

@end
