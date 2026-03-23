// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#import "SceneDelegate.h"

@implementation SceneDelegate

- (void)scene:(UIScene*)scene
willConnectToSession:(UISceneSession*)session
     options:(UISceneConnectionOptions*)connectionOptions
{
  (void)session;
  (void)connectionOptions;
  if (![scene isKindOfClass:[UIWindowScene class]])
  {
    return;
  }

  UIWindowScene* windowScene = (UIWindowScene*)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

  UIUserInterfaceIdiom idiom = [[UIDevice currentDevice] userInterfaceIdiom];
  NSString* storyboardName =
    (idiom == UIUserInterfaceIdiomPad) ? @"MainStoryboard_iPad" : @"MainStoryboard_iPhone";
  UIStoryboard* storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:nil];
  UIViewController* rootViewController = [storyboard instantiateInitialViewController];
  self.window.rootViewController = rootViewController;
  [self.window makeKeyAndVisible];
}

@end
