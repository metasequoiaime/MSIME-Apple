#import "../../src/input/InputController.mm"
#import "../settings/TestPreferenceSuite.h"

#include <cassert>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

// Dictionary maintenance from the settings window, driven through real sessions: every controller holding one lets go while the quiesce lease is live, keys pass through meanwhile, and the next key after the lease is gone opens a new session with the mode the Engine held put back.

@interface QuiesceClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *marked;
@property(nonatomic, strong) NSMutableArray<NSString *> *insertions;
@end
@implementation QuiesceClient
- (NSRange)selectedRange { return NSMakeRange(0, 0); }
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range { (void)range; return nil; }
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rect {
    (void)index;
    *rect = NSMakeRect(100, 100, 1, 16);
    return @{};
}
- (void)insertText:(id)text replacementRange:(NSRange)range {
    (void)range;
    if (!self.insertions) self.insertions = [NSMutableArray array];
    if ([text isKindOfClass:NSString.class]) [self.insertions addObject:text];
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)range {
    (void)selection; (void)range;
    self.marked = [text isKindOfClass:NSAttributedString.class] ? [text string] : text;
}
@end

@interface QuiescePanel : MSIMECandidatePanel
@property(nonatomic) BOOL requestedVisible;
@end
@implementation QuiescePanel
- (BOOL)isVisible { return self.requestedVisible; }
- (void)orderFrontRegardless { self.requestedVisible = YES; }
- (void)orderOut:(id)sender { (void)sender; self.requestedVisible = NO; }
@end

static NSDictionary *QuiesceOptions;

// The options file is the only thing replaced: session opening, release and reopening are the controller's own.
@interface QuiesceController : MSIMEInputController
@end
@implementation QuiesceController
- (NSDictionary *)runtimeOptions { return QuiesceOptions; }
@end

static NSEvent *Key(unsigned short code, NSString *characters, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0
                             context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
}

// What the settings window's maintenance request needs: the exclusive lock beside the user journal.
static bool MaintenanceLockAvailable(NSString *userData) {
    NSString *path = [userData stringByAppendingPathComponent:@".msime-dictionary-access.lock"];
    const int descriptor = open(path.fileSystemRepresentation, O_RDWR | O_CREAT, 0600);
    assert(descriptor >= 0);
    const bool acquired = flock(descriptor, LOCK_EX | LOCK_NB) == 0;
    close(descriptor);
    return acquired;
}

static void AnnounceMaintenance() {
    [NSNotificationCenter.defaultCenter postNotificationName:MSIMEDictionaryMaintenanceWillBeginNotification object:nil];
}

static QuiesceController *Controller(MSIMEAppearancePreferences *appearance, QuiesceClient *client) {
    QuiesceController *controller = [QuiesceController alloc];
    [controller setValue:appearance forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:[[QuiescePanel alloc] init] forKey:@"panel"];
    return controller;
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSMutableDictionary *options = [@{@"api_version": @1,
            @"preferences": @{@"scheme": @"quanpin", @"default_ime_mode": @"chinese", @"candidate_page_size": @5,
                              @"learning": @NO, @"chinese_punctuation": @YES}} mutableCopy];
        for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
            options[name] = path;
        }
        QuiesceOptions = options;
        NSString *userData = options[@"user_data"];
        const std::string leaseRoot(userData.fileSystemRepresentation);

        NSString *suite = [@"msime.dictionary-quiesce." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *appearance =
            [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults
                                                       skinsRoot:[NSURL fileURLWithPath:root]];

        // Two clients, as IMK creates a controller per text input client; each holds its own session.
        QuiesceClient *typing = [QuiesceClient new];
        QuiesceClient *english = [QuiesceClient new];
        QuiesceController *first = Controller(appearance, typing);
        QuiesceController *second = Controller(appearance, english);
        [first prepareSession];
        [second prepareSession];
        assert([first valueForKey:@"session"] && [second valueForKey:@"session"]);
        [second setDedicatedEnglishInputMode:YES];
        assert([[second valueForKey:@"view"][@"dedicated_english"] isEqual:@YES]);
        assert(!MaintenanceLockAvailable(userData));

        // Something is being typed when maintenance begins. Unicode mode needs no dictionary.
        assert([first handleEvent:Key(32, @"U", NSEventModifierFlagShift) client:typing]);
        for (NSArray *stroke in @[@[@21, @"4"], @[@14, @"e"], @[@19, @"2"], @[@2, @"d"]])
            assert([first handleEvent:Key([stroke[0] unsignedShortValue], stroke[1], 0) client:typing]);
        assert([typing.marked isEqual:@"U4e2d"] && typing.insertions.count == 0);

        // Without a live lease the notification drops nothing.
        AnnounceMaintenance();
        assert([first valueForKey:@"session"] && [second valueForKey:@"session"]);
        assert([typing.marked isEqual:@"U4e2d"]);

        // With it, every controller lets go at once and what was typed is committed, not lost.
        assert(msime::dictionary_lease::raise_dictionary_quiesce_lease(leaseRoot));
        AnnounceMaintenance();
        assert(![first valueForKey:@"session"] && ![second valueForKey:@"session"]);
        assert(typing.marked.length == 0 && typing.insertions.count == 1);
        assert(MaintenanceLockAvailable(userData));

        // A key while the lease is live goes to the application and opens nothing.
        assert(![first handleEvent:Key(0, @"a", 0) client:typing]);
        assert(![second handleEvent:Key(0, @"a", 0) client:english]);
        assert(![first valueForKey:@"session"] && ![second valueForKey:@"session"]);
        assert(MaintenanceLockAvailable(userData));

        // Lease gone: the next key opens a session again, and dedicated English is what it was.
        msime::dictionary_lease::lower_dictionary_quiesce_lease(leaseRoot);
        [second handleEvent:Key(0, @"a", 0) client:english];
        assert([second valueForKey:@"session"]);
        assert([[second valueForKey:@"view"][@"dedicated_english"] isEqual:@YES]);
        [first handleEvent:Key(0, @"n", 0) client:typing];
        assert([first valueForKey:@"session"]);
        assert(![[first valueForKey:@"view"][@"dedicated_english"] isEqual:@YES]);
        assert(!MaintenanceLockAvailable(userData));

        // A missed notification: the preferences timer's check finds the lease and releases every holder.
        assert(msime::dictionary_lease::raise_dictionary_quiesce_lease(leaseRoot));
        [MSIMEInputController releaseQuiescedDictionarySessions];
        assert(![first valueForKey:@"session"] && ![second valueForKey:@"session"]);
        assert(MaintenanceLockAvailable(userData));
        msime::dictionary_lease::lower_dictionary_quiesce_lease(leaseRoot);

        // A lease that has run out (a settings process that died) no longer keeps input off.
        {
            NSString *lease = [userData stringByAppendingPathComponent:@".msime-dictionary-quiesce"];
            const long long expired = (long long)(NSDate.date.timeIntervalSince1970 * 1000) - 1;
            NSString *contents = [NSString stringWithFormat:@"%lld\n", expired];
            assert([contents writeToFile:lease atomically:YES encoding:NSUTF8StringEncoding error:nil]);
            [first handleEvent:Key(0, @"n", 0) client:typing];
            assert([first valueForKey:@"session"]);
            [NSFileManager.defaultManager removeItemAtPath:lease error:nil];
        }

        [(MSIMEClientSession *)[first valueForKey:@"session"] closeWithError:nil];
        [(MSIMEClientSession *)[second valueForKey:@"session"] closeWithError:nil];
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        MSIMERemoveTestPreferenceSuite(defaults, suite);
    }
    return 0;
}
