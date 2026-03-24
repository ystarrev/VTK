// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#import <UIKit/UIKit.h>

#ifdef __cplusplus
class vtkIOSRenderWindow;
class vtkIOSRenderWindowInteractor;
typedef vtkIOSRenderWindow* vtkIOSRenderWindowRef;
typedef vtkIOSRenderWindowInteractor* vtkIOSRenderWindowInteractorRef;
#else
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

- (vtkIOSRenderWindowRef)getVTKRenderWindow;
- (void)setVTKRenderWindow:(vtkIOSRenderWindowRef)theVTKRenderWindow;
- (vtkIOSRenderWindowInteractorRef)getInteractor;
- (void)initializeParametricObjects;
- (void)setupPipeline;

@end
