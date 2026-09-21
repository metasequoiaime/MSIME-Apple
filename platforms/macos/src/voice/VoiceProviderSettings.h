#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const MSIMEVoiceProviderSettingsDidChangeNotification;
FOUNDATION_EXPORT NSArray<NSString *> *MSIMEVoiceASRProviderIDs(void);
FOUNDATION_EXPORT NSArray<NSString *> *MSIMEVoiceASRProviderTitles(void);
FOUNDATION_EXPORT NSString *MSIMEVoiceASRProviderDefaultEndpoint(NSString *provider);
FOUNDATION_EXPORT NSString *MSIMEVoiceASRProviderDefaultModel(NSString *provider);
FOUNDATION_EXPORT BOOL MSIMEVoiceASRProviderUsesService(NSString *provider);
@interface MetasequoiaVoiceProviderSettings : NSObject
@property(nonatomic, copy) NSString *provider;
@property(nonatomic, copy) NSString *endpoint;
@property(nonatomic, copy) NSString *model;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *modelPath;
@property(nonatomic) BOOL polishEnabled;
@property(nonatomic, copy) NSString *polishEndpoint;
@property(nonatomic, copy) NSString *polishModel;
@property(nonatomic, copy) NSString *polishToken;
/// CoreAudio device UID; an empty value means the system default input.
@property(nonatomic, copy) NSString *captureDevice;
+ (instancetype)loadSettings;
- (BOOL)validate:(NSError **)error;
- (BOOL)save:(NSError **)error;
@end
@interface MetasequoiaVoiceProviderSettingsWindow : NSWindowController
+ (instancetype)sharedController;
- (void)showAndActivate;
@end
NS_ASSUME_NONNULL_END
