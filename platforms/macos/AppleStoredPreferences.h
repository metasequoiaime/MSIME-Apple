#pragma once
#import <Foundation/Foundation.h>
inline NSInteger MSIMEStoredScheme(NSUserDefaults *d) { return [d integerForKey:@"MSIMEClientInputScheme"]; }
inline BOOL MSIMEStoredAutocorrectEnabled(NSUserDefaults *d) { return [d boolForKey:@"MSIMEClientAutocorrect"]; }
