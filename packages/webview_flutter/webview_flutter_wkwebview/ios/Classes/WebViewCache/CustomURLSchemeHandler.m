
#import "CustomURLSchemeHandler.h"
//#import <SDWebImageManager.h>
#import <MobileCoreServices/MobileCoreServices.h>

#define  kWKWebViewReuseScheme  @"fuse"

@interface CustomURLSchemeHandler()

@property (nonatomic,strong)NSString *replacedStr;

@property (nonatomic,strong)NSMutableDictionary *taskVaildDic;

@property(nonatomic,assign)NSTimeInterval start;

@property (nonatomic,strong) dispatch_queue_t serialQueue;
@end

@implementation CustomURLSchemeHandler


- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask API_AVAILABLE(ios(12.0)){
    
    if(!self.serialQueue){
        self.serialQueue = dispatch_queue_create("wkserial", DISPATCH_QUEUE_SERIAL);
    }
    NSString* scheme = urlSchemeTask.request.URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"bltest"]) {
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"index.js" ofType:nil];
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:urlSchemeTask.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type" : @"text/plain"}];
        [urlSchemeTask didReceiveResponse:response];
        [urlSchemeTask didReceiveData:data];
        [urlSchemeTask didFinish];
    }
    
//    return;

        dispatch_sync(self.serialQueue, ^{
            [_taskVaildDic setValue:@(YES) forKey:urlSchemeTask.description];
        });
        [_taskVaildDic setValue:@(YES) forKey:urlSchemeTask.description];
        NSDictionary *headers = urlSchemeTask.request.allHTTPHeaderFields;
        NSString *accept = headers[@"Accept"];
        
        //当前的requestUrl的scheme都是customScheme
        NSString *requestUrl = urlSchemeTask.request.URL.absoluteString;
        NSString *fileName = [[requestUrl componentsSeparatedByString:@"?"].firstObject componentsSeparatedByString:@"ui-h5/"].lastObject;
        NSString *replacedStr = [requestUrl stringByReplacingOccurrencesOfString:kWKWebViewReuseScheme withString:@"https"];
        self.replacedStr = replacedStr;
        //Intercept and load local resources.
        if ((accept.length >= @"text".length && [accept rangeOfString:@"text/html"].location != NSNotFound)) {
            //html 拦截
            [self loadLocalFile:fileName urlSchemeTask:urlSchemeTask];
        } else if ([self isMatchingRegularExpressionPattern:@"\\.(js|css)" text:requestUrl]) {
            //js、css
            [self loadLocalFile:fileName urlSchemeTask:urlSchemeTask];
        } else if (accept.length >= @"image".length && [accept rangeOfString:@"image"].location != NSNotFound) {
         //image
//          NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:[NSURL URLWithString:replacedStr]];
            
//          [[SDWebImageManager sharedManager].imageCache queryCacheOperationForKey:key done:^(UIImage * _Nullable image, NSData * _Nullable data, SDImageCacheType cacheType) {
//                        if (image) {
//                            NSData *imgData = UIImageJPEGRepresentation(image, 1);
//                            NSString *mimeType = [self getMIMETypeWithCAPIAtFilePath:fileName] ?: @"image/jpeg";
//                            [self resendRequestWithUrlSchemeTask:urlSchemeTask mimeType:mimeType requestData:imgData];
//                        } else {
//                            [self loadLocalFile:fileName urlSchemeTask:urlSchemeTask];
//                        }
//                    }];
            
           
        } else {
            //return an empty json.
            NSData *data = [NSJSONSerialization dataWithJSONObject:@{ } options:NSJSONWritingPrettyPrinted error:nil];
            [self resendRequestWithUrlSchemeTask:urlSchemeTask mimeType:@"text/html" requestData:data];
        }

}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    
    
}


-(BOOL)isMatchingRegularExpressionPattern:(NSString *)pattern text:(NSString *)text{
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    NSTextCheckingResult *result = [regex firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
//    return MHObjectIsNil(result)?NO:YES;
    if (result == nil){
        return NO;
    }else{
        return YES;
    }
}

//Load local resources, eg: html、js、css...
- (void)loadLocalFile:(NSString *)fileName urlSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask API_AVAILABLE(ios(11.0)){
    
//  if(![self->_taskVaildDic boolValueForKey:urlSchemeTask.description default:NO] || !urlSchemeTask || fileName.length == 0){
//      return;
//  }
    id value =  [self->_taskVaildDic valueForKey:urlSchemeTask.description];
    if(value == nil|| !urlSchemeTask){
        return;
    }
  NSString * docsdir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
  NSString * H5FilePath = [[docsdir stringByAppendingPathComponent:@"H5"] stringByAppendingPathComponent:@"h5"];
  //If the resource do not exist, re-send request by replacing to http(s).
  NSString *filePath = [H5FilePath stringByAppendingPathComponent:fileName];
  
  if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
      NSLog(@"开始重新发送网络请求");
      if ([self.replacedStr hasPrefix:kWKWebViewReuseScheme]) {

          self.replacedStr =[self.replacedStr stringByReplacingOccurrencesOfString:kWKWebViewReuseScheme withString:@"https"];
                  
          NSLog(@"请求地址:%@",self.replacedStr);
          
      }
  
//      self.replacedStr = [NSString stringWithFormat:@"%@?%@",self.replacedStr,[SAMKeychain h5Version]?:@""];
      self.replacedStr = [NSString stringWithFormat:@"%@?%@",self.replacedStr,@""];

      _start = CACurrentMediaTime();//开始加载时间
      NSLog(@"web请求开始地址:%@",self.replacedStr);
      
//      @weakify(self);
      __weak typeof(self)weakSelf = self;

      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.replacedStr]];
      NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
      NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
//          @strongify(self);
          __strong typeof(weakSelf)strongSelf = weakSelf;
          id value =  [strongSelf.taskVaildDic valueForKey:urlSchemeTask.description];
          if(value == nil|| !urlSchemeTask){
              return;
          }
//          if([self->_taskVaildDic boolValueForKey:urlSchemeTask.description default:NO] == NO || !urlSchemeTask){
//              return;
//          }
         
          
          [urlSchemeTask didReceiveResponse:response];
          [urlSchemeTask didReceiveData:data];
          if (error) {
              [urlSchemeTask didFailWithError:error];
          } else {
              NSTimeInterval delta = CACurrentMediaTime() - self->_start;
              NSLog(@"=======web请求结束地址%@：：：%f", self.replacedStr, delta);
              [urlSchemeTask didFinish];
          }
      }];
      [dataTask resume];
      [session finishTasksAndInvalidate];
  } else {
      NSLog(@"filePath:%@",filePath);
      id value =  [self->_taskVaildDic valueForKey:urlSchemeTask.description];
      if(value == nil|| !urlSchemeTask){
          return;
      }
//      if(![self->_taskVaildDic boolValueForKey:urlSchemeTask.description default:NO] || !urlSchemeTask || fileName.length == 0){
//          NSLog(@"return");
//          return;
//      }
      
      NSData *data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:nil];
      [self resendRequestWithUrlSchemeTask:urlSchemeTask mimeType:[self getMIMETypeWithCAPIAtFilePath:filePath] requestData:data];
  }
}




- (void)resendRequestWithUrlSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask
                              mimeType:(NSString *)mimeType
                           requestData:(NSData *)requestData  API_AVAILABLE(ios(11.0)) {
//    if(![self->_taskVaildDic boolValueForKey:urlSchemeTask.description default:NO] || !urlSchemeTask|| !urlSchemeTask.request || !urlSchemeTask.request.URL){
//        return;
//    }
    id value =  [self->_taskVaildDic valueForKey:urlSchemeTask.description];
    if(value == nil|| !urlSchemeTask){
        return;
    }
    NSString *mimeType_local = mimeType ? mimeType : @"text/html";
    NSData *data = requestData ? requestData : [NSData data];
    NSURLResponse *response = [[NSURLResponse alloc] initWithURL:urlSchemeTask.request.URL
                                                        MIMEType:mimeType_local
                                           expectedContentLength:data.length
                                                textEncodingName:nil];
    [urlSchemeTask didReceiveResponse:response];
    [urlSchemeTask didReceiveData:data];
    [urlSchemeTask didFinish];
}
-(NSString*)getMIMETypeWithCAPIAtFilePath:(NSString*)path{
    
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[path pathExtension], NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    if (!MIMEType) {
        return @"application/octet-stream";
    }
    return (__bridge NSString *)(MIMEType);
}

@end
