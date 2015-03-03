// Copyright 2010-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIScalingScrollView.h>

#import <OmniUI/OUITiledScalingView.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

@implementation OUIScalingScrollView
@dynamic delegate;

static id _commonInit(OUIScalingScrollView *self)
{
    self->_allowedEffectiveScaleExtent = OFExtentMake(1, 8);
    self->_centerContent = YES;
    
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

// Caller should call -sizeInitialViewSizeFromCanvasSize on us after setting this.
@synthesize allowedEffectiveScaleExtent = _allowedEffectiveScaleExtent;

static OUIScalingView *_scalingView(OUIScalingScrollView *self)
{
    OUIScalingView *view = (OUIScalingView *)[self.delegate viewForZoomingInScrollView:self];
    OBASSERT(view);
    OBASSERT([view isKindOfClass:[OUIScalingView class]]);
    return view;
}

- (CGFloat)fullScreenScaleForCanvasSize:(CGSize)canvasSize;
{
    CGRect scrollBounds = [self.delegate scallingScrollViewContentViewFullScreenBounds:self];

    CGFloat fitXScale = CGRectGetWidth(scrollBounds) / canvasSize.width;
    CGFloat fitYScale = CGRectGetHeight(scrollBounds) / canvasSize.height;
    CGFloat fullScreenScale = MIN(fitXScale, fitYScale); // the maximum size that won't make us scrollable.
    
    return fullScreenScale;
}

- (void)adjustScaleTo:(CGFloat)effectiveScale canvasSize:(CGSize)canvasSize;
{
    OUIScalingView *view = _scalingView(self);
    if (!view)
        return;
    
    view.scale = effectiveScale;
    
    // The scroll view has futzed with our transform to make us look bigger, but we're going to do this by fixing our frame/bounds.
    view.transform = CGAffineTransformIdentity;
    
    // Build the new frame based on an integral scaling of the canvas size and make the bounds match. Thus the view is 1-1 pixel resolution.
    CGRect scaledCanvasSize = CGRectIntegral(CGRectMake(0, 0, effectiveScale * canvasSize.width, effectiveScale * canvasSize.height));
    view.frame = scaledCanvasSize;
    view.bounds = scaledCanvasSize;
    
    // Need to reset the min/max zoom to be factors of our current scale.  The minimum scale allowed needs to be sufficient to fit the whole graph on screen.  Then, allow zooming up to at least 4x that size or 4x the canvas size, whatever is larger.
    CGFloat minimumZoom = MIN(OFExtentMin(_allowedEffectiveScaleExtent), [self fullScreenScaleForCanvasSize:canvasSize]);
    CGFloat maximumZoom = OFExtentMax(_allowedEffectiveScaleExtent);

    BOOL isTiled = [view isKindOfClass:[OUITiledScalingView class]];
    if (!isTiled) {
        // If we are one big view, we need to limit our scale based on estimated VM size.
        
        // Limit the maximum zoom size (for now) based on the pixel count we'll cover.  Assume each pixel in the view backing store is 4 bytes. Limit to 16MB of video memory (other backing stores, animating between two zoom levels will temporarily double this). This does mean that if you have a large canvas, we might not even allow you to reach 100%. Better than crashing.
        CGFloat maxVideoMemory = 16*1024*1024;
        CGFloat canvasVideoUsage = 4 * canvasSize.width * canvasSize.height;
        maximumZoom = MIN(maximumZoom, sqrt(maxVideoMemory / canvasVideoUsage));
    }
        
    // Bummer. Large canvas?
    if (minimumZoom > maximumZoom)
        minimumZoom = maximumZoom;
    
    CGFloat minFactor = minimumZoom/effectiveScale;
    CGFloat maxFactor = maximumZoom/effectiveScale;
    
    self.minimumZoomScale = minFactor;
    self.maximumZoomScale = maxFactor;
    
    if (isTiled)
        [(OUITiledScalingView *)view tileVisibleRect];
    
    CGSize viewSize = view.frame.size;
    self.contentSize = CGSizeMake(viewSize.width, viewSize.height);

    [self adjustContentInsetAnimated:NO];
    
    // UIScrollView will show scrollers if we have the same (or maybe it is nearly the same) size but aren't really scrollable.  See <bug://bugs/60077> (weird scroller issues in landscape mode)
    CGSize scrollSize = self.bounds.size;
    self.showsHorizontalScrollIndicator = scrollSize.width < viewSize.width;
    self.showsVerticalScrollIndicator = scrollSize.height < viewSize.height;
    
    [view scaleChanged];
}

- (void)adjustContentInsetAnimated:(BOOL)animated;
{
    OUIScalingView *view = _scalingView(self);
    if (!view || !_centerContent)
        return;
    
    //NSLog(@"adjustContentInset");
    
    // If the contained view has a size smaller than the scroll view, it will get pinned to the upper left if there are no content insets.
    CGSize viewSize = view.frame.size;
    CGSize scrollSize = self.bounds.size;
    
    CGFloat xSpace = MAX(0, scrollSize.width - viewSize.width);
    CGFloat ySpace = MAX(0, scrollSize.height - viewSize.height);
    
    UIEdgeInsets zi = UIEdgeInsetsMake(ySpace/2, xSpace/2, ySpace/2, xSpace/2);  // natural insets to center the canvas
    UIEdgeInsets ei = self.extraEdgeInsets;                                    // insets required for avoiding the navbar and toolbar
    UIEdgeInsets totalInsets = UIEdgeInsetsMake(fmax(zi.top, ei.top),
                                                fmax(zi.left, ei.left),
                                                fmax(zi.bottom, ei.bottom),
                                                fmax(zi.right, ei.right));
    
    
    if (UIEdgeInsetsEqualToEdgeInsets(self.contentInset, totalInsets))
        return;
    
    if (animated) {
        [UIView beginAnimations:@"OUIAdjustContentInsetAnimation" context:NULL];
        [UIView setAnimationDuration:0.4];
    }
    
    self.contentInset = totalInsets;
    
    if (animated) {
        [UIView commitAnimations];
    }
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{   // layoutSubviews gets called frequently while scrolling, so it would be nice to only do this once,
    // but it turns out that we only get the correct height of the status bar after a few times through.
    // and since there's no noticeable performance problem here, we'll just keep calling it over and over and over again.
    [self adjustContentInsetAnimated:NO];
}

@end
