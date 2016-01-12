// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OBObject : NSObject
@end


@class NSDictionary, NSMutableDictionary;

@interface NSObject (OBDebuggingExtensions)
- (NSMutableDictionary *)debugDictionary;
- (NSString *)shortDescription;

#ifdef DEBUG

// Runtime introspection
- (NSString *)ivars; // "po [value ivars]" to get a runtime dump of ivars
- (NSString *)methods; // "po [value methods]" to get a runtime dump of methods
+ (NSString *)instanceMethods;
+ (NSString *)classMethods;
+ (NSString *)protocols;
+ (NSArray *)subclasses;

// Leak/retain cycle warnings
- (void)expectDeallocationSoon;

#endif

@end

@interface OBObject (OBDebugging)
- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(NSUInteger)level;
- (NSString *)description;
@end

// CF callback for -shortDescription (here instead of in OFCFCallbacks since this is where -shortDescription gets defined).
extern CFStringRef OBNSObjectCopyShortDescription(const void *value);

