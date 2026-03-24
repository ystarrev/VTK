// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause
#import "vtkIOSRenderWindowInteractor.h"
#import "vtkCommand.h"
#import "vtkObjectFactory.h"
#import "vtkRenderWindow.h"

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

@interface vtkIOSGestureHandler : NSObject<UIGestureRecognizerDelegate>
@property (nonatomic, assign) vtkIOSRenderWindowInteractor* interactor;
@property (nonatomic, assign) UIView* view;
@property (nonatomic, strong) UIPinchGestureRecognizer* pinchRecognizer;
@property (nonatomic, strong) UIRotationGestureRecognizer* rotationRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer* panRecognizer;
@property (nonatomic, assign) NSInteger lastNumberOfTouches;
- (instancetype)initWithView:(UIView*)view interactor:(vtkIOSRenderWindowInteractor*)interactor;
- (void)installRecognizers;
- (void)removeRecognizers;
@end

@implementation vtkIOSGestureHandler

- (instancetype)initWithView:(UIView*)view interactor:(vtkIOSRenderWindowInteractor*)interactor
{
  self = [super init];
  if (self)
  {
    self.view = view;
    self.interactor = interactor;
    self.lastNumberOfTouches = 0;
  }
  return self;
}

- (void)installRecognizers
{
  if (!self.view)
  {
    return;
  }

  if (!self.pinchRecognizer)
  {
    self.pinchRecognizer =
      [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onPinch:)];
    self.pinchRecognizer.delegate = self;
    [self.view addGestureRecognizer:self.pinchRecognizer];
  }

  if (!self.rotationRecognizer)
  {
    self.rotationRecognizer =
      [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(onRotate:)];
    self.rotationRecognizer.delegate = self;
    [self.view addGestureRecognizer:self.rotationRecognizer];
  }

  if (!self.panRecognizer)
  {
    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    self.panRecognizer.minimumNumberOfTouches = self.interactor->GetGesturePanMinimumTouches();
    self.panRecognizer.maximumNumberOfTouches = 2;
    self.panRecognizer.delegate = self;
    [self.view addGestureRecognizer:self.panRecognizer];
  }
}

- (void)removeRecognizers
{
  if (self.pinchRecognizer)
  {
    [self.view removeGestureRecognizer:self.pinchRecognizer];
    self.pinchRecognizer = nil;
  }
  if (self.rotationRecognizer)
  {
    [self.view removeGestureRecognizer:self.rotationRecognizer];
    self.rotationRecognizer = nil;
  }
  if (self.panRecognizer)
  {
    [self.view removeGestureRecognizer:self.panRecognizer];
    self.panRecognizer = nil;
  }
  self.lastNumberOfTouches = 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer
  shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)otherGestureRecognizer
{
  (void)gestureRecognizer;
  (void)otherGestureRecognizer;
  return YES;
}

- (void)forwardTouchPositionToInteractor:(UIGestureRecognizer*)sender
{
  if (!self.interactor || !self.view || !self.interactor->GetRenderWindow())
  {
    return;
  }

  CGPoint touchPoint = [sender locationInView:self.view];
  const int* size = self.interactor->GetRenderWindow()->GetSize();
  CGFloat scaleX = self.view.bounds.size.width > 0.0
    ? (CGFloat)size[0] / self.view.bounds.size.width
    : self.view.contentScaleFactor;
  CGFloat scaleY = self.view.bounds.size.height > 0.0
    ? (CGFloat)size[1] / self.view.bounds.size.height
    : self.view.contentScaleFactor;
  int x = (int)lround(scaleX * touchPoint.x);
  int y = (int)lround(size[1] - scaleY * touchPoint.y);
  self.interactor->SetPointerIndex(0);
  self.interactor->SetEventInformation(x, y, 0, 0, 0, 0, 0, 0);
}

- (void)onPinch:(UIPinchGestureRecognizer*)sender
{
  if (!self.interactor || sender.numberOfTouches < 2)
  {
    return;
  }

  [self forwardTouchPositionToInteractor:sender];

  CGFloat scale = sender.scale;
  if (scale < 0.01)
  {
    scale = 0.01;
  }

  if (self.interactor->GetUseMouseWheelPinch())
  {
    switch (sender.state)
    {
      case UIGestureRecognizerStateBegan:
        self.interactor->SetScale(scale);
        break;
      case UIGestureRecognizerStateChanged:
      {
        self.interactor->SetScale(scale);
        double delta = self.interactor->GetScale() - self.interactor->GetLastScale();
        if (fabs(delta) >= 0.01)
        {
          self.interactor->InvokeEvent(delta > 0.0
              ? vtkCommand::MouseWheelBackwardEvent
              : vtkCommand::MouseWheelForwardEvent,
            nullptr);
        }
      }
      break;
      case UIGestureRecognizerStateEnded:
      case UIGestureRecognizerStateCancelled:
      case UIGestureRecognizerStateFailed:
        break;
      default:
        break;
    }
  }
  else
  {
    self.interactor->SetScale(scale);

    switch (sender.state)
    {
      case UIGestureRecognizerStateBegan:
        self.interactor->StartPinchEvent();
        break;
      case UIGestureRecognizerStateChanged:
        self.interactor->PinchEvent();
        break;
      case UIGestureRecognizerStateEnded:
      case UIGestureRecognizerStateCancelled:
      case UIGestureRecognizerStateFailed:
        self.interactor->EndPinchEvent();
        break;
      default:
        break;
    }
  }

  self.interactor->Render();
}

- (void)onRotate:(UIRotationGestureRecognizer*)sender
{
  if (!self.interactor || sender.numberOfTouches < 2)
  {
    return;
  }

  [self forwardTouchPositionToInteractor:sender];
  self.interactor->SetRotation(-sender.rotation * 180.0 / M_PI);

  switch (sender.state)
  {
    case UIGestureRecognizerStateBegan:
      self.interactor->StartRotateEvent();
      break;
    case UIGestureRecognizerStateChanged:
      self.interactor->RotateEvent();
      break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
      self.interactor->EndRotateEvent();
      break;
    default:
      break;
  }

  self.interactor->Render();
}

- (void)onTrackballMotion:(UIGestureRecognizerState)state
{
  switch (state)
  {
    case UIGestureRecognizerStateBegan:
      self.interactor->InvokeEvent(vtkCommand::LeftButtonPressEvent, nullptr);
      break;
    case UIGestureRecognizerStateChanged:
      self.interactor->InvokeEvent(vtkCommand::MouseMoveEvent, nullptr);
      break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
      self.interactor->InvokeEvent(vtkCommand::LeftButtonReleaseEvent, nullptr);
      break;
    default:
      break;
  }
}

- (void)onTwoFingerPan:(UIGestureRecognizerState)state
{
  switch (state)
  {
    case UIGestureRecognizerStateBegan:
      self.interactor->StartPanEvent();
      break;
    case UIGestureRecognizerStateChanged:
      self.interactor->PanEvent();
      break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
      self.interactor->EndPanEvent();
      break;
    default:
      break;
  }
}

- (void)onPan:(UIPanGestureRecognizer*)sender
{
  if (!self.interactor)
  {
    return;
  }

  [self forwardTouchPositionToInteractor:sender];

  if (sender.numberOfTouches == 2 ||
    (self.lastNumberOfTouches == 2 &&
      (sender.state == UIGestureRecognizerStateEnded ||
       sender.state == UIGestureRecognizerStateCancelled ||
       sender.state == UIGestureRecognizerStateFailed)))
  {
    if (self.lastNumberOfTouches == 1)
    {
      [self onTrackballMotion:UIGestureRecognizerStateEnded];
      [self onTwoFingerPan:UIGestureRecognizerStateBegan];
    }
    else
    {
      [self onTwoFingerPan:sender.state];
    }
  }
  else if (sender.numberOfTouches == 1 ||
    (self.lastNumberOfTouches == 1 &&
      (sender.state == UIGestureRecognizerStateEnded ||
       sender.state == UIGestureRecognizerStateCancelled ||
       sender.state == UIGestureRecognizerStateFailed)))
  {
    if (self.lastNumberOfTouches == 2)
    {
      [self onTwoFingerPan:UIGestureRecognizerStateEnded];
      self.interactor->EndPinchEvent();
      self.interactor->EndRotateEvent();
      [self onTrackballMotion:UIGestureRecognizerStateBegan];
    }
    else
    {
      [self onTrackballMotion:sender.state];
    }
  }

  self.lastNumberOfTouches = sender.numberOfTouches;
  self.interactor->Render();
}

@end

//----------------------------------------------------------------------------
vtkStandardNewMacro(vtkIOSRenderWindowInteractor);

//----------------------------------------------------------------------------
void (*vtkIOSRenderWindowInteractor::ClassExitMethod)(void*) = (void (*)(void*))NULL;
void* vtkIOSRenderWindowInteractor::ClassExitMethodArg = (void*)NULL;
void (*vtkIOSRenderWindowInteractor::ClassExitMethodArgDelete)(void*) = (void (*)(void*))NULL;

//----------------------------------------------------------------------------
vtkIOSRenderWindowInteractor::vtkIOSRenderWindowInteractor()
{
  this->UseGestureRecognizers = 0;
  this->GesturePanMinimumTouches = 1;
  this->UseMouseWheelPinch = 0;
  this->SetIOSManager(reinterpret_cast<void*>([[NSMutableDictionary alloc] init]));
}

//----------------------------------------------------------------------------
vtkIOSRenderWindowInteractor::~vtkIOSRenderWindowInteractor()
{
  this->RemoveGestureRecognizers();
  this->SetTimerDictionary(nullptr);
  this->SetIOSManager(nullptr);
  this->Enabled = 0;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::StartEventLoop() {}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::Initialize()
{
  if (!this->RenderWindow)
  {
    vtkErrorMacro(<< "No renderer defined!");
    return;
  }
  if (this->Initialized)
  {
    return;
  }

  this->Initialized = 1;
  vtkRenderWindow* renWin = this->RenderWindow;
  renWin->Start();
  renWin->End();
  const int* size = renWin->GetSize();

  renWin->GetPosition();

  this->Enable();
  this->Size[0] = size[0];
  this->Size[1] = size[1];
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::Enable()
{
  if (this->Enabled)
  {
    return;
  }

  this->GetRenderWindow()->SetInteractor(this);

  this->Enabled = 1;
  this->Modified();

  if (this->UseGestureRecognizers)
  {
    this->InstallGestureRecognizers();
  }
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::Disable()
{
  if (!this->Enabled)
  {
    return;
  }

#ifdef VTK_USE_TDX
  if (this->Device->GetInitialized())
  {
    this->Device->Close();
  }
#endif

  this->RemoveGestureRecognizers();
  this->GetRenderWindow()->SetInteractor(NULL);

  this->Enabled = 0;
  this->Modified();
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::TerminateApp() {}

//----------------------------------------------------------------------------
int vtkIOSRenderWindowInteractor::InternalCreateTimer(
  int timerId, int timerType, unsigned long duration)
{
  (void)timerType;
  (void)duration;
  int platformTimerId = timerId;
  return platformTimerId;
}

//----------------------------------------------------------------------------
int vtkIOSRenderWindowInteractor::InternalDestroyTimer(int platformTimerId)
{
  int timerId = this->GetVTKTimerId(platformTimerId);
  (void)timerId;
  return 0;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::SetClassExitMethod(void (*f)(void*), void* arg)
{
  if (f != vtkIOSRenderWindowInteractor::ClassExitMethod ||
    arg != vtkIOSRenderWindowInteractor::ClassExitMethodArg)
  {
    if ((vtkIOSRenderWindowInteractor::ClassExitMethodArg) &&
      (vtkIOSRenderWindowInteractor::ClassExitMethodArgDelete))
    {
      (*vtkIOSRenderWindowInteractor::ClassExitMethodArgDelete)(
        vtkIOSRenderWindowInteractor::ClassExitMethodArg);
    }
    vtkIOSRenderWindowInteractor::ClassExitMethod = f;
    vtkIOSRenderWindowInteractor::ClassExitMethodArg = arg;
  }
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::SetClassExitMethodArgDelete(void (*f)(void*))
{
  if (f != vtkIOSRenderWindowInteractor::ClassExitMethodArgDelete)
  {
    vtkIOSRenderWindowInteractor::ClassExitMethodArgDelete = f;
  }
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::PrintSelf(ostream& os, vtkIndent indent)
{
  this->Superclass::PrintSelf(os, indent);
  os << indent << "UseGestureRecognizers: " << this->UseGestureRecognizers << "\n";
  os << indent << "GesturePanMinimumTouches: " << this->GesturePanMinimumTouches << "\n";
  os << indent << "UseMouseWheelPinch: " << this->UseMouseWheelPinch << "\n";
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::ExitCallback()
{
  if (this->HasObserver(vtkCommand::ExitEvent))
  {
    this->InvokeEvent(vtkCommand::ExitEvent, NULL);
  }
  else if (this->ClassExitMethod)
  {
    (*this->ClassExitMethod)(this->ClassExitMethodArg);
  }
  this->TerminateApp();
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::SetTimerDictionary(void* dictionary)
{
  NSMutableDictionary* manager = reinterpret_cast<NSMutableDictionary*>(this->GetIOSManager());
  if (!manager)
  {
    return;
  }

  if (dictionary != nullptr)
  {
    [manager setObject:reinterpret_cast<id>(dictionary) forKey:@"TimerDictionary"];
  }
  else
  {
    [manager removeObjectForKey:@"TimerDictionary"];
  }
}

//----------------------------------------------------------------------------
void* vtkIOSRenderWindowInteractor::GetTimerDictionary()
{
  NSMutableDictionary* manager = reinterpret_cast<NSMutableDictionary*>(this->GetIOSManager());
  return reinterpret_cast<void*>([manager objectForKey:@"TimerDictionary"]);
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::SetIOSManager(void* manager)
{
  NSMutableDictionary* currentManager = reinterpret_cast<NSMutableDictionary*>(this->IOSManager);
  NSMutableDictionary* newManager = reinterpret_cast<NSMutableDictionary*>(manager);

  if (currentManager != newManager)
  {
    if (currentManager)
    {
      CFRelease(currentManager);
    }
    if (newManager)
    {
      this->IOSManager = const_cast<void*>(CFRetain(newManager));
    }
    else
    {
      this->IOSManager = nullptr;
    }
  }
}

//----------------------------------------------------------------------------
void* vtkIOSRenderWindowInteractor::GetIOSManager()
{
  return this->IOSManager;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::InstallGestureRecognizers()
{
  if (!this->UseGestureRecognizers || !this->RenderWindow)
  {
    return;
  }

  UIView* view = (__bridge UIView*)this->RenderWindow->GetGenericWindowId();
  if (!view)
  {
    return;
  }

  NSMutableDictionary* manager = reinterpret_cast<NSMutableDictionary*>(this->GetIOSManager());
  vtkIOSGestureHandler* existingHandler =
    reinterpret_cast<vtkIOSGestureHandler*>([manager objectForKey:@"GestureHandler"]);
  if (existingHandler && existingHandler.view == view)
  {
    return;
  }

  if (existingHandler)
  {
    [existingHandler removeRecognizers];
    [manager removeObjectForKey:@"GestureHandler"];
  }

  vtkIOSGestureHandler* handler =
    [[vtkIOSGestureHandler alloc] initWithView:view interactor:this];
  [handler installRecognizers];
  [manager setObject:handler forKey:@"GestureHandler"];
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindowInteractor::RemoveGestureRecognizers()
{
  NSMutableDictionary* manager = reinterpret_cast<NSMutableDictionary*>(this->GetIOSManager());
  vtkIOSGestureHandler* handler =
    reinterpret_cast<vtkIOSGestureHandler*>([manager objectForKey:@"GestureHandler"]);
  if (handler)
  {
    [handler removeRecognizers];
    [manager removeObjectForKey:@"GestureHandler"];
  }
}
