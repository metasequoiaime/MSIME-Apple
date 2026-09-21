#import "../../src/core/AppleStoredPreferences.h"
#include <cassert>
#import "TestPreferenceSuite.h"
// A fixed suite name rather than a per-run one, so this leaves a single domain instead of a new one
// every run - but it still leaves it, and nothing else ever looks at it.
int main(){@autoreleasepool{NSString *suite=[@"msime.test.stored." stringByAppendingString:NSUUID.UUID.UUIDString]; NSUserDefaults *d=[[NSUserDefaults alloc]initWithSuiteName:suite]; [d setInteger:2 forKey:@"MSIMEClientInputScheme"]; [d setBool:YES forKey:@"MSIMEClientAutocorrect"]; assert(MSIMEStoredScheme(d)==2); assert(MSIMEStoredAutocorrectEnabled(d)); MSIMERemoveTestPreferenceSuite(d, suite);}}
