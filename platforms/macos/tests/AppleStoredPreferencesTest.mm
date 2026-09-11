#import "../AppleStoredPreferences.h"
#include <cassert>
int main(){@autoreleasepool{NSUserDefaults *d=[[NSUserDefaults alloc]initWithSuiteName:@"msime.test"]; [d setInteger:2 forKey:@"MSIMEClientInputScheme"]; [d setBool:YES forKey:@"MSIMEClientAutocorrect"]; assert(MSIMEStoredScheme(d)==2); assert(MSIMEStoredAutocorrectEnabled(d));}}
