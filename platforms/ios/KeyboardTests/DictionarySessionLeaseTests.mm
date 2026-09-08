#import <XCTest/XCTest.h>
#include "DictionarySessionLease.h"
#include <memory>
#include <stdexcept>

@interface DictionarySessionLeaseTests : XCTestCase
@end
@implementation DictionarySessionLeaseTests
- (void)testExclusivePublicationWaitsForOtherSessionsAndRestoresAfterFailure
{
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    using metasequoia::apple::DictionarySessionLease;
    {
        DictionarySessionLease first(root);
        auto other = std::make_unique<DictionarySessionLease>(root);
        bool ran = false;
        XCTAssertFalse(first.exclusively([&] { ran = true; }));
        XCTAssertFalse(ran);
        XCTAssertFalse(other->exclusively([&] { ran = true; }));
        other.reset();
        bool failed = false;
        try { first.exclusively([] { throw std::runtime_error("synthetic publication failure"); }); }
        catch (const std::exception &) { failed = true; }
        XCTAssertTrue(failed);
        other = std::make_unique<DictionarySessionLease>(root);
        XCTAssertFalse(other->exclusively([&] { ran = true; }));
        other.reset();
        XCTAssertTrue(first.exclusively([&] { ran = true; }));
        XCTAssertTrue(ran);
    }
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
}
@end
