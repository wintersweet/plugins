//
//  NSDictionary+Lotus.h
//  Pods
//
//  Created by heew on 2021/3/25.
//
//

#import <Foundation/Foundation.h>

@interface NSDictionary (Lotus)


- (id _Nullable )safeObjectForKey:(NSString *_Nullable)aKey;

- (NSString *_Nullable)jsonString;

- (NSString *_Nullable)jsonOneLineString;

- (BOOL)containKey:(NSString *_Nullable)key;

#pragma mark - Dictionary Value Getter
///=============================================================================
/// @name Dictionary Value Getter
///=============================================================================

- (BOOL)boolValueForKey:(NSString *_Nullable)key default:(BOOL)def;

- (char)charValueForKey:(NSString *_Nullable)key default:(char)def;
- (unsigned char)unsignedCharValueForKey:(NSString *_Nullable)key default:(unsigned char)def;

- (short)shortValueForKey:(NSString *_Nullable)key default:(short)def;
- (unsigned short)unsignedShortValueForKey:(NSString *_Nullable)key default:(unsigned short)def;

- (int)intValueForKey:(NSString *_Nullable)key default:(int)def;
- (unsigned int)unsignedIntValueForKey:(NSString *_Nullable)key default:(unsigned int)def;

- (long)longValueForKey:(NSString *_Nullable)key default:(long)def;
- (unsigned long)unsignedLongValueForKey:(NSString *_Nullable)key default:(unsigned long)def;

- (long long)longLongValueForKey:(NSString *_Nullable)key default:(long long)def;
- (unsigned long long)unsignedLongLongValueForKey:(NSString *_Nullable)key default:(unsigned long long)def;

- (float)floatValueForKey:(NSString *_Nullable)key default:(float)def;
- (double)doubleValueForKey:(NSString *_Nullable)key default:(double)def;

- (NSInteger)integerValueForKey:(NSString *_Nullable)key default:(NSInteger)def;
- (NSUInteger)unsignedIntegerValueForKey:(NSString *_Nullable)key default:(NSUInteger)def;

- (nullable NSNumber *)numberValueForKey:(NSString *_Nullable)key default:(nullable NSNumber *)def;
- (nullable NSString *)stringValueForKey:(NSString *_Nullable)key default:(nullable NSString *)def;

@end
