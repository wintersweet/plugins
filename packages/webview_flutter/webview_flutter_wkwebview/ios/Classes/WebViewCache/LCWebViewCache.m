//
//  LCWebViewCache.m
//  LCWebModule
//
//  Created by vonkia on 2021/3/28.
//

#import "LCWebViewCache.h"
#import <CommonCrypto/CommonDigest.h>
#import "ReactiveObjC.h"
#import "NSDictionary+Lotus.h"

static NSTimeInterval const kLCWebViewCacheMaxCacheAge = -604800; //过期时间: 一周
static NSUInteger const kLCWebViewCacheMaxCacheSize = 524288000; //缓存大小: 500M
static NSString * const kLCWebViewCacheDirectory = @"LCWebViewCache"; //缓存文件夹


//MARK: - WKWebView (LCWebViewCache)
@implementation WKWebView (LCWebViewCache)
+ (BOOL)handlesURLScheme:(NSString *)urlScheme {
    return NO;
}
@end


//MARK: - LCWebViewCacheReourceItem
@interface LCWebViewCacheReourceItem : NSObject
@property (nonatomic,strong) NSURLResponse *response;
@property (nonatomic,strong) NSData *data;
@property (nonatomic,strong) NSError *error;
@end
@implementation LCWebViewCacheReourceItem
@end


//MARK: - LCWebViewURLHandler
@interface LCWebViewURLHandler : NSObject <WKURLSchemeHandler>
@property (nonatomic, strong) NSMutableDictionary *taskVaildDic;
@property (nonatomic, strong) dispatch_queue_t serialQueue;
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *rootCachePath;
@end


@implementation LCWebViewURLHandler

- (instancetype)init {
    if (self = [super init]) {
        self.taskVaildDic = [NSMutableDictionary dictionary];
        self.serialQueue = dispatch_queue_create("lcweb_serial_queue", NULL);
        self.operationQueue = [[NSOperationQueue alloc] init];
        self.operationQueue.maxConcurrentOperationCount = 10;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:self.operationQueue];
        self.rootCachePath = [LCWebViewCache getCacheDirectory];
    }
    return self;
}

- (void)dealloc {
    [self.session invalidateAndCancel];
    self.session = nil;
}

- (NSString *)md5:(NSString *)string {
    const char* ptr = [string UTF8String];
    unsigned char md5Buffer[CC_MD5_DIGEST_LENGTH];
    // CC_MD5 之前
    CC_SHA1(ptr, (int)strlen(ptr), md5Buffer);
    NSMutableString* output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x",md5Buffer[i]];
    }
    return output;
}

- (NSData *)dataForRequestId:(NSString *)requestId {
    //load from disk
    NSString *cacheFilePath = [self filePathWithType:1 sessionID:requestId];
    return [NSData dataWithContentsOfFile:cacheFilePath];
}

- (NSDictionary *)responseHeadersWithRequestID:(NSString *)requestId {
    //load from disk
    NSString *responsePath = [self filePathWithType:0 sessionID:requestId];
    return [NSDictionary dictionaryWithContentsOfFile:responsePath];
}

- (void)finishRequestForRequest:(NSURLRequest *)request
                       response:(NSURLResponse *)response
                         result:(NSData *)result {
    //load from cache
    NSString *responseId = [self md5:request.URL.absoluteString]; //存请求的url
    NSHTTPURLResponse *httpRes = (NSHTTPURLResponse *)response;
    NSDictionary *responseHeaders = httpRes.allHeaderFields;
    if (responseHeaders) {
        NSString *responsePath = [self filePathWithType:0 sessionID:responseId];
        [responseHeaders writeToFile:responsePath atomically:YES];
    }
    if (result) {
        NSString *dataPath = [self filePathWithType:1 sessionID:responseId];
        [result writeToFile:dataPath atomically:YES];
    }
}

/// 缓存请求
/// @param type 0:responseHeaders, 1:responseData
/// @param sessionID 唯一id
- (NSString *)filePathWithType:(NSInteger)type sessionID:(NSString *)sessionID {
    NSString *cacheFileName = [sessionID stringByAppendingPathExtension:[@(type) stringValue]];
    return [self.rootCachePath stringByAppendingPathComponent:cacheFileName];
}

- (LCWebViewCacheReourceItem *)loadResource:(NSURLRequest *)request {
    //load from cache
    NSString *requestId = [self md5:request.URL.absoluteString];
    NSDictionary *responseHeaders = [self responseHeadersWithRequestID:requestId];
    if (responseHeaders) {
        LCWebViewCacheReourceItem *item = [[LCWebViewCacheReourceItem alloc] init];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:responseHeaders];
        item.response = resp;
        item.data = [self dataForRequestId:requestId];
        return item;
    } else {
        return nil;
    }
}

- (NSString *)getRequestCookieHeaderForURL:(NSURL *)URL {
    NSArray *cookieArray = [self searchAppropriateCookies:URL];
    if (cookieArray != nil && cookieArray.count > 0) {
        NSDictionary *cookieDic = [NSHTTPCookie requestHeaderFieldsWithCookies:cookieArray];
        if ([cookieDic objectForKey:@"Cookie"]) {
            return cookieDic[@"Cookie"];
        }
    }
    return nil;
}

- (NSArray *)searchAppropriateCookies:(NSURL *)URL {
    NSMutableArray *cookieArray = [NSMutableArray array];
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
        if ([URL.host containsString:cookie.domain]) {
            [cookieArray addObject:cookie];
        }
    }
    return cookieArray;
}

//MARK: WKURLSchemeHandler
- (void)webView:(WKWebView *)webView startURLSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask {
    dispatch_sync(self.serialQueue, ^{
        [self.taskVaildDic setValue:@(YES) forKey:urlSchemeTask.description];
    });
    
    //获取Cookie
    NSURLRequest *request = [urlSchemeTask request];
    NSMutableURLRequest *mutaRequest = [request mutableCopy];
    [mutaRequest setValue:[self getRequestCookieHeaderForURL:request.URL] forHTTPHeaderField:@"Cookie"];
    request = [mutaRequest copy];
    //判断是否缓存
    BOOL shouldCache = YES;
    if (request.HTTPMethod && ![request.HTTPMethod.uppercaseString isEqualToString:@"GET"]) {
        shouldCache = NO;
    }
    NSString *hasAjax = [request valueForHTTPHeaderField:@"X-Requested-With"];
    if (hasAjax != nil) {
        shouldCache = NO;
    }
    //获取缓存item
    LCWebViewCacheReourceItem *item = [self loadResource:request];
    NSDictionary *responseHeaders = [(NSHTTPURLResponse *)item.response allHeaderFields];
    NSString *contentType = responseHeaders[@"Content-Type"];
    if ([contentType isEqualToString:@"video/mp4"]) {
        shouldCache = NO;
    }
    
    // 获取网页内容有更改时关键字段
    NSDictionary *cachedHeaders = [[NSUserDefaults standardUserDefaults] objectForKey:mutaRequest.URL.absoluteString];
    //设置request headers (带上上次的请求头下面两参数一种就可以，也可以两个都带上)
    if (cachedHeaders) {
        NSString *etag = [cachedHeaders objectForKey:@"Etag"];
        if (etag) {
            [mutaRequest setValue:etag forHTTPHeaderField:@"If-None-Match"];
        }
        NSString *lastModified = [cachedHeaders objectForKey:@"Last-Modified"];
        if (lastModified) {
            [mutaRequest setValue:lastModified forHTTPHeaderField:@"If-Modified-Since"];
        }
    }
    // 请求是否需要刷新网页
    @weakify(self);
    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"httpResponse == %@", httpResponse);
        // 根据statusCode设置缓存策略
        if ((httpResponse.statusCode == 304 || httpResponse.statusCode == 0) && item && shouldCache) {
            [urlSchemeTask didReceiveResponse:item.response];
            if (item.data) {
                [urlSchemeTask didReceiveData:item.data];
            }
            [urlSchemeTask didFinish];
            [mutaRequest setCachePolicy:NSURLRequestReturnCacheDataElseLoad];
        } else {
            @strongify(self);
            if (![self.taskVaildDic boolValueForKey:urlSchemeTask.description default:NO] || !urlSchemeTask){
                return;
            }
            [urlSchemeTask didReceiveResponse:response];
            [urlSchemeTask didReceiveData:data];
            if (error) {
                [urlSchemeTask didFailWithError:error];
            } else {
                [urlSchemeTask didFinish];
                if (shouldCache) {
                    [self finishRequestForRequest:request response:response result:data];
                }
            }
            [mutaRequest setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
            // 保存当前的NSHTTPURLResponse
            [[NSUserDefaults standardUserDefaults] setObject:httpResponse.allHeaderFields forKey:mutaRequest.URL.absoluteString];
        }
    }];
    [dataTask resume];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask {
    dispatch_sync(self.serialQueue, ^{
         [self.taskVaildDic setValue:@(NO) forKey:urlSchemeTask.description];
    });
}
@end


//MARK: - LCWebViewCache
@interface LCWebViewCache ()
@property (nonatomic, assign) NSUInteger initialViewsMaxCount;
@property (nonatomic, strong) NSMutableArray <WKWebView *>*preloadedViews;
@end

@implementation LCWebViewCache
+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static LCWebViewCache *instance = nil;
    dispatch_once(&onceToken,^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (id)allocWithZone:(struct _NSZone *)zone{
    return [self sharedInstance];
}
 
- (instancetype)init {
    if (self = [super init]) {
        self.initialViewsMaxCount = 10;
        self.preloadedViews = [NSMutableArray arrayWithCapacity:self.initialViewsMaxCount];
        [self prepareWithCount:self.initialViewsMaxCount];
    }
    return self;
}

+ (void)initialize {
    [self cleanDiskWithCompletionBlock:^{
        NSLog(@"cleanDisk");
    }];
}

//MARK: Public
/// 从池中获取一个WKWebView
+ (WKWebView *)getWKWebViewFromPool {
    return [[self sharedInstance] getWKWebViewFromPool];
}

/// 缓存路径
+ (NSString *)getCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:kLCWebViewCacheDirectory];
    
    BOOL isDir = YES;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            return nil;
        }
    }
    return path;
}

/// 清除缓存
/// @param completionBlock 完成回调
+ (void)cleanDiskWithCompletionBlock:(void(^)(void))completionBlock {
    NSString *diskCachePath = [self getCacheDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 这两个变量主要是为了下面生成NSDirectoryEnumerator准备的
        // 一个是记录遍历的文件目录，一个是记录遍历需要预先获取文件的哪些属性
        NSURL *diskCacheURL = [NSURL fileURLWithPath:diskCachePath isDirectory:YES];
        NSArray *resourceKeys = @[NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];
        
        // 递归地遍历diskCachePath这个文件夹中的所有目录，此处不是直接使用diskCachePath，而是使用其生成的NSURL
        // 此处使用includingPropertiesForKeys:resourceKeys，这样每个file的resourceKeys对应的属性也会在遍历时预先获取到
        // NSDirectoryEnumerationSkipsHiddenFiles表示不遍历隐藏文件
        NSDirectoryEnumerator *fileEnumerator = [fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:resourceKeys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];
        // 获取文件的过期时间，SDWebImage中默认是一个星期
        // 不过这里虽然称*expirationDate为过期时间，但是实质上并不是这样。
        // 其实是这样的，比如在2015/12/12/00:00:00最后一次修改文件，对应的过期时间应该是
        // 2015/12/19/00:00:00，不过现在时间是2015/12/27/00:00:00，我先将当前时间减去1个星期，得到
        // 2015/12/20/00:00:00，这个时间才是我们函数中的expirationDate。
        // 用这个expirationDate和最后一次修改时间modificationDate比较看谁更晚就行。
        NSTimeInterval maxCacheAge = kLCWebViewCacheMaxCacheAge;
        NSUInteger maxCacheSize = kLCWebViewCacheMaxCacheSize;
        
        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:maxCacheAge];
        // 用来存储对应文件的一些属性，比如文件所需磁盘空间
        NSMutableDictionary *cacheFiles = [NSMutableDictionary dictionary];
        // 记录当前已经使用的磁盘缓存大小
        NSUInteger currentCacheSize = 0;

        // 在缓存的目录开始遍历文件.  此次遍历有两个目的:
        //  1. 移除过期的文件
        //  2. 同时存储每个文件的属性（比如该file是否是文件夹、该file所需磁盘大小，修改时间）
        NSMutableArray *urlsToDelete = [[NSMutableArray alloc] init];
        for (NSURL *fileURL in fileEnumerator) {
            NSDictionary *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:NULL];
            // 当前扫描的是目录，就跳过
            if ([resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }
            // 移除过期文件
            // 这里判断过期的方式：对比文件的最后一次修改日期和expirationDate谁更晚，如果expirationDate更晚，就认为该文件已经过期，具体解释见上面
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                [urlsToDelete addObject:fileURL];
                continue;
            }
            // 计算当前已经使用的cache大小，
            // 并将对应file的属性存到cacheFiles中
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += [totalAllocatedSize unsignedIntegerValue];
            [cacheFiles setObject:resourceValues forKey:fileURL];
        }
        
        for (NSURL *fileURL in urlsToDelete) {
            // 根据需要移除文件的url来移除对应file
            [fileManager removeItemAtURL:fileURL error:nil];
        }
        // 如果我们当前cache的大小已经超过了允许配置的缓存大小，那就删除已经缓存的文件。
        // 删除策略就是，首先删除修改时间更早的缓存文件
        if (maxCacheSize > 0 && currentCacheSize > maxCacheSize) {
            // 直接将当前cache大小降到允许最大的cache大小的一般
            const NSUInteger desiredCacheSize = maxCacheSize / 2;
            // 根据文件修改时间来给所有缓存文件排序，按照修改时间越早越在前的规则排序
            NSArray *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                            usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
                                                            }];
            // 每次删除file后，就计算此时的cache的大小
            // 如果此时的cache大小已经降到期望的大小了，就停止删除文件了
            for (NSURL *fileURL in sortedFiles) {
                if ([fileManager removeItemAtURL:fileURL error:nil]) {
                    // 获取该文件对应的属性
                    NSDictionary *resourceValues = cacheFiles[fileURL];
                    // 根据resourceValues获取该文件所需磁盘空间大小
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    // 计算当前cache大小
                    currentCacheSize -= [totalAllocatedSize unsignedIntegerValue];
                    if (currentCacheSize < desiredCacheSize) {
                        break;
                    }
                }
            }
        }
        // 如果有completionBlock，就在主线程中调用
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock();
            });
        }
    });
}


//MARK: Private
/// 预初始化若干WKWebView
/// @param count 个数
- (void)prepareWithCount:(NSUInteger)count {
    // Actually does nothing, only initialization must be called.
    while (self.preloadedViews.count < MIN(count,self.initialViewsMaxCount)) {
        id preloadedView = [self createPreloadedView];
        if (preloadedView) {
            [self.preloadedViews addObject:preloadedView];
        } else {
            break;
        }
    }
}

/// 从池中获取一个WKWebView
- (WKWebView *)getWKWebViewFromPool {
    if (!self.preloadedViews.count) {
        return [self createPreloadedView];
    } else {
        id preloadedView = self.preloadedViews.firstObject;
        [self.preloadedViews removeObject:preloadedView];
        return preloadedView;
    }
}

/// 创建一个WKWebView
- (WKWebView *)createPreloadedView {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.preferences.javaScriptEnabled = YES;
    configuration.suppressesIncrementalRendering = YES; // 是否支持记忆读取
    [configuration.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];//支持跨域
    [configuration setURLSchemeHandler:[LCWebViewURLHandler new] forURLScheme:@"https"];
    [configuration setURLSchemeHandler:[LCWebViewURLHandler new] forURLScheme:@"http"];
    
#ifndef POD_CONFIGURATION_RELEASE
    [self setupVConsoleEnabled:configuration]; //显示vConsole
#endif
    
    WKWebView *wkWebView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    wkWebView.allowsBackForwardNavigationGestures = YES; // 是否允许手势左滑返回上一级, 类似导航控制的左滑返回
    wkWebView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    return wkWebView;
}

/// 用于进行JavaScript注入
/// @param configuration 配置
- (void)setupVConsoleEnabled:(WKWebViewConfiguration *)configuration {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"LCWebModule" ofType:@"bundle"];
    NSString *vConsolePath = [path stringByAppendingPathComponent:@"vconsole.min.js"];
    NSString *vConsoleStr = [NSString stringWithContentsOfFile:vConsolePath encoding:NSUTF8StringEncoding error:nil];
    NSString *jsErrorPath = [path stringByAppendingPathComponent:@"jserror.js"];
    NSString *jsErrorStr = [NSString stringWithContentsOfFile:jsErrorPath encoding:NSUTF8StringEncoding error:nil];
    if (vConsoleStr && jsErrorStr) {
        NSString *jsStr = [vConsoleStr stringByAppendingString:jsErrorStr];
        WKUserScript *wkUScript = [[WKUserScript alloc] initWithSource:jsStr injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
        [configuration.userContentController addUserScript:wkUScript];
    }
}
@end
