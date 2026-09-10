#import <UIKit/UIKit.h>
#import "../../shared/apple/MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "../../crates/host-api/include/msime_client.h"

@interface MSIMEKeyboardViewController : UIInputViewController <MSIMETextClient>
@property(nonatomic, strong) MSIMEClientSession *session;
@property(nonatomic, strong) UILabel *candidateLabel;
@property(nonatomic, strong) UIStackView *candidateStack;
@property(nonatomic, strong) NSMapTable<UIButton *, NSDictionary *> *candidateBindings;
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
    self.candidateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.candidateLabel.numberOfLines = 1;
    self.candidateLabel.textAlignment = NSTextAlignmentCenter;
    self.candidateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.candidateLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.candidateLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.candidateLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.candidateLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:4],
        [self.candidateLabel.heightAnchor constraintEqualToConstant:24]]];
    self.candidateStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.candidateBindings = [NSMapTable weakToStrongObjectsMapTable];
    self.candidateStack.axis = UILayoutConstraintAxisHorizontal;
    self.candidateStack.distribution = UIStackViewDistributionFillEqually;
    self.candidateStack.spacing = 4;
    self.candidateStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.candidateStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.candidateStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:6],
        [self.candidateStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-6],
        [self.candidateStack.topAnchor constraintEqualToAnchor:self.candidateLabel.bottomAnchor constant:2],
        [self.candidateStack.heightAnchor constraintEqualToConstant:30]]];
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
        [rows.topAnchor constraintEqualToAnchor:self.candidateStack.bottomAnchor constant:6],
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
    NSArray *candidates = transition[@"view"][@"candidates"];
    NSMutableArray *labels = [NSMutableArray array];
    for (UIView *view in self.candidateStack.arrangedSubviews) [view removeFromSuperview];
    for (NSUInteger index = 0; index < candidates.count; ++index) {
        NSDictionary *candidate = candidates[index];
        NSString *text = candidate[@"text"];
        if ([text isKindOfClass:NSString.class]) {
            NSString *marker = [candidate[@"highlighted"] boolValue] ? @"[" : @"";
            NSString *suffix = [candidate[@"highlighted"] boolValue] ? @"]" : @"";
            [labels addObject:[NSString stringWithFormat:@"%lu.%@%@%@", (unsigned long)(index + 1), marker, text, suffix]];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:text forState:UIControlStateNormal];
            NSDictionary *binding = @{
                @"generation": candidate[@"generation"] ?: @0,
                @"index": candidate[@"index"] ?: @(index),
            };
            [self.candidateBindings setObject:binding forKey:button];
            [button addTarget:self action:@selector(candidatePressed:) forControlEvents:UIControlEventTouchUpInside];
            [self.candidateStack addArrangedSubview:button];
        }
    }
    self.candidateLabel.text = labels.count ? [labels componentsJoinedByString:@"  "] : @"";
}

- (void)candidatePressed:(UIButton *)button {
    NSDictionary *binding = [self.candidateBindings objectForKey:button];
    if (![binding isKindOfClass:NSDictionary.class]) return;
    [self apply:[self.session selectGeneration:[binding[@"generation"] unsignedLongLongValue]
                                             index:[binding[@"index"] unsignedIntegerValue]
                                             error:nil]];
}

- (void)handleCharacter:(NSString *)character {
    if (character.length != 1) return;
    [self apply:[self.session typeASCII:(uint8_t)[character characterAtIndex:0] shift:NO error:nil]];
}

- (void)deleteBackward {
    [self apply:[self.session command:MSIME_BACKSPACE error:nil]];
}

@end
