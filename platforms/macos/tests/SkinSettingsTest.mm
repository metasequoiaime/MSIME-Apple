#import "AppearancePreferences.h"
#import "SkinSettingsView.h"
#import "CandidateSkinPreviewView.h"
#include <cassert>
#include <fstream>

static void WritePackage(const std::filesystem::path &root) {
    std::filesystem::create_directories(root / "synthetic");
    std::ofstream file(root / "synthetic" / "skin.toml");
    file << R"toml(schema_version = 1
id = "synthetic"
name = "Synthetic Card"
version = "1"
description = "Synthetic package fixture"
base = "wechat"
[supports]
layouts = ["horizontal", "vertical"]
themes = ["dark", "light"]
[candidate_window]
min_width_dip = 0
[candidate_window.decoration]
top_inset_dip = 0
width_dip = 0
)toml";
    assert(file.good());
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        char temporary[] = "/tmp/msime-skin-cards-test-XXXXXX";
        assert(mkdtemp(temporary));
        const std::filesystem::path root = std::filesystem::path(temporary) / "skins";
        NSString *suite = [@"app.msime.test.skin-cards." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *preferences = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:[NSURL fileURLWithPath:@(root.c_str()) isDirectory:YES]];
        MetasequoiaSkinSettingsView *cards = [[MetasequoiaSkinSettingsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 700) preferences:preferences];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 700) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        [window.contentView addSubview:cards];
        [NSLayoutConstraint activateConstraints:@[
            [cards.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
            [cards.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
            [cards.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
            [cards.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]
        ]];
        NSArray<NSSwitch *> *switches = [cards valueForKey:@"switches"];
        NSArray<MSIMECandidatePreviewView *> *previews = [cards valueForKey:@"previews"];
        NSArray<NSButton *> *themes = [cards valueForKey:@"themeButtons"];
        NSTextField *diagnostics = [cards valueForKey:@"diagnosticsLabel"];
        NSTextField *empty = [cards valueForKey:@"emptyLabel"];
        assert(switches.count == 4 && previews.count == 4 && !empty.hidden && diagnostics.hidden);
        assert(switches[0].state == NSControlStateValueOn);
        [window.contentView layoutSubtreeIfNeeded];
        assert(!cards.hasAmbiguousLayout && ![[cards valueForKey:@"externalCards"] hasAmbiguousLayout]);
        __block NSUInteger changes = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:preferences queue:nil usingBlock:^(NSNotification *note) { (void)note; ++changes; }];
        for (NSUInteger index = 0; index < 4; ++index) {
            [NSApp sendAction:switches[index].action to:switches[index].target from:switches[index]];
            assert([preferences.skinID isEqual:switches[index].identifier]);
            assert([[[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:preferences.skinsRoot] skinID] isEqual:preferences.skinID]);
            assert([preferences resolvedSkinForDark:NO].id == preferences.skinID.UTF8String);
            for (NSUInteger other = 0; other < 4; ++other) assert(switches[other].state == (other == index ? NSControlStateValueOn : NSControlStateValueOff));
            [switches[index] performClick:nil];
            assert(switches[index].state == NSControlStateValueOn);
            NSDictionary *before = [defaults persistentDomainForName:suite];
            NSUInteger count = changes;
            BOOL dark = previews[index].previewUsesDark;
            [NSApp sendAction:themes[index].action to:themes[index].target from:themes[index]];
            assert(previews[index].previewUsesDark != dark);
            assert([[defaults persistentDomainForName:suite] isEqual:before] && changes == count);
        }
        // Opening is scoped to the injected directory; Finder is replaced in native tests.
        __block NSUInteger opens = 0;
        cards.directoryOpener = ^BOOL(NSURL *url) {
            assert([url isEqual:preferences.skinsRoot]);
            assert(std::filesystem::is_directory(root));
            ++opens;
            return YES;
        };
        assert(!std::filesystem::exists(root));
        [NSApp sendAction:NSSelectorFromString(@"openDirectory:") to:cards from:nil];
        assert(opens == 1 && std::filesystem::is_directory(root));
        WritePackage(root);
        std::filesystem::create_directory(root / "broken");
        { std::ofstream invalid(root / "broken" / "skin.toml"); invalid << "schema_version = 2\n"; }
        for (NSUInteger iteration = 0; iteration < 3; ++iteration) {
            [cards reload];
            assert(switches.count == 5 && previews.count == 5 && !diagnostics.hidden && empty.hidden);
            assert([diagnostics.stringValue containsString:@"1 个"] && [diagnostics.stringValue containsString:@"broken"]);
            [window.contentView layoutSubtreeIfNeeded];
            assert(![[cards valueForKey:@"externalCards"] hasAmbiguousLayout]);
        }
        preferences.skinID = @"synthetic";
        assert(switches.lastObject.state == NSControlStateValueOn);
        assert(previews.lastObject.previewSkin.id == "synthetic");
        for (NSUInteger index = 0; index < 4; ++index) assert(switches[index].state == NSControlStateValueOff);
        std::filesystem::remove_all(root / "synthetic");
        [cards reload];
        assert(switches.count == 4 && !empty.hidden);
        assert([preferences.skinID isEqual:@"synthetic"] && [preferences resolvedSkinForDark:NO].id == "fluent");
        cards.directoryOpener = ^BOOL(NSURL *url) { (void)url; return NO; };
        [NSApp sendAction:NSSelectorFromString(@"openDirectory:") to:cards from:nil];
        assert([diagnostics.stringValue isEqual:@"无法打开皮肤目录。"] && !diagnostics.hidden);
        // Construction of a directory cannot replace a regular file.
        std::filesystem::remove_all(root);
        { std::ofstream file(root); file << "synthetic sentinel"; }
        [NSApp sendAction:NSSelectorFromString(@"openDirectory:") to:cards from:nil];
        assert([diagnostics.stringValue containsString:@"无法创建"] && std::filesystem::is_regular_file(root));
        std::filesystem::remove(root);
        [cards reload];
        preferences.skinID = @"fluent";
        [window.contentView layoutSubtreeIfNeeded];
        if (argc == 2) {
            NSBitmapImageRep *bitmap = [cards bitmapImageRepForCachingDisplayInRect:cards.bounds];
            [cards cacheDisplayInRect:cards.bounds toBitmapImageRep:bitmap];
            assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[1]) atomically:YES]);
        }
        NSScrollView *settingsScroll = (id)preferences.window.contentView.subviews[0];
        NSGridView *grid = (id)settingsScroll.documentView;
        NSButton *browse = nil;
        for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
            NSControl *control = (id)[grid cellAtColumnIndex:1 rowIndex:row].contentView;
            if (control.action == NSSelectorFromString(@"showSkinCatalog:")) browse = (id)control;
        }
        assert([browse.title isEqual:@"浏览所有皮肤…"] && [preferences respondsToSelector:browse.action]);
        NSWindowController *catalogWindow = [preferences skinCatalogController];
        MetasequoiaSkinSettingsView *catalogView = (id)catalogWindow.window.contentView.subviews.firstObject;
        assert([catalogView isKindOfClass:MetasequoiaSkinSettingsView.class]);
        assert([catalogView valueForKey:@"preferences"] == preferences);
        assert([preferences skinCatalogController] == catalogWindow && !catalogWindow.window.isVisible);
        [catalogWindow.window.contentView layoutSubtreeIfNeeded];
        assert(catalogView.frame.size.width == 700 && catalogView.frame.size.height == 720);
        for (NSString *theme in @[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]) {
            catalogWindow.window.appearance = [NSAppearance appearanceNamed:theme];
            [catalogView viewDidChangeEffectiveAppearance];
            NSArray<NSTextField *> *titles = [catalogView valueForKey:@"titles"];
            assert([titles.firstObject.stringValue containsString:[theme isEqual:NSAppearanceNameDarkAqua] ? @"Dark" : @"Light"]);
        }
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        std::filesystem::remove_all(std::filesystem::path(temporary));
    }
}
