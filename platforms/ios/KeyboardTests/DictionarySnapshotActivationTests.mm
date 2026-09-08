#import <XCTest/XCTest.h>
#import "MetasequoiaInputSessionBridge.h"
#import "DictionarySnapshotBridge.h"

@interface DictionarySnapshotActivationTests : XCTestCase
@end
@implementation DictionarySnapshotActivationTests
- (void)testActualBridgeChecksOtherSessionsAndVersionsBeforeActivating
{
    __block NSURL *user = nil;
    __block NSData *originalMarker = nil;
    __block NSString *originalVersion = nil;
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSFileManager *manager = NSFileManager.defaultManager;
    @try
    {
        @autoreleasepool
        {
            MetasequoiaInputSessionBridge *session = [[MetasequoiaInputSessionBridge alloc] init];
            NSError *error = nil;
            NSDictionary *context = [session dictionarySnapshotContextWithError:&error];
            XCTAssertNotNil(context);
            XCTAssertNil(error);
            if (!context) return;
            user = context[@"user"];
            originalVersion = context[@"localVersion"];
            originalMarker = [NSData dataWithContentsOfURL:[user URLByAppendingPathComponent:@"active-user-generation"]];
            __block BOOL emitted = NO;
            MSIMEPreparedDictionarySnapshot *prepared = [DictionarySnapshotBridge
                prepareResources:context[@"resources"] userDirectory:user identifier:identifier
                contentIdentifier:context[@"contentIdentifier"] maximumRecords:1
                nextRecord:^NSDictionary *(NSError **failure) {
                    if (emitted) return nil;
                    emitted = YES;
                    return @{@"type": @"overlay", @"deleted": @NO,
                        @"data": @{@"kind": @"quick", @"code": @"activationfixture", @"word": @"合成应用验收",
                                   @"weight": @100000, @"user_inserted": @YES}};
                } error:&error];
            XCTAssertNotNil(prepared);
            XCTAssertNil(error);
            if (!prepared) return;
            MetasequoiaInputSessionBridge *other = [[MetasequoiaInputSessionBridge alloc] init];
            XCTAssertFalse([session activateDictionarySnapshot:prepared expectedVersion:originalVersion error:&error]);
            XCTAssertEqual(error.code, 423);
            other = nil;
            error = nil;
            XCTAssertFalse([session activateDictionarySnapshot:prepared expectedVersion:@"stale-version" error:&error]);
            XCTAssertEqual(error.code, 409);
            error = nil;
            XCTAssertTrue([session activateDictionarySnapshot:prepared expectedVersion:originalVersion error:&error]);
            XCTAssertNil(error);
            NSString *version = [session localDictionaryStateVersionWithError:&error];
            NSString *prefix = [NSString stringWithFormat:@"local-v1:%@:", identifier];
            XCTAssertTrue([version hasPrefix:prefix]);
            NSDictionary *page = [session personalEntriesAtOffset:0 error:&error];
            NSArray *entries = page[@"entries"];
            XCTAssertEqual(entries.count, 1u);
            XCTAssertEqualObjects(entries.firstObject[@"value"], @"合成应用验收");
            NSDictionary *newWord = @{@"kind": @"quickPhrase", @"key": @"afteractivation", @"value": @"应用后合成词条", @"weight": @100000};
            XCTAssertTrue([session applyPersonalPrevious:nil replacement:newWord requestID:NSUUID.UUID.UUIDString error:&error]);
            XCTAssertTrue([session activateDictionarySnapshot:prepared expectedVersion:originalVersion error:&error]);
            MetasequoiaInputSessionBridge *reopened = [[MetasequoiaInputSessionBridge alloc] init];
            NSDictionary *reopenedPage = [reopened personalEntriesAtOffset:0 error:&error];
            XCTAssertEqual([reopenedPage[@"entries"] count], 2u);
            XCTAssertNil(error);
        }
    }
    @finally
    {
        if (user)
        {
            // Restore the simulator's original pointer only after every test
            // session has released its lease; original journal files were untouched.
            NSURL *marker = [user URLByAppendingPathComponent:@"active-user-generation"];
            if (originalMarker) XCTAssertTrue([originalMarker writeToURL:marker atomically:YES]);
            else [manager removeItemAtURL:marker error:nil];
            NSURL *created = [[user URLByAppendingPathComponent:@"snapshot-generations"] URLByAppendingPathComponent:identifier];
            [manager removeItemAtURL:created error:nil];
            @autoreleasepool
            {
                MetasequoiaInputSessionBridge *restored = [[MetasequoiaInputSessionBridge alloc] init];
                XCTAssertEqualObjects([restored localDictionaryStateVersionWithError:nil], originalVersion);
            }
        }
    }
}
@end
