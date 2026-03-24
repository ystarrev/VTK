// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#import "MyGLKViewController.h"
#import <QuartzCore/QuartzCore.h>

#include "vtkActor.h"
#include "vtkCommand.h"
#include "vtkInteractorStyleMultiTouchCamera.h"
#include "vtkIOSRenderWindow.h"
#include "vtkIOSRenderWindowInteractor.h"
#include "vtkMath.h"
#include "vtkNew.h"
#include "vtkObjectFactory.h"
#include "vtkOpenGLCamera.h"
#include "vtkOpenGLProperty.h"
#include "vtkOpenGLRayCastImageDisplayHelper.h"
#include "vtkOpenGLRenderer.h"
#include "vtkOpenGLShaderProperty.h"
#include "vtkOpenGLTexture.h"
#include "vtkOpenGLUniforms.h"
#include "vtkParametricBoy.h"
#include "vtkParametricConicSpiral.h"
#include "vtkParametricCrossCap.h"
#include "vtkParametricDini.h"
#include "vtkParametricEllipsoid.h"
#include "vtkParametricEnneper.h"
#include "vtkParametricFigure8Klein.h"
#include "vtkParametricFunction.h"
#include "vtkParametricFunctionSource.h"
#include "vtkParametricKlein.h"
#include "vtkParametricMobius.h"
#include "vtkParametricRandomHills.h"
#include "vtkParametricRoman.h"
#include "vtkParametricSpline.h"
#include "vtkParametricSuperEllipsoid.h"
#include "vtkParametricSuperToroid.h"
#include "vtkParametricTorus.h"
#include "vtkPoints.h"
#include "vtkPolyDataMapper.h"
#include "vtkProperty.h"
#include "vtkRenderer.h"
#include "vtkSmartPointer.h"
#include "vtkTexture.h"
#include "vtkVersion.h"

#include <algorithm>
#include <deque>
#include <vector>

@interface MyGLKViewController ()
{
  std::deque<vtkSmartPointer<vtkParametricFunction>> _parametricObjects;
  std::vector<vtkSmartPointer<vtkRenderer>> _renderers;
  vtkSmartPointer<vtkIOSRenderWindow> _renderWindowOwner;
  vtkSmartPointer<vtkIOSRenderWindowInteractor> _interactorOwner;
  CADisplayLink* _displayLink;
  CGSize _lastViewportSize;
  BOOL _appIsActive;
  BOOL _didAttachWindow;
  BOOL _didInitInteractor;
}

- (void)attachRenderWindowIfNeeded;
- (void)ensureInteractorInitialized;
- (void)updateRenderWindowFrame;
- (void)renderFrame;
- (void)startDisplayLinkIfNeeded;
- (void)stopDisplayLink;
- (void)tearDownGL;
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

- (vtkIOSRenderWindow*)getVTKRenderWindow
{
  return _myVTKRenderWindow;
}

- (void)setVTKRenderWindow:(vtkIOSRenderWindow*)theVTKRenderWindow
{
  _myVTKRenderWindow = theVTKRenderWindow;
}

- (vtkIOSRenderWindowInteractor*)getInteractor
{
  return _interactorOwner;
}

- (void)initializeParametricObjects
{
  _parametricObjects.clear();
  _parametricObjects.push_back(vtkSmartPointer<vtkParametricBoy>::New());
  _parametricObjects.push_back(vtkSmartPointer<vtkParametricConicSpiral>::New());
  _parametricObjects.push_back(vtkSmartPointer<vtkParametricCrossCap>::New());
  _parametricObjects.push_back(vtkSmartPointer<vtkParametricDini>::New());

  auto ellipsoid = vtkSmartPointer<vtkParametricEllipsoid>::New();
  ellipsoid->SetXRadius(0.5);
  ellipsoid->SetYRadius(2.0);
  _parametricObjects.push_back(ellipsoid);

  _parametricObjects.push_back(vtkSmartPointer<vtkParametricEnneper>::New());
  _parametricObjects.push_back(vtkSmartPointer<vtkParametricFigure8Klein>::New());
  _parametricObjects.push_back(vtkSmartPointer<vtkParametricKlein>::New());

  auto mobius = vtkSmartPointer<vtkParametricMobius>::New();
  mobius->SetRadius(2.0);
  mobius->SetMinimumV(-0.5);
  mobius->SetMaximumV(0.5);
  _parametricObjects.push_back(mobius);

  auto randomHills = vtkSmartPointer<vtkParametricRandomHills>::New();
  randomHills->AllowRandomGenerationOff();
  _parametricObjects.push_back(randomHills);

  _parametricObjects.push_back(vtkSmartPointer<vtkParametricRoman>::New());

  auto superEllipsoid = vtkSmartPointer<vtkParametricSuperEllipsoid>::New();
  superEllipsoid->SetN1(0.5);
  superEllipsoid->SetN2(0.1);
  _parametricObjects.push_back(superEllipsoid);

  auto superToroid = vtkSmartPointer<vtkParametricSuperToroid>::New();
  superToroid->SetN1(0.2);
  superToroid->SetN2(3.0);
  _parametricObjects.push_back(superToroid);

  _parametricObjects.push_back(vtkSmartPointer<vtkParametricTorus>::New());

  auto spline = vtkSmartPointer<vtkParametricSpline>::New();
  auto inputPoints = vtkSmartPointer<vtkPoints>::New();
  vtkMath::RandomSeed(8775070);
  for (int p = 0; p < 10; ++p)
  {
    inputPoints->InsertNextPoint(
      vtkMath::Random(0.0, 1.0), vtkMath::Random(0.0, 1.0), vtkMath::Random(0.0, 1.0));
  }
  spline->SetPoints(inputPoints);
  _parametricObjects.push_back(spline);
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

  [self initializeParametricObjects];

  _renderers.clear();
  std::vector<vtkSmartPointer<vtkParametricFunctionSource>> sources;
  std::vector<vtkSmartPointer<vtkPolyDataMapper>> mappers;
  std::vector<vtkSmartPointer<vtkActor>> actors;

  for (size_t i = 0; i < _parametricObjects.size(); ++i)
  {
    sources.push_back(vtkSmartPointer<vtkParametricFunctionSource>::New());
    sources[i]->SetParametricFunction(_parametricObjects[i]);
    sources[i]->Update();

    mappers.push_back(vtkSmartPointer<vtkPolyDataMapper>::New());
    mappers[i]->SetInputConnection(sources[i]->GetOutputPort());

    actors.push_back(vtkSmartPointer<vtkActor>::New());
    actors[i]->SetMapper(mappers[i]);

    _renderers.push_back(vtkSmartPointer<vtkRenderer>::New());
  }

  const unsigned int gridDimensions = 4;
  for (size_t i = _parametricObjects.size(); i < gridDimensions * gridDimensions; ++i)
  {
    _renderers.push_back(vtkSmartPointer<vtkRenderer>::New());
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

  const int rendererSize = 200;
  renderWindow->SetSize(rendererSize * gridDimensions, rendererSize * gridDimensions);

  for (int row = 0; row < static_cast<int>(gridDimensions); ++row)
  {
    for (int col = 0; col < static_cast<int>(gridDimensions); ++col)
    {
      int index = row * gridDimensions + col;
      double viewport[4] = {
        static_cast<double>(col) / gridDimensions,
        static_cast<double>(gridDimensions - (row + 1)) / gridDimensions,
        static_cast<double>(col + 1) / gridDimensions,
        static_cast<double>(gridDimensions - row) / gridDimensions
      };

      renderWindow->AddRenderer(_renderers[index]);
      _renderers[index]->SetViewport(viewport);
      _renderers[index]->SetBackground(.2, .3, .4);

      if (index >= static_cast<int>(_parametricObjects.size()))
      {
        continue;
      }

      _renderers[index]->AddActor(actors[index]);
      _renderers[index]->ResetCamera();
      _renderers[index]->GetActiveCamera()->Azimuth(30);
      _renderers[index]->GetActiveCamera()->Elevation(-30);
      _renderers[index]->GetActiveCamera()->Zoom(0.9);
      _renderers[index]->ResetCameraClippingRange();
    }
  }
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

  int width = (int)lround(container.bounds.size.width * container.contentScaleFactor);
  int height = (int)lround(container.bounds.size.height * container.contentScaleFactor);

  [self getVTKRenderWindow]->SetPosition(0, 0);
  [self getVTKRenderWindow]->SetSize(width, height);
  if (_interactorOwner)
  {
    _interactorOwner->SetSize(width, height);
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

- (void)tearDownGL
{
  _didInitInteractor = NO;
  _didAttachWindow = NO;
  _lastViewportSize = CGSizeZero;
  _parametricObjects.clear();
  _renderers.clear();
  _interactorOwner = nullptr;
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
