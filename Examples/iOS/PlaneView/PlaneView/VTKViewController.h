// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#import <UIKit/UIKit.h>

// Forward declarations
class vtkIOSRenderWindow;
class vtkRenderer;
class vtkIOSRenderWindowInteractor;
class vtkPlaneWidget;
class vtkPolyDataMapper;
class vtkProbeFilter;
class vtkTPWCallback;
class vtkIOSRenderWindowInteractor;

@interface VTKViewController : UIViewController
{
@private
  vtkIOSRenderWindow* RenderWindow;
  vtkIOSRenderWindowInteractor* Interactor;
  vtkPlaneWidget* PlaneWidget;
  vtkRenderer* Renderer;
  vtkProbeFilter* Probe;
  vtkPolyDataMapper* OutlineMapper;
  vtkPolyDataMapper* ProbeMapper;
  vtkTPWCallback* PlaneCallback;
}

@property (nonatomic, strong) UIWindow* window;

- (void)setProbeEnabled:(bool)val;
- (bool)getProbeEnabled;

- (void)setNewDataFile:(NSURL*)url;

- (vtkIOSRenderWindowInteractor*)getInteractor;

@end
