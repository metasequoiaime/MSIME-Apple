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
    [self buildKeyboard];
}

- (void)buildKeyboard {
    UIStackView *rows = [[UIStackView alloc] initWithFrame:CGRectZero];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 6;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *keys = @[@[@"q", @"w", @"e", @"r", @"t", @"y", @"u", @"i", @"o", @"p"],
                     @[@"a", @"s", @"d", @"f", @"g", @"h", @"j", @"k", @"l"],
                     @[@"z", @"x", @"c", @"v", @"b", @"n", @"m"]];
    for (NSArray *rowKeys in keys) {
        UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 4;
        for (NSString *key in rowKeys) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:key.uppercaseString forState:UIControlStateNormal];
            button.backgroundColor = UIColor.secondarySystemBackgroundColor;
            [button addTarget:self action:@selector(keyPressed:) forControlEvents:UIControlEventTouchUpInside];
            button.accessibilityLabel = key;
            [row addArrangedSubview:button];
        }
        [rows addArrangedSubview:row];
    }
    UIStackView *actions = [[UIStackView alloc] initWithFrame:CGRectZero];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.distribution = UIStackViewDistributionFillEqually;
    actions.spacing = 4;
    for (NSString *title in @[@"空格", @"⌫", @"回车"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:title forState:UIControlStateNormal];
        button.backgroundColor = UIColor.tertiarySystemBackgroundColor;
        [button addTarget:self action:@selector(actionPressed:) forControlEvents:UIControlEventTouchUpInside];
        [actions addArrangedSubview:button];
    }
    [rows addArrangedSubview:actions];
    [self.view addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [rows.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:6],
        [rows.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-6],
        [rows.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6],
        [rows.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-6]]];
}

- (void)keyPressed:(UIButton *)button {
    [self handleCharacter:button.accessibilityLabel];
}

- (void)actionPressed:(UIButton *)button {
    if ([button.currentTitle isEqualToString:@"空格"]) [self apply:[self.session command:MSIME_COMMIT_CANDIDATE error:nil]];
    else if ([button.currentTitle isEqualToString:@"⌫"]) [self deleteBackward];
    else [self apply:[self.session command:MSIME_COMMIT_RAW error:nil]];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self apply:[self.session setFocused:NO error:nil]];
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [self.session closeWithError:nil];
    [super viewDidDisappear:animated];
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
