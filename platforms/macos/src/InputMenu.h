#pragma once

#import <AppKit/AppKit.h>

inline NSMenuItem *CreateInputModeItem(NSString *title, SEL action, id target, BOOL selected)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = target;
    item.enabled = YES;
    item.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
    return item;
}

inline NSMenu *CreateMetasequoiaInputMenu(id target, BOOL englishMode, BOOL traditionalOutput, BOOL japaneseMode = NO)
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"水杉输入法"];
    menu.autoenablesItems = NO;

    [menu addItem:CreateInputModeItem(japaneseMode ? @"日语输入" : @"中文输入", @selector(selectChineseMode:), target, !englishMode)];
    [menu addItem:CreateInputModeItem(@"英文输入", @selector(selectEnglishMode:), target, englishMode)];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:CreateInputModeItem(@"简体输出", @selector(selectSimplifiedOutput:), target, !traditionalOutput)];
    [menu addItem:CreateInputModeItem(@"繁体输出", @selector(selectTraditionalOutput:), target, traditionalOutput)];
    [menu itemAtIndex:3].enabled = !japaneseMode;
    [menu itemAtIndex:4].enabled = !japaneseMode;
    [menu addItem:[NSMenuItem separatorItem]];

    // The IMK menu is the only entry point left once the floating toolbar is hidden, so it carries the character
    // palette too.
    NSMenuItem *characterPaletteItem = [[NSMenuItem alloc] initWithTitle:@"表情与符号…"
                                                                  action:@selector(openCharacterPalette:)
                                                           keyEquivalent:@""];
    characterPaletteItem.target = target;
    characterPaletteItem.enabled = YES;
    [menu addItem:characterPaletteItem];

    NSMenuItem *updateItem = [[NSMenuItem alloc] initWithTitle:@"检查更新…"
                                                        action:@selector(checkForUpdates:)
                                                 keyEquivalent:@""];
    updateItem.target = target;
    updateItem.enabled = YES;
    [menu addItem:updateItem];

    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"水杉输入法设置…"
                                                          action:@selector(showPreferences:)
                                                   keyEquivalent:@""];
    settingsItem.target = target;
    settingsItem.enabled = YES;
    [menu addItem:settingsItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *voice = [[NSMenuItem alloc] initWithTitle:@"开始/结束语音输入（⌃⌥V）"
                                                   action:@selector(toggleVoiceInput:)
                                            keyEquivalent:@""];
    voice.target = target;
    voice.enabled = YES;
    [menu addItem:voice];
    NSMenuItem *voiceSettings = [[NSMenuItem alloc] initWithTitle:@"语音输入设置…"
                                                           action:@selector(showVoiceSettings:)
                                                    keyEquivalent:@""];
    voiceSettings.target = target;
    voiceSettings.enabled = YES;
    [menu addItem:voiceSettings];
    NSMenuItem *writing = [[NSMenuItem alloc] initWithTitle:@"润色选中文字…"
        action:@selector(showWritingAssistant:) keyEquivalent:@""];
    writing.target = target; writing.enabled = YES;
    [menu addItem:writing];
    return menu;
}
