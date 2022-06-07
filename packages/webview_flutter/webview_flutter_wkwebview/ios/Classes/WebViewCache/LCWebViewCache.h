//
//  LCWebViewCache.h
//  LCWebModule
//
//  Created by vonkia on 2021/6/06.
//

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LCWebViewCache : NSObject

/// 从池中获取一个WKWebView
+ (WKWebView *)getWKWebViewFromPool;

/// 缓存路径
+ (NSString *)getCacheDirectory;

/// 清除缓存
/// @param completionBlock 完成回调
+ (void)cleanDiskWithCompletionBlock:(void(^)(void))completionBlock;

@end

NS_ASSUME_NONNULL_END
