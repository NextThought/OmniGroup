// Copyright 2003-2005, 2007-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLParser.h>

#import <libxml/SAX2.h>
#import <libxml/parser.h>
#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFXMLInternedStringTable.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniBase/assertions.h>

#import "OFXMLError.h"

RCS_ID("$Id$");

@interface OFXMLParserState : NSObject
{
@public
    xmlParserCtxtPtr ctxt;
    OFXMLParser *parser;
    NSObject <OFXMLParserTarget> *target;
    
    struct {
        void (*setSystemID)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSURL *systemID, NSString *publicID);
        void (*addProcessingInstruction)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSString *piName, NSString *piValue);
        
        OFXMLParserElementBehavior (*behaviorForElementWithQName)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, OFXMLQName *name, NSMutableArray *attributeQNames, NSMutableArray *attributeValues);
        void (*startElementWithQName)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, OFXMLQName *elementQName, NSMutableArray *attributeQNames, NSMutableArray *attributeValues);
        
        void (*endElement)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser);
        void (*endUnparsedElementWithQName)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, OFXMLQName *elementName, NSString *identifier, NSData *contents);
        
        void (*addWhitespace)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSString *whitespace);
        void (*addString)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSString *string);
    } targetImp;
    
    NSUInteger elementDepth;
    BOOL rootElementFinished;
    
    NSCharacterSet *nonWhitespaceCharacterSet;
    OFXMLWhitespaceBehavior *whitespaceBehavior;
    NSMutableArray *whitespaceBehaviorStack;
    
    NSError *error;
    NSMutableArray *loadWarnings;
    
    BOOL ownsNameTable;
    OFXMLInternedNameTable nameTable;
    
    // Support for unparsed/skipped blocks
    OFXMLParserElementBehavior unparsedBlockBehavior;
    off_t unparsedBlockStart; // < 0 if we aren't in an unparsed block.
    unsigned int unparsedBlockElementNesting;
    NSString *unparsedElementID; // The value of the xml:id attribute, if any
}
@end

@implementation OFXMLParserState
@end

// CFXML only has one callback for this; not sure why there are two.
static void _internalSubsetSAXFunc(void *ctx, const xmlChar *name, const xmlChar *ExternalID, const xmlChar *SystemID)
{
    //NSLog(@"_internalSubsetSAXFunc name:'%s' ExternalID:'%s' SystemID:'%s'", name, ExternalID, SystemID);
}

static void _externalSubsetSAXFunc(void *ctx, const xmlChar *name, const xmlChar *ExternalID, const xmlChar *SystemID)
{
    //NSLog(@"_externalSubsetSAXFunc name:'%s' ExternalID:'%s' SystemID:'%s'", name, ExternalID, SystemID);
    
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    // We pick up the root element name when it is opened (curently assume that it matches the name in the DOCTYPE).
    
    if (state->targetImp.setSystemID) {
        NSURL *systemID = NULL;
        if (SystemID) {
            CFStringRef systemIDString = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)SystemID, kCFStringEncodingUTF8);
            systemID = CFBridgingRelease(CFURLCreateWithString(kCFAllocatorDefault, systemIDString, NULL));
            CFRelease(systemIDString);
            
            if (!systemID)
                NSLog(@"Unable to create URL from system id '%s'.", SystemID);
        }
        NSString *publicID = nil;
        if (ExternalID)
            publicID = CFBridgingRelease(CFStringCreateWithCString(kCFAllocatorDefault, (const char *)ExternalID, kCFStringEncodingUTF8));
        
        state->targetImp.setSystemID(state->target, @selector(parser:setSystemID:publicID:), parser, systemID, publicID);
    }
}

static void _startElementNsSAX2Func(void *ctx, const xmlChar *localname, const xmlChar *prefix, const xmlChar *URI, int nb_namespaces, const xmlChar **namespaces, int nb_attributes, int nb_defaulted, const xmlChar **attributes)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
    
    // Unparsed element support
    if (state->unparsedBlockStart >= 0) {
        // Already in an unparsed block.  Increment our counter and bail.
        state->unparsedBlockElementNesting++;
        //fprintf(stderr, " ## start nested unparsed element '%s'; depth now %d\n", localname, state->unparsedBlockElementNesting);
        return;
    }
    
    NSMutableArray *attributeQNames = nil;
    NSMutableArray *attributeValues = nil;
    
    // Note: the segregation of namespace and attibutes will force us to reorder xmlns attributes to the beginning when round-tripping (since we map namespaces to attributes to avoid losing them).
    if (nb_namespaces) {
        if (!attributeQNames)
            attributeQNames = [[NSMutableArray alloc] init];
        if (!attributeValues)
            attributeValues = [[NSMutableArray alloc] init];
        
        int namespaceIndex;
        for (namespaceIndex = 0; namespaceIndex < nb_namespaces; namespaceIndex++) {
            // Each namespace is given by two elements, a prefix and URI.
            
            OFXMLQName *qname = OFXMLInternedNameTableGetInternedName(state->nameTable, OFXMLNamespaceXMLNSCString, (const char *)namespaces[0]);
            
            NSString *URIString;
            if (namespaces[1])
                URIString = [[NSString alloc] initWithUTF8String:(const char *)namespaces[1]];
            else {
                NSLog(@"Bogus namespace; no URI string");
                continue;
            }
            
            [attributeQNames addObject:qname];
            [attributeValues addObject:URIString];
            [URIString release];
        }
    }
    
    if (nb_attributes) {
        if (!attributeQNames)
            attributeQNames = [[NSMutableArray alloc] init];
        if (!attributeValues)
            attributeValues = [[NSMutableArray alloc] init];
        
        // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
        while (nb_attributes--) {
            // TODO: Intern the values or not?  Don't have a great way to do it with the current setup since we want NULL terminated strings.  Some attribute values may be the same over and over; maybe we could intern if the length is small enough?
            
            const char *attributeLocalname = (const char *)attributes[0];
            //const char *prefix = (const char *)attributes[1];
            const char *attributeNsURI = (const char *)attributes[2];
            const char *valueStart = (const char *)attributes[3];
            const char *valueEnd = (const char *)attributes[4];

            OFXMLQName *qname = OFXMLInternedNameTableGetInternedName(state->nameTable, attributeNsURI, attributeLocalname);
            NSString *value = [[NSString alloc] initWithBytes:valueStart length:valueEnd - valueStart encoding:NSUTF8StringEncoding];
            
            // We specify XML_PARSE_NOENT so entities are already parsed up front.  Clients of the framework should thus always get nice Unicode strings w/o worrying about this muck.
            
            [attributeQNames addObject:qname];
            [attributeValues addObject:value];
            
            [value release];
            
            attributes += 5;
        }
    }
    
    OFXMLQName *elementQName = OFXMLInternedNameTableGetInternedName(state->nameTable, (const char *)URI, (const char *)localname);

    // This gets called after the input pointer has scanned up to the end of the attributes.  For <foo bar="x" /> the input will be pointing at the '/'.  Find the starting byte of this element by scanning backwards looking for '<'.  Since we get called while inside the element, we don't have to worry about '<' in CDATA blocks.  Not sure if libxml2 handles non-conforming documents with '<' in attributes.
    OFXMLParserElementBehavior behavior = OFXMLParserElementBehaviorParse;
    if (state->targetImp.behaviorForElementWithQName)
        behavior = state->targetImp.behaviorForElementWithQName(state->target, @selector(parser:behaviorForElementWithQName:attributeQNames:attributeValues:), parser, elementQName, attributeQNames, attributeValues);
    if (behavior != OFXMLParserElementBehaviorParse) {
        const xmlChar *p = state->ctxt->input->cur;
        const xmlChar *base = state->ctxt->input->base;
        
        if (behavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) {
            // do not include the element, just the data
            OBASSERT(*p == '/' || *p == '>');
            if (*p == '/')
                p++;
            if (*p == '>')
                p++;
        } else {
            while (p >= base) {
                if (*p == '<')
                    break;
                p--;
            }
        }
        
        if (*p == '<' || behavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) {
            state->unparsedBlockBehavior = behavior;
            state->unparsedBlockStart = p - base;
            state->unparsedBlockElementNesting = 0;
            //fprintf(stderr, "unparsed element '%s' starts at offset %qd\n", localname, state->unparsedBlockStart);
            
            // Store the xml:id of the element, if it has one, so we can pass it to the end hook.  We could pass the entire set of attributes, but I only need the id right now.
            OBASSERT(state->unparsedElementID == nil);

            OFXMLQName *idQName = OFXMLInternedNameTableGetInternedName(state->nameTable, OFXMLNamespaceXMLCString, "id");
            NSUInteger idIndex = [attributeQNames indexOfObject:idQName];
            if (idIndex != NSNotFound) {
                state->unparsedElementID = [[attributeValues objectAtIndex:idIndex] copy];
            }
            
            [attributeQNames release];
            [attributeValues release];

            return;
        } else {
            OBASSERT_NOT_REACHED("Didn't find element open.");
        }
    }
    

    // TODO: Maintain our own stack of return values from startElement and pass them to the end call?  Or require all the targets to maintain their own stack if they need it?
    state->elementDepth++;
    
    if (state->targetImp.startElementWithQName)
        state->targetImp.startElementWithQName(state->target, @selector(parser:startElementWithQName:attributeQNames:attributeValues:), state->parser, elementQName, attributeQNames, attributeValues);
    
    [attributeQNames release];
    [attributeValues release];
    
    
    // TODO: Make OFXMLWhitespaceBehaviorType QName aware.
    OFXMLWhitespaceBehaviorType oldBehavior = (OFXMLWhitespaceBehaviorType)[[state->whitespaceBehaviorStack lastObject] unsignedIntegerValue];
    OFXMLWhitespaceBehaviorType newBehavior = [state->whitespaceBehavior behaviorForElementName:elementQName.name];
    
    if (newBehavior == OFXMLWhitespaceBehaviorTypeAuto)
        newBehavior = oldBehavior;
    
    [state->whitespaceBehaviorStack addObject:@(newBehavior)];
    
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
        
#if 0
    NSLog(@"start element localname:'%s' prefix:'%s' URI:'%s'", localname, prefix, URI);
    
    // Each namespace is given by two elements, a prefix and URI
    while (nb_namespaces--) {
        NSLog(@"  namespace: prefix:'%s' uri:'%s'", namespaces[0], namespaces[1]);
        namespaces += 2;
    }
    
    // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
    while (nb_attributes--) {
        NSString *value = [[NSString alloc] initWithBytes:attributes[3] length:attributes[4]-attributes[3] encoding:NSUTF8StringEncoding];
        NSLog(@"  attribute: localname:'%s' prefix:'%s' URI:'%s' value:'%@'", attributes[0], attributes[1], attributes[2], value);
        [value release];
        attributes += 5;
    }
#endif
}

static void _endElementNsSAX2Func(void *ctx, const xmlChar *localname, const xmlChar *prefix, const xmlChar *URI)
{
    //NSLog(@"end element localname:'%s' prefix:'%s' URI:'%s'", localname, prefix, URI);
    
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    // See if we've finished an unparsed block
    if (state->unparsedBlockStart >= 0) {
        if (state->unparsedBlockElementNesting == 0) {
            // Don't call back (or create the contents data) if we just wanted to skip it.
            if ((state->unparsedBlockBehavior == OFXMLParserElementBehaviorUnparsed || state->unparsedBlockBehavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) && state->targetImp.endUnparsedElementWithQName) {
                // This gets called right after the closing '>'.  This is the end of our unparsed block.
                const xmlChar *p = state->ctxt->input->cur;
                const xmlChar *base = state->ctxt->input->base;
                
                if (state->unparsedBlockBehavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) {
                    // do not include the element in the data passed to -endUnparsedElementWithQName    
                    while (p >= base) {
                        if (*p == '<')
                            break;
                        p--;
                    }
                }
                
                OBASSERT(p > base);
//                OBASSERT(p[-1] == '>');
                
                size_t end = p - base;
                //fprintf(stderr, "unparsed element '%s' at %qd extended for %qd\n", localname, state->unparsedBlockStart, end - state->unparsedBlockStart);
                
                OBASSERT(end > (typeof(end))state->unparsedBlockStart); // signed vs. unsigned, but we checked unparsedBlockStart >= 0 above, so the cast is safe
                size_t length = (size_t)(end - state->unparsedBlockStart);
                
                NSData *data = [[NSData alloc] initWithBytes:state->ctxt->input->base + state->unparsedBlockStart length:length];
                OFXMLQName *qname = OFXMLInternedNameTableGetInternedName(state->nameTable, (const char *)URI, (const char *)localname);
                
                state->targetImp.endUnparsedElementWithQName(state->target, @selector(parser:endUnparsedElementWithQName:identifier:contents:), parser, qname, state->unparsedElementID, data);

                [state->unparsedElementID release];
                state->unparsedElementID = nil;
                
                [data release];            
            }
            
            state->unparsedBlockStart = -1; // end of the unparsed block
            return;
        } else {
            state->unparsedBlockElementNesting--;
            //fprintf(stderr, " ## end nested unparsed element '%s'; depth now %d\n", localname, state->unparsedBlockElementNesting);
            return;
        }
    }
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
    
    OBASSERT(state->elementDepth > 0);
    if (state->elementDepth > 0) {
        state->elementDepth--;
        if (state->elementDepth == 0)
            state->rootElementFinished = YES;
    }
    
    if (state->targetImp.endElement)
        state->targetImp.endElement(state->target, @selector(parserEndElement:), parser);

    [state->whitespaceBehaviorStack removeLastObject];
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
}

static void _charactersSAXFunc(void *ctx, const xmlChar *ch, int len)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    // Unparsed element support; if we are in the middle of an unparsed element, ignore characters
    if (state->unparsedBlockStart >= 0)
        return;
    
    // Ignore whitespace and text outside the root element.
    if (state->elementDepth == 0)
        return;
    
    NSString *str = [[NSString alloc] initWithBytes:ch length:len encoding:NSUTF8StringEncoding];
    //NSLog(@"characters: '%@'", str);
    
    if ([str rangeOfCharacterFromSet:state->nonWhitespaceCharacterSet].length == 0) {
        OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
        
        // Only add the whitespace if our current behavior dictates that we do so (and we are actually inside the root element)
        OFXMLWhitespaceBehaviorType currentBehavior = (OFXMLWhitespaceBehaviorType)[[state->whitespaceBehaviorStack lastObject] unsignedIntegerValue];
        
        if (currentBehavior == OFXMLWhitespaceBehaviorTypePreserve) {
            if (state->targetImp.addWhitespace)
                state->targetImp.addWhitespace(state->target, @selector(parser:addWhitespace:), parser, str);
        }
    } else {
        //NSLog(@"_addString:%@", str);
        if (state->targetImp.addString)
            state->targetImp.addString(state->target, @selector(parser:addWhitespace:), parser, str);
    }
    
    [str release];
}

static void _processingInstructionSAXFunc(void *ctx, const xmlChar *target, const xmlChar *data)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    if (state->targetImp.addProcessingInstruction) {
        NSString *name = [[NSString alloc] initWithUTF8String:(const char *)target];
        NSString *value = data ? [[NSString alloc] initWithUTF8String:(const char *)data] : @"";
    
        state->targetImp.addProcessingInstruction(state->target, @selector(parser:addProcessingInstructionNamed:value:), parser, name, value);
        
        [name release];
        [value release];
    }
}

static void _xmlStructuredErrorFunc(void *userData, xmlErrorPtr error)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)userData;
    
    NSError *errorObject = OFXMLCreateError(error);
    if (errorObject == nil)
        return; // should be ignored.
    
    if (error->level == XML_ERR_WARNING)
        [state->loadWarnings addObject:errorObject];
    else {
        OBASSERT(error->level == XML_ERR_ERROR || error->level == XML_ERR_FATAL);
        
        // Error or fatal.  We don't ask for recovery, so for now anything that isn't a warning is fatal.
        OBASSERT(state->error == nil);
        state->error = [errorObject retain];
        xmlStopParser(state->ctxt);
    }
    [errorObject release];
}


static void _OFXMLParserStateCleanUp(OFXMLParserState *state)
{
    OBPRECONDITION(state->ctxt == NULL); // we don't clean this up
    OBPRECONDITION(state->error == nil); // the caller should have taken ownership and cleaned this up
    
    [state->whitespaceBehaviorStack release];
    [state->nonWhitespaceCharacterSet release];
    [state->loadWarnings release];
    
    if (state->ownsNameTable && state->nameTable)
        OFXMLInternedNameTableFree(state->nameTable);
}

@implementation OFXMLParser
{
    OFXMLParserState *_state; // Only set while parsing.
}

- (id)initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(NSObject <OFXMLParserTarget> *)target error:(NSError **)outError;
{
    if (!(self = [super init]))
        return nil;

    OBPRECONDITION(whitespaceBehavior);
    
    _encoding = kCFStringEncodingInvalidId;
    
    LIBXML_TEST_VERSION
    
    _state = [[OFXMLParserState alloc] init];
    
    _state->parser = self;
    _state->whitespaceBehaviorStack = [[NSMutableArray alloc] init];
    _state->nonWhitespaceCharacterSet = [[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet] copy];
    _state->loadWarnings = [[NSMutableArray alloc] init];
    _state->whitespaceBehavior = whitespaceBehavior;
    
    _state->target = target;
    
    // Assert on deprecated target methods.
    OBASSERT_NOT_IMPLEMENTED(target, parser:shouldLeaveElementAsUnparsedBlock:); // Takes a OFXMLQName and attribute names/values now.
    OBASSERT_NOT_IMPLEMENTED(target, parser:startElementNamed:attributeOrder:attributeValues:); // QName aware version now.
    OBASSERT_NOT_IMPLEMENTED(target, parser:endUnparsedElementNamed:contents:); // QName aware version now.
    OBASSERT_NOT_IMPLEMENTED(target, parser:endUnparsedElementWithQName:contents:); // And we pass the xml:id now.
    
    // -methodForSelector returns _objc_msgForward
#define GET_IMP(slot, sel) do { \
    if ([target respondsToSelector:sel]) \
        _state->targetImp.slot = (typeof(_state->targetImp.slot))[target methodForSelector:sel]; \
} while (0)
    GET_IMP(setSystemID, @selector(parser:setSystemID:publicID:));
    GET_IMP(addProcessingInstruction, @selector(parser:addProcessingInstructionNamed:value:));
    GET_IMP(behaviorForElementWithQName, @selector(parser:behaviorForElementWithQName:attributeQNames:attributeValues:));
    GET_IMP(startElementWithQName, @selector(parser:startElementWithQName:attributeQNames:attributeValues:));
    GET_IMP(endElement, @selector(parserEndElement:));
    GET_IMP(endUnparsedElementWithQName, @selector(parser:endUnparsedElementWithQName:identifier:contents:));
    GET_IMP(addWhitespace, @selector(parser:addWhitespace:));
    GET_IMP(addString, @selector(parser:addString:));
#undef GET_IMP

    if ([target respondsToSelector:@selector(internedNameTableForParser:)]) {
        _state->nameTable = [target internedNameTableForParser:self];
        _state->ownsNameTable = NO;
    }
    if (!_state->nameTable) {
        _state->nameTable = OFXMLInternedNameTableCreate(NULL);
        _state->ownsNameTable = YES;
    }
    
    _state->unparsedBlockStart = -1;
    
    // Set up default whitespace behavior
    [_state->whitespaceBehaviorStack addObject:@(defaultWhitespaceBehavior)];
    
    
    // TODO: Add support for passing along the source URL
    // We want whitespace reported since we may or may not keep it depending on our whitespaceBehavior input.
    
    xmlSAXHandler sax;
    memset(&sax, 0, sizeof(sax));
    
    sax.initialized = XML_SAX2_MAGIC; // Use the SAX2 callbacks
    
    sax.internalSubset = _internalSubsetSAXFunc;
    sax.characters = _charactersSAXFunc;
    sax.processingInstruction = _processingInstructionSAXFunc;
    sax.externalSubset = _externalSubsetSAXFunc;
    sax.startElementNs = _startElementNsSAX2Func;
    sax.endElementNs = _endElementNsSAX2Func;
    sax.serror = _xmlStructuredErrorFunc;
    
    // xmlSAXUserParseMemory hides the xmlParserCtxtPtr.  But, this means we can't get the source encoding, so we use the push approach.
    NSUInteger xmlLength = [xmlData length];
    OBASSERT(xmlLength < INT_MAX); // Need a different API for super-long XML.
    
    _state->ctxt = xmlCreatePushParserCtxt(&sax, (__bridge void *)_state/*user data*/, [xmlData bytes], (int)xmlLength, NULL);
    
    // Set the options on our XML parser instance.
    // We set XML_PARSE_HUGE to bypass any hardcoded internal parser limits, such as 10000000 byte input length limit.
    //
    // Those limits are enforced by default with the version of libxml2 that ships with iOS 7 and OS X 10.9.
    // rdar://problem/14280255 and rdar://problem/14280241 asks them to reconsider this default configuration because it breaks binary compatibilty for existing libxml2 clients.
    
    int options = 0;
    options |= XML_PARSE_NOENT;     // Turn entities into content
    options |= XML_PARSE_NONET;     // Don't allow network access
    options |= XML_PARSE_NSCLEAN;   // Remove redundant namespace declarations
    options |= XML_PARSE_NOCDATA;   // Merge CDATA as text nodes
    options |= XML_PARSE_HUGE;      // Relax any hardcoded limit from the parser
    
    options = xmlCtxtUseOptions(_state->ctxt, options);
    if (options != 0)
        NSLog(@"Unsupported xml parser options: 0x%08x", options);

    // Encoding isn't set until after the terminate.
    int rc = xmlParseChunk(_state->ctxt, NULL, 0, TRUE/*terminate*/);
    
    OBASSERT((rc == 0) == (_state->error == nil));
    
    BOOL result = YES;
    if (rc != 0 || _state->error) {
        if (outError)
            *outError = [[_state->error retain] autorelease];
        [_state->error release];
        _state->error = nil; // we've dealt with cleaning up the error portion of the state
        result = NO;
    } else {
        CFStringEncoding encoding = kCFStringEncodingUTF8;
        if (_state->ctxt->encoding) {
            CFStringRef encodingName = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)_state->ctxt->encoding, kCFStringEncodingUTF8);
            CFStringEncoding parsedEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName);
            CFRelease(encodingName);
            if (parsedEncoding == kCFStringEncodingInvalidId) {
#ifdef DEBUG
                NSLog(@"No string encoding found for '%s'.", _state->ctxt->encoding);
#endif
            } else
                encoding = parsedEncoding;
        }
        _encoding = encoding;
        if (_state->loadWarnings)
            _loadWarnings = [[NSArray alloc] initWithArray:_state->loadWarnings];
        
        // CFXML reports the <?xml...?> as a PI, but libxml2 doesn't.  It has the information we need in the context structure.  But, if there were other PIs, they'll be first in the list now.  So, we store this information out of the PIs now.
        if (_state->ctxt->version && *_state->ctxt->version)
            _versionString = [[NSString alloc] initWithUTF8String:(const char *)_state->ctxt->version];
        else
            _versionString = @"1.0";
        _standalone = _state->ctxt->standalone? YES : NO;
        
        OBASSERT(_state->elementDepth == 0); // should have finished the root element.
        OBASSERT(_state->rootElementFinished);
        OBASSERT([_state->whitespaceBehaviorStack count] == 1); // The default one should be one the stack.
        OBASSERT(![NSString isEmptyString:_versionString]);
    }
    
    xmlFreeParserCtxt(_state->ctxt);
    _state->ctxt = NULL;
    
    _OFXMLParserStateCleanUp(_state);
    [_state release];
    _state = nil;
    
    if (!result) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc;
{
    [_versionString release];
    [_loadWarnings release];
    [super dealloc];
}

- (NSUInteger)elementDepth;
{
    return _state ? _state->elementDepth : 0;
}

@end
