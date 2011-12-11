//
//  PSStackedViewDelegate.h
//  PSStackedView
//
//  Created by Peter Steinberger on 7/14/11.
//  Copyright 2011 Peter Steinberger. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PSStackedViewController;

@protocol PSStackedViewDelegate <NSObject>

@optional

/// viewController will be inserted
- (void)stackedView:(PSStackedViewController *)stackedView willInsertViewController:(UIViewController *)viewController;

/// viewController has been inserted
- (void)stackedView:(PSStackedViewController *)stackedView didInsertViewController:(UIViewController *)viewController;

/// viewController will be removed
- (void)stackedView:(PSStackedViewController *)stackedView willRemoveViewController:(UIViewController *)viewController;

/// viewController has been removed
- (void)stackedView:(PSStackedViewController *)stackedView didRemoveViewController:(UIViewController *)viewController;

/// viewController is now visible
- (void)stackedView:(PSStackedViewController *)stackedView isNowVisibleViewController:(UIViewController *)viewController;

/// viewController is now hidden
- (void)stackedView:(PSStackedViewController *)stackedView isNowHiddenViewController:(UIViewController *)viewController;

@end
