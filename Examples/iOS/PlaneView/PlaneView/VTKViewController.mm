// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause
#import "VTKViewController.h"

#import "vtkActor.h"
#import "vtkAutoInit.h"
#import "vtkCamera.h"
#import "vtkCommand.h"
#import "vtkDebugLeaks.h"
#import "vtkIOSRenderWindow.h"
#import "vtkIOSRenderWindowInteractor.h"
#import "vtkImageData.h"
#import "vtkInteractorStyleMultiTouchCamera.h"
#import "vtkNew.h"
#import "vtkObjectFactory.h"
#import "vtkOpenGLState.h"
#import "vtkOpenGLCamera.h"
#import "vtkOpenGLProperty.h"
#import "vtkOpenGLRayCastImageDisplayHelper.h"
#import "vtkOpenGLShaderProperty.h"
#import "vtkOpenGLTexture.h"
#import "vtkOpenGLUniforms.h"
#import "vtkOutlineFilter.h"
#import "vtkPlaneWidget.h"
#import "vtkPolyData.h"
#import "vtkPolyDataMapper.h"
#import "vtkProbeFilter.h"
#import "vtkRTAnalyticSource.h"
#import "vtkRenderer.h"
#import "vtkStructuredGridOutlineFilter.h"
#import "vtkUnstructuredGrid.h"
#import "vtkVersion.h"
#import "vtkXMLImageDataReader.h"
#import "vtkXMLRectilinearGridReader.h"
#import "vtkXMLStructuredGridReader.h"
#import "vtkXMLUnstructuredGridReader.h"

#include <cmath>

VTK_MODULE_INIT(vtkRenderingOpenGL2);

// This does the actual work: updates the probe.
// Callback for the interaction
class vtkTPWCallback : public vtkCommand
{
public:
  static vtkTPWCallback* New() { return new vtkTPWCallback; }
  virtual void Execute(vtkObject* caller, unsigned long, void*)
  {
    vtkPlaneWidget* planeWidget = reinterpret_cast<vtkPlaneWidget*>(caller);
    planeWidget->GetPolyData(this->PolyData);
    this->Actor->VisibilityOn();
  }
  vtkTPWCallback()
    : PolyData(0)
    , Actor(0)
  {
  }
  vtkPolyData* PolyData;
  vtkActor* Actor;
};

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

@interface VTKViewController ()
{
  BOOL _appIsActive;
  BOOL _didAttachWindow;
  CGSize _lastViewportSize;
  CADisplayLink* _displayLink;
}

- (void)attachRenderWindowIfNeeded;
- (void)renderFrame;
- (void)startDisplayLinkIfNeeded;
- (void)stopDisplayLink;
- (void)updateCameraForViewportChange;
- (void)tearDownGL;

@end

@implementation VTKViewController

- (void)setProbeEnabled:(bool)val
{
  self->PlaneWidget->SetEnabled(val ? 1 : 0);
}

- (bool)getProbeEnabled
{
  return (self->PlaneWidget->GetEnabled() ? true : false);
}

//----------------------------------------------------------------------------
- (vtkIOSRenderWindowInteractor*)getInteractor
{
  return self->Interactor;
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

  self->RenderWindow = vtkIOSRenderWindow::New();
  self->RenderWindow->SetMultiSamples(0);
  self->RenderWindow->SetStencilCapable(0);
  self->RenderWindow->SetAlphaBitPlanes(0);
  self->Renderer = vtkRenderer::New();
  self->RenderWindow->AddRenderer(self->Renderer);

  // this example uses VTK's built in interaction but you could choose
  // to use your own instead.
  self->Interactor = vtkIOSRenderWindowInteractor::New();
  self->Interactor->SetRenderWindow(self->RenderWindow);
  self->Interactor->SetUseGestureRecognizers(1);

  vtkInteractorStyleMultiTouchCamera* ismt = vtkInteractorStyleMultiTouchCamera::New();
  self->Interactor->SetInteractorStyle(ismt);
  ismt->Delete();

  vtkNew<vtkPolyData> plane;
  vtkNew<vtkRTAnalyticSource> wavelet;
  wavelet->Update();

  self->Probe = vtkProbeFilter::New();
  self->Probe->SetInputData(plane.Get());
  self->Probe->SetSourceData(wavelet->GetOutput());

  self->ProbeMapper = vtkPolyDataMapper::New();
  self->ProbeMapper->SetInputConnection(self->Probe->GetOutputPort());
  double tmp[2];
  wavelet->GetOutput()->GetScalarRange(tmp);
  self->ProbeMapper->SetScalarRange(tmp[0], tmp[1]);

  vtkNew<vtkActor> probeActor;
  probeActor->SetMapper(self->ProbeMapper);
  probeActor->VisibilityOff();

  // An outline is shown for context.
  vtkNew<vtkOutlineFilter> outline;
  outline->SetInputData(wavelet->GetOutput());

  self->OutlineMapper = vtkPolyDataMapper::New();
  self->OutlineMapper->SetInputConnection(outline->GetOutputPort());

  vtkNew<vtkActor> outlineActor;
  outlineActor->SetMapper(self->OutlineMapper);

  // The SetInteractor method is how 3D widgets are associated with the render
  // window interactor. Internally, SetInteractor sets up a bunch of callbacks
  // using the Command/Observer mechanism (AddObserver()).
  self->PlaneCallback = vtkTPWCallback::New();
  self->PlaneCallback->PolyData = plane.Get();
  self->PlaneCallback->Actor = probeActor.Get();

  // The plane widget is used probe the dataset.
  vtkNew<vtkPlaneWidget> planeWidget;
  planeWidget->SetInteractor(self->Interactor);
  planeWidget->SetDefaultRenderer(self->Renderer);
  planeWidget->SetInputData(wavelet->GetOutput());
  planeWidget->NormalToXAxisOn();
  planeWidget->SetResolution(30);
  planeWidget->SetHandleSize(0.07);
  planeWidget->SetRepresentationToOutline();
  planeWidget->PlaceWidget();
  planeWidget->AddObserver(vtkCommand::InteractionEvent, self->PlaneCallback);
  planeWidget->On();
  self->PlaneWidget = planeWidget.Get();
  self->PlaneCallback->Execute(self->PlaneWidget, 0, NULL);
  planeWidget->Register(0);

  self->Renderer->AddActor(outlineActor.Get());
  self->Renderer->AddActor(probeActor.Get());
  self->Renderer->SetBackground(0.3, 0.5, 0.4);
}

- (void)setNewDataFile:(NSURL*)url
{
  vtkXMLDataReader* reader = NULL;
  vtkPolyDataAlgorithm* outline = NULL;

  // setup the reader and outline filter based
  // on data type
  if ([url.pathExtension isEqual:@"vtu"])
  {
    reader = vtkXMLUnstructuredGridReader::New();
    outline = vtkOutlineFilter::New();
  }
  if ([url.pathExtension isEqual:@"vts"])
  {
    reader = vtkXMLStructuredGridReader::New();
    outline = vtkStructuredGridOutlineFilter::New();
  }
  if ([url.pathExtension isEqual:@"vtr"])
  {
    reader = vtkXMLRectilinearGridReader::New();
    outline = vtkOutlineFilter::New();
  }
  if ([url.pathExtension isEqual:@"vti"])
  {
    reader = vtkXMLImageDataReader::New();
    outline = vtkOutlineFilter::New();
  }

  if (!reader || !outline)
  {
    return;
  }

  reader->SetFileName([url.path cStringUsingEncoding:NSASCIIStringEncoding]);
  reader->Update();
  self->Probe->SetSourceData(reader->GetOutputDataObject(0));
  double tmp[2];
  vtkDataSet* ds = vtkDataSet::SafeDownCast(reader->GetOutputDataObject(0));
  ds->GetScalarRange(tmp);
  self->ProbeMapper->SetScalarRange(tmp[0], tmp[1]);
  outline->SetInputData(ds);
  self->OutlineMapper->SetInputConnection(outline->GetOutputPort(0));
  self->PlaneWidget->SetInputData(ds);
  self->PlaneWidget->PlaceWidget(ds->GetBounds());

  self->PlaneCallback->Execute(self->PlaneWidget, 0, NULL);

  self->Renderer->ResetCamera();
  self->RenderWindow->Render();
  self->PlaneWidget->PlaceWidget(ds->GetBounds());
  self->RenderWindow->Render();
  reader->Delete();
  outline->Delete();
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  _appIsActive = ([UIApplication sharedApplication].applicationState == UIApplicationStateActive);
  _lastViewportSize = CGSizeZero;

  self.view.multipleTouchEnabled = YES;
  self.view.backgroundColor = [UIColor blackColor];

  UITapGestureRecognizer* tapRecognizer =
    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
  tapRecognizer.numberOfTapsRequired = 2;
  tapRecognizer.cancelsTouchesInView = NO;
  tapRecognizer.delaysTouchesBegan = NO;
  tapRecognizer.delaysTouchesEnded = NO;
  [self.view addGestureRecognizer:tapRecognizer];

  // setup the vis pipeline
  [self setupPipeline];

  [self attachRenderWindowIfNeeded];
  [self resizeView];

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

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self stopDisplayLink];
  [self tearDownGL];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];

  if ([self isViewLoaded] && ([[self view] window] == nil))
  {
    self.view = nil;
    [self stopDisplayLink];
    [self tearDownGL];
  }
}

- (void)tearDownGL
{
  if (self->PlaneWidget)
  {
    self->PlaneWidget->Off();
    self->PlaneWidget->Delete();
    self->PlaneWidget = nullptr;
  }
  if (self->PlaneCallback)
  {
    self->PlaneCallback->Delete();
    self->PlaneCallback = nullptr;
  }
  if (self->ProbeMapper)
  {
    self->ProbeMapper->Delete();
    self->ProbeMapper = nullptr;
  }
  if (self->OutlineMapper)
  {
    self->OutlineMapper->Delete();
    self->OutlineMapper = nullptr;
  }
  if (self->Probe)
  {
    self->Probe->Delete();
    self->Probe = nullptr;
  }
  if (self->Renderer)
  {
    self->Renderer->Delete();
    self->Renderer = nullptr;
  }
  if (self->Interactor)
  {
    self->Interactor->Delete();
    self->Interactor = nullptr;
  }
  if (self->RenderWindow)
  {
    self->RenderWindow->Delete();
    self->RenderWindow = nullptr;
  }
  _didAttachWindow = NO;
  _lastViewportSize = CGSizeZero;
}

- (void)attachRenderWindowIfNeeded
{
  if (_didAttachWindow || !self->RenderWindow || !self.view)
  {
    return;
  }

  self->RenderWindow->SetParentId((__bridge void*)self.view);
  self->RenderWindow->Initialize();
  (void)self->RenderWindow->GetWindowId();

  if (self->Interactor)
  {
    self->Interactor->Initialize();
    self->Interactor->Enable();
  }

  if (self->PlaneWidget)
  {
    self->PlaneWidget->SetInteractor(self->Interactor);
    self->PlaneWidget->SetDefaultRenderer(self->Renderer);
    self->PlaneWidget->On();
  }

  _didAttachWindow = YES;
}

- (void)resizeView
{
  if (!self->RenderWindow)
  {
    return;
  }

  [self attachRenderWindowIfNeeded];

  double scale = self.view.contentScaleFactor;
  const int width = (int)lround(self.view.bounds.size.width * scale);
  const int height = (int)lround(self.view.bounds.size.height * scale);
  const BOOL sizeChanged = (_lastViewportSize.width != width || _lastViewportSize.height != height);

  self->RenderWindow->SetSize(width, height);
  if (self->Interactor)
  {
    self->Interactor->SetSize(width, height);
  }
  _lastViewportSize = CGSizeMake(width, height);

  if (sizeChanged)
  {
    [self updateCameraForViewportChange];
  }

  (void)self->RenderWindow->GetWindowId();
}

- (void)viewWillLayoutSubviews
{
  [super viewWillLayoutSubviews];
  [self resizeView];
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  [self startDisplayLinkIfNeeded];
  [self resizeView];
  [self renderFrame];
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
  [self stopDisplayLink];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  (void)size;

  __weak typeof(self) weakSelf = self;
  [coordinator animateAlongsideTransition:nil
                               completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
                                 VTKViewController* strongSelf = weakSelf;
                                 if (!strongSelf)
                                 {
                                   return;
                                 }
                                 [strongSelf.view layoutIfNeeded];
                                 [strongSelf resizeView];
                                 [strongSelf updateCameraForViewportChange];
                                 [strongSelf renderFrame];
                               }];
}

- (void)renderFrame
{
  if (!_appIsActive || !self.view.window || !self->RenderWindow)
  {
    return;
  }

  [self attachRenderWindowIfNeeded];
  [self resizeView];
  self->RenderWindow->Render();
}

- (void)startDisplayLinkIfNeeded
{
  if (_displayLink || !_appIsActive || !self.view.window)
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

- (void)updateCameraForViewportChange
{
  if (!self->Renderer)
  {
    return;
  }

  self->Renderer->ResetCamera();
  self->Renderer->ResetCameraClippingRange();
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
  [self startDisplayLinkIfNeeded];
  [self resizeView];
  [self updateCameraForViewportChange];
  [self renderFrame];
}

- (void)handleTap:(UITapGestureRecognizer*)sender
{
  if (sender.state == UIGestureRecognizerStateEnded)
  {
    vtkIOSRenderWindowInteractor* interactor = [self getInteractor];
    if (!interactor)
    {
      return;
    }
    self->Renderer->ResetCamera();
    [self renderFrame];
  }
}

@end
