// Copyright 2006-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateFormatter.h>

#import <OmniFoundation/OFRelativeDateParser.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

@implementation OFRelativeDateFormatter
{
    NSDateComponents *_defaultTimeDateComponents;
    BOOL _useEndOfDuration;
    BOOL _useRelativeDayNames;
    BOOL _wantsTruncatedTime;
}

- (void)dealloc;
{
    [_defaultTimeDateComponents release];
    [super dealloc];
}

#pragma mark API

- (void)setUseRelativeDayNames:(BOOL)useRelativeDayNames;
{
    // We either want our relative formatting or the system's, not both
    OBASSERT_IF(useRelativeDayNames, [self doesRelativeDateFormatting] == NO);
    
    _useRelativeDayNames = useRelativeDayNames;
}

- (BOOL)useRelativeDayNames;
{
    return _useRelativeDayNames;
}

- (void)setWantsTruncatedTime:(BOOL)wantsTruncatedTime;
{
    _wantsTruncatedTime = wantsTruncatedTime;
}

- (BOOL)wantsTruncatedTime;
{
    return _wantsTruncatedTime;   
}

#pragma mark NSFomatter subclass

static NSString *truncatedTimeString(NSDateComponents *comps, NSDateComponents *defaultDateComps)
{
    NSInteger defaultHour = 0;
    NSInteger defaultMinute = 0;
    if (defaultDateComps) {
	defaultHour = [defaultDateComps hour];
	defaultMinute = [defaultDateComps minute];
    }
    // don't display the time if its the default time
    if ([comps hour] == defaultHour && [comps minute] == defaultMinute)
	return @"";
    
    NSInteger hour = [comps hour];
    if (hour > 12)
	hour-=12;
    NSString *meridian = ([comps hour] < 12) ? @"a" : @"p";
    NSString *mins = [NSString stringWithFormat:@":%02ld", [comps minute]];
    NSString *timeString = [NSString stringWithFormat:@"%ld", hour];
    if ([comps minute] != 0)
	timeString = [timeString stringByAppendingString:mins];
    timeString = [timeString stringByAppendingString:meridian];
    return timeString;
}

#define DATE_STRING() do { \
[self setTimeStyle:NSDateFormatterNoStyle]; \
dateString = [super stringForObjectValue:obj]; \
[self setTimeStyle:timeStyle]; \
} while (0)

#if 1
- (NSString *)stringForObjectValue:(id)obj;
{
    if (!obj)
	return @"";
    
    // just return the basic NSDateFormatter values
    if (!_useRelativeDayNames && !_wantsTruncatedTime)
	return [super stringForObjectValue:obj];
    
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *value = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitWeekday fromDate:obj];
    NSDateFormatterStyle timeStyle = [self timeStyle];
    NSString *dateString = @"";

    // return truncated time, but not relative day names (if we're set to return the date at all)
    if (!_useRelativeDayNames && _wantsTruncatedTime) {
	if (timeStyle != NSDateFormatterNoStyle) {
	    // get the default date string, but make our own truncated time
	    DATE_STRING();
	    return [dateString stringByAppendingFormat:@" %@", truncatedTimeString(value, _defaultTimeDateComponents)];
	}
    }
    
    // construct relative day names
    NSDateComponents *today = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:[NSDate date]];
    
    // if today, and no time set, just say "Today", if there is a time, return the time
    if ([self dateStyle] == NSDateFormatterNoStyle)
        DATE_STRING();
    else if ([today year] == [value year] && [today month] == [value month] && [today day] == [value day])
        dateString = NSLocalizedStringFromTableInBundle(@"Today", @"OFDateProcessing", OMNI_BUNDLE, @"Today");
    else if ([today year] == [value year] && [today month] == [value month] && [today day]+1 == [value day])
        dateString = NSLocalizedStringFromTableInBundle(@"Tomorrow", @"OFDateProcessing", OMNI_BUNDLE, @"Tomorrow");
    else if ([today year] == [value year] && [today month] == [value month] && [today day]-1 == [value day])
        dateString = NSLocalizedStringFromTableInBundle(@"Yesterday", @"OFDateProcessing", OMNI_BUNDLE, @"Yesterday");
    else 
        DATE_STRING();
    
    if (_wantsTruncatedTime)
	return [[dateString stringByAppendingFormat:@" %@", truncatedTimeString(value, _defaultTimeDateComponents)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    NSDateFormatterStyle dateStyle = [self dateStyle];
    [self setDateStyle:NSDateFormatterNoStyle];
    NSString *timeString = [super stringForObjectValue:obj];
    if ( ! [NSString isEmptyString:timeString]) {
        dateString = [[dateString stringByAppendingFormat:@" %@", timeString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    [self setDateStyle:dateStyle];
    return dateString;
}
#endif

#if 0
- (NSAttributedString *)attributedStringForObjectValue:(id)obj withDefaultAttributes:(NSDictionary *)attrs;
{
    NSAttributedString *result = [super attributedStringForObjectValue:obj withDefaultAttributes:attrs];
    //NSLog(@"%s: obj:%@ result:%@", __PRETTY_FUNCTION__, obj, result);
    return result;
}
#endif

- (NSString *)editingStringForObjectValue:(id)obj;
{
    return [super stringForObjectValue:obj];
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString **)error;
{
    NSError *relativeError = nil;
    NSDate *date = nil;
    
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string fromStartingDate:_referenceDate useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents calendar:[self calendar] withCustomFormat:self.dateFormat error:&relativeError];

    if (success)
        *obj = date;
    
    return success;
 }

- (BOOL)isPartialStringValid:(NSString **)partialStringPtr proposedSelectedRange:(NSRangePointer)proposedSelRangePtr originalString:(NSString *)origString originalSelectedRange:(NSRange)origSelRange errorDescription:(NSString **)error;
{
    return YES;
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string range:(inout NSRange *)rangep error:(out NSError **)error;
{
    NSDate *date = nil;
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string fromStartingDate:_referenceDate useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents calendar:[self calendar] withCustomFormat:self.dateFormat error:error];

    if (success)
        *obj = date;

    return success;
}

- (NSString *)stringFromDate:(NSDate *)date;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (NSDate *)dateFromString:(NSString *)string;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OFRelativeDateFormatter *copy = [super copyWithZone:zone];
    copy->_defaultTimeDateComponents = [_defaultTimeDateComponents copy];
    copy->_useEndOfDuration = _useEndOfDuration;
    copy->_useRelativeDayNames = _useRelativeDayNames;
    copy->_wantsTruncatedTime = _wantsTruncatedTime;
    return copy;
}

@end
