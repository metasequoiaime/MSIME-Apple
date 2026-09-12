#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const MSIMEVoiceProviderSettingsDidChangeNotification;
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
+ (instancetype)loadSettings;
- (BOOL)validate:(NSError **)error;
- (BOOL)save:(NSError **)error;
@end
@interface MetasequoiaVoiceProviderSettingsWindow : NSWindowController
+ (instancetype)sharedController;
- (void)showAndActivate;
@end
NS_ASSUME_NONNULL_END
