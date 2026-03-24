// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#import "MyGLKViewController.h"
#import <QuartzCore/QuartzCore.h>

#include "vtkActor.h"
#include "vtkColorTransferFunction.h"
#include "vtkCommand.h"
#include "vtkImageData.h"
#include "vtkInteractorStyleMultiTouchCamera.h"
#include "vtkIOSRenderWindow.h"
#include "vtkIOSRenderWindowInteractor.h"
#include "vtkNew.h"
#include "vtkObjectFactory.h"
#include "vtkOpenGLCamera.h"
#include "vtkOpenGLGPUVolumeRayCastMapper.h"
#include "vtkOpenGLProperty.h"
#include "vtkOpenGLRayCastImageDisplayHelper.h"
#include "vtkOpenGLRenderer.h"
#include "vtkOpenGLShaderProperty.h"
#include "vtkOpenGLTexture.h"
#include "vtkOpenGLUniforms.h"
#include "vtkPiecewiseFunction.h"
#include "vtkPointData.h"
#include "vtkProperty.h"
#include "vtkRenderer.h"
#include "vtkSmartPointer.h"
#include "vtkTexture.h"
#include "vtkVersion.h"
#include "vtkVolume.h"
#include "vtkVolumeProperty.h"
#include "vtkXMLImageDataReader.h"

@interface MyGLKViewController () <UIDocumentPickerDelegate>
{
  vtkSmartPointer<vtkIOSRenderWindow> _renderWindowOwner;
  vtkSmartPointer<vtkIOSRenderWindowInteractor> _interactorOwner;
  vtkSmartPointer<vtkOpenGLRenderer> _renderer;
  vtkSmartPointer<vtkOpenGLGPUVolumeRayCastMapper> _volumeMapper;
  vtkSmartPointer<vtkVolumeProperty> _volumeProperty;
  vtkSmartPointer<vtkVolume> _volume;
  CADisplayLink* _displayLink;
  CGSize _lastViewportSize;
  BOOL _appIsActive;
  BOOL _didAttachWindow;
  BOOL _didInitInteractor;
  BOOL _didPresentDocumentPicker;
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
- (void)presentVolumeFilePicker;
- (void)loadVolumeFromURL:(NSURL*)url;

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

  _volumeMapper = vtkSmartPointer<vtkOpenGLGPUVolumeRayCastMapper>::New();
  _volumeMapper->SetAutoAdjustSampleDistances(1);
  _volumeMapper->SetSampleDistance(0.5);

  _volumeProperty = vtkSmartPointer<vtkVolumeProperty>::New();
  _volumeProperty->SetShade(1);
  _volumeProperty->SetInterpolationTypeToLinear();

  vtkNew<vtkColorTransferFunction> ctf;
  ctf->AddRGBPoint(0, 0, 0, 0);
  ctf->AddRGBPoint(255 * 67.0106 / 3150.0, 0.54902, 0.25098, 0.14902);
  ctf->AddRGBPoint(255 * 251.105 / 3150.0, 0.882353, 0.603922, 0.290196);
  ctf->AddRGBPoint(255 * 439.291 / 3150.0, 1, 0.937033, 0.954531);
  ctf->AddRGBPoint(255 * 3071 / 3150.0, 0.827451, 0.658824, 1);

  double tweak = 80.0;
  vtkNew<vtkPiecewiseFunction> pwf;
  pwf->AddPoint(0, 0);
  pwf->AddPoint(255 * (67.0106 + tweak) / 3150.0, 0);
  pwf->AddPoint(255 * (251.105 + tweak) / 3150.0, 0.3);
  pwf->AddPoint(255 * (439.291 + tweak) / 3150.0, 0.5);
  pwf->AddPoint(255 * 3071 / 3150.0, 0.616071);

  _volumeProperty->SetColor(ctf.GetPointer());
  _volumeProperty->SetScalarOpacity(pwf.GetPointer());

  _volume = vtkSmartPointer<vtkVolume>::New();
  _volume->SetMapper(_volumeMapper);
  _volume->SetProperty(_volumeProperty);

  _renderer->SetBackground2(0.2, 0.3, 0.4);
  _renderer->SetBackground(0.1, 0.1, 0.1);
  _renderer->GradientBackgroundOn();
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
  if (!_didPresentDocumentPicker)
  {
    _didPresentDocumentPicker = YES;
    [self presentVolumeFilePicker];
  }
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
                                   strongSelf->_renderer->GetActiveCamera()->Zoom(1.4);
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
  BOOL sizeChanged = (_lastViewportSize.width != width || _lastViewportSize.height != height);

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
    _renderer->GetActiveCamera()->Zoom(1.4);
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

- (void)presentVolumeFilePicker
{
  UIDocumentPickerViewController* picker =
    [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[
      @"public.item",
      @"public.data",
      @"public.content",
      @"public.xml"
    ]
                                                           inMode:UIDocumentPickerModeOpen];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  picker.modalPresentationStyle = UIModalPresentationFormSheet;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)loadVolumeFromURL:(NSURL*)url
{
  if (!url || !_renderer || !_volumeMapper || !_volume)
  {
    return;
  }

  BOOL didAccess = [url startAccessingSecurityScopedResource];
  vtkNew<vtkXMLImageDataReader> reader;
  reader->SetFileName(url.fileSystemRepresentation);
  reader->Update();
  if (didAccess)
  {
    [url stopAccessingSecurityScopedResource];
  }

  vtkImageData* output = reader->GetOutput();
  if (!output || !output->GetPointData() || !output->GetPointData()->GetScalars())
  {
    NSLog(@"Failed to load VTI volume from %@", url.path);
    return;
  }

  _volumeMapper->SetInputConnection(reader->GetOutputPort());
  if (!_renderer->HasViewProp(_volume))
  {
    _renderer->AddVolume(_volume);
  }
  _renderer->ResetCamera();
  _renderer->GetActiveCamera()->Zoom(1.4);
  _renderer->ResetCameraClippingRange();
  [self renderFrame];
}

- (void)tearDownGL
{
  _didInitInteractor = NO;
  _didAttachWindow = NO;
  _lastViewportSize = CGSizeZero;
  _volume = nullptr;
  _volumeProperty = nullptr;
  _volumeMapper = nullptr;
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

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
  (void)controller;
  NSURL* selectedURL = urls.firstObject;
  [self loadVolumeFromURL:selectedURL];
}

@end
