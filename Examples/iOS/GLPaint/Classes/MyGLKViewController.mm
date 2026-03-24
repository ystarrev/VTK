// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#import "MyGLKViewController.h"
#import <QuartzCore/QuartzCore.h>

#include "vtkActor.h"
#include "vtkCamera.h"
#include "vtkCommand.h"
#include "vtkConeSource.h"
#include "vtkGlyph3D.h"
#include "vtkInteractorStyleMultiTouchCamera.h"
#include "vtkIOSRenderWindow.h"
#include "vtkIOSRenderWindowInteractor.h"
#include "vtkNew.h"
#include "vtkObject.h"
#include "vtkObjectFactory.h"
#include "vtkOpenGLCamera.h"
#include "vtkOpenGLProperty.h"
#include "vtkOpenGLRayCastImageDisplayHelper.h"
#include "vtkOpenGLRenderer.h"
#include "vtkOpenGLShaderProperty.h"
#include "vtkOpenGLTexture.h"
#include "vtkOpenGLUniforms.h"
#include "vtkPolyDataMapper.h"
#include "vtkProperty.h"
#include "vtkRenderer.h"
#include "vtkSphereSource.h"
#include "vtkTexture.h"
#include "vtkSmartPointer.h"
#include "vtkVersion.h"

#include <algorithm>

@interface MyGLKViewController ()
{
  vtkSmartPointer<vtkConeSource> _coneSource;
  vtkSmartPointer<vtkIOSRenderWindow> _renderWindowOwner;
  vtkSmartPointer<vtkIOSRenderWindowInteractor> _interactorOwner;
  vtkSmartPointer<vtkOpenGLRenderer> _renderer;
  CADisplayLink* _displayLink;
  CGSize _lastViewportSize;
  BOOL _appIsActive;
  BOOL _didAttachWindow;
  BOOL _didFrameInitialCamera;
  BOOL _didInitInteractor;
}

- (void)attachRenderWindowIfNeeded;
- (void)ensureInteractorInitialized;
- (void)updateRenderWindowFrame;
- (void)renderFrame;
- (void)startDisplayLinkIfNeeded;
- (void)stopDisplayLink;
- (void)tearDownGL;
- (void)applyConeSizeForSliderValue:(float)value;
- (void)applicationWillResignActive:(NSNotification*)notification;
- (void)applicationDidBecomeActive:(NSNotification*)notification;

@end

class VTKIOSInlineFactory : public vtkObjectFactory
{
public:
  static VTKIOSInlineFactory* New() { return new VTKIOSInlineFactory(); }
  vtkTypeMacro(VTKIOSInlineFactory, vtkObjectFactory);
  const char* GetVTKSourceVersion() VTK_FUTURE_CONST override { return VTK_SOURCE_VERSION; }
  const char* GetDescription() VTK_FUTURE_CONST override { return "VTK iOS inline factory"; }
  static vtkObject* CreateOpenGLShaderProperty() { return vtkOpenGLShaderProperty::New(); }
  static vtkObject* CreateOpenGLUniforms() { return vtkOpenGLUniforms::New(); }
  static vtkObject* CreateOpenGLCamera() { return vtkOpenGLCamera::New(); }
  static vtkObject* CreateOpenGLProperty() { return vtkOpenGLProperty::New(); }
  static vtkObject* CreateOpenGLTexture() { return vtkOpenGLTexture::New(); }
  static vtkObject* CreateOpenGLRayCastImageDisplayHelper()
  {
    return vtkOpenGLRayCastImageDisplayHelper::New();
  }
  void RegisterOverridePublic(const char* classOverride, const char* subclass,
    const char* description, int enableFlag, CreateFunction createFunction,
    vtkOverrideAttribute* attributes = nullptr)
  {
    this->RegisterOverride(classOverride, subclass, description, enableFlag, createFunction,
      attributes);
  }
};

@implementation MyGLKViewController

//----------------------------------------------------------------------------
- (vtkIOSRenderWindow*)getVTKRenderWindow
{
  return _myVTKRenderWindow;
}

//----------------------------------------------------------------------------
- (void)setVTKRenderWindow:(vtkIOSRenderWindow*)theVTKRenderWindow
{
  _myVTKRenderWindow = theVTKRenderWindow;
}

//----------------------------------------------------------------------------
- (vtkIOSRenderWindowInteractor*)getInteractor
{
  return _interactorOwner;
}

- (void)setupPipeline
{
  static bool didRegisterOverrides = false;
  if (!didRegisterOverrides)
  {
    VTKIOSInlineFactory* factory = VTKIOSInlineFactory::New();
    if (factory)
    {
      factory->RegisterOverridePublic("vtkShaderProperty", "vtkOpenGLShaderProperty",
        "OpenGL shader property override", 1, VTKIOSInlineFactory::CreateOpenGLShaderProperty);
      factory->RegisterOverridePublic("vtkUniforms", "vtkOpenGLUniforms",
        "OpenGL uniforms override", 1, VTKIOSInlineFactory::CreateOpenGLUniforms);
      factory->RegisterOverridePublic(
        "vtkCamera", "vtkOpenGLCamera", "OpenGL camera override", 1,
        VTKIOSInlineFactory::CreateOpenGLCamera);
      factory->RegisterOverridePublic(
        "vtkProperty", "vtkOpenGLProperty", "OpenGL property override", 1,
        VTKIOSInlineFactory::CreateOpenGLProperty);
      factory->RegisterOverridePublic(
        "vtkTexture", "vtkOpenGLTexture", "OpenGL texture override", 1,
        VTKIOSInlineFactory::CreateOpenGLTexture);
      factory->RegisterOverridePublic("vtkRayCastImageDisplayHelper",
        "vtkOpenGLRayCastImageDisplayHelper", "OpenGL ray cast image display helper override", 1,
        VTKIOSInlineFactory::CreateOpenGLRayCastImageDisplayHelper);
      vtkObjectFactory::RegisterFactory(factory);
      factory->Delete();
    }
    didRegisterOverrides = true;
  }

  _renderWindowOwner = vtkSmartPointer<vtkIOSRenderWindow>::New();
  vtkIOSRenderWindow* renderWindow = _renderWindowOwner.GetPointer();
  renderWindow->SetMultiSamples(0);
  renderWindow->SetStencilCapable(0);
  renderWindow->SetAlphaBitPlanes(0);
  [self setVTKRenderWindow:renderWindow];

  _interactorOwner = vtkSmartPointer<vtkIOSRenderWindowInteractor>::New();
  _interactorOwner->SetRenderWindow(renderWindow);
  _interactorOwner->SetUseGestureRecognizers(1);
  vtkNew<vtkInteractorStyleMultiTouchCamera> style;
  _interactorOwner->SetInteractorStyle(style.GetPointer());

  _renderer = vtkSmartPointer<vtkOpenGLRenderer>::New();
  renderWindow->AddRenderer(_renderer);

  vtkNew<vtkSphereSource> sphere;
  sphere->SetThetaResolution(24);
  sphere->SetPhiResolution(24);

  vtkNew<vtkPolyDataMapper> sphereMapper;
  sphereMapper->SetInputConnection(sphere->GetOutputPort());
  vtkNew<vtkActor> sphereActor;
  sphereActor->SetMapper(sphereMapper.GetPointer());
  sphereActor->GetProperty()->SetColor(0.92, 0.94, 0.96);

  _coneSource = vtkSmartPointer<vtkConeSource>::New();
  _coneSource->SetResolution(24);
  [self applyConeSizeForSliderValue:self.coneSizeSlider ? self.coneSizeSlider.value : 0.5f];

  vtkNew<vtkGlyph3D> glyph;
  glyph->SetInputConnection(sphere->GetOutputPort());
  glyph->SetSourceConnection(_coneSource->GetOutputPort());
  glyph->SetVectorModeToUseNormal();
  glyph->SetScaleModeToScaleByVector();
  glyph->SetScaleFactor(0.25);

  vtkNew<vtkPolyDataMapper> spikeMapper;
  spikeMapper->SetInputConnection(glyph->GetOutputPort());

  vtkNew<vtkActor> spikeActor;
  spikeActor->SetMapper(spikeMapper.GetPointer());
  spikeActor->GetProperty()->SetColor(0.98, 0.66, 0.22);

  _renderer->AddActor(sphereActor.GetPointer());
  _renderer->AddActor(spikeActor.GetPointer());
  _renderer->SetBackground(0.08, 0.10, 0.14);
  _renderer->ResetCamera();
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  _appIsActive = ([UIApplication sharedApplication].applicationState == UIApplicationStateActive);

  self.view.backgroundColor = [UIColor blackColor];
  UIView* container = self.vtkContainerView ?: self.view;
  container.multipleTouchEnabled = YES;

  if (self.vtkContainerView && self.vtkContainerView.superview == self.view)
  {
    self.vtkContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
      [self.vtkContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
      [self.vtkContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
      [self.vtkContainerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
      [self.vtkContainerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
  }

  [self setupPipeline];

  if (self.coneSizeSlider)
  {
    [self.coneSizeSlider addTarget:self
                            action:@selector(coneSizeSliderChanged:)
                  forControlEvents:UIControlEventValueChanged];
  }

  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center addObserver:self
             selector:@selector(applicationWillResignActive:)
                 name:UIApplicationWillResignActiveNotification
               object:nil];
  [center addObserver:self
             selector:@selector(applicationDidBecomeActive:)
                 name:UIApplicationDidBecomeActiveNotification
               object:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];

  [self attachRenderWindowIfNeeded];
  [self ensureInteractorInitialized];
  [self updateRenderWindowFrame];
  [self renderFrame];
  [self startDisplayLinkIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];

  [self stopDisplayLink];
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  [self updateRenderWindowFrame];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  (void)size;

  __weak typeof(self) weakSelf = self;
  [coordinator animateAlongsideTransition:nil
                               completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
                                 MyGLKViewController* strongSelf = weakSelf;
                                 if (!strongSelf)
                                 {
                                   return;
                                 }

                                 [strongSelf.view layoutIfNeeded];
                                 [strongSelf updateRenderWindowFrame];
                                 if (strongSelf->_renderer)
                                 {
                                   strongSelf->_renderer->ResetCamera();
                                   strongSelf->_renderer->ResetCameraClippingRange();
                                 }
                                 [strongSelf renderFrame];
                               }];
}

- (void)attachRenderWindowIfNeeded
{
  if (_didAttachWindow || ![self getVTKRenderWindow])
  {
    return;
  }

  UIView* container = self.vtkContainerView ?: self.view;
  if (!container)
  {
    return;
  }

  UIScreen* screen = nil;
  if (@available(iOS 13.0, *))
  {
    screen = container.window.windowScene.screen;
  }
  if (!screen)
  {
    screen = container.window.screen ?: self.view.window.screen;
  }

  CGFloat screenScale = screen ? screen.scale : self.view.traitCollection.displayScale;
  container.contentScaleFactor = screenScale;
  container.layer.contentsScale = screenScale;
  [self getVTKRenderWindow]->SetParentId((__bridge void*)container);
  [self updateRenderWindowFrame];
  [self getVTKRenderWindow]->Initialize();
  [self updateRenderWindowFrame];
  _didAttachWindow = YES;

  if (_renderer && !_didFrameInitialCamera)
  {
    _renderer->ResetCamera();
    _renderer->ResetCameraClippingRange();
    _didFrameInitialCamera = YES;
  }
}

- (void)ensureInteractorInitialized
{
  if (_didInitInteractor || !_interactorOwner)
  {
    return;
  }

  _interactorOwner->Initialize();
  _interactorOwner->Enable();
  _didInitInteractor = YES;
}

- (void)updateRenderWindowFrame
{
  if (![self getVTKRenderWindow])
  {
    return;
  }

  UIView* container = self.vtkContainerView ?: self.view;
  if (!container || CGRectIsEmpty(container.bounds))
  {
    return;
  }

  if (container.window)
  {
    container.contentScaleFactor = container.window.screen.scale;
    container.layer.contentsScale = container.contentScaleFactor;
  }

  const int width = (int)lround(container.bounds.size.width * container.contentScaleFactor);
  const int height = (int)lround(container.bounds.size.height * container.contentScaleFactor);
  const BOOL sizeChanged = (_lastViewportSize.width != width || _lastViewportSize.height != height);
  [self getVTKRenderWindow]->SetPosition(0, 0);
  [self getVTKRenderWindow]->SetSize(width, height);
  if (_interactorOwner)
  {
    _interactorOwner->SetSize(width, height);
  }

  if (sizeChanged && _renderer && _didAttachWindow)
  {
    _renderer->ResetCamera();
    _renderer->ResetCameraClippingRange();
  }

  _lastViewportSize = CGSizeMake(width, height);

  (void)[self getVTKRenderWindow]->GetWindowId();
}

- (void)renderFrame
{
  if (!_appIsActive || !self.isViewLoaded || !self.view.window)
  {
    return;
  }

  [self attachRenderWindowIfNeeded];
  [self ensureInteractorInitialized];
  [self updateRenderWindowFrame];
  if ([self getVTKRenderWindow])
  {
    [self getVTKRenderWindow]->Render();
  }
}

- (void)applyConeSizeForSliderValue:(float)value
{
  if (!_coneSource)
  {
    return;
  }

  const double normalizedValue = std::max(0.0f, std::min(1.0f, value));
  const double coneHeight = 0.12 + normalizedValue * 0.45;
  const double coneRadius = 0.04 + normalizedValue * 0.18;
  _coneSource->SetHeight(coneHeight);
  _coneSource->SetRadius(coneRadius);
  _coneSource->Modified();
}

- (void)startDisplayLinkIfNeeded
{
  if (_displayLink || !_appIsActive || !self.isViewLoaded || !self.view.window)
  {
    return;
  }

  _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame)];
  [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink
{
  [_displayLink invalidate];
  _displayLink = nil;
}

- (void)applicationWillResignActive:(NSNotification*)notification
{
  (void)notification;
  _appIsActive = NO;
  [self stopDisplayLink];
}

- (void)applicationDidBecomeActive:(NSNotification*)notification
{
  (void)notification;
  _appIsActive = YES;
  [self renderFrame];
  [self startDisplayLinkIfNeeded];
}

- (IBAction)coneSizeSliderChanged:(id)sender
{
  UISlider* slider = (UISlider*)sender;
  [self applyConeSizeForSliderValue:slider.value];
  [self renderFrame];
}

- (void)tearDownGL
{
  _didInitInteractor = NO;
  _didAttachWindow = NO;
  _didFrameInitialCamera = NO;
  _lastViewportSize = CGSizeZero;
  _coneSource = nullptr;
  _interactorOwner = nullptr;
  _renderer = nullptr;
  _renderWindowOwner = nullptr;
  [self setVTKRenderWindow:nullptr];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self stopDisplayLink];
  [self tearDownGL];
}

@end
