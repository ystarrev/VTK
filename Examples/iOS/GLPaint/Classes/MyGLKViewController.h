// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#import <UIKit/UIKit.h>

// Note: This file should be includable by both pure Objective-C and Objective-C++ source files.
// To achieve this, we use the neat technique below:
#ifdef __cplusplus
// Forward declarations
class vtkIOSRenderWindow;
class vtkIOSRenderWindowInteractor;

// Type declarations
typedef vtkIOSRenderWindow* vtkIOSRenderWindowRef;
typedef vtkIOSRenderWindowInteractor* vtkIOSRenderWindowInteractorRef;
#else
// Type declarations
typedef void* vtkIOSRenderWindowRef;
typedef void* vtkIOSRenderWindowInteractorRef;
#endif

@interface MyGLKViewController : UIViewController
{
@private
  vtkIOSRenderWindowRef _myVTKRenderWindow;
}

@property (nonatomic, strong) UIWindow* window;
@property (nonatomic, weak) IBOutlet UIView* vtkContainerView;
@property (nonatomic, weak) IBOutlet UISlider* coneSizeSlider;

- (vtkIOSRenderWindowRef)getVTKRenderWindow;
- (void)setVTKRenderWindow:(vtkIOSRenderWindowRef)theVTKRenderWindow;

- (vtkIOSRenderWindowInteractorRef)getInteractor;

- (void)setupPipeline;
- (IBAction)coneSizeSliderChanged:(id)sender;

@end
