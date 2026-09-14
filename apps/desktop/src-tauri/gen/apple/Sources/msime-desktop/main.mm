#include "bindings/bindings.h"
#import <Foundation/Foundation.h>
#include <cstdlib>

static void configure_shared_state() {
	NSURL *container = [[NSFileManager defaultManager]
		containerURLForSecurityApplicationGroupIdentifier:@"group.app.msime.ios"];
	if (container == nil) return;
	NSURL *state = [container URLByAppendingPathComponent:@"MSIME" isDirectory:YES];
	setenv("MSIME_CLIENT_STATE_DIR", state.fileSystemRepresentation, 1);
}

int main(int argc, char * argv[]) {
	@autoreleasepool {
		configure_shared_state();
		ffi::start_app();
	}
	return 0;
}
