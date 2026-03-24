// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause
//
//  VTKView.h
//
//  Created by Alexis Girault on 4/3/17.
//

#import <UIKit/UIKit.h>

@interface VTKView : UIView

- (void)displayCoordinates:(int*)coordinates ofTouch:(CGPoint)touchPoint scale:(CGFloat)scale height:(CGFloat)height;
- (void)normalizedCoordinates:(double*)coordinates
                      ofTouch:(CGPoint)touch
                        scale:(CGFloat)scale
                        width:(CGFloat)width
                       height:(CGFloat)height;

@end
