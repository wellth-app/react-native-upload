#import <Foundation/Foundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTBridgeModule.h>
#import <Photos/Photos.h>

#import "VydiaRNFileUploader.h"

@implementation VydiaRNFileUploader

RCT_EXPORT_MODULE();

@synthesize bridge = _bridge;
static VydiaRNFileUploader* staticInstance = nil;
static NSString *BACKGROUND_SESSION_ID = @"ReactNativeBackgroundUpload";
NSMutableDictionary *_responsesData;
NSURLSession *_urlSession = nil;
void (^backgroundSessionCompletionHandler)(void) = nil;
BOOL limitNetwork = NO;

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (dispatch_queue_t)methodQueue
 {
   return dispatch_get_main_queue();
 }

-(id) init {
    self = [super init];
    if (self) {
        staticInstance = self;
        _responsesData = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)_sendEventWithName:(NSString *)eventName body:(id)body {
    if (staticInstance == nil) return;
    [staticInstance sendEventWithName:eventName body:body];
}

- (NSArray<NSString *> *)supportedEvents {
    return @[
        @"RNFileUploader-progress",
        @"RNFileUploader-error",
        @"RNFileUploader-cancelled",
        @"RNFileUploader-completed"
    ];
}

- (void)startObserving {
    // JS side is ready to receive events; create the background url session if necessary
    // iOS will then deliver the tasks completed while the app was dead (if any)
    NSString *appGroup = nil;
    double delayInSeconds = 5;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self urlSession:appGroup];
    });
}

+ (void)setCompletionHandlerWithIdentifier: (NSString *)identifier completionHandler: (void (^)())completionHandler {
    if ([BACKGROUND_SESSION_ID isEqualToString:identifier]) {
        backgroundSessionCompletionHandler = completionHandler;
    }
}

/*
 Gets file information for the path specified.  Example valid path is: file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/trim.A5F76017-14E9-4890-907E-36A045AF9436.MOV
 Returns an object such as: {mimeType: "video/quicktime", size: 2569900, exists: true, name: "trim.AF9A9225-FC37-416B-A25B-4EDB8275A625.MOV", extension: "MOV"}
 */
RCT_EXPORT_METHOD(getFileInfo:(NSString *)path resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    @try {
        // Escape non latin characters in filename
        NSString *escapedPath = [path stringByAddingPercentEncodingWithAllowedCharacters: NSCharacterSet.URLQueryAllowedCharacterSet];
       
        NSURL *fileUri = [NSURL URLWithString:escapedPath];
        NSString *pathWithoutProtocol = [fileUri path];
        NSString *name = [fileUri lastPathComponent];
        NSString *extension = [name pathExtension];
        bool exists = [[NSFileManager defaultManager] fileExistsAtPath:pathWithoutProtocol];
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys: name, @"name", nil];
        [params setObject:extension forKey:@"extension"];
        [params setObject:[NSNumber numberWithBool:exists] forKey:@"exists"];

        if (exists)
        {
            [params setObject:[self guessMIMETypeFromFileName:name] forKey:@"mimeType"];
            NSError* error;
            NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:pathWithoutProtocol error:&error];
            if (error == nil)
            {
                unsigned long long fileSize = [attributes fileSize];
                [params setObject:[NSNumber numberWithLong:fileSize] forKey:@"size"];
            }
        }
        resolve(params);
    }
    @catch (NSException *exception) {
        reject(@"RN Uploader", exception.name, nil);
    }
}

/*
 Borrowed from http://stackoverflow.com/questions/2439020/wheres-the-iphone-mime-type-database
*/
- (NSString *)guessMIMETypeFromFileName: (NSString *)fileName {
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[fileName pathExtension], NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    
    if (UTI) {
        CFRelease(UTI);
    }
  
    if (!MIMEType) {
        return @"application/octet-stream";
    }
    return (__bridge NSString *)(MIMEType);
}

/*
 Utility method to copy a PHAsset file into a local temp file, which can then be uploaded.
 */
- (void)copyAssetToFile: (NSString *)assetUrl completionHandler: (void(^)(NSString *__nullable tempFileUrl, NSError *__nullable error))completionHandler {
    NSURL *url = [NSURL URLWithString:assetUrl];
    PHAsset *asset = [PHAsset fetchAssetsWithALAssetURLs:@[url] options:nil].lastObject;
    if (!asset) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:@"Asset could not be fetched.  Are you missing permissions?" forKey:NSLocalizedDescriptionKey];
        completionHandler(nil,  [NSError errorWithDomain:@"RNUploader" code:5 userInfo:details]);
        return;
    }
    PHAssetResource *assetResource = [[PHAssetResource assetResourcesForAsset:asset] firstObject];
    NSString *pathToWrite = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSURL *pathUrl = [NSURL fileURLWithPath:pathToWrite];
    NSString *fileURI = pathUrl.absoluteString;

    PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
    options.networkAccessAllowed = YES;

    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:assetResource toFile:pathUrl options:options completionHandler:^(NSError * _Nullable e) {
        if (e == nil) {
            completionHandler(fileURI, nil);
        }
        else {
            completionHandler(nil, e);
        }
    }];
}

/*
 * Starts a file upload.
 * Options are passed in as the first argument as a js hash:
 * {
 *   url: string.  url to post to.
 *   path: string.  path to the file on the device
 *   headers: hash of name/value header pairs
 * }
 *
 * Returns a promise with the string ID of the upload.
 */
RCT_EXPORT_METHOD(startUpload:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    NSString *uploadUrl = options[@"url"];
    __block NSString *fileURI = options[@"path"];
    NSString *method = options[@"method"] ?: @"POST";
    NSString *uploadType = options[@"type"] ?: @"raw";
    NSString *fieldName = options[@"field"];
    NSString *customUploadId = options[@"customUploadId"];
    NSString *appGroup = options[@"appGroup"];
    NSDictionary *headers = options[@"headers"];
    NSDictionary *parameters = options[@"parameters"];

    @try {
        NSURL *requestUrl = [NSURL URLWithString: uploadUrl];
        if (requestUrl == nil) {
            return reject(@"RN Uploader", @"URL not compliant with RFC 2396", nil);
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl];
        [request setHTTPMethod: method];

        [headers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull val, BOOL * _Nonnull stop) {
            if ([val respondsToSelector:@selector(stringValue)]) {
                val = [val stringValue];
            }
            if ([val isKindOfClass:[NSString class]]) {
                [request setValue:val forHTTPHeaderField:key];
            }
        }];


        // asset library files have to be copied over to a temp file.  they can't be uploaded directly
        if ([fileURI hasPrefix:@"assets-library"]) {
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_enter(group);
            [self copyAssetToFile:fileURI completionHandler:^(NSString * _Nullable tempFileUrl, NSError * _Nullable error) {
                if (error) {
                    dispatch_group_leave(group);
                    reject(@"RN Uploader", @"Asset could not be copied to temp file.", nil);
                    return;
                }
                fileURI = tempFileUrl;
                dispatch_group_leave(group);
            }];
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        }

        NSString *uploadId = customUploadId ? customUploadId : [[NSUUID UUID] UUIDString];
        NSURLSessionUploadTask *uploadTask;

        if ([uploadType isEqualToString:@"multipart"]) {
            NSString *uuidStr = [[NSUUID UUID] UUIDString];
            [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", uuidStr] forHTTPHeaderField:@"Content-Type"];

            NSData *multipartData = [self createBodyWithBoundary:uuidStr path:fileURI parameters: parameters fieldName:fieldName];
            
            NSURL *multipartDataFileUrl = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", [self getTmpDirectory], uploadId]];
            [multipartData writeToURL:multipartDataFileUrl atomically:YES];

            uploadTask = [[self urlSession: appGroup] uploadTaskWithRequest:request fromFile:multipartDataFileUrl];
        } else {
            if (parameters.count > 0) {
                reject(@"RN Uploader", @"Parameters supported only in multipart type", nil);
                return;
            }

            uploadTask = [[self urlSession: appGroup] uploadTaskWithRequest:request fromFile:[NSURL URLWithString: fileURI]];
        }

        uploadTask.taskDescription = uploadId;

        [uploadTask resume];
        resolve(uploadTask.taskDescription);
    }
    @catch (NSException *exception) {
        reject(@"RN Uploader", exception.name, nil);
    }
}

/*
 * Cancels file upload
 * Accepts upload ID as a first argument, this upload will be cancelled
 * Event "cancelled" will be fired when upload is cancelled.
 */
RCT_EXPORT_METHOD(cancelUpload: (NSString *)cancelUploadId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
    [_urlSession getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        for (NSURLSessionTask *uploadTask in uploadTasks) {
            if ([uploadTask.taskDescription isEqualToString:cancelUploadId]){
                // == checks if references are equal, while isEqualToString checks the string value
                [uploadTask cancel];
            }
        }
    }];
    resolve([NSNumber numberWithBool:YES]);
}

RCT_EXPORT_METHOD(canSuspendIfBackground) {
    if (backgroundSessionCompletionHandler) {
        backgroundSessionCompletionHandler();
        backgroundSessionCompletionHandler = nil;
    }
}

RCT_EXPORT_METHOD(shouldLimitNetwork: (BOOL) limit) {
    limitNetwork = limit;
}

RCT_EXPORT_METHOD(getAllUploads:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    NSString *appGroup = nil;
    [[self urlSession: appGroup] getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        NSMutableArray *uploads = [NSMutableArray new];
        for (NSURLSessionUploadTask *uploadTask in uploadTasks) {
            NSString *state;
            switch (uploadTask.state) {
            case NSURLSessionTaskStateRunning:
                state = @"running";
                break;
            case NSURLSessionTaskStateSuspended:
                state = @"pending";
                break;
            case NSURLSessionTaskStateCanceling:
                state = @"cancelled";
                break;
            case NSURLSessionTaskStateCompleted:
                state = @"completed";
                break;
            }
            
            NSDictionary *upload = @{
                @"id" : uploadTask.taskDescription,
                @"state" : state
            };
            [uploads addObject:upload];
        }
        resolve(uploads);
    }];
}

- (NSData *)createBodyWithBoundary:(NSString *)boundary
            path:(NSString *)path
            parameters:(NSDictionary *)parameters
            fieldName:(NSString *)fieldName {

    NSMutableData *httpBody = [NSMutableData data];

    // Escape non latin characters in filename
    NSString *escapedPath = [path stringByAddingPercentEncodingWithAllowedCharacters: NSCharacterSet.URLQueryAllowedCharacterSet];

    // resolve path
    NSURL *fileUri = [NSURL URLWithString: escapedPath];
    
    NSError* error = nil;
    NSData *data = [NSData dataWithContentsOfURL:fileUri options:NSDataReadingMappedAlways error: &error];

    if (data == nil) {
        NSLog(@"Failed to read file %@", error);
    }

    NSString *filename  = [path lastPathComponent];
    NSString *mimetype  = [self guessMIMETypeFromFileName:path];

    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *parameterKey, NSString *parameterValue, BOOL *stop) {
        [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", parameterKey] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"%@\r\n", parameterValue] dataUsingEncoding:NSUTF8StringEncoding]];
    }];

    [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fieldName, filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", mimetype] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:data];
    [httpBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    [httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    return httpBody;
}

- (NSURLSession *)urlSession: (NSString *) groupId {
    if (_urlSession == nil) {
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:BACKGROUND_SESSION_ID];
        if (groupId != nil && ![groupId isEqualToString:@""]) {
            sessionConfiguration.sharedContainerIdentifier = groupId;
        }
        if (limitNetwork) {
            sessionConfiguration.allowsCellularAccess = NO;
        }
        _urlSession = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:nil];
    }

    return _urlSession;
}

- (NSString *)getTmpDirectory {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *namespace = @"react-native-upload";
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingString:namespace];
    
    [manager createDirectoryAtPath: tmpPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    return tmpPath;
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithObjectsAndKeys:task.taskDescription, @"id", nil];
    NSURLSessionDataTask *uploadTask = (NSURLSessionDataTask *)task;
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)uploadTask.response;
    if (response != nil)
    {
        [data setObject:[NSNumber numberWithInteger:response.statusCode] forKey:@"responseCode"];
    }
    //Add data that was collected earlier by the didReceiveData method
    NSMutableData *responseData = _responsesData[@(task.taskIdentifier)];
    if (responseData) {
        [_responsesData removeObjectForKey:@(task.taskIdentifier)];
        NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        [data setObject:response forKey:@"responseBody"];
    } else {
        [data setObject:[NSNull null] forKey:@"responseBody"];
    }

    if (error == nil)
    {
        [self _sendEventWithName:@"RNFileUploader-completed" body:data];
    }
    else
    {
        [data setObject:error.localizedDescription forKey:@"error"];
        if (error.code == NSURLErrorCancelled) {
            [self _sendEventWithName:@"RNFileUploader-cancelled" body:data];
        } else {
            [self _sendEventWithName:@"RNFileUploader-error" body:data];
        }
    }

    NSURL *multipartDataFileUrl = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", [self getTmpDirectory], task.taskDescription]];
    [[NSFileManager defaultManager] removeItemAtURL:multipartDataFileUrl error:nil];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    float progress = -1;
    if (totalBytesExpectedToSend > 0) //see documentation.  For unknown size it's -1 (NSURLSessionTransferSizeUnknown)
    {
        progress = 100.0 * (float)totalBytesSent / (float)totalBytesExpectedToSend;
    }
    [self _sendEventWithName:@"RNFileUploader-progress" body:@{ @"id": task.taskDescription, @"progress": [NSNumber numberWithFloat:progress] }];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (!data.length) {
        return;
    }
    //Hold returned data so it can be picked up by the didCompleteWithError method later
    NSMutableData *responseData = _responsesData[@(dataTask.taskIdentifier)];
    if (!responseData) {
        responseData = [NSMutableData dataWithData:data];
        _responsesData[@(dataTask.taskIdentifier)] = responseData;
    } else {
        [responseData appendData:data];
    }
}

#pragma mark - NSURLSessionDelegate

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    if (backgroundSessionCompletionHandler) {
        NSLog(@"RNBU Did Finish Events For Background URLSession (has backgroundSessionCompletionHandler)");
        // This long delay is set as a security if the JS side does not call :canSuspendIfBackground: promptly
        double delayInSeconds = 45.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            if (backgroundSessionCompletionHandler) {
                backgroundSessionCompletionHandler();
                NSLog(@"RNBU did call backgroundSessionCompletionHandler (timeout)");
                backgroundSessionCompletionHandler = nil;
            }
        });
    } else {
        NSLog(@"RNBU Did Finish Events For Background URLSession (no backgroundSessionCompletionHandler)");
    }
}

@end
