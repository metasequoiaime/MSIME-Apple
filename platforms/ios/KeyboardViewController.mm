#import <UIKit/UIKit.h>
#import "../../shared/apple/MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "../../crates/host-api/include/msime_client.h"

@interface MSIMEKeyboardViewController : UIInputViewController <MSIMETextClient>
@property(nonatomic, strong) MSIMEClientSession *session;
@end

@implementation MSIMEKeyboardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSDictionary *options = @{};
    self.session = [[MSIMEClientSession alloc] initWithOptions:options error:nil];
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
