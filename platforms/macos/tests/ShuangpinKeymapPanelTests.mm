#import "../src/ShuangpinKeymapPanel.h"

#import <AppKit/AppKit.h>

#include "shuangpin/shuangpin_profile.h"

#include <cmath>
#include <cstring>
#include <stdexcept>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

NSDictionary<NSString *, NSString *> *KeyDefinition(NSString *key)
{
    for (NSArray<NSDictionary<NSString *, NSString *> *> *row in MetasequoiaXiaoheKeymapRows())
    {
        for (NSDictionary<NSString *, NSString *> *definition in row)
        {
            if ([definition[@"key"] isEqualToString:key])
            {
                return definition;
            }
        }
    }
    return nil;
}

bool NearlyEqual(CGFloat first, CGFloat second)
{
    return std::abs(first - second) < 0.01;
}

NSString *DisplayUnit(const std::string &unit)
{
    if (!unit.empty() && unit.front() == 'v')
    {
        return [@"ü" stringByAppendingString:[NSString stringWithUTF8String:unit.c_str() + 1]];
    }
    return [NSString stringWithUTF8String:unit.c_str()];
}

NSDictionary<NSString *, NSSet<NSString *> *> *ExpectedXiaoheUnitsByKey()
{
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *result = [NSMutableDictionary dictionary];
    const ShuangpinProfile &profile = GetXiaoheShuangpinProfile();
    for (const auto &entry : profile.initials)
    {
        NSString *key = [NSString stringWithUTF8String:entry.second.c_str()].uppercaseString;
        if (result[key] == nil)
        {
            result[key] = [NSMutableSet set];
        }
        [result[key] addObject:DisplayUnit(entry.first)];
    }
    for (const auto &entry : profile.finals)
    {
        NSString *key = [NSString stringWithUTF8String:entry.second.c_str()].uppercaseString;
        if (result[key] == nil)
        {
            result[key] = [NSMutableSet set];
        }
        [result[key] addObject:DisplayUnit(entry.first)];
    }
    return result;
}

NSSet<NSString *> *DisplayedUnits(NSDictionary<NSString *, NSString *> *definition)
{
    NSString *normalized = [definition[@"codes"] stringByReplacingOccurrencesOfString:@" / " withString:@" · "];
    return [NSSet setWithArray:[normalized componentsSeparatedByString:@" · "]];
}
} // namespace

int main(int argc, const char *argv[])
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        const BOOL preview =
            argc == 2 && (std::strcmp(argv[1], "--preview") == 0 || std::strcmp(argv[1], "--preview-dark") == 0);
        if (preview)
        {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            [NSApp finishLaunching];
            if (std::strcmp(argv[1], "--preview-dark") == 0)
            {
                NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            }
            MetasequoiaShuangpinKeymapPanel *previewPanel = [[MetasequoiaShuangpinKeymapPanel alloc] init];
            [previewPanel updateHighlightedKey:@"v"];
            NSWindow *previewWindow =
                [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 620.0, 203.0)
                                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
            previewWindow.title = @"小鹤双拼键位提示预览";
            previewWindow.contentView = previewPanel.contentView;
            [previewWindow center];
            [previewWindow makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];
            [NSApp run];
            return 0;
        }

        for (NSString *name in @[ @"xiaohe", @"ziranma", @"microsoft", @"shoudao" ])
        {
            const auto &profile = GetShuangpinProfile(name.UTF8String);
            NSMutableDictionary *definitions = [NSMutableDictionary dictionary];
            for (NSArray *row in MetasequoiaShuangpinKeymapRows(name))
                for (NSDictionary *definition in row) definitions[definition[@"key"]] = definition;
            for (const auto *mapping : {&profile.initials, &profile.finals})
                for (const auto &entry : *mapping)
                {
                    NSString *key = @(entry.second.c_str()).uppercaseString;
                    Require([DisplayedUnits(definitions[key]) containsObject:DisplayUnit(entry.first)],
                            "A double-pinyin hint drifted from the Engine profile.");
                }
            for (const auto &entry : profile.zero_initials)
                Require([MetasequoiaShuangpinZeroInitialText(name) containsString:
                    [NSString stringWithFormat:@"%@=%@", DisplayUnit(entry.first), @(entry.second.c_str())]],
                    "Zero-initial hints did not follow the selected profile.");
            MetasequoiaShuangpinKeymapPanel *profilePanel = [MetasequoiaShuangpinKeymapPanel new];
            [profilePanel setProfileName:name];
            NSView *content = profilePanel.contentView;
            [profilePanel setProfileName:name];
            Require(profilePanel.contentView == content, "Unchanged profile rebuilt the keymap panel.");
            if ([name isEqual:@"microsoft"])
            {
                [profilePanel updateHighlightedKey:@";"];
                Require([profilePanel.contentView.accessibilityValue containsString:@"当前按键 ;：ing"],
                        "Microsoft semicolon was absent from accessible key hints.");
            }
        }

        NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *rows = MetasequoiaXiaoheKeymapRows();
        Require(rows.count == 3 && rows[0].count == 10 && rows[1].count == 9 && rows[2].count == 7,
                "The Xiaohe keymap did not preserve the three physical QWERTY rows.");
        NSDictionary<NSString *, NSSet<NSString *> *> *expectedUnits = ExpectedXiaoheUnitsByKey();
        for (NSString *key in expectedUnits)
        {
            Require([DisplayedUnits(KeyDefinition(key)) isEqualToSet:expectedUnits[key]],
                    "The visual keymap drifted from the engine's Xiaohe profile.");
        }
        NSString *zeroInitialText = MetasequoiaXiaoheZeroInitialText();
        const ShuangpinProfile &xiaohe = GetXiaoheShuangpinProfile();
        Require(xiaohe.zero_initials.size() > 0, "The Xiaohe profile stopped carrying zero-initial syllables.");
        for (const auto &entry : xiaohe.zero_initials)
        {
            NSString *pair = [NSString stringWithFormat:@"%@=%@", DisplayUnit(entry.first),
                                                        [NSString stringWithUTF8String:entry.second.c_str()]];
            // These codes are the part of Xiaohe a beginner cannot derive from the key caps, and they map to a
            // two-letter code rather than to one key, so the panel has to spell them out.
            Require([zeroInitialText containsString:pair],
                    "The keymap hint dropped a zero-initial syllable from the engine's Xiaohe profile.");
        }
        // The builder caches into a function-local static, so comparing two calls compared one
        // pointer with itself and could never fail — deleting the sort that this was meant to
        // protect left the suite green. Assert the ordering property directly instead: the entries
        // come out of an unordered_map, so only the sort keeps the line from rendering in an order
        // that depends on the toolchain's hashing.
        NSString *zeroInitialPrefix = @"零声母  ";
        Require([zeroInitialText hasPrefix:zeroInitialPrefix], "The zero-initial line lost its label.");
        NSArray<NSString *> *renderedEntries =
            [[zeroInitialText substringFromIndex:zeroInitialPrefix.length] componentsSeparatedByString:@" · "];
        Require(renderedEntries.count == xiaohe.zero_initials.size(),
                "The zero-initial line did not list every syllable exactly once.");
        Require([renderedEntries isEqualToArray:[renderedEntries sortedArrayUsingSelector:@selector(compare:)]],
                "The zero-initial line was not in a deterministic order.");

        Require(MetasequoiaShouldShowShuangpinKeymap(YES, YES, YES) &&
                    !MetasequoiaShouldShowShuangpinKeymap(NO, YES, YES) &&
                    !MetasequoiaShouldShowShuangpinKeymap(YES, NO, YES) &&
                    !MetasequoiaShouldShowShuangpinKeymap(YES, YES, NO),
                "The keymap visibility policy escaped the enabled Shuangpin composition.");

        const NSRect visibleFrame = NSMakeRect(0.0, 0.0, 1440.0, 900.0);
        const NSSize panelSize = NSMakeSize(620.0, 203.0);
        NSRect frame =
            MetasequoiaShuangpinKeymapPanelFrame(NSMakeRect(400.0, 400.0, 2.0, 20.0), panelSize, 60.0, visibleFrame);
        // Assert the gap the placement exists to preserve rather than a literal origin, so growing the panel does not
        // fail this for a reason unrelated to placement.
        Require(NearlyEqual(frame.origin.x, 400.0) && NearlyEqual(NSMaxY(frame) + 60.0 + 8.0, 400.0),
                "The keymap panel was not placed below the candidate clearance.");
        frame =
            MetasequoiaShuangpinKeymapPanelFrame(NSMakeRect(1400.0, 400.0, 2.0, 20.0), panelSize, 60.0, visibleFrame);
        Require(NearlyEqual(frame.origin.x, 804.0), "The keymap panel was not clamped inside the screen's right edge.");
        frame = MetasequoiaShuangpinKeymapPanelFrame(NSMakeRect(300.0, 20.0, 2.0, 20.0), panelSize, 60.0, visibleFrame);
        Require(NearlyEqual(frame.origin.y, 108.0),
                "The keymap panel did not clear candidates above the caret near the screen bottom.");

        MetasequoiaShuangpinKeymapPanel *panel = [[MetasequoiaShuangpinKeymapPanel alloc] init];
        Require((panel.styleMask & NSWindowStyleMaskNonactivatingPanel) != 0,
                "The keymap panel could activate the input-method process.");
        Require(panel.level == NSPopUpMenuWindowLevel, "The keymap panel could render behind the input client.");
        Require(!panel.opaque && panel.hasShadow, "The keymap panel did not preserve its floating surface appearance.");
        Require([panel.contentView.accessibilityLabel isEqualToString:@"小鹤双拼键位提示"],
                "The keymap panel did not expose an accessible identity.");
        [panel updateHighlightedKey:@"v"];
        Require([panel.contentView.accessibilityValue containsString:@"当前按键 V：zh / ui · ü"],
                "The highlighted key was not reflected in the accessible keymap description.");
        [panel orderOut:nil];
    }
    return 0;
}
