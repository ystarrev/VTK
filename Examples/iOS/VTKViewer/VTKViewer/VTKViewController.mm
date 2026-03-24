// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-FileCopyrightText: Copyright (C) Copyright © 2017 Kitware, Inc.
// SPDX-License-Identifier: BSD-3-Clause

//
//  VTKViewController.mm
//  VTKViewer
//
//  Created by Max Smolens on 6/19/17.
//

#import "VTKViewController.h"

#import "VTKLoader.h"
#import "VTKView.h"

#import <QuartzCore/QuartzCore.h>

#include "vtkActor.h"
#include "vtkCamera.h"
#include "vtkCubeSource.h"
#include "vtkInteractorStyleMultiTouchCamera.h"
#include "vtkIOSRenderWindow.h"
#include "vtkIOSRenderWindowInteractor.h"
#include "vtkNew.h"
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
#include "vtkSmartPointer.h"
#include "vtkTexture.h"
#include "vtkVersion.h"

@interface VTKViewController ()
{
  vtkSmartPointer<vtkIOSRenderWindow> _renderWindowOwner;
  vtkSmartPointer<vtkIOSRenderWindowInteractor> _interactorOwner;
  CADisplayLink* _displayLink;
  CGSize _lastDrawableSize;
  BOOL _appIsActive;
  BOOL _didAttachWindow;
  BOOL _didInitInteractor;
}

@property (strong, nonatomic) NSArray<NSURL*>* initialUrls;

// Views
@property (strong, nonatomic) IBOutlet VTKView* vtkView;
@property (strong, nonatomic) IBOutlet UIVisualEffectView* headerContainer;

// VTK
@property (nonatomic) vtkSmartPointer<vtkOpenGLRenderer> renderer;

- (void)setupRenderer;
- (void)setupGestures;
- (void)attachRenderWindowIfNeeded;
- (void)ensureInteractorInitialized;
- (void)updateRenderWindowFrame;
- (void)renderFrame;
- (void)startDisplayLinkIfNeeded;
- (void)stopDisplayLink;
- (CGSize)drawableSize;
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

@implementation VTKViewController

- (void)viewDidLoad
{
  [super viewDidLoad];

  _appIsActive = ([UIApplication sharedApplication].applicationState == UIApplicationStateActive);
  self.view.backgroundColor = [UIColor blackColor];
  self.vtkView.multipleTouchEnabled = YES;

  [self setupGestures];
  [self setupRenderer];

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
                                 VTKViewController* strongSelf = weakSelf;
                                 if (!strongSelf)
                                 {
                                   return;
                                 }

                                 [strongSelf.view layoutIfNeeded];
                                 [strongSelf updateRenderWindowFrame];
                                 if (strongSelf.renderer)
                                 {
                                   strongSelf.renderer->ResetCamera();
                                   strongSelf.renderer->ResetCameraClippingRange();
                                 }
                                 [strongSelf renderFrame];
                               }];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self stopDisplayLink];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
}

- (void)setupRenderer
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
  _renderWindowOwner->SetMultiSamples(0);
  _renderWindowOwner->SetStencilCapable(0);
  _renderWindowOwner->SetAlphaBitPlanes(0);

  _interactorOwner = vtkSmartPointer<vtkIOSRenderWindowInteractor>::New();
  _interactorOwner->SetRenderWindow(_renderWindowOwner);
  _interactorOwner->SetUseGestureRecognizers(1);
  vtkNew<vtkInteractorStyleMultiTouchCamera> style;
  _interactorOwner->SetInteractorStyle(style.GetPointer());

  self.renderer = vtkSmartPointer<vtkOpenGLRenderer>::New();
  self.renderer->SetBackground(0.4, 0.4, 0.4);
  self.renderer->SetBackground2(0.2, 0.2, 0.2);
  self.renderer->GradientBackgroundOn();
  _renderWindowOwner->AddRenderer(self.renderer);

  if (self.initialUrls)
  {
    [self loadFilesInternal:self.initialUrls];
    self.initialUrls = nil;
  }
  else
  {
    auto cubeSource = vtkSmartPointer<vtkCubeSource>::New();
    auto mapper = vtkSmartPointer<vtkPolyDataMapper>::New();
    mapper->SetInputConnection(cubeSource->GetOutputPort());
    auto actor = vtkSmartPointer<vtkActor>::New();
    actor->SetMapper(mapper);
    self.renderer->AddActor(actor);
    self.renderer->ResetCamera();
    self.renderer->ResetCameraClippingRange();
  }
}

- (void)setupGestures
{
  UITapGestureRecognizer* doubleTapRecognizer =
    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDoubleTap:)];
  doubleTapRecognizer.numberOfTapsRequired = 2;
  doubleTapRecognizer.delegate = self;
  [self.view addGestureRecognizer:doubleTapRecognizer];
}

- (void)onDoubleTap:(UITapGestureRecognizer*)sender
{
  (void)sender;
  [UIView animateWithDuration:0.2
                   animations:^{
                     BOOL show = self.headerContainer.alpha < 1.0;
                     self.headerContainer.alpha = show ? 1.0 : 0.0;
                   }];
}

- (void)attachRenderWindowIfNeeded
{
  if (_didAttachWindow || !self.vtkView.window || !_renderWindowOwner)
  {
    return;
  }

  UIScreen* screen = nil;
  if (@available(iOS 13.0, *))
  {
    screen = self.vtkView.window.windowScene.screen;
  }
  if (!screen)
  {
    screen = self.vtkView.window.screen ?: self.view.window.screen;
  }

  CGFloat screenScale = screen ? screen.scale : self.view.traitCollection.displayScale;
  self.vtkView.contentScaleFactor = screenScale;
  self.vtkView.layer.contentsScale = screenScale;

  _renderWindowOwner->SetParentId((__bridge void*)self.vtkView);
  [self updateRenderWindowFrame];
  _renderWindowOwner->Initialize();
  [self updateRenderWindowFrame];
  _didAttachWindow = YES;

  if (self.renderer)
  {
    self.renderer->ResetCamera();
    self.renderer->ResetCameraClippingRange();
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

- (CGSize)drawableSize
{
  if (!self.vtkView)
  {
    return CGSizeZero;
  }

  CGFloat scale = self.vtkView.contentScaleFactor > 0.0 ? self.vtkView.contentScaleFactor : UIScreen.mainScreen.scale;
  return CGSizeMake(lround(self.vtkView.bounds.size.width * scale),
    lround(self.vtkView.bounds.size.height * scale));
}

- (void)updateRenderWindowFrame
{
  if (!_renderWindowOwner || !self.vtkView || CGRectIsEmpty(self.vtkView.bounds))
  {
    return;
  }

  if (self.vtkView.window)
  {
    self.vtkView.contentScaleFactor = self.vtkView.window.screen.scale;
    self.vtkView.layer.contentsScale = self.vtkView.contentScaleFactor;
  }

  CGSize drawableSize = [self drawableSize];
  const BOOL sizeChanged =
    (drawableSize.width != _lastDrawableSize.width || drawableSize.height != _lastDrawableSize.height);

  _renderWindowOwner->SetPosition(0, 0);
  _renderWindowOwner->SetSize((int)drawableSize.width, (int)drawableSize.height);
  if (_interactorOwner)
  {
    _interactorOwner->SetSize((int)drawableSize.width, (int)drawableSize.height);
  }

  if (sizeChanged && self.renderer && _didAttachWindow)
  {
    self.renderer->ResetCamera();
    self.renderer->ResetCameraClippingRange();
  }

  _lastDrawableSize = drawableSize;

  (void)_renderWindowOwner->GetWindowId();
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

  if (_renderWindowOwner)
  {
    _renderWindowOwner->Render();
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

- (NSArray<NSString*>*)supportedFileTypes
{
  NSArray* documentTypes =
    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];
  NSDictionary* vtkDocumentType = [documentTypes objectAtIndex:0];
  return [vtkDocumentType objectForKey:@"LSItemContentTypes"];
}

- (IBAction)onAddDataButtonPressed:(id)sender
{
  (void)sender;
  UIDocumentPickerViewController* documentPicker =
    [[UIDocumentPickerViewController alloc] initWithDocumentTypes:[self supportedFileTypes]
                                                           inMode:UIDocumentPickerModeImport];
  documentPicker.delegate = self;
  documentPicker.allowsMultipleSelection = YES;
  documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
  [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
  didPickDocumentsAtURLs:(nonnull NSArray<NSURL*>*)urls
{
  (void)controller;
  [self loadFiles:urls];
}

- (void)loadFiles:(nonnull NSArray<NSURL*>*)urls
{
  if (!self.isViewLoaded)
  {
    self.initialUrls = urls;
    return;
  }

  if (self.renderer->GetViewProps()->GetNumberOfItems() == 0)
  {
    [self loadFilesInternal:urls];
  }
  else
  {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIAlertController* alertController =
        [UIAlertController alertControllerWithTitle:@"Import"
                                            message:@"There are other objects in the scene."
                                     preferredStyle:UIAlertControllerStyleAlert];

      void (^onSelectedAction)(UIAlertAction*) = ^(UIAlertAction* action) {
        if (action.style == UIAlertActionStyleCancel)
        {
          self.renderer->RemoveAllViewProps();
        }
        [self loadFilesInternal:urls];
      };

      [alertController addAction:[UIAlertAction actionWithTitle:@"Add"
                                                          style:UIAlertActionStyleDefault
                                                        handler:onSelectedAction]];
      [alertController addAction:[UIAlertAction actionWithTitle:@"Replace"
                                                          style:UIAlertActionStyleCancel
                                                        handler:onSelectedAction]];

      [self presentViewController:alertController animated:YES completion:nil];
    });
  }
}

- (void)loadFilesInternal:(nonnull NSArray<NSURL*>*)urls
{
  for (NSURL* url in urls)
  {
    [self loadFileInternal:url];
  }
}

- (void)loadFileInternal:(NSURL*)url
{
  vtkSmartPointer<vtkActor> actor = [VTKLoader loadFromURL:url];

  NSString* alertTitle;
  NSString* alertMessage;
  if (actor)
  {
    self.renderer->AddActor(actor);
    self.renderer->ResetCamera();
    self.renderer->ResetCameraClippingRange();
    [self renderFrame];
    alertTitle = @"Import";
    alertMessage = [NSString stringWithFormat:@"Imported %@", [url lastPathComponent]];
  }
  else
  {
    alertTitle = @"Import Failed";
    alertMessage = [NSString stringWithFormat:@"Could not load %@", [url lastPathComponent]];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    UIAlertController* alertController =
      [UIAlertController alertControllerWithTitle:alertTitle
                                          message:alertMessage
                                   preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Ok"
                                                        style:UIAlertActionStyleDefault
                                                      handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
  });
}

@end
