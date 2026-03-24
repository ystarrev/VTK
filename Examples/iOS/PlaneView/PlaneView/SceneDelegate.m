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

  UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
  UIViewController* rootViewController = [storyboard instantiateInitialViewController];
  self.window.rootViewController = rootViewController;
  [self.window makeKeyAndVisible];
}

@end
