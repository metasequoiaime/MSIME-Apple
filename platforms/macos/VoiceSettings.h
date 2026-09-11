#pragma once
#import <Foundation/Foundation.h>
@interface MetasequoiaVoiceSettings : NSObject
@property(nonatomic,copy) NSString *provider, *endpoint, *model, *token;
@property(nonatomic,copy) NSString *modelPath, *polishEndpoint, *polishModel, *polishToken;
@property(nonatomic) BOOL polishEnabled;
+ (instancetype)loadSettings;
- (BOOL)validate:(NSError **)error;
- (BOOL)save:(NSError **)error;
@end
