// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause
//
//  VTKView.m
//
//  Created by Alexis Girault on 4/3/17.
//

#import "VTKView.h"

@implementation VTKView

- (void)displayCoordinates:(int*)coordinates ofTouch:(CGPoint)touchPoint scale:(CGFloat)scale height:(CGFloat)height
{
  coordinates[0] = (int)lround(scale * touchPoint.x);
  coordinates[1] = (int)lround(height - scale * touchPoint.y);
}

- (void)normalizedCoordinates:(double*)coordinates
                      ofTouch:(CGPoint)touch
                        scale:(CGFloat)scale
                        width:(CGFloat)width
                       height:(CGFloat)height
{
  int display[2] = { 0 };
  [self displayCoordinates:display ofTouch:touch scale:scale height:height];
  coordinates[0] = width > 0.0 ? (double)display[0] / width : 0.0;
  coordinates[1] = height > 0.0 ? (double)display[1] / height : 0.0;
}

@end
