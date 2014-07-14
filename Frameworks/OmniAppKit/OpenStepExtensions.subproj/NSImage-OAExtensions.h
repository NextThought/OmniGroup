// Copyright 1997-2005, 2007-2009, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSImage.h>
#import <AppKit/NSCell.h>  // For NSControlTint

@class CIImage, CIContext;

#define OAAquaImageTintSuffix      (@"Aqua")
#define OAGraphiteImageTintSuffix  (@"Graphite")
#define OAClearImageTintSuffix     (@"Clear")

extern NSString * const OADropDownTriangleImageName;
extern NSString * const OAInfoTemplateImageName;

@class /* Foundation     */ NSMutableSet;
@class /* OmniFoundation */ OFEnumNameTable;

@interface NSImage (OAExtensions)

   // Returns an image with the specified name from the specified bundle
+ (NSImage *)imageNamed:(NSString *)imageName inBundle:(NSBundle *)aBundle;
   // Returns an image with the specified control tint if one is available, otherwise returns the image with the specified name. Tinted images are searched for by appending the name of the tint ("Graphite", "Aqua", "Clear") to the image, with an optional hyphen separating the name from the tint.
+ (NSImage *)imageNamed:(NSString *)imageStem withTint:(NSControlTint)imageTint inBundle:(NSBundle *)aBundle allowingNil:(BOOL)allowNil;
+ (NSImage *)imageNamed:(NSString *)imageStem withTint:(NSControlTint)imageTint inBundle:(NSBundle *)aBundle;
   // Calls imageNamed:withTint:inBundle:, using the current control tint.
+ (NSImage *)tintedImageNamed:(NSString *)imageStem inBundle:(NSBundle *)aBundle allowingNil:(BOOL)allowNil;
+ (NSImage *)tintedImageNamed:(NSString *)imageStem inBundle:(NSBundle *)aBundle;
+ (NSImage *)tintedImageWithSize:(NSSize)size flipped:(BOOL)drawingHandlerShouldBeCalledWithFlippedContext drawingHandler:(BOOL (^)(NSRect dstRect))drawingHandler;
    // Automatically refreshes its cache when the system tint color changes

+ (NSImage *)imageForFileType:(NSString *)fileType;
    // Caching wrapper for -[NSWorkspace iconForFileType:].  This method is not thread-safe at the moment.
+ (NSImage *)imageForFile:(NSString *)path;

+ (NSImage *)draggingIconWithTitle:(NSString *)title andImage:(NSImage *)image;

/** Returns an image tinted with the passed in color, using NSCompositeSourceIn (R = S*Da), where S is the tintColor and Da is the alpha values in the image represented by self. This allows the tintColor to have an alpha value that survives into the result.
 */
- (NSImage *)imageByTintingWithColor:(NSColor *)tintColor;

- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta;
- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op;
- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op fraction:(CGFloat)delta;
- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op;

    // Puts the image on the pasteboard as TIFF, and also supplies data from any PDF, EPS, or PICT representations available. Returns the number of types added to the pasteboard and adds their names to notThese. This routine uses -addTypes:owner:, so the pasteboard must have previously been set up using -declareTypes:owner.
- (int)addDataToPasteboard:(NSPasteboard *)aPasteboard exceptTypes:(NSMutableSet *)notThese;

//

- (NSImageRep *)imageRepOfClass:(Class)imageRepClass;
- (NSImageRep *)imageRepOfSize:(NSSize)aSize; // uses -[NSImageRep size], not pixelsWide and pixelsHigh. maybe we need -imageRepOfPixelSize: too?

- (NSImage *)scaledImageOfSize:(NSSize)aSize;

- (NSData *)bmpData;
- (NSData *)bmpDataWithBackgroundColor:(NSColor *)backgroundColor;

- (NSData *)pngData;

// icon utilties

// Creates a document-preview style icon. All images supplied should have reps at 128x128, 32x32, and 16x16 for best results. Caller is responsible for positioning content appropriately within the icon frame (i.e. so it appears in the right place composited on the icon).
+ (NSImage *)documentIconWithContent:(NSImage *)contentImage;
    // Assumes images named "DocumentIconTemplate" and "DocumentIconMask" exist in your app wrapper.
+ (NSImage *)documentIconWithTemplate:(NSImage *)templateImage content:(NSImage *)contentImage contentMask:(NSImage *)contentMask;
    // Lets you provide your own template images.

// System Images
+ (NSImage *)httpInternetLocationImage;
+ (NSImage *)ftpInternetLocationImage;
+ (NSImage *)mailInternetLocationImage;
+ (NSImage *)newsInternetLocationImage;
+ (NSImage *)genericInternetLocationImage;

+ (NSImage *)aliasBadgeImage;

// For storing image tints
+ (OFEnumNameTable *)tintNameEnumeration;

// CoreImage

// Returns a CIImage containing this NSImage. If there is a NSCIImageRep or NSBitmapImageRep in the image, it will be used; otherwise the image will be rendered into a CGLayer and a CIImage created from that.
- (CIImage *)ciImageForContext:(CIContext *)ctxt;   // defaults to scale = 1
- (CIImage *)ciImageForContext:(CIContext *)ctxt scale:(CGFloat)scale;

@end
