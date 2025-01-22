#import <XCTest/XCTest.h>
#import "VydiaRNFileUploader.h"

@interface VydiaRNFileUploaderTests : XCTestCase

@property (nonatomic, strong) VydiaRNFileUploader *fileUploader;

@end

@implementation VydiaRNFileUploaderTests

- (void)setUp {
    [super setUp];
    self.fileUploader = [[VydiaRNFileUploader alloc] init];
}

- (void)tearDown {
    self.fileUploader = nil;
    [super tearDown];
}

- (void)testGetFileInfo {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Get file info"];
    
    NSString *path = @"file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/trim.A5F76017-14E9-4890-907E-36A045AF9436.MOV";
    
    [self.fileUploader getFileInfo:path resolve:^(NSDictionary *fileInfo) {
        XCTAssertNotNil(fileInfo);
        XCTAssertEqualObjects(fileInfo[@"name"], @"trim.AF9A9225-FC37-416B-A25B-4EDB8275A625.MOV");
        XCTAssertEqualObjects(fileInfo[@"extension"], @"MOV");
        XCTAssertTrue([fileInfo[@"exists"] boolValue]);
        XCTAssertEqualObjects(fileInfo[@"mimeType"], @"video/quicktime");
        XCTAssertNotNil(fileInfo[@"size"]);
        
        [expectation fulfill];
    } reject:^(NSString *code, NSString *message, NSError *error) {
        XCTFail(@"Failed to get file info: %@", error.localizedDescription);
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testStartUpload {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Start upload"];
    
    NSDictionary *options = @{
        @"url": @"https://example.com/upload",
        @"path": @"file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/trim.A5F76017-14E9-4890-907E-36A045AF9436.MOV",
        @"method": @"POST",
        @"type": @"raw",
        @"field": @"file",
        @"customUploadId": @"12345",
        @"appGroup": @"com.example.app",
        @"headers": @{
            @"Authorization": @"Bearer token123"
        },
        @"parameters": @{
            @"param1": @"value1",
            @"param2": @"value2"
        },
        @"parts": @[
            @{
                @"path": @"file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/part1.txt",
                @"name": @"part1.txt",
                @"type": @"text/plain"
            },
            @{
                @"path": @"file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/part2.txt",
                @"name": @"part2.txt",
                @"type": @"text/plain"
            }
        ],
        @"partsOrder": @{
            @"0": @"part1.txt",
            @"1": @"part2.txt"
        }
    };
    
    [self.fileUploader startUpload:options resolve:^(NSString *uploadId) {
        XCTAssertNotNil(uploadId);
        XCTAssertEqualObjects(uploadId, @"12345");
        
        [expectation fulfill];
    } reject:^(NSString *code, NSString *message, NSError *error) {
        XCTFail(@"Failed to start upload: %@", error.localizedDescription);
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testNormalizePartsFromAssetLibrary {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Normalize parts from asset library"];
    
    NSArray *parts = @[
        @{
            @"path": @"assets-library://asset/asset.mov?id=123456789&ext=mov",
            @"name": @"asset.mov",
            @"type": @"video/quicktime"
        },
        @{
            @"path": @"file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/part1.txt",
            @"name": @"part1.txt",
            @"type": @"text/plain"
        }
    ];
    
    NSArray *expectedResult = @[
        @{
            @"path": @"file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/tempFileUrl.mov",
            @"name": @"asset.mov",
            @"type": @"video/quicktime"
        },
        @{
            @"path": @"file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/part1.txt",
            @"name": @"part1.txt",
            @"type": @"text/plain"
        }
    ];
    
    [self.fileUploader normalizePartsFromAssetLibrary:parts reject:^(NSString *code, NSString *message, NSError *error) {
        XCTFail(@"Failed to normalize parts from asset library: %@", error.localizedDescription);
    }];
    
    XCTAssertEqualObjects(parts, expectedResult);
    
    [expectation fulfill];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

}

- (void)testCopyAssetToFile {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Copy asset to file"];
    
    NSString *assetUrl = @"assets-library://asset/asset.mov?id=123456789&ext=mov";
    
    [self.fileUploader copyAssetToFile:assetUrl completionHandler:^(NSString *tempFileUrl, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(tempFileUrl);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

}

- (void)testCreateBodyWithBoundary {
    // Prepare test data
    NSString *boundary = @"TestBoundary";
    NSDictionary *parameters = @{
        @"param1": @"value1",
        @"param2": @"value2"
    };
    NSArray *parts = @[
        @{
            @"path": @"file:///path/to/file1.txt",
            @"field": @"file",
        },
        @{
            @"path": @"file:///path/to/file2.txt",
            @"field": @"file",
        }
    ];
    NSDictionary *partsOrder = @{
        @"0": @"file1.txt",
        @"1": @"file2.txt"
    };
    
    // Expected result
    NSMutableData *expectedResult = [NSMutableData data];
    
    // Add parts as dictated by `partsOrder` to the request body
    [expectedResult appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", @"file1.txt"] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"%@\r\n", @"value1"] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [expectedResult appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", @"file2.txt"] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"%@\r\n", @"value2"] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Put each part in its own part, delimited by the boundary
    [expectedResult appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", @"file", @"file1.txt"] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", @"text/plain"] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[NSData data]];
    [expectedResult appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    [expectedResult appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", @"file", @"file2.txt"] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", @"text/plain"] dataUsingEncoding:NSUTF8StringEncoding]];
    [expectedResult appendData:[NSData data]];
    [expectedResult appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Write a boundary to conclude the request body
    [expectedResult appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Call the method under test
    NSData *result = [self.fileUploader createBodyWithBoundary:boundary parameters:parameters parts:parts order:partsOrder];
    
    // Assert the result
    XCTAssertEqualObjects(result, expectedResult);
}

- (void)testUrlSession {
    // Prepare test data
    NSString *groupId = @"com.example.app";
    
    // Create an instance of VydiaRNFileUploader
    VydiaRNFileUploader *fileUploader = [[VydiaRNFileUploader alloc] init];
    
    // Call the method under test
    NSURLSession *urlSession = [fileUploader urlSession:groupId];
    
    // Assert the result
    XCTAssertNotNil(urlSession);
    XCTAssertEqualObjects(urlSession.configuration.identifier, BACKGROUND_SESSION_ID);
    XCTAssertEqualObjects(urlSession.configuration.sharedContainerIdentifier, groupId);
    XCTAssertEqual(urlSession.configuration.allowsCellularAccess, !limitNetwork);
}
@end
