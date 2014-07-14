// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBackgroundActivity.h>

#import <OmniFoundation/OFPreference.h>
#import <Foundation/Foundation.h>
#import <libkern/OSAtomic.h>
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif

RCS_ID("$Id$")

// Make sure to log if we hit a log call before this is loaded from preferences/environment
static NSInteger OFBackgroundActivityDebug = NSIntegerMax;

#define DEBUG_ACTIVITY(level, format, ...) do { \
    if (OFBackgroundActivityDebug >= (level)) \
        NSLog(@"BACKGROUND (%d) %@: " format, RunningActivityCount, [self shortDescription], ## __VA_ARGS__); \
    } while (0)


static int32_t RunningActivityCount = 0;

@implementation OFBackgroundActivity
{
    NSString *_identifier;
    BOOL _finished;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    UIBackgroundTaskIdentifier _task;
#else
    BOOL _suddenTerminationDisabled;
#endif
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFInitializeDebugLogLevel(OFBackgroundActivityDebug);
}

+ (instancetype)backgroundActivityWithIdentifier:(NSString *)identifier;
{
    return [[[self alloc] initWithIdentifier:identifier] autorelease];
}

- initWithIdentifier:(NSString *)identifier;
{
    if (!(self = [super init]))
        return nil;
    
    _identifier = [identifier copy];
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    _task = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        // The Mac side and the new API on NSProcessInfo doesn't have an expiration handler. Should we expose this on iOS?
        NSLog(@"OFBackgroundActivity %@ expired", _identifier);
    }];
    if (_task == UIBackgroundTaskInvalid)
        NSLog(@"OFBackgroundActivity %@ unable to start background task", _identifier);
    else
        OSAtomicIncrement32(&RunningActivityCount);
#else
    [[NSProcessInfo processInfo] disableSuddenTermination];
    _suddenTerminationDisabled = YES;
    OSAtomicIncrement32(&RunningActivityCount);
#endif
    
    DEBUG_ACTIVITY(1, @"started");
    
    return self;
}

- (void)dealloc;
{
    if (!_finished)
        [self finished];
    [_identifier release];
    [super dealloc];
}

- (void)finished;
{
    // We maintain our own state for this in case iOS returns UIBackgroundTaskInvalid when we ask it to give us a background task (which it will do if the app doesn't support backgrounding or possibly in other cases).
    OBPRECONDITION(_finished == NO, @"Called -finished twice?");
    
    _finished = YES;
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    UIBackgroundTaskIdentifier task;
    @synchronized(self) {
        task = _task;
        _task = UIBackgroundTaskInvalid;
    }
    
    if (task != UIBackgroundTaskInvalid) {
        // Delay ending the task until the current call stack is done, letting other resources possible be deallocated in the autorelease pool (since we may be going to sleep and not dying outright). Also, we might be on a background queue (probably safe to call UIApplication here, but let's not assume so).
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OSAtomicDecrement32(&RunningActivityCount);
            DEBUG_ACTIVITY(1, @"finished");

            // Do this last since it might be the last thing we do...
            [[UIApplication sharedApplication] endBackgroundTask:task];
        }];
    }
#else
    // Probably don't need to delay here since we'll be terminated instead of put to sleep, but let's do so so we don't have to assume NSProcessInfo is thread-safe.
    BOOL disabled;
    @synchronized(self) {
        disabled = _suddenTerminationDisabled;
        _suddenTerminationDisabled = NO;
    }
    
    if (disabled) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OSAtomicDecrement32(&RunningActivityCount);
            DEBUG_ACTIVITY(1, @"finished");
            
            // Do this last since it might be the last thing we do...
            [[NSProcessInfo processInfo] enableSuddenTermination];
        }];
    }
#endif
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, _identifier];
}

@end
