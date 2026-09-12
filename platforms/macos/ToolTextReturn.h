#pragma once
#import <Foundation/Foundation.h>
#include <cstdint>

// One-shot handoff to the exact IMK client which opened a tool window.
// No input is persisted; stale windows and other clients cannot consume it.
struct MSIMEToolTextReturn {
    __weak id target = nil;
    NSString *pending = nil;
    double deadline = 0;
    uint64_t generation = 0;

    uint64_t capture(id client) {
        target = client;
        pending = nil;
        deadline = 0;
        return ++generation;
    }
    bool queue(NSString *text, uint64_t token, double now) {
        if (token != generation || !target || ![text isKindOfClass:NSString.class] ||
            text.length == 0 || text.length > 4096 || pending) return false;
        pending = [text copy];
        deadline = now + 2;
        return true;
    }
    void discard(uint64_t token) {
        if (token != generation) return;
        target = nil;
        pending = nil;
        deadline = 0;
        ++generation;
    }
    NSString *take(id client, double now) {
        if (!pending) return nil;
        NSString *text = client && client == target && now < deadline ? pending : nil;
        discard(generation);
        return text;
    }
};
