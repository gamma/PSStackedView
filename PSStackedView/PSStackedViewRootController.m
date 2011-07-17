//
//  SVStackRootController.m
//  PSStackedView
//
//  Created by Peter Steinberger on 7/14/11.
//  Copyright 2011 Peter Steinberger. All rights reserved.
//

#import "PSStackedViewRootController.h"
#import "PSStackedViewGlobal.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#define kSVStackAnimationDuration 0.3
#define kSVCornerRadius 6.f
#define kSVMaskKey @"kPSMaskKey"
#define kSVGradientShadow @"kPSGradientShadow"
#define kSVShadowWidth 20.f

@interface PSStackedViewRootController() <UIGestureRecognizerDelegate> {
    // internal drag state handling
    NSInteger lastDragOffset_;
    SVSnapOption lastDragOption_;
    BOOL lastDragDividedOne_;
    
    NSInteger lastVisibleIndexBeforeRotation_;
}

@property(nonatomic, assign) NSMutableArray* viewControllers;
@property(nonatomic, assign) NSInteger firstVisibleIndex;
@property(nonatomic, assign, getter=isShowingFullMenu) BOOL showingFullMenu;

@end

@implementation PSStackedViewRootController

@synthesize backMinWidth = backMinWidth_;
@synthesize backEmptyWidth = backEmptyWidth_;
@synthesize viewControllers = viewControllers_;
@synthesize showingFullMenu  = showingFullMenu_;
@synthesize firstVisibleIndex = firstVisibleIndex_;


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if ((self = [super init])) {
        viewControllers_ = [[NSMutableArray alloc] init];
        
        // set some reasonble defaults
        showingFullMenu_ = YES;
        backMinWidth_ = 60;
        backEmptyWidth_ = 200;
        
        // add a gesture recognizer to detect dragging to the guest controllers
        UIPanGestureRecognizer* panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanFrom:)];
        [panRecognizer setMaximumNumberOfTouches:1];
        [panRecognizer setDelaysTouchesBegan:YES];
        [panRecognizer setDelaysTouchesEnded:YES];
        [panRecognizer setCancelsTouchesInView:YES];
        [self.view addGestureRecognizer:panRecognizer];
        [panRecognizer release];
    }
    return self;
}

- (void)dealloc {
    [viewControllers_ release];
    [super dealloc];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private Helpers

- (void)addMastToViewController:(UIViewController *)controller corners:(UIRectCorner)corners {
    // Re-calculate the size of the mask to account for adding/removing rows.
    CGRect frame = controller.view.bounds;
    if([controller.view isKindOfClass:[UIScrollView class]] && ((UIScrollView *)controller.view).contentSize.height > controller.view.frame.size.height) {
    	frame.size = ((UIScrollView *)controller.view).contentSize;
    } else {
        frame.size = controller.view.frame.size;
    }
    
    // Create the path (with only the top-left corner rounded)
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:frame 
                                                   byRoundingCorners:corners
                                                         cornerRadii:CGSizeMake(kSVCornerRadius, kSVCornerRadius)];
    
    // Create the shape layer and set its path
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = frame;
    maskLayer.path = maskPath.CGPath;
    
    // Set the newly created shape layer as the mask for the image view's layer
    controller.view.layer.mask = maskLayer;
}

- (void)removeMaskFromController:(UIViewController *)controller {
    controller.view.layer.mask = nil;
}

#define SHADOW_HEIGHT 20.0
#define SHADOW_INVERSE_HEIGHT 10.0
- (void)addShadowToViewController:(UIViewController *)controller {
    
    CAGradientLayer *newShadow = [[[CAGradientLayer alloc] init] autorelease];
    newShadow.startPoint = CGPointMake(0, 0.5);
    newShadow.endPoint = CGPointMake(1.0, 0.5);
	CGRect newShadowFrame = CGRectMake(-kSVShadowWidth, 0, kSVShadowWidth, controller.view.height);
    
	newShadow.frame = newShadowFrame;
	CGColorRef darkColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.6].CGColor;
	CGColorRef lightColor = [UIColor clearColor].CGColor;
	newShadow.colors = [NSArray arrayWithObjects:(id)lightColor, (id)darkColor, nil];

    newShadow.name = kSVGradientShadow;
    [controller.view.superview.layer addSublayer:newShadow];
}

- (void)removeShadowFromViewController:(UIViewController *)controller {
    NSMutableSet *removeLayers = [NSMutableSet set];
    for (CALayer *layer in controller.view.layer.sublayers) {
        if (layer.name == kSVGradientShadow) {
            [removeLayers addObject:layer];
        }
    }
    [removeLayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
}

// return screen width
- (NSUInteger)screenWidth {
    NSUInteger screenWidth = SVIsLandscape() ? self.view.height : self.view.width;
    return screenWidth;
}

// total stack width if completely expanded
- (NSUInteger)totalStackWidth {
    NSUInteger totalStackWidth = 0;
    for (UIViewController<PSStackedViewDelegate> *controller in self.viewControllers) {
        totalStackWidth += [controller stackableMaxWidth];
    }
    return totalStackWidth;
}

// menu is only collapsable if stack is large enough
- (BOOL)isMenuCollapsable {
    NSUInteger screenWidth = [self screenWidth];
    NSUInteger totalWidth = [self totalStackWidth];
    
    BOOL isMenuCollapsable = totalWidth + self.backEmptyWidth > screenWidth;
    return isMenuCollapsable;
}

// return current left border (how it *should* be)
- (NSUInteger)leftBorder {
    if (self.isShowingFullMenu) {
        return self.backEmptyWidth;
    }else {
        return self.backMinWidth;
    }
}

// minimal left border is depending on amount of VCs
- (NSUInteger)minimalLeftBorder {
    if ([self isMenuCollapsable]) {
        return self.backMinWidth;
    }else {
        return self.backEmptyWidth;
    }
}

// if view controller is completely hidden behind other controller, its set to invisible to save resources
- (BOOL)isViewControllerVisible:(UIViewController<PSStackedViewDelegate> *)viewController completely:(BOOL)completely {
    NSUInteger screenWidth = [self screenWidth];
    
    if ((viewController.view.left < screenWidth && !completely) || (completely && viewController.view.right <= screenWidth)) {
        return YES;
    }
    return NO;
}

// returns view controller that is displayed before viewController 
- (UIViewController<PSStackedViewDelegate> *)previousViewController:(UIViewController<PSStackedViewDelegate> *)viewController {
    NSParameterAssert(viewController);
    
    NSUInteger vcIndex = [self.viewControllers indexOfObject:viewController];
    UIViewController<PSStackedViewDelegate> *prevVC = nil;
    if (vcIndex > 0) {
        prevVC = [self.viewControllers objectAtIndex:vcIndex-1];
    }
    
    return prevVC;
}

// returns view controller that is displayed after viewController 
- (UIViewController<PSStackedViewDelegate> *)nextViewController:(UIViewController<PSStackedViewDelegate> *)viewController {
    NSParameterAssert(viewController);
    
    NSUInteger vcIndex = [self.viewControllers indexOfObject:viewController];
    UIViewController<PSStackedViewDelegate> *nextVC = nil;
    if (vcIndex + 1 < [self.viewControllers count]) {
        nextVC = [self.viewControllers objectAtIndex:vcIndex+1];
    }
    
    return nextVC;
}

// first view controller in stack
- (UIViewController<PSStackedViewDelegate> *)firstViewController {
    if ([self.viewControllers count]) {
        return [self.viewControllers objectAtIndex:0];
    }
    return nil;
}

// last view controller in stack
- (UIViewController<PSStackedViewDelegate> *)lastViewController {
    return [self.viewControllers lastObject];
}

// returns last visible view controller. this *can* be the last view controller in the stack, 
// but also one of the previous ones if the user navigates back in the stack
- (UIViewController<PSStackedViewDelegate> *)lastVisibleViewControllerCompletelyVisible:(BOOL)completely {
    __block UIViewController<PSStackedViewDelegate> *lastVisibleViewController = nil;
    
    [self.viewControllers enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        UIViewController<PSStackedViewDelegate> *currentViewController = (UIViewController<PSStackedViewDelegate> *)obj;
        if ([self isViewControllerVisible:currentViewController completely:completely]) {
            lastVisibleViewController = currentViewController;
            *stop = YES;
        }
    }];
    
    return lastVisibleViewController;
}


// at some point, dragging does not make any more sense
- (BOOL)snapPointAvailableAfterOffset:(NSInteger)offset {
    BOOL snapPointAvailableAfterOffset = YES;
    NSUInteger screenWidth = [self screenWidth];
    NSUInteger totalWidth = [self totalStackWidth];
    NSUInteger minCommonWidth = MIN(screenWidth, totalWidth);
    
    // are we at the end?
    UIViewController *lastViewController = [self lastViewController];
    if (lastViewController == [self lastVisibleViewControllerCompletelyVisible:NO]) {
        if (minCommonWidth+[self minimalLeftBorder] <= lastViewController.view.right) {
            snapPointAvailableAfterOffset = NO;
        }
    }
        
    // slow down first controller when dragged to the right
    if ([self canCollapseStack] == 0) {
        snapPointAvailableAfterOffset = NO;
    }
    
    // not using [self canExand] here, as firstVisibleIndex is set while scrolling (menu!)
    if ([self firstViewController].view.left > self.backEmptyWidth) {
        snapPointAvailableAfterOffset = NO;
    }
    
    return snapPointAvailableAfterOffset;
}

// ensures index is on rightmost position
- (void)displayViewControllerIndexOnRightMost:(NSUInteger)index animated:(BOOL)animated; {
    NSInteger indexOffset = index - self.lastVisibleIndex;
    if (indexOffset > 0) {
        [self collapseStack:indexOffset animated:animated];
    }else if(indexOffset >= 0) {
        [self expandStack:indexOffset animated:animated];
    }
}

// try to fit in as many VCs as possible
- (void)correctFirstVisibleIndex {
    
    // sanity check
    if (self.firstVisibleIndex > [self.viewControllers count] - 1) {
        self.firstVisibleIndex = [self.viewControllers count] - 1;
    }
    
    // calculate if firstVisibleIndex is reasonable, adjust if not
    // we don't allow collapsing indefinitely! (only upon available screen space)
    NSInteger screenSpaceLeft = [self screenWidth] - [self leftBorder];
    while (screenSpaceLeft > 0 && self.firstVisibleIndex > 0 && [self.viewControllers count]) {
        NSInteger lastVisibleIndex = [self lastVisibleIndex];
        
        for (NSUInteger firstIndex = self.firstVisibleIndex; firstIndex <= lastVisibleIndex; firstIndex++) {
            UIViewController *vc = [self.viewControllers objectAtIndex:firstIndex];
            screenSpaceLeft -= vc.view.width;
        }
        
        if (self.firstVisibleIndex > 0 && screenSpaceLeft >= ((UIViewController *)[self.viewControllers objectAtIndex:self.firstVisibleIndex-1]).view.width) {
            self.firstVisibleIndex -= 1;
        }
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - SVStackRootController (Public)

- (void)updateViewControllerMasks {
    // only one!
    if ([self.viewControllers count] == 1) {
        [self addMastToViewController:[self firstViewController] corners:UIRectCornerAllCorners];
    }else {
        // rounded corners on first and last controller
        [self.viewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if (idx == 0) {
                [self addMastToViewController:obj corners:UIRectCornerBottomLeft | UIRectCornerTopLeft];
            }else if(idx == [self.viewControllers count]-1) {
                [self addMastToViewController:obj corners:UIRectCornerBottomRight | UIRectCornerTopRight];                
            }else {
                [self removeMaskFromController:obj];
            }
        }];
    }
}

- (void)pushViewController:(UIViewController<PSStackedViewDelegate> *)viewController animated:(BOOL)animated; {    
    SVLog(@"pushing VC with index %d on stack: %@ (animated: %d)", [self.viewControllers count], viewController, animated);
    
    // add to view stack!
    viewController.view.frame = self.view.bounds;
    viewController.view.width = [viewController stackableMaxWidth];
    
    NSUInteger leftGap = [self totalStackWidth] + [self minimalLeftBorder];    
    viewController.view.left = leftGap;
    viewController.view.autoresizingMask = UIViewAutoresizingFlexibleHeight; // width is not flexible!
    
    [viewController viewWillAppear:animated];
    
//    UIView *containerView = [[UIView alloc] initWithFrame:viewController.view.frame];
//    containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
//    [containerView addSubview:viewController.view];
    
    //[self.view addSubview:containerView];
    [viewController viewDidAppear:animated];
        
    [viewControllers_ addObject:viewController];
    
    [self addShadowToViewController:viewController];
    [self updateViewControllerMasks];
    [self displayViewControllerIndexOnRightMost:[self.viewControllers count]-1 animated:animated];
}

- (UIViewController<PSStackedViewDelegate> *)popViewControllerAnimated:(BOOL)animated; {
    SVLog(@"popping last VC: %@ (animated:%d)", [self lastViewController], animated);
    
    UIViewController<PSStackedViewDelegate> *lastController = [self lastViewController];
    if (lastController) {        
        
        // remove from view stack!
        [lastController viewWillAppear:animated];
        [lastController.view removeFromSuperview];
        [lastController viewDidDisappear:animated];
        
        [self removeShadowFromViewController:lastController];
        [self removeMaskFromController:lastController];
        [viewControllers_ removeLastObject];
        [self updateViewControllerMasks];
        
        // realign view controllers
        [self alignStackAnimated:animated];
    }
    
    return lastController;
}


// moves the stack to a specific offset. 
- (void)moveStackWithOffset:(NSInteger)offset animated:(BOOL)animated userDragging:(BOOL)userDragging {
    SVLog(@"moving stack on %d pixels (animated:%d, decellerating:%d)", offset, animated, userDragging);
    
    if (animated) {
        [UIView beginAnimations:@"stackAnim" context:nil];
        [UIView setAnimationDuration:kSVStackAnimationDuration];
        [UIView setAnimationBeginsFromCurrentState:YES];
    }
    
    // enumerate controllers from right to left
    // scroll each controller until we begin to overlap!
    __block BOOL isTopViewController = YES;
    [self.viewControllers enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        UIViewController<PSStackedViewDelegate> *currentViewController = (UIViewController<PSStackedViewDelegate> *)obj;
        UIViewController<PSStackedViewDelegate> *leftViewController = [self previousViewController:currentViewController];
        UIViewController<PSStackedViewDelegate> *rightViewController = [self nextViewController:currentViewController];        
        NSInteger minimalLeftBorder = [self minimalLeftBorder];
        
        // we just move the top view controller
        NSInteger currentVCLeftPosition = currentViewController.view.left;
        if (isTopViewController) {
            currentVCLeftPosition += offset;
        }else {
            // make sure we're connected to the next controller!
            currentVCLeftPosition = rightViewController.view.left - currentViewController.view.width;
        }
        
        // prevent scrolling < minimal width (except for the top view controller - allow stupidness!)
        if (currentVCLeftPosition < minimalLeftBorder && (!userDragging || (userDragging && !isTopViewController))) {
            currentVCLeftPosition = minimalLeftBorder;
        }
        
        // a previous view controller is not allowed to overlap the next view controller.
        if (leftViewController && leftViewController.view.right > currentVCLeftPosition) {
            NSInteger leftVCLeftPosition = currentVCLeftPosition - leftViewController.view.width;
            if (leftVCLeftPosition < minimalLeftBorder) {
                leftVCLeftPosition = minimalLeftBorder;
            }
            leftViewController.view.left = leftVCLeftPosition;
        }
        
        currentViewController.view.left = currentVCLeftPosition;
        
        isTopViewController = NO; // there can only be one.
    }];
    
    // update firstVisibleIndex
#ifdef kSVStackedViewKitDebugEnabled
    NSUInteger oldFirstVisibleIndex = self.firstVisibleIndex;
#endif
    
    NSInteger minLeft = [self firstViewController].view.left;
    for (UIViewController *vc in self.viewControllers) {
        NSInteger vcLeft = vc.view.left;
        if (minLeft < vcLeft) {
            self.firstVisibleIndex = [self.viewControllers indexOfObject:vc]-1;
            break;
        }
    }
    
    // don't get all too excited about the new index - it may be wrong! (e.g. too high stacking)
    [self correctFirstVisibleIndex];
    
#ifdef kSVStackedViewKitDebugEnabled
    if (oldFirstVisibleIndex != self.firstVisibleIndex) {
        SVLog(@"updating firstVisibleIndex from %d to %d", oldFirstVisibleIndex, self.firstVisibleIndex);
    }
#endif
    
    if (animated) {
        [UIView commitAnimations];
    }
}

// last visible index is calculated dynamically, depending on width of VCs
- (NSInteger)lastVisibleIndex {
    NSInteger lastVisibleIndex = self.firstVisibleIndex;
    
    NSInteger screenSpaceLeft = [self screenWidth] - [self leftBorder];
    while (screenSpaceLeft > 0 && lastVisibleIndex < [self.viewControllers count]) {
        UIViewController *vc = [self.viewControllers objectAtIndex:lastVisibleIndex];
        screenSpaceLeft -= vc.view.width;
        
        if (screenSpaceLeft >= 0) {
            lastVisibleIndex++;
        }        
    }
    
    lastVisibleIndex--; // compensate for last failure
    
    return lastVisibleIndex;
}


- (void)alignStackAnimated:(BOOL)animated; {
    [self correctFirstVisibleIndex];
    
    if (animated) {
        [UIView beginAnimations:@"stackAnim" context:nil];
        [UIView setAnimationDuration:kSVStackAnimationDuration];
        [UIView setAnimationBeginsFromCurrentState:YES];
    }
    
    // iterate over all view controllers and snap them to their correct positions
    [self.viewControllers enumerateObjectsWithOptions:0 usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        UIViewController<PSStackedViewDelegate> *currentViewController = (UIViewController<PSStackedViewDelegate> *)obj;
        UIViewController<PSStackedViewDelegate> *leftViewController = [self previousViewController:currentViewController];
        
        if (idx <= self.firstVisibleIndex) {
            // collapsed = snap to menu
            currentViewController.view.left = [self leftBorder];
        }else {
            // connect vc to left vc's right!
            currentViewController.view.left = leftViewController.view.right;
        }
    }];
    
    if (animated) {
        [UIView commitAnimations];
    }
}


- (NSUInteger)canCollapseStack; {
    NSUInteger steps = [self.viewControllers count] - self.firstVisibleIndex - 1;
    
    if (self.lastVisibleIndex == [self.viewControllers count]-1) {
        //SVLog(@"complete stack is displayed - aborting.");
        steps = 0;
    }else if (self.firstVisibleIndex + steps > [self.viewControllers count]-1) {
        steps = [self.viewControllers count] - self.firstVisibleIndex - 1;
        //SVLog(@"too much steps, adjusting to %d", steps);
    }
    
    return steps;
}


- (NSUInteger)collapseStack:(NSUInteger)steps animated:(BOOL)animated; { // (<--- increases firstVisibleIndex)
    [self correctFirstVisibleIndex];
    SVLog(@"collapsing stack with %d steps [%d-%d]", steps, self.firstVisibleIndex, self.lastVisibleIndex);
    
    // sliding menu is it's own step
    if([self isMenuCollapsable] && self.isShowingFullMenu) {
        self.showingFullMenu = NO;
        steps--;
    }
    
    NSUInteger maxCollapseStackCount = [self canCollapseStack];
    if (steps > maxCollapseStackCount) {
        steps = maxCollapseStackCount;
    }
        
    // hide older VCs, show newer ones
    self.firstVisibleIndex += steps;
    
    [self alignStackAnimated:animated];
    return steps;
}

- (NSUInteger)canExpandStack; {
    NSUInteger steps = self.firstVisibleIndex;
    
    // sanity check
    if (steps >= [self.viewControllers count]-1) {
        SVLog(@"Warning: firstVisibleIndex is higher than viewController count!");
        steps = [self.viewControllers count]-1;
    }
    
    return steps;
}

- (NSUInteger)expandStack:(NSUInteger)steps animated:(BOOL)animated; { // (---> decreases firstVisibleIndex)
    [self correctFirstVisibleIndex];
    SVLog(@"expanding stack with %d steps [%d-%d]", steps, self.firstVisibleIndex, self.lastVisibleIndex);

    if (self.firstVisibleIndex < steps) {
        steps = self.firstVisibleIndex;
        SVLog(@"Warn! steps are too high! adjusting to %d", steps);
    }
    
    NSUInteger maxExpandStackCount = [self canExpandStack];
    if (steps > maxExpandStackCount) {
        steps = maxExpandStackCount;
    }
    
    if (steps == 0 && self.firstVisibleIndex == 0) {
        self.showingFullMenu = YES;
    }else {
        // show older VCs!
        self.firstVisibleIndex -= steps;
    }
    
    [self alignStackAnimated:animated];
    return steps; 
}

- (void)handlePanFrom:(UIPanGestureRecognizer *)recognizer {
    CGPoint translatedPoint = [recognizer translationInView:self.view];
    
    NSInteger offset = translatedPoint.x - lastDragOffset_;
    
    // if the move does not make sense (no snapping region), only use 1/2 offset
    BOOL snapPointAvailable = [self snapPointAvailableAfterOffset:offset];
    if (!snapPointAvailable) {
        SVLog(@"offset dividing/2 in effect");
        
        // we only want to move full pixels - but if we drag slowly, 1 get divided to zero.
        // so only omit every second event
        if (offset == 1) {
            if(!lastDragOffset_) {
                lastDragOffset_ = YES;
                offset = 0;
            }else {
                lastDragOffset_ = NO;
            }
        }else {
            offset = offset/2;            
        }
    }
    [self moveStackWithOffset:offset animated:NO userDragging:YES];
    
    // set up designated drag destination
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        if (offset > 0) {
            lastDragOption_ = SVSnapOptionRight;
        }else {
            lastDragOption_ = SVSnapOptionLeft;
        }
    }else {
        // if there's a continuous drag in one direction, keep designation - else use nearest to snap.
        if ((lastDragOption_ == SVSnapOptionLeft && offset > 0) || (lastDragOption_ == SVSnapOptionRight && offset < 0)) {
            lastDragOption_ = SVSnapOptionNearest;
        }
    }
    
    // save last point to calculate new offset
    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged) {
        lastDragOffset_ = translatedPoint.x;
    }else {
        lastDragOffset_ = 0;
    }
    
    // perform snapping after gesture ended
    BOOL gestureEnded = recognizer.state == UIGestureRecognizerStateEnded;
    if (gestureEnded) {
        
        if (lastDragOption_ == SVSnapOptionRight) {
            
            // with manually snapping right, the index gets changed. revert that.
            if (self.firstVisibleIndex+1 < [self.viewControllers count]) {
                self.firstVisibleIndex++;
                
                // special condition: we dragged menu to border
                if ([self firstViewController].view.left > [self minimalLeftBorder]) {
                    self.firstVisibleIndex--;
                }
            }
            
            [self expandStack:1 animated:YES];
        }else if(lastDragOption_ == SVSnapOptionLeft) {
            [self collapseStack:1 animated:YES];
        }else {
            [self alignStackAnimated:YES];
        }
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)viewDidLoad {
    [super viewDidLoad];
    
    for (UIViewController *controller in self.viewControllers) {
        // forces view loading, calls viewDidLoad via system
        UIView *controllerView = controller.view;
#pragma unused(controllerView)
        //        [controller viewDidLoad];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    for (UIViewController *controller in self.viewControllers) {
        [controller viewWillAppear:animated];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    for (UIViewController *controller in self.viewControllers) {
        [controller viewWillDisappear:animated];
    }
    
    [super viewWillDisappear:animated];
}

- (void)viewDidUnload {
    for (UIViewController *controller in self.viewControllers) {
        [controller viewDidUnload];
    }
    
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES; // we're on an iPad.
}

// event relay
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration; {
    for (UIViewController *controller in self.viewControllers) {
        [controller willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    }
    
    lastVisibleIndexBeforeRotation_ = self.lastVisibleIndex;
}

// event relay
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation; {
    for (UIViewController *controller in self.viewControllers) {
        [controller didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    }    
    
    // enlarge/shrinken stack
    [self displayViewControllerIndexOnRightMost:lastVisibleIndexBeforeRotation_ animated:YES];
}

// event relay
- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration; {
    for (UIViewController *controller in self.viewControllers) {
        [controller willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    }
    [self updateViewControllerMasks];
}

@end