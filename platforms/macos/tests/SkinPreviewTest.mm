#import "AppearancePreferences.h"
#import "CandidateSkinPreviewView.h"
#import "CloudAppearanceSettings.h"
#import <CoreText/CoreText.h>
#include <cassert>
#include <fstream>

static NSView *FindControl(NSView *root, NSString *label) {
    if ([root.accessibilityLabel isEqual:label]) return root;
    for (NSView *child in root.subviews) {
        NSView *found = FindControl(child, label);
        if (found) return found;
    }
    return nil;
}

static NSString *RenderedFamily(NSFont *font) {
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"合" attributes:@{NSFontAttributeName:font}];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    assert(CFArrayGetCount(runs) == 1);
    CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
    CTFontRef actual = (CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
    NSString *family = CFBridgingRelease(CTFontCopyFamilyName(actual));
    CFRelease(line);
    return family;
}

static void TestFallbackFonts(MSIMEAppearancePreferences *preferences, NSUserDefaults *defaults) {
    NSComboBox *entry = (id)FindControl(preferences.window.contentView, @"添加补充字体");
    NSPopUpButton *list = (id)FindControl(preferences.window.contentView, @"补充字体顺序");
    assert(entry && list);
    NSString *sans = [NSFont fontWithName:@"PingFangSC-Regular" size:18].familyName;
    NSString *serif = [NSFont fontWithName:@"STSongti-SC-Regular" size:18].familyName;
    assert(sans && serif);
    __block NSUInteger notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:preferences queue:nil usingBlock:^(NSNotification *note) { (void)note; ++notifications; }];
    [preferences applySharedCandidatePreferences:@{@"candidate_font_family": @"Menlo", @"candidate_fallback_fonts": @[sans, serif]}];
    assert(notifications == 0 && list.numberOfItems == 2);
    assert([RenderedFamily([preferences candidateFontOfSize:18]) isEqual:sans]);
    [list selectItemAtIndex:1];
    [NSApp sendAction:NSSelectorFromString(@"moveFallbackFontUp:") to:preferences from:nil];
    assert([preferences.fallbackFonts.firstObject isEqual:serif]);
    assert([RenderedFamily([preferences candidateFontOfSize:18]) isEqual:serif]);
    [NSApp sendAction:NSSelectorFromString(@"moveFallbackFontDown:") to:preferences from:nil];
    assert([preferences.fallbackFonts.firstObject isEqual:sans]);
    entry.stringValue = @"MSIME Synthetic Unavailable Supplement";
    [NSApp sendAction:NSSelectorFromString(@"addFallbackFont:") to:preferences from:entry];
    assert(preferences.fallbackFonts.count == 3 && list.indexOfSelectedItem == 2);
    [NSApp sendAction:NSSelectorFromString(@"removeFallbackFont:") to:preferences from:nil];
    assert(preferences.fallbackFonts.count == 2);
    MSIMEAppearancePreferences *reloaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:preferences.skinsRoot];
    assert([reloaded.fallbackFonts isEqual:preferences.fallbackFonts]);
    NSArray *saved = preferences.fallbackFonts;
    for (id invalid in @[@"bad", NSNull.null, @[@""], @[@YES], @[[ @"字" stringByPaddingToLength:43 withString:@"字" startingAtIndex:0]]]) {
        [preferences applySharedCandidatePreferences:@{@"candidate_fallback_fonts": invalid}];
        assert([preferences.fallbackFonts isEqual:saved]);
    }
    NSMutableArray *limit = [NSMutableArray array];
    for (NSUInteger i = 0; i < 32; ++i) [limit addObject:sans];
    preferences.fallbackFonts = limit;
    assert(preferences.fallbackFonts.count == 32 && list.numberOfItems == 32);
    [limit addObject:serif];
    preferences.fallbackFonts = limit;
    assert(preferences.fallbackFonts.count == 32);
    NSUInteger countAtLimit = notifications;
    entry.stringValue = serif;
    [NSApp sendAction:NSSelectorFromString(@"addFallbackFont:") to:preferences from:entry];
    assert(preferences.fallbackFonts.count == 32 && notifications == countAtLimit);
    NSMutableString *mutableFamily = [sans mutableCopy];
    NSMutableArray *mutableFonts = [NSMutableArray arrayWithObject:mutableFamily];
    [preferences applySharedCandidatePreferences:@{@"candidate_fallback_fonts": mutableFonts}];
    [mutableFamily appendString:@" synthetic mutation"];
    [mutableFonts removeAllObjects];
    assert(([preferences.fallbackFonts isEqual:@[sans]]));
    preferences.fontFamily = @"MSIME Synthetic Unavailable Primary";
    preferences.fallbackFonts = @[@"MSIME Synthetic Unavailable Supplement", serif];
    assert([[preferences candidateFontOfSize:18].familyName isEqual:serif]);
    preferences.fallbackFonts = @[];
    assert([[preferences sharedPreferencesByMerging:@{@"candidate_fallback_fonts": @[sans]}][@"candidate_fallback_fonts"] isEqual:@[]]);
    assert([[preferences candidateFontOfSize:18].fontName isEqual:[NSFont systemFontOfSize:18].fontName]);
    preferences.fontFamily = @"Segoe UI";
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}

static void TestCloudImportCache(MSIMEAppearancePreferences *preferences, NSUserDefaults *defaults) {
    NSDictionary *original = MSIMECloudAppearanceSnapshot(defaults);
    [preferences applySharedCandidatePreferences:@{@"candidate_font_size": @12, @"candidate_page_size": @1,
        @"candidate_layout": @"vertical", @"candidate_font_family": @"Menlo", @"candidate_preedit_font_size": @28}];
    [preferences applySharedInputPreferences:@{@"scheme": @"wubi", @"shuangpin_profile": @"microsoft", @"shuangpin_preedit_uses_raw": @NO, @"chinese_punctuation": @NO}];
    [preferences applySharedAssistancePreferences:@{@"autocorrect": @NO, @"quanpin": @{@"autocorrect_neighbor": @NO}}];
    [preferences applySharedToolbarVisibility:NO];
    assert(!preferences.chinesePunctuation && !preferences.autocorrect && !preferences.shuangpinPreeditUsesRaw && !preferences.floatingToolbarEnabled);
    NSDictionary *effective = [preferences cloudSettingsSnapshot];
    assert(MSIMEValidateCloudAppearance(effective));
    assert([effective[@"platform.macos.candidate_font_size"] isEqual:@12]);
    assert([effective[@"platform.macos.candidate_page_size"] isEqual:@1]);
    assert([effective[@"platform.macos.candidate_panel_style"] isEqual:@1]);
    assert([effective[@"platform.macos.input_scheme"] isEqual:@2]);
    for (NSString *key in @[@"autocorrect", @"chinese_punctuation", @"shuangpin_preedit_uses_raw", @"floating_toolbar"])
        assert([effective[[@"platform.macos." stringByAppendingString:key]] isEqual:@NO]);
    assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:original]);
    NSMutableDictionary *imported = [original mutableCopy];
    imported[@"platform.macos.candidate_skin"] = @"wechat";
    imported[@"platform.macos.candidate_font_size"] = @32;
    imported[@"platform.macos.candidate_page_size"] = @9;
    imported[@"platform.macos.candidate_panel_style"] = @0;
    imported[@"platform.macos.input_scheme"] = @1;
    imported[@"platform.macos.shuangpin_preedit_uses_raw"] = @YES;
    imported[@"platform.macos.autocorrect"] = @YES;
    imported[@"platform.macos.chinese_punctuation"] = @YES;
    imported[@"platform.macos.floating_toolbar"] = @YES;
    __block NSUInteger notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:preferences queue:nil usingBlock:^(NSNotification *note) {
        (void)note; ++notifications;
        assert(preferences.fontSize == 32 && preferences.pageSize == 9 && !preferences.vertical);
        assert([preferences resolvedSkinForDark:NO].id == "wechat");
    }];
    NSMutableDictionary *invalid = [imported mutableCopy];
    invalid[@"platform.macos.candidate_font_size"] = @33;
    assert(![preferences applyCloudSettingsSnapshot:invalid]);
    assert(notifications == 0 && preferences.fontSize == 12);
    assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:original]);
    assert([preferences applyCloudSettingsSnapshot:imported]);
    assert(notifications == 1);
    assert([[preferences cloudSettingsSnapshot] isEqual:imported]);
    assert(notifications == 1); // Export is read-only and must not schedule a save.
    assert([effective[@"platform.macos.candidate_font_size"] isEqual:@12]); // Earlier snapshot stays immutable.
    assert(preferences.shuangpinPreeditUsesRaw && preferences.autocorrect && preferences.chinesePunctuation && preferences.floatingToolbarEnabled);
    assert([preferences.inputScheme isEqual:@"shuangpin"]);
    assert([preferences.fontFamily isEqual:@"Menlo"] && preferences.preeditFontSize == 28);
    assert([preferences.shuangpinProfile isEqual:@"microsoft"] && !preferences.autocorrectNeighbor);
    NSDictionary *merged = [preferences sharedPreferencesByMerging:@{}];
    assert([merged[@"candidate_font_size"] isEqual:@32] && [merged[@"candidate_page_size"] isEqual:@9]);
    assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:imported]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    assert([preferences applyCloudSettingsSnapshot:original]);
    preferences.fontFamily = @"Segoe UI";
    preferences.preeditFontSize = 16;
}

static NSBitmapImageRep *Draw(MSIMECandidatePreviewView *preview) {
    [preview.superview layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [preview bitmapImageRepForCachingDisplayInRect:preview.bounds];
    assert(bitmap && bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0);
    [preview cacheDisplayInRect:preview.bounds toBitmapImageRep:bitmap];
    NSColor *corner = [[bitmap colorAtX:10 y:10] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *expected = [preview.previewCanvasFillColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    assert(corner.alphaComponent > .99);
    assert(std::abs(corner.redComponent - expected.redComponent) < .03);
    return bitmap;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *suite = [@"app.msime.test.preview." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        char temporary[] = "/tmp/msime-preview-test-XXXXXX";
        assert(mkdtemp(temporary));
        const std::filesystem::path root(temporary);
        MSIMEAppearancePreferences *preferences = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:[NSURL fileURLWithPath:@(root.c_str()) isDirectory:YES]];
        NSDictionary *input = @{@"shuangpin_preedit_uses_raw": @NO, @"synthetic_unowned": @42};
        assert(preferences.shuangpinPreeditUsesRaw);
        assert([[preferences sharedPreferencesByMerging:input][@"shuangpin_preedit_uses_raw"] isEqual:@YES]);
        preferences.shuangpinPreeditUsesRaw = NO;
        NSDictionary *merged = [preferences sharedPreferencesByMerging:input];
        assert([merged[@"shuangpin_preedit_uses_raw"] isEqual:@NO]);
        assert([merged[@"synthetic_unowned"] isEqual:@42]);
        assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:preferences.skinsRoot] shuangpinPreeditUsesRaw]);
        preferences.shuangpinPreeditUsesRaw = YES;
        NSWindow *window = preferences.window;
        NSScrollView *settingsScroll = (id)window.contentView.subviews[0];
        NSGridView *grid = (id)settingsScroll.documentView;
        NSScrollView *scroll = (id)window.contentView.subviews[1];
        MSIMECandidatePreviewView *preview = (id)scroll.documentView;
        NSButton *theme = (id)window.contentView.subviews[2];
        NSButton *showcase = (id)window.contentView.subviews[3];
        assert([preview isKindOfClass:MSIMECandidatePreviewView.class]);
        [window.contentView layoutSubtreeIfNeeded];
        assert(!grid.hasAmbiguousLayout && !scroll.hasAmbiguousLayout && !preview.hasAmbiguousLayout);
        assert(scroll.frame.size.height > 200 && preview.frame.size.width > 500);
        assert(grid.frame.size.height > settingsScroll.contentView.bounds.size.height);
        NSView *lastControl = [grid cellAtColumnIndex:1 rowIndex:grid.numberOfRows - 1].contentView;
        [lastControl scrollRectToVisible:lastControl.bounds];
        assert(NSContainsRect(grid.visibleRect, lastControl.frame));
        // Restore the initial input settings after checking that the form can scroll.
        NSView *firstControl = [grid cellAtColumnIndex:1 rowIndex:0].contentView;
        [firstControl scrollRectToVisible:firstControl.bounds];
        assert(NSContainsRect(grid.visibleRect, firstControl.frame));
        NSPopUpButton *preedit = (id)[grid cellAtColumnIndex:1 rowIndex:2].contentView;
        assert(preedit.indexOfSelectedItem == 1);
        [preedit selectItemAtIndex:0];
        [NSApp sendAction:preedit.action to:preedit.target from:preedit];
        assert(!preferences.shuangpinPreeditUsesRaw);
        assert([[preferences sharedPreferencesByMerging:input][@"shuangpin_preedit_uses_raw"] isEqual:@NO]);
        [preedit selectItemAtIndex:1];
        [NSApp sendAction:preedit.action to:preedit.target from:preedit];
        assert(preferences.shuangpinPreeditUsesRaw);
        assert([preview.accessibilityLabel isEqual:@"候选窗口预览"]);
        __block NSUInteger notifications = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:preferences queue:nil usingBlock:^(NSNotification *note) { (void)note; ++notifications; }];
        for (NSString *skin in @[@"fluent", @"wechat", @"graphite", @"willow_green"]) {
            preferences.skinID = skin;
            for (NSNumber *vertical in @[@NO, @YES]) {
                preferences.vertical = vertical.boolValue;
                for (NSNumber *size in @[@1, @2, @5, @7, @9]) {
                    preferences.pageSize = size.unsignedIntegerValue;
                    for (NSNumber *font in @[@12, @13, @16, @18, @20, @32]) {
                        preferences.fontSize = font.unsignedIntegerValue;
                        NSFont *candidateFont = [NSFont systemFontOfSize:font.doubleValue];
                        NSFont *preeditFont = [NSFont systemFontOfSize:preferences.preeditFontSize];
                        CGFloat preeditHeight = MAX(22.0, ceil(preeditFont.ascender - preeditFont.descender + preeditFont.leading) + 6.0);
                        CGFloat rowHeight = ceil(candidateFont.ascender - candidateFont.descender + candidateFont.leading) + 8.0;
                        NSInteger rows = vertical.boolValue ? MIN(size.integerValue, 5) : 1;
                        CGFloat footerHeight = vertical.boolValue && size.integerValue > 5 ? 18.0 : 0.0;
                        CGFloat expectedHeight = 10 + 16 + 4 + 6 + preeditHeight + rows * rowHeight + footerHeight + 6 + 14;
                        assert(std::abs(preview.previewContentHeight - expectedHeight) < .01);
                        assert(preview.previewSkin.id == skin.UTF8String);
                        NSString *expected = [NSString stringWithFormat:@"%@，%@ 个候选，%@ pt", vertical.boolValue ? @"纵向列表" : @"横向排列", size, font];
                        assert([preview.accessibilityValue isEqual:expected]);
                        NSDictionary *before = [defaults persistentDomainForName:suite];
                        NSUInteger count = notifications;
                        BOOL originalTheme = preview.previewUsesDark;
                        Draw(preview);
                        [NSApp sendAction:theme.action to:theme.target from:theme];
                        assert(preview.previewUsesDark != originalTheme);
                        assert([theme.title isEqual:preview.forcedThemeButtonTitle]);
                        Draw(preview);
                        assert([[defaults persistentDomainForName:suite] isEqual:before] && notifications == count);
                    }
                }
            }
        }
        // Real layout control updates the preview, without a separate preview-specific setting.
        NSPopUpButton *layout = nil;
        for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
            NSView *control = [grid cellAtColumnIndex:1 rowIndex:row].contentView;
            if ([control.accessibilityLabel isEqual:@"候选排列"]) layout = (id)control;
        }
        assert(layout);
        NSComboBox *familyControl = nil;
        for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
            NSView *control = [grid cellAtColumnIndex:1 rowIndex:row].contentView;
            if ([control.accessibilityLabel isEqual:@"候选字体"]) familyControl = (id)control;
        }
        assert(familyControl && familyControl.numberOfItems > 0);
        NSUInteger familyNotifications = notifications;
        [preferences applySharedCandidatePreferences:@{@"candidate_font_family": @"MSIME Synthetic Unavailable Family"}];
        assert(notifications == familyNotifications);
        assert([familyControl.stringValue isEqual:@"MSIME Synthetic Unavailable Family"]);
        assert([[preferences candidateFontOfSize:18].fontName isEqual:[NSFont systemFontOfSize:18].fontName]);
        assert([[preferences sharedPreferencesByMerging:@{}][@"candidate_font_family"] isEqual:familyControl.stringValue]);
        for (id invalid in @[@"", @YES, NSNull.null, [@"字" stringByPaddingToLength:43 withString:@"字" startingAtIndex:0]]) {
            [preferences applySharedCandidatePreferences:@{@"candidate_font_family": invalid}];
            assert([preferences.fontFamily isEqual:@"MSIME Synthetic Unavailable Family"]);
        }
        NSString *installedFamily = [NSFont fontWithName:@"Menlo" size:18].familyName;
        assert(installedFamily);
        familyControl.stringValue = installedFamily;
        [NSApp sendAction:familyControl.action to:familyControl.target from:familyControl];
        assert([[preferences candidateFontOfSize:18].familyName isEqual:installedFamily]);
        MSIMEAppearancePreferences *familyReloaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:preferences.skinsRoot];
        assert([familyReloaded.fontFamily isEqual:installedFamily]);
        NSDictionary *familyMerge = [preferences sharedPreferencesByMerging:@{@"candidate_fallback_fonts": @[@"Synthetic Supplementary"], @"synthetic_unowned": @42}];
        assert([familyMerge[@"candidate_font_family"] isEqual:installedFamily]);
        assert(([familyMerge[@"candidate_fallback_fonts"] isEqual:@[@"Synthetic Supplementary"]]));
        assert([familyMerge[@"synthetic_unowned"] isEqual:@42]);
        NSFont *measuredCandidate = [preferences candidateFontOfSize:preferences.fontSize];
        NSFont *measuredPreedit = [preferences candidateFontOfSize:preferences.preeditFontSize];
        CGFloat measuredRow = ceil(measuredCandidate.ascender - measuredCandidate.descender + measuredCandidate.leading) + 8;
        CGFloat measuredHeader = MAX(22.0, ceil(measuredPreedit.ascender - measuredPreedit.descender + measuredPreedit.leading) + 6);
        CGFloat familyHeight = 10 + 16 + 4 + 6 + measuredHeader + 5 * measuredRow + 18 + 6 + 14;
        assert(std::abs(preview.previewContentHeight - familyHeight) < .01);
        Draw(preview);
        familyControl.stringValue = @"";
        [NSApp sendAction:familyControl.action to:familyControl.target from:familyControl];
        assert([familyControl.stringValue isEqual:installedFamily]);
        preferences.fontFamily = @"Segoe UI";
        TestFallbackFonts(preferences, defaults);
        TestCloudImportCache(preferences, defaults);
        NSTextField *colorField = (id)FindControl(preferences.window.contentView, @"候选文字颜色");
        NSColorWell *colorWell = (id)FindControl(preferences.window.contentView, @"选择候选文字颜色");
        assert(colorField && colorWell);
        NSUInteger colorNotifications = notifications;
        [preferences applySharedCandidatePreferences:@{@"candidate_text_color": @"#1234aB"}];
        assert(notifications == colorNotifications && [colorField.stringValue isEqual:@"#1234aB"]);
        NSColor *custom = [NSColor colorWithSRGBRed:18/255.0 green:52/255.0 blue:171/255.0 alpha:1];
        assert([preview.previewTextColor isEqual:custom]);
        Draw(preview);
        for (id invalid in @[@"red", @"#123", @"#12345678", @"#GG0000", @YES]) {
            [preferences applySharedCandidatePreferences:@{@"candidate_text_color": invalid}];
            assert([preferences.candidateTextColor isEqual:@"#1234aB"]);
        }
        colorWell.color = [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1];
        [NSApp sendAction:colorWell.action to:colorWell.target from:colorWell];
        assert([preferences.candidateTextColor isEqual:@"#FF0000"]);
        MSIMEAppearancePreferences *colorReloaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:preferences.skinsRoot];
        assert([colorReloaded.candidateTextColor isEqual:@"#FF0000"]);
        colorField.stringValue = @"#112233";
        [NSApp sendAction:colorField.action to:colorField.target from:colorField];
        assert([[preferences sharedPreferencesByMerging:@{}][@"candidate_text_color"] isEqual:@"#112233"]);
        [preferences applySharedCandidatePreferences:@{}];
        assert(preferences.candidateTextColor == nil);
        [preferences applySharedCandidatePreferences:@{@"candidate_text_color": @"#112233"}];
        [preferences applySharedCandidatePreferences:@{@"candidate_text_color": NSNull.null}];
        assert(preferences.candidateTextColor == nil);
        preferences.candidateTextColor = @"#112233";
        [NSApp sendAction:NSSelectorFromString(@"resetTextColor:") to:preferences from:nil];
        assert([preferences sharedPreferencesByMerging:@{}][@"candidate_text_color"] == NSNull.null);
        colorReloaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:preferences.skinsRoot];
        assert(colorReloaded.candidateTextColor == nil);
        preferences.fontFamily = @"Helvetica";
        preferences.fontSize = 32;
        NSFont *fallbackFont = [preferences candidateFontOfSize:32];
        CGFloat actualHeight = ceil([@"水杉(Ss)" sizeWithAttributes:@{NSFontAttributeName:fallbackFont}].height);
        assert(actualHeight > ceil(fallbackFont.ascender - fallbackFont.descender + fallbackFont.leading));
        NSFont *headerFont = [preferences candidateFontOfSize:preferences.preeditFontSize];
        CGFloat headerHeight = MAX(22.0, MAX(ceil([@"nihao" sizeWithAttributes:@{NSFontAttributeName:headerFont}].height), ceil(headerFont.ascender - headerFont.descender + headerFont.leading)) + 6);
        CGFloat fallbackPreviewHeight = 10 + 16 + 4 + 6 + headerHeight + 5 * (actualHeight + 8) + 18 + 6 + 14;
        assert(std::abs(preview.previewContentHeight - fallbackPreviewHeight) < .01);
        Draw(preview);
        preferences.fontFamily = @"Segoe UI";
        // Shared updates do not persist or notify; native controls own explicit edits.
        NSUInteger beforeShared = notifications;
        [preferences applySharedCandidatePreferences:@{@"candidate_preedit_font_size": @32, @"candidate_preedit_style": @"empty"}];
        assert(notifications == beforeShared && preferences.preeditFontSize == 32 && !preferences.showsCandidatePreedit);
        for (id invalid in @[@YES, @11, @33, @12.5, @"20", NSNull.null]) {
            [preferences applySharedCandidatePreferences:@{@"candidate_preedit_font_size": invalid, @"candidate_preedit_style": invalid}];
            assert(preferences.preeditFontSize == 32 && !preferences.showsCandidatePreedit);
        }
        NSPopUpButton *preeditSizeControl = nil;
        NSPopUpButton *preeditStyleControl = nil;
        for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
            NSView *control = [grid cellAtColumnIndex:1 rowIndex:row].contentView;
            if ([control.accessibilityLabel isEqual:@"候选窗拼音字号"]) preeditSizeControl = (id)control;
            if ([control.accessibilityLabel isEqual:@"候选窗预编辑"]) preeditStyleControl = (id)control;
        }
        assert(preeditSizeControl && preeditStyleControl && preeditSizeControl.indexOfSelectedItem == 20 && preeditStyleControl.indexOfSelectedItem == 1);
        CGFloat hiddenHeight = preview.previewContentHeight;
        [preeditStyleControl selectItemAtIndex:0];
        [NSApp sendAction:preeditStyleControl.action to:preeditStyleControl.target from:preeditStyleControl];
        assert(preview.previewContentHeight > hiddenHeight);
        Draw(preview);
        CGFloat largeHeight = preview.previewContentHeight;
        [preeditSizeControl selectItemAtIndex:0];
        [NSApp sendAction:preeditSizeControl.action to:preeditSizeControl.target from:preeditSizeControl];
        assert(preview.previewContentHeight < largeHeight && preferences.preeditFontSize == 12);
        Draw(preview);
        NSDictionary *preeditMerged = [preferences sharedPreferencesByMerging:@{@"synthetic_unowned": @42}];
        assert([preeditMerged[@"candidate_preedit_font_size"] isEqual:@12]);
        assert([preeditMerged[@"candidate_preedit_style"] isEqual:@"pinyin"] && [preeditMerged[@"synthetic_unowned"] isEqual:@42]);
        MSIMEAppearancePreferences *reloaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:preferences.skinsRoot];
        assert(reloaded.preeditFontSize == 12 && reloaded.showsCandidatePreedit);
        // Showcase uses compact fonts; compare the layouts at the standard size.
        preferences.fontSize = 18;
        [layout selectItemAtIndex:0];
        [NSApp sendAction:layout.action to:layout.target from:layout];
        CGFloat horizontal = preview.previewContentHeight;
        [layout selectItemAtIndex:1];
        [NSApp sendAction:layout.action to:layout.target from:layout];
        assert(preview.previewContentHeight > horizontal);
        CGFloat verticalHeight = preview.previewContentHeight;
        NSDictionary *before = [defaults persistentDomainForName:suite];
        NSUInteger count = notifications;
        showcase.state = NSControlStateValueOn;
        [NSApp sendAction:showcase.action to:showcase.target from:showcase];
        assert(preview.previewContentHeight > verticalHeight);
        Draw(preview);
        assert([[defaults persistentDomainForName:suite] isEqual:before] && notifications == count);
        // A fresh preview follows effective appearance until its local theme is overridden.
        MSIMECandidatePreviewView *automatic = [[MSIMECandidatePreviewView alloc] initWithFrame:NSMakeRect(0, 0, 580, 190)];
        automatic.preferences = preferences;
        automatic.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        assert(automatic.previewUsesDark);
        automatic.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        assert(!automatic.previewUsesDark);
        [automatic toggleForcedTheme];
        assert(automatic.previewUsesDark);
        automatic.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        assert(automatic.previewUsesDark);
        [automatic setPreviewSkinId:@"wechat"];
        assert(automatic.previewSkin.id == "wechat" && [preferences.skinID isEqual:@"willow_green"]);
        [automatic setPreviewSkinId:@"missing-package"];
        assert(automatic.previewSkin.id == "fluent");
        // A large external decoration increases scrollable height, not the fixed settings window.
        std::filesystem::create_directory(root / "synthetic");
        {
            std::ofstream manifest(root / "synthetic" / "skin.toml");
            manifest << R"toml(schema_version = 1
id = "synthetic"
name = "Synthetic"
version = "1"
base = "fluent"
preview = "image.png"
[supports]
layouts = ["horizontal", "vertical"]
themes = ["dark", "light"]
[candidate_window]
min_width_dip = 200
[candidate_window.decoration]
top_inset_dip = 180
width_dip = 120
[candidate.light]
surface = "#fff7fa"
[candidate.dark]
surface = "#123456"
)toml";
            assert(manifest.good());
        }
        NSBitmapImageRep *decoration = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:4 pixelsHigh:4 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        for (NSInteger y = 0; y < 4; ++y) for (NSInteger x = 0; x < 4; ++x) {
            unsigned char *pixel = decoration.bitmapData + y * decoration.bytesPerRow + x * 4;
            pixel[0] = 255; pixel[1] = 0; pixel[2] = 0; pixel[3] = 255;
        }
        decoration = [decoration bitmapImageRepByRetaggingWithColorSpace:NSColorSpace.sRGBColorSpace];
        assert(decoration);
        assert([[decoration representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@((root / "synthetic" / "image.png").c_str()) atomically:YES]);
        [preferences reloadSkins];
        preferences.skinID = @"synthetic";
        assert(preview.previewSkin.id == "synthetic" && preview.previewSkin.decorationTopDip == 180);
        NSBitmapImageRep *withDecoration = Draw(preview);
        const CGFloat scale = withDecoration.pixelsWide / preview.bounds.size.width;
        if (argc == 2) assert([[withDecoration representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[1]) atomically:YES]);
        NSColor *red = [[withDecoration colorAtX:(preview.bounds.size.width - 60) * scale y:80 * scale] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        // ColorSync may convert the fixture through the display profile; test visible red,
        // not byte identity between an image profile and the window's backing color space.
        assert(red.alphaComponent > .99 && red.redComponent > .8 &&
               red.redComponent - red.greenComponent > .5 && red.redComponent - red.blueComponent > .5);
        [window.contentView layoutSubtreeIfNeeded];
        assert(preview.frame.size.height > scroll.contentView.bounds.size.height);
        [preview scrollRectToVisible:NSMakeRect(0, preview.frame.size.height - 20, 100, 20)];
        assert(scroll.contentView.bounds.origin.y > 0);
        [preview setShowsLayoutShowcase:NO];
        if (argc == 2) {
            if (!preview.previewUsesDark) [preview toggleForcedTheme];
            assert([[Draw(preview) representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[1]) atomically:YES]);
        }
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        std::filesystem::remove_all(root);
    }
}
