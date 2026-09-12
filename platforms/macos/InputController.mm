#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import <CoreText/CoreText.h>
#import "MSIMEClientSession.h"
#import "RuntimeOptions.h"
#import "../../shared/apple/TextClient.h"
#include "msime_client.h"
#import "CandidatePlacement.h"
#import "UpdateController.h"
#import "ScreenKeyboardPanel.h"
#import "DictionaryWindowController.h"
#import "ClientDictionaryRuntime.h"
#import "AppearancePreferences.h"
#import "PreferencesWindowController.h"
#import "BackendAccountEntry.h"
#import "BackendSelectionObservation.h"
#include "ToolTextReturn.h"
#include "ToolApplicationActivation.h"
#include "PreferenceSaveState.h"
#include "PreferenceLoadState.h"
#include "PreferenceSnapshotMerge.h"
#import "CandidateChrome.h"
#import "CandidateTextMetrics.h"
#include "CandidateSkin.h"
#import "ChineseTextConversion.h"
#include "FullWidthInput.h"
#include "ModifierTap.h"
#import "ShuangpinKeymapPanel.h"
#import "FloatingToolbarPanel.h"
#import "VoiceInputService.h"
#import "VoiceSettings.h"
#import "CloudCandidateRequest.h"
#import "CustomTranslationBatch.h"
#include "WubiCommitPolicy.h"

static BOOL MSIMEScriptConversionApplies(id value) {
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"scheme"] isKindOfClass:NSNumber.class]) return NO;
    if ([value[@"scheme"] integerValue] < 0 || [value[@"scheme"] integerValue] > 2) return NO;
    NSString *mode = value[@"local_mode"];
    // Temporary Japanese retains the original Chinese scheme in the host snapshot.
    return ![mode isKindOfClass:NSString.class] ||
        (![mode isEqualToString:@"unicode"] && ![mode isEqualToString:@"temporary_japanese"]);
}

static NSString *CandidateDisplay(NSDictionary *candidate, BOOL traditional) {
    NSString *annotation = candidate[@"annotation"];
    NSString *text = candidate[@"text"];
    id corrected = candidate[@"corrected"];
    if ([corrected isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)corrected) == CFBooleanGetTypeID() &&
        [corrected boolValue]) text = [text stringByAppendingString:@"*"];
    if ([annotation isKindOfClass:NSString.class]) text = [text stringByAppendingString:annotation];
    text = MSIMEChineseOutputString(text, traditional);
    id source = candidate[@"source"];
    // Engine CandidateSource: CloudSuggestion=2, AiSuggestion=3. These badges
    // are presentation-only, matching the Windows candidate-view suffixes.
    if ([source isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)source) != CFBooleanGetTypeID() &&
        !CFNumberIsFloatType((__bridge CFNumberRef)source)) {
        if ([source isEqual:@2]) return [text stringByAppendingString:@" ☁️"];
        if ([source isEqual:@3]) return [text stringByAppendingString:@" 🤖"];
    }
    return text;
}

static NSString *CandidateTranslation(NSDictionary *candidate) {
    id text = candidate[@"translation"];
    return [text isKindOfClass:NSString.class] ? text : @"";
}

static NSColor *SkinColor(msime::mac::Rgba color) {
    return [NSColor colorWithSRGBRed:color.r green:color.g blue:color.b alpha:color.a];
}

static BOOL MSIMEUnsignedCandidateIdentityValue(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           !CFNumberIsFloatType((__bridge CFNumberRef)value) && [value compare:@0] != NSOrderedAscending;
}
static NSUInteger MSIMECandidateDeletionSlot(NSEvent *event) {
    const NSEventModifierFlags required = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
    if ((event.modifierFlags & (required | NSEventModifierFlagCommand)) != required) return NSNotFound;
    // Main-row physical digits only; Option/Shift characters vary by layout.
    const unsigned short codes[] = {18, 19, 20, 21, 23, 22, 26, 28};
    for (NSUInteger slot = 0; slot < 8; ++slot) if (event.keyCode == codes[slot]) return slot;
    return NSNotFound;
}
static BOOL MSIMEPunctuationToggle(NSEvent *event) {
    const NSEventModifierFlags modifiers = NSEventModifierFlagControl | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagCommand;
    return event.keyCode == 47 && (event.modifierFlags & modifiers) == NSEventModifierFlagControl;
}
static BOOL MSIMECurrentCandidateIdentity(id identifier, NSDictionary *view) {
    if (![identifier isKindOfClass:NSDictionary.class] || ![view[@"focused"] isEqual:@YES]) return NO;
    for (NSString *key in @[@"session", @"generation", @"index"])
        if (!MSIMEUnsignedCandidateIdentityValue(identifier[key])) return NO;
    return [identifier[@"session"] isEqual:view[@"session"]] && [identifier[@"generation"] isEqual:view[@"generation"]] &&
           [identifier[@"index"] compare:@(NSUIntegerMax)] != NSOrderedDescending;
}

@interface MSIMECandidatePanel : NSPanel
@end
@implementation MSIMECandidatePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// Match the pinned Windows TextBlock preedit marker spacing in logical points.
static constexpr CGFloat MSIMEPreeditCaretWidth = 1.25;
static constexpr CGFloat MSIMEPreeditCaretSideAir = 0.85;
static constexpr CGFloat MSIMEPreeditCaretEndAir = 1.5;
static constexpr CGFloat MSIMEPreeditCaretGap = MSIMEPreeditCaretWidth + 2 * MSIMEPreeditCaretSideAir;
struct MSIMEPreeditSlotMetrics { CGFloat ascent; CGFloat descent; };
static void MSIMEPreeditSlotRelease(void *context) { delete static_cast<MSIMEPreeditSlotMetrics *>(context); }
static CGFloat MSIMEPreeditSlotAscent(void *context) { return static_cast<MSIMEPreeditSlotMetrics *>(context)->ascent; }
static CGFloat MSIMEPreeditSlotDescent(void *context) { return static_cast<MSIMEPreeditSlotMetrics *>(context)->descent; }
static CGFloat MSIMEPreeditSlotWidth(void *) { return MSIMEPreeditCaretGap; }

@interface MSIMECandidatePreeditField : NSTextField
@property(nonatomic) NSUInteger caretIndex;
@property(nonatomic) BOOL showsCaret;
@property(nonatomic, strong) NSColor *caretColor;
@property(nonatomic, readonly) NSRect caretRect;
@end

@implementation MSIMECandidatePreeditField
- (void)setCaretIndex:(NSUInteger)value { _caretIndex = value; self.needsDisplay = YES; }
- (void)setShowsCaret:(BOOL)value { _showsCaret = value; self.needsDisplay = YES; }
- (void)setCaretColor:(NSColor *)value { _caretColor = value; self.needsDisplay = YES; }
- (CTLineRef)newPreeditLine CF_RETURNS_RETAINED {
    NSFont *font = self.font ?: [NSFont systemFontOfSize:16];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:self.stringValue attributes:@{
        NSFontAttributeName:font,
        NSForegroundColorAttributeName:self.textColor ?: NSColor.labelColor
    }];
    if (self.showsCaret && self.caretIndex < self.stringValue.length) {
        CTRunDelegateCallbacks callbacks = {kCTRunDelegateVersion1, MSIMEPreeditSlotRelease,
            MSIMEPreeditSlotAscent, MSIMEPreeditSlotDescent, MSIMEPreeditSlotWidth};
        CTRunDelegateRef slot = CTRunDelegateCreate(&callbacks, new MSIMEPreeditSlotMetrics{font.ascender, -font.descender});
        NSAttributedString *gap = [[NSAttributedString alloc] initWithString:@"\uFFFC" attributes:@{
            (__bridge NSString *)kCTRunDelegateAttributeName:(__bridge id)slot, NSFontAttributeName:font
        }];
        [text insertAttributedString:gap atIndex:self.caretIndex];
        CFRelease(slot);
    }
    return CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
}
- (NSRect)caretRectForLine:(CTLineRef)line origin:(CGFloat *)origin baseline:(CGFloat *)baseline {
    CGFloat ascent = 0, descent = 0;
    CTLineGetTypographicBounds(line, &ascent, &descent, nullptr);
    CGFloat offset = CTLineGetOffsetForStringIndex(line, MIN(self.caretIndex, self.stringValue.length), nullptr);
    if (self.showsCaret) offset += self.caretIndex < self.stringValue.length ? MSIMEPreeditCaretSideAir : MSIMEPreeditCaretEndAir;
    CGFloat available = MAX(0.0, NSWidth(self.bounds) - 4.0 - MSIMEPreeditCaretWidth);
    // Scroll just enough to keep the insertion point inside the clipped row.
    *origin = 2.0 - MAX(0.0, offset - available);
    CGFloat top = MAX(0.0, (NSHeight(self.bounds) - ascent - descent) / 2.0);
    *baseline = top + ascent;
    return NSMakeRect(*origin + offset, top, MSIMEPreeditCaretWidth, MIN(ascent + descent, NSHeight(self.bounds)));
}
- (NSRect)caretRect {
    if (!self.showsCaret || !self.stringValue.length) return NSZeroRect;
    CTLineRef line = [self newPreeditLine];
    CGFloat origin, baseline;
    NSRect caret = [self caretRectForLine:line origin:&origin baseline:&baseline];
    CFRelease(line);
    return caret;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CTLineRef line = [self newPreeditLine];
    CGFloat origin, baseline;
    NSRect caret = [self caretRectForLine:line origin:&origin baseline:&baseline];
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    CGContextClipToRect(context, NSRectToCGRect(self.bounds));
    CGContextTranslateCTM(context, origin, baseline);
    CGContextScaleCTM(context, 1, -1);
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, 0, 0);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
    if (self.showsCaret && self.stringValue.length) {
        [self.caretColor ?: NSColor.controlAccentColor setFill];
        NSRectFill(NSIntersectionRect(caret, self.bounds));
    }
}
@end

@interface MSIMEInputController : IMKInputController <MSIMEFloatingToolbarDelegate>
@end

@implementation MSIMEInputController {
    MSIMEClientSession *_session;
    MSIMEVoiceInputService *_voiceService;
    uint64_t _voiceGeneration;
    id _activeClient;
    MSIMEToolTextReturn _emojiReturn;
    NSDictionary *_view;
    NSObject *_candidateMenuToken;
    NSPanel *_panel;
    MSIMEShuangpinKeymapPanel *_keymapPanel;
    MSIMEFloatingToolbarPanel *_toolbar;
    NSString *_preferencesDirectory;
    NSTimer *_preferencesTimer;
    MSIMEPreferenceLoadState _preferenceLoadState;
    MSIMEPreferenceSaveState _preferenceSaveState;
    MSIMEAppearancePreferences *_appearance;
    NSUInteger _requestedPageSize;
    BOOL _skinShowsSelectedBar;
    BOOL _focusPending;
    MSIMEModifierTap _modifierTap;
    MSIMEDictionaryWindowController *_dictionaryWindow;
    NSTimer *_cloudTimer;
    MSIMECloudCandidateRequest *_cloudRequest;
    NSDictionary *_cloudQuery;
    uint64_t _cloudEpoch;
    NSOperationQueue *_glossQueue;
    NSDictionary *_glossRequest;
    uint64_t _glossEpoch;
    NSNumber *_glossEnabled;
    NSString *_glossTargetLanguage;
    NSArray<NSDictionary *> *_glossResults;
    MSIMECustomTranslationBatch *_customBatch;
    NSDictionary *_customQuery;
    NSDictionary *_customTranslationConfig;
    NSArray<NSDictionary *> *_customResults;
    uint64_t _customEpoch;
}

- (void)cancelCustomTranslations {
    ++_customEpoch;
    [_customBatch cancel];
    _customBatch = nil;
    _customQuery = nil;
    _customResults = nil;
}
- (void)cancelCandidateTranslations {
    [self cancelCandidateGloss];
    [self cancelCustomTranslations];
}
- (NSDictionary *)currentCustomTranslationRequest {
    if (!_activeClient || !_session || _focusPending || _appearance.englishMode ||
        (_appearance && !_appearance.candidateTranslations) || (_glossEnabled && !_glossEnabled.boolValue)) return nil;
    NSDictionary *query = [_session translationQueryWithError:nil];
    NSDictionary *config = query[@"custom_translation"];
    if (![config isKindOfClass:NSDictionary.class] || ![config[@"enabled"] isEqual:@YES]) return nil;
    // A preference snapshot can be pending in Engine while the composition is active.
    if ((_customTranslationConfig && ![_customTranslationConfig isEqual:config]) ||
        (_glossTargetLanguage && ![_glossTargetLanguage isEqual:query[@"target_language"]])) return nil;
    NSDictionary *view = [_session viewWithError:nil];
    if ([view[@"scheme"] isEqual:@3] || [view[@"local_mode"] isEqual:@"temporary_japanese"] ||
        ![view[@"generation"] isEqual:query[@"generation"]]) return nil;
    NSDictionary *gloss = [self currentGlossRequest];
    // Resolve the local dictionary first; never transmit an already-resolved key.
    if (gloss && (![_glossRequest isEqual:gloss] || !_glossResults)) return nil;
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSDictionary *candidate in view[@"candidates"]) {
        if (![candidate[@"text"] isKindOfClass:NSString.class] || ![candidate[@"source"] isKindOfClass:NSNumber.class]) continue;
        BOOL resolved = NO;
        for (NSDictionary *result in _glossResults)
            if (gloss && [result[@"text"] isEqual:candidate[@"text"]]) { resolved = YES; break; }
        if (!resolved) [candidates addObject:@{@"text":candidate[@"text"], @"source":candidate[@"source"]}];
    }
    if (!candidates.count) return nil;
    return @{@"generation":query[@"generation"], @"target_language":query[@"target_language"],
        @"custom_translation":config, @"candidates":[candidates copy]};
}
- (void)applyCandidateTranslationResults {
    NSMutableArray *results = [NSMutableArray array];
    if (_glossResults && [_glossRequest isEqual:[self currentGlossRequest]]) [results addObjectsFromArray:_glossResults];
    if (_customResults && [_customQuery isEqual:[self currentCustomTranslationRequest]]) [results addObjectsFromArray:_customResults];
    NSDictionary *view = [_session viewWithError:nil];
    if (!view) return;
    NSDictionary *applied = [_session applyTranslations:results generation:[view[@"generation"] unsignedLongLongValue] error:nil];
    if ([applied[@"applied"] boolValue]) [self apply:applied];
}
- (MSIMECustomTranslationBatch *)customBatchForItems:(NSArray<NSDictionary *> *)items completion:(void (^)(NSArray<NSDictionary *> *))completion {
    return [[MSIMECustomTranslationBatch alloc] initWithItems:items configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:completion];
}
- (void)synchronizeCustomTranslations {
    NSDictionary *query = [self currentCustomTranslationRequest];
    if (!query) { [self cancelCustomTranslations]; return; }
    if ([_customQuery isEqual:query]) return;
    [self cancelCustomTranslations];
    _customQuery = query;
    NSArray *plan = [MSIMEClientSession customTranslationPlan:@{@"target_language":query[@"target_language"], @"candidates":query[@"candidates"]} error:nil];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *item in plan) {
        NSDictionary *descriptor = [MSIMEClientSession customTranslationHTTPRequest:@{@"config":query[@"custom_translation"],
            @"text":item[@"key"], @"source_language":item[@"source_language"], @"target_language":item[@"target_language"]} error:nil];
        if (descriptor) [items addObject:@{@"text":item[@"text"], @"request":descriptor}];
    }
    if (!items.count) return;
    uint64_t epoch = _customEpoch;
    MSIMEClientSession *session = _session;
    id client = _activeClient;
    __weak MSIMEInputController *weakSelf = self;
    _customBatch = [self customBatchForItems:items completion:^(NSArray<NSDictionary *> *results) {
        MSIMEInputController *current = weakSelf;
        if (!current || current->_customEpoch != epoch || current->_session != session || current->_activeClient != client ||
            ![[current currentCustomTranslationRequest] isEqual:query]) return;
        current->_customBatch = nil;
        current->_customResults = [results copy];
        [current applyCandidateTranslationResults];
    }];
    [_customBatch start];
}
- (void)cancelCandidateGloss {
    ++_glossEpoch;
    [_glossQueue cancelAllOperations];
    _glossRequest = nil;
    _glossResults = nil;
}
- (NSDictionary *)currentGlossRequest {
    if (!_activeClient || !_session || _focusPending || _appearance.englishMode ||
        (_appearance && !_appearance.candidateTranslations) || (_glossEnabled && !_glossEnabled.boolValue)) return nil;
    if (_glossTargetLanguage && ![_glossTargetLanguage isEqual:@"en"]) return nil;
    NSDictionary *query = [_session translationQueryWithError:nil];
    if (!query || ![query[@"target_language"] isEqual:@"en"]) return nil;
    NSDictionary *view = [_session viewWithError:nil];
    // Windows suppresses candidate translations in Japanese, including a
    // temporary Japanese composition whose view retains its original scheme.
    if ([view[@"scheme"] isEqual:@3] || [view[@"local_mode"] isEqual:@"temporary_japanese"]) return nil;
    if (![view[@"generation"] isEqual:query[@"generation"]]) return nil;
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSDictionary *candidate in view[@"candidates"])
        if ([candidate[@"text"] isKindOfClass:NSString.class] && [candidate[@"source"] isKindOfClass:NSNumber.class])
            [candidates addObject:@{@"text":candidate[@"text"], @"source":candidate[@"source"]}];
    return candidates.count ? @{@"generation":query[@"generation"], @"candidates":[candidates copy]} : nil;
}
- (NSDictionary *)readCandidateGloss:(NSDictionary *)request resources:(NSString *)resources {
    return [MSIMEClientSession candidateGlossRequest:request resources:resources error:nil];
}
- (void)synchronizeCandidateGloss {
    NSDictionary *request = [self currentGlossRequest];
    if (!request) { [self cancelCandidateGloss]; return; }
    if ([_glossRequest isEqual:request]) return;
    [self cancelCandidateGloss];
    _glossRequest = request;
    NSString *resources = [_session.hostOptions[@"resources"] copy];
    if (![resources isKindOfClass:NSString.class] || !resources.isAbsolutePath) { _glossResults = @[]; return; }
    if (!_glossQueue) { _glossQueue = [NSOperationQueue new]; _glossQueue.maxConcurrentOperationCount = 1; _glossQueue.qualityOfService = NSQualityOfServiceUtility; }
    const uint64_t epoch = _glossEpoch;
    MSIMEClientSession *session = _session;
    id client = _activeClient;
    __weak MSIMEInputController *weakSelf = self;
    [_glossQueue addOperationWithBlock:^{
        NSDictionary *result = [weakSelf readCandidateGloss:request resources:resources];
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMEInputController *current = weakSelf;
            if (!current || current->_glossEpoch != epoch || current->_session != session || current->_activeClient != client ||
                ![[current currentGlossRequest] isEqual:request] || (result && ![result[@"generation"] isEqual:request[@"generation"]])) return;
            current->_glossResults = [result[@"translations"] copy] ?: @[];
            [current applyCandidateTranslationResults];
        });
    }];
}

- (void)cancelCloudCandidates {
    ++_cloudEpoch;
    [_cloudTimer invalidate];
    _cloudTimer = nil;
    [_cloudRequest cancel];
    _cloudRequest = nil;
    _cloudQuery = nil;
}

- (MSIMECloudCandidateRequest *)cloudRequestForURL:(NSURL *)url completion:(void (^)(NSData *))completion {
    return [[MSIMECloudCandidateRequest alloc] initWithURL:url configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:completion];
}

- (void)synchronizeCloudCandidates {
    NSDictionary *query = _activeClient && _session && !_focusPending && !_appearance.englishMode &&
        (!_appearance || _appearance.cloudCandidates) ? [_session onlineQueryWithError:nil] : nil;
    NSString *url = query ? [MSIMEClientSession cloudRequestURLForQuery:query error:nil] : nil;
    if (!url) { [self cancelCloudCandidates]; return; }
    if ([_cloudQuery isEqual:query]) return;
    [self cancelCloudCandidates];
    _cloudQuery = [query copy];
    const uint64_t epoch = _cloudEpoch;
    MSIMEClientSession *session = _session;
    id client = _activeClient;
    __weak MSIMEInputController *weakSelf = self;
    _cloudTimer = [NSTimer timerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        MSIMEInputController *controller = weakSelf;
        if (!controller || controller->_cloudEpoch != epoch || controller->_session != session ||
            controller->_activeClient != client || controller->_focusPending || controller->_appearance.englishMode ||
            (controller->_appearance && !controller->_appearance.cloudCandidates) ||
            ![[session onlineQueryWithError:nil] isEqual:query]) return;
        controller->_cloudTimer = nil;
        controller->_cloudRequest = [controller cloudRequestForURL:[NSURL URLWithString:url] completion:^(NSData *body) {
            MSIMEInputController *current = weakSelf;
            if (!current || current->_cloudEpoch != epoch || current->_session != session ||
                current->_activeClient != client || current->_focusPending || current->_appearance.englishMode ||
                (current->_appearance && !current->_appearance.cloudCandidates) ||
                ![[session onlineQueryWithError:nil] isEqual:query]) return;
            current->_cloudRequest = nil;
            if (!body) return;
            NSDictionary *result = [session applyCloudResponse:body query:query error:nil];
            // Remember the post-apply identity so rendering does not re-request this result.
            current->_cloudQuery = [[session onlineQueryWithError:nil] copy];
            if ([result[@"applied"] boolValue]) [current apply:result];
        }];
        [controller->_cloudRequest start];
    }];
    [NSRunLoop.mainRunLoop addTimer:_cloudTimer forMode:NSRunLoopCommonModes];
}

- (void)ensureAppearance {
    if (_appearance) return;
    _appearance = [MSIMEAppearancePreferences sharedPreferences];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged:) name:MSIMEAppearanceDidChangeNotification object:_appearance];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged:) name:MSIMEVoiceSettingsDidChangeNotification object:nil];
}
- (void)appearanceChanged:(NSNotification *)notification {
    (void)notification;
    _preferenceLoadState.reset(); // Local edits invalidate older disk reads.
    if (!_appearance.cloudCandidates) [self cancelCloudCandidates];
    if (_appearance) _glossEnabled = @(_appearance.candidateTranslations);
    if (_appearance && !_appearance.candidateTranslations) {
        [self cancelCandidateTranslations];
        NSDictionary *view = [_session viewWithError:nil];
        if (view) {
            NSDictionary *cleared = [_session applyTranslations:@[] generation:[view[@"generation"] unsignedLongLongValue] error:nil];
            if (cleared[@"view"]) _view = cleared[@"view"];
        }
    }
    if (_appearance.englishMode && _activeClient && ([_view[@"editing_text"] length] || [_view[@"candidates"] count])) {
        [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
    }
    [self syncPageSize];
    [self syncPunctuation];
    [self syncCharacterWidth];
    [_toolbar applyLightSkin:[_appearance resolvedSkinForDark:NO].tokens darkSkin:[_appearance resolvedSkinForDark:YES].tokens];
    [_toolbar updateEnglishInputMode:_appearance.englishMode chinesePunctuationEnabled:_appearance.chinesePunctuation fullWidthEnabled:_appearance.fullWidthInput traditionalChineseOutputEnabled:_appearance.traditionalOutput];
    if (_activeClient) [self renderCandidates];
    if (_activeClient) [_toolbar setVisible:_appearance.floatingToolbarEnabled forDelegate:self];
    [self persistAppearancePreferences];
}
- (void)persistAppearancePreferences {
    if (!_preferencesDirectory) return;
    if (!_preferenceSaveState.request()) return;
    NSString *directory = [_preferencesDirectory copy];
    // Capture all host-owned fields together on the main thread. Both CAS
    // attempts use this same snapshot; later changes schedule a fresh save.
    NSDictionary *overrides = [_appearance sharedPreferencesByMerging:@{}];
    __weak MSIMEInputController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *loadError = nil;
        NSDictionary *snapshot = [MSIMEClientSession loadPreferencesInDirectory:directory error:&loadError];
        NSDictionary *preferences = snapshot ? MSIMEMergePreferenceSnapshot(snapshot[@"preferences"], overrides) : nil;
        uint64_t revision = [snapshot[@"revision"] unsignedLongLongValue];
        NSError *saveError = nil;
        NSDictionary *saved = nil;
        if (preferences) {
            saved = [MSIMEClientSession savePreferencesInDirectory:directory expectedRevision:revision snapshot:@{ @"format_version": @1, @"revision": @(revision), @"preferences": preferences } error:&saveError];
        }
        if (!saved && snapshot) {
            NSError *retryLoadError = nil;
            NSDictionary *latest = [MSIMEClientSession loadPreferencesInDirectory:directory error:&retryLoadError];
            NSDictionary *latestPreferences = latest ? MSIMEMergePreferenceSnapshot(latest[@"preferences"], overrides) : nil;
            if (latestPreferences) {
                saveError = nil;
                saved = [MSIMEClientSession savePreferencesInDirectory:directory expectedRevision:[latest[@"revision"] unsignedLongLongValue] snapshot:@{ @"format_version": @1, @"revision": latest[@"revision"] ?: @0, @"preferences": latestPreferences } error:&saveError];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMEInputController *controller = weakSelf;
            if (!controller) return;
            const bool again = controller->_preferenceSaveState.finish();
            if (saved && !saveError) [controller reloadPreferences];
            if (again) [controller persistAppearancePreferences];
        });
    });
}
- (void)syncPageSize {
    if (!_session) return;
    [self ensureAppearance];
    NSUInteger size = _appearance.pageSize;
    if (_requestedPageSize == size) return;
    NSDictionary *result = [_session setCandidatePageSize:(uint8_t)size error:nil];
    if (result) {
        _requestedPageSize = size;
        _view = result[@"view"];
    }
}
- (void)syncPunctuation {
    if (!_session) return;
    NSDictionary *view = [_session setChinesePunctuationEnabled:_appearance.chinesePunctuation error:nil];
    if (view) [self apply:@{@"view":view}];
}
- (void)syncCharacterWidth {
    if (!_session) return;
    NSDictionary *view = [_session setCharacterWidthFull:_appearance.fullWidthInput error:nil];
    if (view) [self apply:@{@"view":view}];
}
- (NSMenu *)menu {
    [self ensureAppearance];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"水杉输入法"];
    menu.autoenablesItems = NO;
    for (NSUInteger mode = 0; mode < 2; ++mode) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:mode ? @"英文输入" : @"中文输入" action:mode ? @selector(selectEnglishMode:) : @selector(selectChineseMode:) keyEquivalent:@""];
        item.target = self;
        item.state = (_appearance.englishMode == (mode == 1) && (mode == 1 || ![_view[@"dedicated_english"] isEqual:@YES])) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    NSMenuItem *englishCandidates = [[NSMenuItem alloc] initWithTitle:@"英文候选模式" action:@selector(toggleDedicatedEnglishMode:) keyEquivalent:@"e"];
    englishCandidates.target = self;
    englishCandidates.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagShift;
    englishCandidates.state = !_appearance.englishMode && [_view[@"dedicated_english"] isEqual:@YES] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:englishCandidates];
    [menu addItem:NSMenuItem.separatorItem];
    for (NSUInteger script = 0; script < 2; ++script) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:script ? @"繁体输出" : @"简体输出" action:script ? @selector(selectTraditionalOutput:) : @selector(selectSimplifiedOutput:) keyEquivalent:@""];
        item.target = self;
        item.state = _appearance.traditionalOutput == (script == 1) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *palette = [[NSMenuItem alloc] initWithTitle:@"表情与符号…" action:@selector(openCharacterPalette:) keyEquivalent:@""];
    palette.target = self;
    [menu addItem:palette];
    NSMenuItem *emoji = [[NSMenuItem alloc] initWithTitle:@"水杉表情面板…" action:@selector(showEmoji:) keyEquivalent:@""];
    emoji.target = self;
    [menu addItem:emoji];
    NSMenuItem *keyboard = [[NSMenuItem alloc] initWithTitle:@"水杉屏幕键盘…" action:@selector(showScreenKeyboard:) keyEquivalent:@""];
    keyboard.target = self;
    [menu addItem:keyboard];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"候选设置…" action:@selector(showAppearance:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    NSMenuItem *dictionary = [[NSMenuItem alloc] initWithTitle:@"个人词典…" action:@selector(showDictionary:) keyEquivalent:@""];
    dictionary.target = self;
    [menu addItem:dictionary];
    NSMenuItem *account = [[NSMenuItem alloc] initWithTitle:@"账户状态…" action:@selector(showAccount:) keyEquivalent:@""]; account.target = self; [menu addItem:account];
    NSMenuItem *clipboard = [[NSMenuItem alloc] initWithTitle:@"云剪贴板…" action:@selector(showCloudClipboard:) keyEquivalent:@""]; clipboard.target = self; [menu addItem:clipboard];
    NSMenuItem *handwriting = [[NSMenuItem alloc] initWithTitle:@"手写输入…" action:@selector(showHandwriting:) keyEquivalent:@""]; handwriting.target = self; [menu addItem:handwriting];
    NSMenuItem *prepare = [[NSMenuItem alloc] initWithTitle:@"准备词库…" action:@selector(prepareDictionary:) keyEquivalent:@""];
    prepare.target = self;
    [menu addItem:prepare];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""];
    updates.target = self;
    [menu addItem:updates];
    NSMenuItem *website = [[NSMenuItem alloc] initWithTitle:@"官方网站" action:@selector(openWebsite:) keyEquivalent:@""];
    website.target = self;
    [menu addItem:website];
    NSMenuItem *voice = [[NSMenuItem alloc] initWithTitle:@"开始/结束语音输入" action:@selector(toggleVoiceInput:) keyEquivalent:@""];
    voice.target = self;
    [menu addItem:voice];
    NSMenuItem *voiceSettings = [[NSMenuItem alloc] initWithTitle:@"语音输入设置…" action:@selector(showVoiceSettings:) keyEquivalent:@""];
    voiceSettings.target = self;
    [menu addItem:voiceSettings];
    return menu;
}
- (void)showAccount:(id)sender {
    (void)sender;
    if (!MSIMEOpenBackendAccount(NSClassFromString(@"MSIMEBackendAccountWindow"))) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"账户窗口暂不可用";
        alert.informativeText = @"请重新启动输入法；若仍无法打开，请检查安装是否完整。";
        [alert runModal];
    }
}
- (void)showCloudClipboard:(id)sender {
    if (!MSIMEOpenBackendClipboard(NSClassFromString(@"MSIMEBackendAccountWindow"))) {
        [self showAccount:sender];
    }
}
- (void)showHandwriting:(id)sender {
    (void)sender;
    Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
    id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
    if (![shared respondsToSelector:@selector(showHandwriting)]) { [self showAccount:nil]; return; }
    [shared performSelector:@selector(showHandwriting)];
}
- (void)showEmoji:(id)sender {
    (void)sender;
    Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
    id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
    NSDictionary *options = [self runtimeOptions];
    NSRunningApplication *application = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!_activeClient || !application || application.processIdentifier == NSProcessInfo.processInfo.processIdentifier ||
        ![shared respondsToSelector:@selector(showEmojiWithOptions:selectionAttempt:)]) return;
    if (!MSIMEToolApplicationMatches([(id<IMKTextInput>)_activeClient bundleIdentifier], application.bundleIdentifier)) return;
    const uint64_t token = _emojiReturn.capture(_activeClient);
    __weak MSIMEInputController *weakSelf = self;
    BOOL (^selection)(NSString *) = ^BOOL(NSString *text) {
        MSIMEInputController *controller = weakSelf;
        if (!controller || application.terminated ||
            !controller->_emojiReturn.queue(text, token, NSProcessInfo.processInfo.systemUptime)) return NO;
        // The Swift bridge closes its window before this activation is executed.
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMEInputController *current = weakSelf;
            if (!current || current->_emojiReturn.generation != token || !current->_emojiReturn.pending) return;
            if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == application.processIdentifier &&
                current->_activeClient && current->_activeClient == current->_emojiReturn.target) {
                [current commitPendingEmojiForClient:current->_activeClient];
                return;
            }
            if (!MSIMEActivateToolApplication(NSApp, NSRunningApplication.currentApplication, application)) {
                if (current->_emojiReturn.fail(token)) [current reportEmojiDeliveryFailure];
            }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            MSIMEInputController *current = weakSelf;
            if (current && current->_emojiReturn.fail(token)) [current reportEmojiDeliveryFailure];
        });
        return YES;
    };
    [shared performSelector:@selector(showEmojiWithOptions:selectionAttempt:)
                 withObject:options withObject:selection];
}
- (void)showScreenKeyboard:(id)sender {
    (void)sender;
    [[MSIMEScreenKeyboardPanel sharedPanel] showKeyboard];
}
- (void)setEnglishInputMode:(BOOL)enabled {
    [self ensureAppearance];
    if (enabled && !_appearance.englishMode && _session && _activeClient) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return; // Do not hide an unsettled composition after an Engine failure.
        [self apply:finished];
    }
    _appearance.englishMode = enabled;
    [_panel orderOut:nil];
    [_keymapPanel orderOut:nil];
}
- (void)selectChineseMode:(id)sender {
    (void)sender;
    if ([_view[@"dedicated_english"] isEqual:@YES]) [self setDedicatedEnglishInputMode:NO];
    else [self setEnglishInputMode:NO];
}
- (void)setDedicatedEnglishInputMode:(BOOL)enabled {
    if (!_activeClient) return;
    [self ensureAppearance];
    if (!_session || _focusPending) [self prepareSession];
    if (!_session) return;
    if ([_view[@"editing_text"] isKindOfClass:NSString.class] && [_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    NSError *error = nil;
    NSDictionary *view = [_session setDedicatedEnglishEnabled:enabled error:&error];
    if (!view) { if (error) NSBeep(); return; }
    _appearance.englishMode = NO;
    [self apply:@{@"view":view}];
}
- (void)toggleDedicatedEnglishMode:(id)sender {
    (void)sender;
    [self setDedicatedEnglishInputMode:_appearance.englishMode || ![_view[@"dedicated_english"] isEqual:@YES]];
}
- (void)selectSimplifiedOutput:(id)sender { (void)sender; [self ensureAppearance]; _appearance.traditionalOutput = NO; }
- (void)selectTraditionalOutput:(id)sender { (void)sender; [self ensureAppearance]; _appearance.traditionalOutput = YES; }
- (void)selectEnglishMode:(id)sender { (void)sender; [self setEnglishInputMode:YES]; }
- (void)showSystemCharacterPalette { [NSApp orderFrontCharacterPalette:nil]; }
- (void)checkForUpdates:(id)sender { (void)sender; [[MSIMEUpdateController sharedController] checkForUpdates:nil]; }
- (void)showVoiceSettings:(id)sender { (void)sender; [[MSIMEVoiceSettings sharedSettings] showAndActivate]; }
- (void)toggleVoiceInput:(id)sender {
    (void)sender;
    if (!_session) [self prepareSession];
    if (!_session) return;
    if (!_voiceService) _voiceService = [[MSIMEVoiceInputService alloc] init];
    if (_voiceService.active) { [_voiceService stopMicrophoneCapture]; [_voiceService stopTranscription]; [_voiceService cancelWithError:nil]; return; }
    __weak MSIMEInputController *weakSelf = self;
    void (^start)(void) = ^{
        MSIMEInputController *controller = weakSelf;
        if (!controller || !controller->_session) return;
        NSError *error = nil;
        if (![controller->_voiceService startWithSession:controller->_session generation:&controller->_voiceGeneration error:&error]) return;
        NSString *language = [[NSUserDefaults standardUserDefaults] stringForKey:@"MSIMEClientVoiceLanguage"] ?: @"zh-CN";
        if (![controller->_voiceService startTranscriptionWithLanguage:language textHandler:^(NSString *text, BOOL final) {
            (void)final;
            [controller->_voiceService applyText:text generation:controller->_voiceGeneration completion:^(NSDictionary *result, NSError *applyError) { if (result && !applyError) [controller apply:result]; }];
        } error:&error]) { [controller->_voiceService cancelWithError:nil]; return; }
        if (![controller->_voiceService startMicrophoneCapture:^(AVAudioPCMBuffer *buffer) { (void)buffer; } error:&error]) { [controller->_voiceService stopTranscription]; [controller->_voiceService cancelWithError:nil]; }
    };
    if (_voiceService.speechAuthorizationStatus != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        [_voiceService requestSpeechPermission:^(BOOL granted) { if (granted) [weakSelf toggleVoiceInput:nil]; }];
        return;
    }
    if (_voiceService.microphoneAuthorizationStatus != AVAuthorizationStatusAuthorized) {
        [_voiceService requestMicrophonePermission:^(BOOL granted) { if (granted) [weakSelf toggleVoiceInput:nil]; }];
        return;
    }
    start();
}
- (void)openWebsite:(id)sender { (void)sender; [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://msime.app/"]]; }
- (void)openCharacterPalette:(id)sender {
    (void)sender;
    if (_session && _activeClient) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    [self showSystemCharacterPalette];
}
- (void)showAppearance:(id)sender {
    (void)sender;
    [[MSIMEPreferencesWindowController sharedController] showAndActivate];
}
- (void)showDictionary:(id)sender { (void)sender; if (!_session) [self prepareSession]; if (!_session) return; _dictionaryWindow = [[MSIMEDictionaryWindowController alloc] initWithOptions:_session.hostOptions]; [_dictionaryWindow showWindow:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)prepareDictionary:(id)sender {
    (void)sender;
    if (_session && _activeClient) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
        [_session setFocused:NO error:nil];
        [_session closeWithError:nil];
        _session = nil;
        [_preferencesTimer invalidate];
        _preferencesTimer = nil;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO; panel.canChooseDirectories = YES; panel.allowsMultipleSelection = NO;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *state = [support URLByAppendingPathComponent:@"app.msime.client.preview" isDirectory:YES];
        [MSIMEDictionaryRuntime prepareResourcesDirectory:panel.URL.path stateRoot:state.path completion:^(NSDictionary *options, NSError *error) {
            if (!options) { NSAlert *alert = [NSAlert new]; alert.messageText = @"词库准备失败"; alert.informativeText = error.localizedDescription ?: @"无法准备词库"; [alert runModal]; return; }
            NSData *data = [NSJSONSerialization dataWithJSONObject:options options:0 error:nil];
            NSURL *target = [state URLByAppendingPathComponent:@"runtime-options.json"];
            [[NSFileManager defaultManager] createDirectoryAtURL:state withIntermediateDirectories:YES attributes:nil error:nil];
            [data writeToURL:target options:NSDataWritingAtomic error:nil];
        }];
    }];
}

- (void)activateServer:(id)sender {
    [self cancelCandidateTranslations];
    [self cancelCloudCandidates];
    _modifierTap.reset();
    [super activateServer:sender];
    [self ensureAppearance];
    if (_activeClient && _activeClient != sender) [self apply:[_session setFocused:NO error:nil]];
    [_appearance activateInputModeForApplication:[sender respondsToSelector:@selector(bundleIdentifier)] ? [sender bundleIdentifier] : nil];
    _toolbar = [MSIMEFloatingToolbarPanel sharedPanel];
    [_toolbar applyLightSkin:[_appearance resolvedSkinForDark:NO].tokens darkSkin:[_appearance resolvedSkinForDark:YES].tokens];
    [_toolbar activateForDelegate:self visible:_appearance.floatingToolbarEnabled];
    _activeClient = sender;
    _preferenceLoadState.reset();
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MSIMEClientSessionDidReplaceSnapshotNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(snapshotSessionReplaced:) name:MSIMEClientSessionDidReplaceSnapshotNotification object:nil];
    MSIMESetBackendSelectionObservation([NSNotificationCenter defaultCenter], self, @selector(handwritingCandidateSelected:), YES);
    [_toolbar updateEnglishInputMode:_appearance.englishMode chinesePunctuationEnabled:_appearance.chinesePunctuation fullWidthEnabled:_appearance.fullWidthInput traditionalChineseOutputEnabled:_appearance.traditionalOutput];
    [self ensureAppearance];
    _focusPending = _appearance.englishMode;
    if (!_appearance.englishMode) [self prepareSession];
    else [self startPreferencesMonitoring];
    [self commitPendingEmojiForClient:sender];
}

- (void)commitPendingEmojiForClient:(id)client {
    const BOOL hadPending = _emojiReturn.pending != nil;
    NSString *toolText = _emojiReturn.take(client, NSProcessInfo.processInfo.systemUptime);
    if (toolText) [client insertText:toolText replacementRange:NSMakeRange(NSNotFound, 0)];
    else if (hadPending) [self reportEmojiDeliveryFailure];
}

- (void)reportEmojiDeliveryFailure {
    Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
    id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
    if ([shared respondsToSelector:@selector(showEmojiDeliveryFailure)])
        [shared performSelector:@selector(showEmojiDeliveryFailure)];
}

- (void)handwritingCandidateSelected:(NSNotification *)notification {
    NSString *text = notification.userInfo[@"text"];
    if (![text isKindOfClass:NSString.class] || text.length == 0 || !_activeClient) return;
    [_activeClient insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)snapshotSessionReplaced:(NSNotification *)notification {
    if (notification.object != _session) return;
    [self cancelCandidateTranslations];
    [self cancelCloudCandidates];
    _modifierTap.reset();
    _requestedPageSize = 0;
    _preferenceLoadState.reset();
    _focusPending = YES;
    if (_activeClient) {
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"", @"preedit": @"", @"caret_position": @0}}, (id<MSIMETextClient>)_activeClient);
    }
    _view = [_session viewWithError:nil] ?: @{};
    [_panel orderOut:nil];
    [_keymapPanel orderOut:nil];
}

- (NSDictionary *)runtimeOptions { return MSIMELoadRuntimeOptions(); }

- (void)prepareSession {
    if (!_session) {
        NSDictionary *options = [self runtimeOptions];
        if (options) {
            _session = [[MSIMEClientSession alloc] initWithOptions:options error:nil];
            _requestedPageSize = 0;
            id directory = options[@"preferences_directory"];
            if ([directory isKindOfClass:NSString.class] && [directory isAbsolutePath]) _preferencesDirectory = [directory copy];
        }
    }
    [self syncPageSize];
    if (_session) {
        [self syncPunctuation];
        [self syncCharacterWidth];
        [self apply:[_session setFocused:YES error:nil]];
        _focusPending = NO;
    }
    [self startPreferencesMonitoring];
}

- (void)startPreferencesMonitoring {
    if (!_preferencesDirectory) {
        id directory = [self runtimeOptions][@"preferences_directory"];
        if ([directory isKindOfClass:NSString.class] && [directory isAbsolutePath]) _preferencesDirectory = [directory copy];
    }
    if (_activeClient && _preferencesDirectory) {
        [_preferencesTimer invalidate];
        __weak MSIMEInputController *weakSelf = self;
        _preferencesTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf reloadPreferences];
        }];
        [self reloadPreferences];
    }
}

- (NSDictionary *)readPreferencesSnapshotInDirectory:(NSString *)directory error:(NSError **)error {
    return [MSIMEClientSession loadPreferencesInDirectory:directory error:error];
}

- (void)completePreferenceLoad:(NSDictionary *)snapshot error:(NSError *)error generation:(uint64_t)generation
                       session:(MSIMEClientSession *)session client:(id)client {
    if (!_preferenceLoadState.finish(generation)) return;
    if (!snapshot || error || !_activeClient || _activeClient != client || _session != session) return;
    if (!session) {
        [self applySharedToolbarPreferences:snapshot[@"preferences"]];
        return;
    }
    NSError *updateError = nil;
    NSDictionary *result = [session updatePreferencesSnapshot:snapshot error:&updateError];
    // Failed loads/updates retain the existing window appearance and runtime.
    if (result && !updateError) {
        [self applySharedToolbarPreferences:snapshot[@"preferences"]];
        _view = [session viewWithError:nil] ?: result[@"view"];
        [self renderCandidates];
        [self synchronizeCloudCandidates];
        [self synchronizeCandidateGloss];
        [self synchronizeCustomTranslations];
    }
}

- (void)reloadPreferences {
    if (!_activeClient || !_preferencesDirectory || _preferenceSaveState.saving || !_preferenceLoadState.begin()) return;
    const uint64_t generation = _preferenceLoadState.generation;
    MSIMEClientSession *session = _session;
    id client = _activeClient;
    NSString *directory = [_preferencesDirectory copy];
    __weak MSIMEInputController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSDictionary *snapshot = [weakSelf readPreferencesSnapshotInDirectory:directory error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf completePreferenceLoad:snapshot error:error generation:generation session:session client:client];
        });
    });
}

- (void)applySharedToolbarPreferences:(NSDictionary *)preferences {
    BOOL translationChanged = NO;
    id glossEnabled = preferences[@"candidate_translations"];
    if ([glossEnabled isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)glossEnabled) == CFBooleanGetTypeID()) {
        translationChanged = ![_glossEnabled isEqual:glossEnabled];
        _glossEnabled = glossEnabled;
    }
    id target = preferences[@"translation_target_language"];
    if ([@[@"en", @"fr", @"ja", @"es", @"ru", @"de", @"ko"] containsObject:target]) {
        translationChanged |= ![_glossTargetLanguage isEqual:target];
        _glossTargetLanguage = [target copy];
    }
    NSDictionary *custom = preferences[@"custom_translation"];
    if ([custom isKindOfClass:NSDictionary.class]) {
        translationChanged |= ![_customTranslationConfig isEqual:custom];
        _customTranslationConfig = [custom copy];
    }
    if (translationChanged || (_glossEnabled && !_glossEnabled.boolValue)) {
        [self cancelCandidateTranslations];
        NSDictionary *view = [_session viewWithError:nil];
        if (view) [_session applyTranslations:@[] generation:[view[@"generation"] unsignedLongLongValue] error:nil];
    }
    id pageSize = preferences[@"candidate_page_size"];
    if ([pageSize isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)pageSize) != CFBooleanGetTypeID() &&
        [pageSize doubleValue] == [pageSize integerValue] && [pageSize integerValue] >= 1 && [pageSize integerValue] <= 9 &&
        [pageSize unsignedIntegerValue] != _requestedPageSize) _requestedPageSize = 0;
    [_appearance applySharedInputPreferences:preferences];
    [_appearance applySharedCandidatePreferences:preferences];
    [_appearance applySharedAssistancePreferences:preferences];
    [_appearance applySharedLocalModes:preferences[@"local_modes"]];
    [_toolbar updateEnglishInputMode:_appearance.englishMode chinesePunctuationEnabled:_appearance.chinesePunctuation fullWidthEnabled:_appearance.fullWidthInput traditionalChineseOutputEnabled:_appearance.traditionalOutput];
    Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
    id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
    if ([shared respondsToSelector:@selector(applyEmojiPreferences:)])
        [shared performSelector:@selector(applyEmojiPreferences:) withObject:preferences];
    [[MSIMEScreenKeyboardPanel sharedPanel] applyThemePreferences:preferences];
    [_toolbar applyThemePreferences:preferences];
    [_toolbar applySizingPreferences:preferences];
    NSDictionary *toolbar = preferences[@"floating_toolbar"];
    id enabled = [toolbar isKindOfClass:NSDictionary.class] ? toolbar[@"enabled"] : nil;
    if ([enabled isKindOfClass:NSNumber.class]) {
        [_appearance applySharedToolbarVisibility:[enabled boolValue]];
        [_toolbar setVisible:_appearance.floatingToolbarEnabled forDelegate:self];
    }
}

- (void)deactivateServer:(id)sender {
    // A delayed callback from the previous client must not tear down the
    // active client's composition, panels, monitoring or pending modifier tap.
    if (!sender || sender != _activeClient) return;
    [self cancelCandidateTranslations];
    [self cancelCloudCandidates];
    _modifierTap.reset();
    MSIMESetBackendSelectionObservation([NSNotificationCenter defaultCenter], self, @selector(handwritingCandidateSelected:), NO);
    _preferenceLoadState.reset();
    [_toolbar deactivateForDelegate:self];
    [_keymapPanel orderOut:nil];
    [_preferencesTimer invalidate];
    _preferencesTimer = nil;
    if (_session) [self apply:[_session setFocused:NO error:nil]];
    [_panel orderOut:nil];
    _activeClient = nil;
    [super deactivateServer:sender];
}

- (void)floatingToolbarDidRequestToggleInputMode:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self setEnglishInputMode:!_appearance.englishMode]; }
- (void)floatingToolbarDidRequestTogglePunctuation:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [self ensureAppearance];
    if (_session && _activeClient && [_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    _appearance.chinesePunctuation = !_appearance.chinesePunctuation;
    [self syncPunctuation];
    [_toolbar updateEnglishInputMode:_appearance.englishMode chinesePunctuationEnabled:_appearance.chinesePunctuation fullWidthEnabled:_appearance.fullWidthInput traditionalChineseOutputEnabled:_appearance.traditionalOutput];
}
- (void)floatingToolbarDidRequestToggleFullWidth:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; _appearance.fullWidthInput = !_appearance.fullWidthInput; }
- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; _appearance.traditionalOutput = !_appearance.traditionalOutput; }
- (void)floatingToolbarDidRequestOpenCharacterPalette:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self openCharacterPalette:nil]; }
- (void)floatingToolbarDidRequestOpenEmoji:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self showEmoji:nil]; }
- (void)floatingToolbarDidRequestOpenScreenKeyboard:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self showScreenKeyboard:nil]; }
- (void)floatingToolbarDidRequestOpenSettings:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self showAppearance:nil]; }
- (void)floatingToolbarDidRequestCheckForUpdates:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [[MSIMEUpdateController sharedController] checkForUpdates:nil]; }
- (void)floatingToolbarDidRequestOpenWebsite:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://msime.app/"]];
}
- (void)floatingToolbarDidRequestHide:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    _appearance.floatingToolbarEnabled = NO;
    [_toolbar setVisible:NO forDelegate:self];
}

- (void)dealloc {
    [_customBatch cancel];
    [_glossQueue cancelAllOperations];
    [_cloudTimer invalidate];
    [_cloudRequest cancel];
    [_preferencesTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSUInteger)recognizedEvents:(id)sender {
    (void)sender;
    return NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp && event.type != NSEventTypeFlagsChanged) return NO;
    if (!sender) { _modifierTap.reset(); return NO; }
    [self ensureAppearance];
    if (sender != _activeClient) {
        [self cancelCandidateTranslations];
        [self cancelCloudCandidates];
        _modifierTap.reset();
        _preferenceLoadState.reset();
        // Clear the previous client's marked text before accepting the new focus.
        [self apply:[_session setFocused:NO error:nil]];
        _activeClient = sender;
        [_appearance activateInputModeForApplication:[sender respondsToSelector:@selector(bundleIdentifier)] ? [sender bundleIdentifier] : nil];
        _focusPending = _appearance.englishMode;
        if (!_appearance.englishMode) [self apply:[_session setFocused:YES error:nil]];
    }
    if (_modifierTap.observe(event, _appearance.shiftTapShortcut, _appearance.controlTapShortcut)) {
        [self setEnglishInputMode:!_appearance.englishMode];
        return YES;
    }
    if (event.type != NSEventTypeKeyDown) return NO;
    [_appearance lockActiveInputMode];
    const NSEventModifierFlags competing = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption;
    if (_appearance.controlOptionSpaceShortcut && event.keyCode == 49 &&
        (event.modifierFlags & (competing | NSEventModifierFlagShift)) == (NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        if (!event.isARepeat) [self setEnglishInputMode:!_appearance.englishMode];
        return YES;
    }
    if (_appearance.inputModeShortcut && event.keyCode == 49 && (event.modifierFlags & NSEventModifierFlagShift) && !(event.modifierFlags & competing)) {
        if (!event.isARepeat) [self setEnglishInputMode:!_appearance.englishMode];
        return YES;
    }
    if (MSIMEPunctuationToggle(event)) {
        if (!event.isARepeat) [self floatingToolbarDidRequestTogglePunctuation:nil];
        return YES;
    }
    if (_appearance.characterSetShortcut && event.keyCode == 3 &&
        (event.modifierFlags & (competing | NSEventModifierFlagShift)) == (NSEventModifierFlagControl | NSEventModifierFlagShift)) {
        // Like the Windows host, reserve the chord but only toggle in Chinese mode.
        if (!event.isARepeat && !_appearance.englishMode) [self floatingToolbarDidRequestToggleTraditionalOutput:nil];
        return YES;
    }
    if (event.keyCode == 14 && (event.modifierFlags & (competing | NSEventModifierFlagShift)) == (NSEventModifierFlagControl | NSEventModifierFlagShift)) {
        if (!event.isARepeat) [self toggleDedicatedEnglishMode:nil];
        return YES;
    }
    if (msime::mac::IsFullWidthInputToggle(event.keyCode, event.modifierFlags) && (!_appearance.englishMode || event.keyCode == 49)) {
        if (!event.isARepeat) _appearance.fullWidthInput = !_appearance.fullWidthInput;
        return YES;
    }
    if (_appearance.englishMode) return NO;
    if (!_session) [self prepareSession];
    if (!_session) return NO;
    if (_focusPending) [self prepareSession];
    [self syncPageSize];
    NSUInteger deletionSlot = MSIMECandidateDeletionSlot(event);
    if (_panel.isVisible && deletionSlot != NSNotFound) {
        if (event.isARepeat) return YES;
        NSArray *candidates = _view[@"candidates"];
        if (![candidates isKindOfClass:NSArray.class] || deletionSlot >= candidates.count) return YES;
        NSDictionary *candidate = candidates[deletionSlot];
        if (![candidate isKindOfClass:NSDictionary.class]) return YES;
        NSDictionary *identifier = candidate[@"id"];
        if (!MSIMECurrentCandidateIdentity(identifier, _view)) return YES;
        NSError *error = nil;
        NSDictionary *result = [_session removeGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] error:&error];
        if (result) [self apply:result];
        else if (error) NSBeep();
        return YES; // Never finish composition or leak a reserved deletion chord.
    }
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
        return NO;
    }
    uint32_t command = UINT32_MAX;
    [self ensureAppearance];
    if (_panel.isVisible && event.keyCode == 48 && [_appearance navigationEnabled:@"tab"]) {
        [self apply:[_session command:(event.modifierFlags & NSEventModifierFlagShift) ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE error:nil]];
        return YES;
    }
    if (_panel.isVisible && !(event.modifierFlags & NSEventModifierFlagShift)) {
        NSString *characters = event.charactersIgnoringModifiers;
        if (characters.length == 1) {
            const unichar character = [characters characterAtIndex:0];
            NSDictionary *wordCharacter = [_appearance wordCharacterOptions];
            BOOL brackets = [wordCharacter[@"keys"] isEqual:@"brackets"];
            BOOL first = character == (brackets ? '[' : '-');
            BOOL last = character == (brackets ? ']' : '=');
            if ([wordCharacter[@"enabled"] boolValue] && (first || last)) {
                if (![_view[@"focused"] isEqual:@YES] || ![_view[@"candidates"] isKindOfClass:NSArray.class]) return YES;
                for (NSDictionary *candidate in _view[@"candidates"]) {
                    if (![candidate isKindOfClass:NSDictionary.class]) continue;
                    if (![candidate[@"highlighted"] isEqual:@YES]) continue;
                    NSDictionary *identifier = candidate[@"id"];
                    if (!MSIMECurrentCandidateIdentity(identifier, _view)) return YES;
                    NSDictionary *selected = [_session selectEdgeGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] edge:first ? MSIME_FIRST_HAN : MSIME_LAST_HAN error:nil];
                    if (selected) [self apply:selected];
                    return YES; // Unsupported/stale candidates must not turn into punctuation.
                }
                return YES;
            }
            const BOOL previous = ([_appearance navigationEnabled:@"minus_equal"] && character == '-') || ([_appearance navigationEnabled:@"brackets"] && character == '[') || ([_appearance navigationEnabled:@"comma_period"] && character == ',');
            const BOOL next = ([_appearance navigationEnabled:@"minus_equal"] && character == '=') || ([_appearance navigationEnabled:@"brackets"] && character == ']') || ([_appearance navigationEnabled:@"comma_period"] && character == '.');
            if (previous || next) {
                [self apply:[_session command:previous ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE error:nil]];
                return YES;
            }
        }
    }
    if (_panel.isVisible && [_appearance navigationEnabled:@"arrows"] && event.keyCode >= 123 && event.keyCode <= 126) {
        const BOOL horizontal = event.keyCode == 123 || event.keyCode == 124;
        if (horizontal == _appearance.vertical) return YES;
        const BOOL backwards = event.keyCode == 123 || event.keyCode == 126;
        [self apply:[_session command:backwards ? MSIME_PREVIOUS_CANDIDATE : MSIME_NEXT_CANDIDATE error:nil]];
        return YES;
    }
    switch (event.keyCode) {
        case 48: return NO;
        case 51: command = MSIME_BACKSPACE; break;
        case 36: case 76: command = MSIME_COMMIT_RAW; break;
        case 53: command = MSIME_CANCEL; break;
        case 49: command = MSIME_COMMIT_CANDIDATE; break;
        case 123: command = MSIME_MOVE_LEFT; break;
        case 124: command = MSIME_MOVE_RIGHT; break;
        case 115: command = _panel.isVisible ? MSIME_FIRST_CANDIDATE_ON_PAGE : MSIME_MOVE_HOME; break;
        case 119: command = _panel.isVisible ? MSIME_LAST_CANDIDATE_ON_PAGE : MSIME_MOVE_END; break;
        case 117: command = MSIME_DELETE_FORWARD; break;
        case 116: if (![_appearance navigationEnabled:@"page_up_down"]) return NO; command = MSIME_PREVIOUS_PAGE; break;
        case 121: if (![_appearance navigationEnabled:@"page_up_down"]) return NO; command = MSIME_NEXT_PAGE; break;
        case 126: if (![_appearance navigationEnabled:@"arrows"]) return NO; command = MSIME_PREVIOUS_CANDIDATE; break;
        case 125: if (![_appearance navigationEnabled:@"arrows"]) return NO; command = MSIME_NEXT_CANDIDATE; break;
    }
    NSDictionary *transition = nil;
    if (command != UINT32_MAX) transition = [_session command:command error:nil];
    else if (event.characters.length == 1 && [event.characters characterAtIndex:0] <= 127) {
        transition = [_session typeASCII:(uint8_t)[event.characters characterAtIndex:0] shift:(event.modifierFlags & NSEventModifierFlagShift) != 0 error:nil];
    }
    if (!transition) return NO;
    [self apply:transition];
    if (command == UINT32_MAX && [transition[@"handled"] boolValue] &&
        ![transition[@"commit"] isKindOfClass:NSString.class] && event.characters.length == 1 &&
        [event.characters characterAtIndex:0] >= 'a' && [event.characters characterAtIndex:0] <= 'z' &&
        MSIMEShouldAutoCommitWubi(_appearance.wubiAutoCommitUnique, transition[@"view"])) {
        NSDictionary *committed = [_session command:MSIME_COMMIT_CANDIDATE error:nil];
        if (committed) [self apply:committed];
    }
    if ([transition[@"handled"] boolValue]) return YES;
    // Match Apple: Engine gets first refusal, then finish any composition before fallback.
    if ([_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return NO;
        [self apply:finished];
    }
    if (_appearance.fullWidthInput && [_view[@"editing_text"] isKindOfClass:NSString.class] &&
        ![_view[@"editing_text"] length] && event.characters.length == 1 &&
        msime::mac::IsFullWidthDirectCharacter([event.characters characterAtIndex:0], event.modifierFlags)) {
        const unichar converted = msime::mac::FullWidthCharacter([event.characters characterAtIndex:0]);
        [(id<MSIMETextClient>)sender insertText:[NSString stringWithCharacters:&converted length:1] replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
        return YES;
    }
    return NO;
}

- (void)commitComposition:(id)sender {
    if (sender != _activeClient || !_session) return;
    [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
}

- (void)apply:(NSDictionary *)transition {
    if (!transition || !_activeClient) return;
    NSDictionary *displayTransition = transition;
    if (_appearance.traditionalOutput && MSIMEScriptConversionApplies(transition[@"commit_context"]) && [transition[@"commit"] isKindOfClass:NSString.class]) {
        NSMutableDictionary *converted = [transition mutableCopy];
        converted[@"commit"] = MSIMEChineseOutputString(transition[@"commit"], YES);
        displayTransition = converted;
    }
    MSIMEApplyTransition(displayTransition, (id<MSIMETextClient>)_activeClient);
    _view = transition[@"view"];
    [self renderCandidates];
    [self synchronizeCloudCandidates];
    [self synchronizeCandidateGloss];
    [self synchronizeCustomTranslations];
}

- (void)updateKeymapPanel {
    NSString *editing = MSIMEShuangpinKeymapEditingText(_view);
    NSNumber *scheme = _view[@"scheme"];
    NSString *profile = _view[@"shuangpin_profile"];
    NSString *mode = _view[@"local_mode"];
    NSNumber *dedicatedEnglish = _view[@"dedicated_english"];
    if (!_session || !_activeClient || _appearance.englishMode ||
        ![scheme isKindOfClass:NSNumber.class] || scheme.integerValue != 1 ||
        ![mode isKindOfClass:NSString.class] || ![mode isEqualToString:@"none"] ||
        ![dedicatedEnglish isKindOfClass:NSNumber.class] || dedicatedEnglish.boolValue ||
        ![profile isKindOfClass:NSString.class] || profile.length == 0 ||
        !MSIMEShouldShowShuangpinKeymap(YES, _appearance.shuangpinKeymap, editing.length > 0)) {
        [_keymapPanel orderOut:nil];
        return;
    }
    NSRect cursor = NSZeroRect;
    [_activeClient attributesForCharacterIndex:0 lineHeightRectangle:&cursor];
    if (!MSIMEValidCaret(cursor)) { [_keymapPanel orderOut:nil]; return; }
    if (!_keymapPanel) _keymapPanel = [[MSIMEShuangpinKeymapPanel alloc] init];
    [_keymapPanel setProfileName:profile];
    [_keymapPanel updateHighlightedKey:MSIMEShuangpinKeymapHighlightedKey(_view)];
    CGFloat clearance = _appearance.fontSize + 42.0;
    if (_appearance.vertical) clearance = (_appearance.fontSize + 10.0) * MIN([_view[@"candidates"] count], _appearance.pageSize) + 24.0;
    NSArray *candidates = _view[@"candidates"];
    if ([candidates isKindOfClass:NSArray.class] && candidates.count) {
        NSFont *font = [_appearance candidateFontOfSize:_appearance.fontSize];
        CGFloat rowHeight = MSIMECandidateTextHeight(@"", font) + 12;
        BOOL traditional = _appearance.traditionalOutput && MSIMEScriptConversionApplies(_view);
        for (NSDictionary *candidate in candidates)
            rowHeight = MAX(rowHeight, MSIMECandidateTextHeight(CandidateDisplay(candidate, traditional), font) + 12);
        if (!_appearance.vertical) {
            CGFloat glossHeight = 0;
            NSFont *glossFont = [_appearance candidateFontOfSize:font.pointSize * 0.78];
            for (NSDictionary *candidate in candidates) {
                NSString *translation = CandidateTranslation(candidate);
                if (translation.length) glossHeight = MAX(glossHeight, [translation sizeWithAttributes:@{NSFontAttributeName:glossFont}].height + 4);
            }
            rowHeight += glossHeight;
        }
        clearance = MAX(clearance, (_appearance.vertical ? candidates.count : 1) * rowHeight + 24);
    }
    id preedit = [_view[@"preedit"] isKindOfClass:NSString.class] ? _view[@"preedit"] : editing;
    if (_appearance.showsCandidatePreedit && [preedit length] && [_view[@"candidates"] count]) {
        NSFont *preeditFont = [_appearance candidateFontOfSize:_appearance.preeditFontSize];
        clearance += MAX(22.0, MSIMECandidateTextHeight(preedit, preeditFont) + 6.0);
    }
    [_keymapPanel showNearCaretRect:cursor candidateClearance:clearance];
}

- (void)renderCandidates {
    _candidateMenuToken = [NSObject new];
    [self updateKeymapPanel];
    if (_appearance.englishMode) { [_panel orderOut:nil]; return; }
    NSArray *candidates = _view[@"candidates"];
    if (![candidates isKindOfClass:NSArray.class] || candidates.count == 0) { [_panel orderOut:nil]; return; }
    NSRect cursor = NSZeroRect;
    [(id<IMKTextInput>)_activeClient attributesForCharacterIndex:0 lineHeightRectangle:&cursor];
    if (!MSIMEValidCaret(cursor)) { [_panel orderOut:nil]; return; }
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSPointInRect(NSMakePoint(NSMinX(cursor), NSMidY(cursor)), candidate.frame)) { screen = candidate; break; }
    }
    screen = screen ?: NSScreen.mainScreen;
    if (!screen) { [_panel orderOut:nil]; return; }
    NSRect visible = screen.visibleFrame;
    [self ensureAppearance];
    const BOOL vertical = _appearance.vertical;
    NSAppearance *currentAppearance = _panel.effectiveAppearance ?: NSApp.effectiveAppearance;
    NSString *currentTheme = [currentAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    const auto skin = [_appearance resolvedSkinForDark:[currentTheme isEqual:NSAppearanceNameDarkAqua]];
    const auto geometry = skin.tokens;
    _skinShowsSelectedBar = geometry.showSelectedBar;
    const CGFloat inset = MAX(2.0, geometry.pad);
    NSFont *font = [_appearance candidateFontOfSize:_appearance.fontSize];
    id preeditValue = _view[@"preedit"];
    if (![preeditValue isKindOfClass:NSString.class]) preeditValue = _view[@"editing_text"];
    NSString *preedit = _appearance.showsCandidatePreedit && [preeditValue isKindOfClass:NSString.class] ? preeditValue : @"";
    NSFont *preeditFont = [_appearance candidateFontOfSize:_appearance.preeditFontSize];
    CGFloat preeditHeight = preedit.length ? MAX(22.0, MSIMECandidateTextHeight(preedit, preeditFont) + 6.0) : 0;
    CGFloat rowHeight = MSIMECandidateTextHeight(@"", font) + 12;
    const NSUInteger page = [_view[@"page"] unsignedIntegerValue];
    const NSUInteger pageCount = [_view[@"page_count"] unsignedIntegerValue];
    const BOOL paging = pageCount > 1;
    CGFloat width = 20;
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    CGFloat totalWidth = 0;
    NSUInteger index = 0;
    const BOOL traditional = _appearance.traditionalOutput && MSIMEScriptConversionApplies(_view);
    NSFont *glossFont = [_appearance candidateFontOfSize:font.pointSize * 0.78];
    CGFloat glossHeight = 0;
    for (NSDictionary *candidate in candidates) {
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)++index, CandidateDisplay(candidate, traditional)];
        rowHeight = MAX(rowHeight, MSIMECandidateTextHeight(title, font) + 12);
        CGFloat itemWidth = ceil([title sizeWithAttributes:@{NSFontAttributeName: font}].width) + 16 + (geometry.showSelectedBar ? 6 : 0);
        NSString *translation = CandidateTranslation(candidate);
        if (translation.length) {
            NSSize glossSize = [translation sizeWithAttributes:@{NSFontAttributeName:glossFont}];
            if (vertical) itemWidth += font.pointSize * 0.65 + ceil(glossSize.width);
            else { itemWidth = MAX(itemWidth, ceil(glossSize.width) + 40 + (geometry.showSelectedBar ? 6 : 0)); glossHeight = MAX(glossHeight, glossSize.height + 4); }
        }
        [widths addObject:@(itemWidth)];
        totalWidth += itemWidth;
        width = MAX(width, itemWidth + 2 * inset);
    }
    width = MIN(width, MAX(80, visible.size.width - 20));
    rowHeight += glossHeight;
    if (paging) width = MAX(width, 76);
    if (!vertical) {
        const CGFloat available = MAX(80, visible.size.width - 32 - (paging ? 56 : 0));
        if (totalWidth > available) {
            const CGFloat scale = available / totalWidth;
            totalWidth = 0;
            for (NSUInteger i = 0; i < widths.count; ++i) {
                widths[i] = @(MAX(24, floor(widths[i].doubleValue * scale)));
                totalWidth += widths[i].doubleValue;
            }
        }
        width = totalWidth + 2 * inset + (paging ? 56 : 0);
    }
    if (!_panel) {
        _panel = [[MSIMECandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        _panel.level = NSPopUpMenuWindowLevel;
        _panel.hasShadow = YES;
        _panel.hidesOnDeactivate = NO;
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    }
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    const CGFloat decorationHeight = skin.decorationTopDip;
    if (preedit.length) width = MAX(width, MIN(ceil([preedit sizeWithAttributes:@{NSFontAttributeName:preeditFont}].width) + 2 * inset + 4 + MSIMEPreeditCaretGap, MAX(80, visible.size.width - 20)));
    width = MAX(width, MAX(skin.minWidthDip, skin.decorationWidthDip));
    CGFloat height = (vertical ? candidates.count : 1) * rowHeight + 2 * inset + (paging && vertical ? 26 : 0) + decorationHeight + preeditHeight;
    [_panel setContentSize:NSMakeSize(width, height)];
    MSIMECandidateChromeView *content = [[MSIMECandidateChromeView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    NSUInteger slot = 0;
    CGFloat x = inset;
    for (NSDictionary *candidate in candidates) {
        NSString *display = CandidateDisplay(candidate, traditional);
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)(slot + 1), display];
        MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:title target:self action:@selector(selectCandidate:)];
        button.candidateID = candidate[@"id"];
        button.menu = [self menuForCandidate:candidate];
        button.tag = (NSInteger)slot;
        CGFloat itemWidth = vertical ? width - 2 * inset : widths[slot].doubleValue;
        button.frame = NSMakeRect(x, vertical ? height - inset - decorationHeight - preeditHeight - ((slot + 1) * rowHeight) : inset, itemWidth, rowHeight);
        ++slot;
        if (!vertical) x += itemWidth;
        button.font = font;
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.toolTip = display;
        button.translation = CandidateTranslation(candidate);
        button.translationFont = glossFont;
        button.translationBelow = !vertical;
        button.translationRowHeight = glossHeight;
        if (button.translation.length) button.toolTip = [display stringByAppendingFormat:@"\n%@", button.translation];
        button.bordered = NO;
        button.candidateHighlighted = [candidate[@"highlighted"] boolValue];
        id fixed = candidate[@"fixed_position"];
        button.candidateFixed = MSIMEUnsignedCandidateIdentityValue(fixed) &&
            [fixed compare:@0] == NSOrderedDescending && [fixed compare:@255] != NSOrderedDescending;
        button.alignment = NSTextAlignmentLeft;
        [content addSubview:button];
    }
    if (paging) {
        for (NSUInteger direction = 0; direction < 2; ++direction) {
            MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:direction == 0 ? @"‹" : @"›" target:self action:@selector(changeCandidatePage:)];
            button.frame = NSMakeRect((vertical ? inset : x) + direction * 28, inset, 28, vertical ? 26 : rowHeight);
            button.bordered = NO;
            button.tag = direction == 0 ? -1 : -2;
            button.enabled = direction == 0 ? page > 0 : page < pageCount - 1;
            button.accessibilityLabel = direction == 0 ? @"上一页候选" : @"下一页候选";
            // A retained button from an old page cannot navigate a newer view.
            button.candidateID = _view;
            [content addSubview:button];
        }
    }
    if (preedit.length) {
        MSIMECandidatePreeditField *label = [MSIMECandidatePreeditField labelWithString:preedit];
        label.identifier = @"candidate-preedit";
        label.accessibilityLabel = @"候选窗预编辑";
        label.font = preeditFont;
        NSString *editing = [_view[@"editing_text"] isKindOfClass:NSString.class] ? _view[@"editing_text"] : @"";
        label.caretIndex = MSIMEPreeditCaretPosition(editing, preedit, _view[@"caret_position"]);
        label.showsCaret = [_view[@"focused"] isEqual:@YES];
        label.frame = NSMakeRect(inset, height - inset - decorationHeight - preeditHeight, width - 2 * inset, preeditHeight);
        [content addSubview:label];
    }
    if (decorationHeight > 0 && _appearance.decorationImage) {
        NSImageView *decoration = [[NSImageView alloc] initWithFrame:NSMakeRect(width - skin.decorationWidthDip, height - decorationHeight, skin.decorationWidthDip, decorationHeight)];
        decoration.image = _appearance.decorationImage;
        decoration.imageScaling = NSImageScaleProportionallyUpOrDown;
        decoration.imageAlignment = NSImageAlignTopRight;
        decoration.wantsLayer = YES;
        [content addSubview:decoration];
    }
    _panel.contentView = content;
    content.appearanceTarget = self;
    content.appearanceAction = @selector(refreshCandidateSkin);
    [self refreshCandidateSkin];
    [_panel setFrameOrigin:MSIMECandidateOrigin(cursor, _panel.frame.size, visible)];
    [_panel orderFrontRegardless];
}

- (void)refreshCandidateSkin {
    if (![_panel.contentView isKindOfClass:MSIMECandidateChromeView.class]) return;
    MSIMECandidateChromeView *content = (id)_panel.contentView;
    NSString *match = [content.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    const auto tokens = [_appearance resolvedSkinForDark:[match isEqual:NSAppearanceNameDarkAqua]].tokens;
    if (tokens.showSelectedBar != _skinShowsSelectedBar) { [self renderCandidates]; return; }
    content.fillColor = SkinColor(tokens.surface);
    content.strokeColor = SkinColor(tokens.border);
    content.cornerRadius = tokens.radius;
    content.lineWidth = tokens.borderWidth;
    for (MSIMECandidateButton *button in content.subviews) {
        if ([button.identifier isEqual:@"candidate-preedit"] && [button isKindOfClass:NSTextField.class]) {
            ((NSTextField *)(id)button).textColor = [_appearance candidateTextColorWithDefault:SkinColor(tokens.text)];
            if ([button isKindOfClass:MSIMECandidatePreeditField.class]) ((MSIMECandidatePreeditField *)(id)button).caretColor = SkinColor(tokens.accent);
        }
        if (![button isKindOfClass:MSIMECandidateButton.class]) continue;
        button.fillColor = SkinColor(tokens.selected);
        button.titleColor = button.candidateHighlighted ? SkinColor(tokens.selectedText) : [_appearance candidateTextColorWithDefault:SkinColor(tokens.text)];
        button.translationColor = [button.titleColor colorWithAlphaComponent:0.65];
        // Windows fixed-position span overrides candidate text, not its number.
        if (button.candidateFixed) button.titleColor = [NSColor colorWithSRGBRed:55.0/255 green:154.0/255 blue:211.0/255 alpha:1];
        button.numberColor = SkinColor(button.candidateHighlighted ? tokens.selectedText : tokens.number);
        button.barColor = SkinColor(tokens.accent);
        button.showSelectedBar = tokens.showSelectedBar;
        button.contentTintColor = SkinColor(tokens.text);
        button.needsDisplay = YES;
    }
    content.needsDisplay = YES;
}

- (void)selectCandidate:(MSIMECandidateButton *)button {
    if (!_activeClient || !_session || !_panel.isVisible || !button.enabled || button.superview != _panel.contentView) return;
    NSDictionary *identifier = button.candidateID;
    if (!MSIMECurrentCandidateIdentity(identifier, _view)) return;
    [self apply:[_session selectGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] error:nil]];
}

- (NSMenu *)menuForCandidate:(NSDictionary *)candidate {
    NSDictionary *identifier = candidate[@"id"];
    if (!MSIMECurrentCandidateIdentity(identifier, _view) || !_candidateMenuToken) return nil;
    NSDictionary *context = @{@"id":[identifier copy], @"render":_candidateMenuToken};
    NSMenuItem *(^item)(NSString *, NSInteger) = ^NSMenuItem *(NSString *title, NSInteger tag) {
        NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:title action:@selector(candidateMenuAction:) keyEquivalent:@""];
        entry.target = self;
        entry.tag = tag;
        entry.representedObject = context;
        return entry;
    };
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"候选操作"];
    menu.autoenablesItems = NO;
    [menu addItem:item(@"置顶", 0)];
    NSMenuItem *fixed = [[NSMenuItem alloc] initWithTitle:@"固定排位" action:nil keyEquivalent:@""];
    NSMenu *positions = [[NSMenu alloc] initWithTitle:@"固定排位"];
    positions.autoenablesItems = NO;
    for (NSInteger position = 1; position <= 5; ++position)
        [positions addItem:item([NSString stringWithFormat:@"第 %ld 位", (long)position], 10 + position)];
    [positions addItem:NSMenuItem.separatorItem];
    [positions addItem:item(@"取消固定", 2)];
    fixed.submenu = positions;
    [menu addItem:fixed];
    NSString *text = candidate[@"text"];
    // Windows hides deletion for one Unicode scalar, including supplementary Han.
    if ([text isKindOfClass:NSString.class] && [text lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding] / 4 > 1) {
        NSMenuItem *remove = item(@"删除", 1);
        NSArray *candidates = _view[@"candidates"];
        NSUInteger slot = [candidates isKindOfClass:NSArray.class] ? [candidates indexOfObjectIdenticalTo:candidate] : NSNotFound;
        if (slot < 8) {
            remove.keyEquivalent = [NSString stringWithFormat:@"%lu", (unsigned long)slot + 1];
            remove.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
        }
        [menu addItem:remove];
    }
    return menu;
}

- (void)candidateMenuAction:(NSMenuItem *)item {
    if (!_activeClient || !_session || !_panel.isVisible || !item.enabled) return;
    NSDictionary *context = item.representedObject;
    if (![context isKindOfClass:NSDictionary.class] || context[@"render"] != _candidateMenuToken) return;
    NSDictionary *identifier = context[@"id"];
    if (!MSIMECurrentCandidateIdentity(identifier, _view)) return;
    uint64_t generation = [identifier[@"generation"] unsignedLongLongValue];
    NSUInteger index = [identifier[@"index"] unsignedIntegerValue];
    NSError *error = nil;
    NSDictionary *result = nil;
    switch (item.tag) {
        case 0: result = [_session pinGeneration:generation index:index error:&error]; break;
        case 1: result = [_session removeGeneration:generation index:index error:&error]; break;
        case 2: result = [_session clearPositionGeneration:generation index:index error:&error]; break;
        default:
            if (item.tag < 11 || item.tag > 15) return;
            result = [_session fixGeneration:generation index:index position:(uint8_t)(item.tag - 10) error:&error];
    }
    if (result) [self apply:result];
    else if (error) NSBeep();
}

- (void)changeCandidatePage:(MSIMECandidateButton *)button {
    if (!_activeClient || !_session || !_panel.isVisible || !button.enabled || button.superview != _panel.contentView) return;
    if (![_view isKindOfClass:NSDictionary.class] || ![_view[@"focused"] isEqual:@YES] ||
        ![button.candidateID isKindOfClass:NSDictionary.class]) return;
    if (![_view[@"focused"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)_view[@"focused"]) != CFBooleanGetTypeID()) return;
    for (NSString *key in @[@"session", @"generation", @"page"]) {
        if (!MSIMEUnsignedCandidateIdentityValue(button.candidateID[key]) ||
            !MSIMEUnsignedCandidateIdentityValue(_view[key]) || ![button.candidateID[key] isEqual:_view[key]]) return;
    }
    if (!MSIMEUnsignedCandidateIdentityValue(_view[@"page_count"])) return;
    const NSUInteger page = [_view[@"page"] unsignedIntegerValue];
    const NSUInteger count = [_view[@"page_count"] unsignedIntegerValue];
    if (count == 0 || page >= count) return;
    if (button.tag == -1 && page > 0) [self apply:[_session command:MSIME_PREVIOUS_PAGE error:nil]];
    if (button.tag == -2 && count > 0 && page < count - 1) [self apply:[_session command:MSIME_NEXT_PAGE error:nil]];
}
@end
