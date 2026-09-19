#include "DictionarySessionLease.h"
#include <cassert>
#include <memory>
#include <stdexcept>

// The lease is what decides whether a dictionary snapshot may be published. Every live keyboard
// bridge holds a shared lease, publication requires the only remaining one, and the upgrade from
// shared to exclusive is not atomic -- so a publication that throws has to leave the lease back
// in the shared state it started from, or the session that survived the failure can never publish
// again. These are the cases that distinguish those states; the bridge sources are shared with
// the Apple client unchanged, so the behaviour asserted here is that client's behaviour.
int main() {
    @autoreleasepool {
        using metasequoia::apple::DictionarySessionLease;
        NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                                 stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        {
            DictionarySessionLease first(root);
            auto other = std::make_unique<DictionarySessionLease>(root);
            bool ran = false;
            // A second live session blocks publication from either side.
            assert(!first.exclusively([&] { ran = true; }));
            assert(!ran);
            assert(!other->exclusively([&] { ran = true; }));
            assert(!ran);

            other.reset();
            bool failed = false;
            try {
                first.exclusively([] { throw std::runtime_error("synthetic publication failure"); });
            } catch (const std::exception &) {
                failed = true;
            }
            // The operation's exception reaches the caller rather than being swallowed into a
            // "publication declined" result: a failed publication is not a busy lease.
            assert(failed);

            // Having restored sharing, a newly created session must again be able to block.
            other = std::make_unique<DictionarySessionLease>(root);
            assert(!other->exclusively([&] { ran = true; }));
            assert(!ran);

            other.reset();
            assert(first.exclusively([&] { ran = true; }));
            assert(ran);
        }
        assert([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
    }
    return 0;
}
