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

inline NSMenu *CreateMetasequoiaInputMenu(id target, BOOL englishMode, BOOL traditionalOutput)
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"水杉输入法"];
    menu.autoenablesItems = NO;
    [menu addItem:CreateInputModeItem(@"中文输入", @selector(selectChineseMode:), target, !englishMode)];
    [menu addItem:CreateInputModeItem(@"英文输入", @selector(selectEnglishMode:), target, englishMode)];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:CreateInputModeItem(@"简体输出", @selector(selectSimplifiedOutput:), target, !traditionalOutput)];
    [menu addItem:CreateInputModeItem(@"繁体输出", @selector(selectTraditionalOutput:), target, traditionalOutput)];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *palette = [[NSMenuItem alloc] initWithTitle:@"表情与符号…" action:@selector(openCharacterPalette:) keyEquivalent:@""];
    palette.target = target; palette.enabled = YES; [menu addItem:palette];
    NSMenuItem *update = [[NSMenuItem alloc] initWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""];
    update.target = target; update.enabled = YES; [menu addItem:update];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"水杉输入法设置…" action:@selector(showPreferences:) keyEquivalent:@""];
    settings.target = target; settings.enabled = YES; [menu addItem:settings];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *voice = [[NSMenuItem alloc] initWithTitle:@"开始/结束语音输入（⌃⌥V）" action:@selector(toggleVoiceInput:) keyEquivalent:@""];
    voice.target = target; voice.enabled = YES; [menu addItem:voice];
    NSMenuItem *voiceSettings = [[NSMenuItem alloc] initWithTitle:@"语音输入设置…" action:@selector(showVoiceSettings:) keyEquivalent:@""];
    voiceSettings.target = target; voiceSettings.enabled = YES; [menu addItem:voiceSettings];
    return menu;
}
