// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause
#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application
  didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
  (void)application;
  (void)launchOptions;
  return YES;
}

- (UISceneConfiguration*)application:(UIApplication*)application
configurationForConnectingSceneSession:(UISceneSession*)connectingSceneSession
                                 options:(UISceneConnectionOptions*)options API_AVAILABLE(ios(13.0))
{
  (void)application;
  (void)connectingSceneSession;
  (void)options;
  UISceneConfiguration* config = [[UISceneConfiguration alloc]
    initWithName:@"Default Configuration"
      sessionRole:UIWindowSceneSessionRoleApplication];
  config.delegateClass = NSClassFromString(@"SceneDelegate");
  return config;
}

@end
