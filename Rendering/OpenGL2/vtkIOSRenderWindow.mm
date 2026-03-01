// SPDX-FileCopyrightText: Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
// SPDX-License-Identifier: BSD-3-Clause

#include "vtkOpenGLRenderWindow.h"

#import "vtkCommand.h"
#import "vtkIOSRenderWindow.h"
#import "vtkIdList.h"
#import "vtkObjectFactory.h"
#import "vtkOpenGLFramebufferObject.h"
#import "vtkOpenGLState.h"
#include "vtkOverrideAttribute.h"
#import "vtkRenderWindowInteractor.h"
#import "vtkRendererCollection.h"
#import "vtkStringScanner.h"

#import <sstream>

#import <UIKit/UIKit.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

#include "vtk_glad.h"


// Minimal UIView subclass that provides a CAEAGLLayer
@interface vtkIOSGLView : UIView
@end

@implementation vtkIOSGLView
+ (Class)layerClass
{
  return [CAEAGLLayer class];
}
@end


VTK_ABI_NAMESPACE_BEGIN
vtkStandardNewMacro(vtkIOSRenderWindow);

//----------------------------------------------------------------------------
vtkIOSRenderWindow::vtkIOSRenderWindow()
{
  this->WindowCreated = 0;
  this->ViewCreated = 0;
  this->SetWindowName("Visualization Toolkit - IOS");
  this->CursorHidden = 0;
  this->ForceMakeCurrent = 0;
  this->OnScreenInitialized = 0;
  this->OffScreenInitialized = 0;
  this->SetFrameBlitModeToBlitToHardware();

  // Provide a symbol loader so glad can resolve OpenGL ES functions on iOS.
  this->SetOpenGLSymbolLoader(
    [](void*, const char* name) -> VTKOpenGLAPIProc
    {
      return reinterpret_cast<VTKOpenGLAPIProc>(dlsym(RTLD_DEFAULT, name));
    },
    nullptr);
}

//----------------------------------------------------------------------------
vtkOverrideAttribute* vtkIOSRenderWindow::CreateOverrideAttributes()
{
  auto* platformAttribute = vtkOverrideAttribute::CreateAttributeChain("Platform", "iOS", nullptr);
  auto* windowSystemAttribute =
    vtkOverrideAttribute::CreateAttributeChain("WindowSystem", "Cocoa", platformAttribute);
  auto* renderingBackendAttribute =
    vtkOverrideAttribute::CreateAttributeChain("RenderingBackend", "OpenGL", windowSystemAttribute);
  return renderingBackendAttribute;
}

void vtkIOSRenderWindow::BlitDisplayFramebuffersToHardware()
{
  auto ostate = this->GetState();
  ostate->PushFramebufferBindings();
  this->DisplayFramebuffer->Bind(GL_READ_FRAMEBUFFER);
  this->GetState()->vtkglViewport(0, 0, this->Size[0], this->Size[1]);
  this->GetState()->vtkglScissor(0, 0, this->Size[0], this->Size[1]);

  if (this->FramebufferId != 0)
  {
    this->GetState()->vtkglBindFramebuffer(GL_DRAW_FRAMEBUFFER, this->FramebufferId);
  }
  else
  {
    this->GetState()->vtkglBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
  }

  this->DisplayFramebuffer->ActivateReadBuffer(0);
  unsigned int drawBuffer = this->DoubleBuffer ? GL_BACK : GL_FRONT;
  if (this->FramebufferId != 0)
  {
    // When drawing to an FBO, use COLOR_ATTACHMENT0 instead of hardware buffers.
    drawBuffer = GL_COLOR_ATTACHMENT0;
  }
  this->GetState()->vtkglDrawBuffer(drawBuffer);

  // recall Blit upper right corner is exclusive of the range
  this->GetState()->vtkglBlitFramebuffer(0, 0, this->Size[0], this->Size[1], 0, 0, this->Size[0],
    this->Size[1], GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, GL_NEAREST);

  this->GetState()->PopFramebufferBindings();
}

//----------------------------------------------------------------------------
vtkIOSRenderWindow::~vtkIOSRenderWindow()
{
  if (this->CursorHidden)
  {
    this->ShowCursor();
  }
  this->Finalize();

  vtkRenderer* ren;
  vtkCollectionSimpleIterator rit;
  this->Renderers->InitTraversal(rit);
  while ((ren = this->Renderers->GetNextRenderer(rit)))
  {
    ren->SetRenderWindow(NULL);
  }

  this->SetContextId(NULL);
  this->SetPixelFormat(NULL);
  this->SetRootWindow(NULL);
  this->SetWindowId(NULL);
  this->SetParentId(NULL);
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::Finalize()
{
  if (this->OffScreenInitialized)
  {
    this->OffScreenInitialized = 0;
    this->DestroyOffScreenWindow();
  }
  if (this->OnScreenInitialized)
  {
    this->OnScreenInitialized = 0;
    this->DestroyWindow();
  }
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::DestroyWindow()
{
  // finish OpenGL rendering
  if (this->OwnContext && this->GetContextId())
  {
    this->MakeCurrent();
    this->ReleaseGraphicsResources(this);
  }
  if (this->GetContextId())
  {
    CFRelease((__bridge CFTypeRef)this->GetContextId());
  }
  if (this->FramebufferId != 0)
  {
    GLuint fb = this->FramebufferId;
    glDeleteFramebuffers(1, &fb);
    this->FramebufferId = 0;
  }
  if (this->DepthRenderbufferId != 0)
  {
    GLuint rb = this->DepthRenderbufferId;
    glDeleteRenderbuffers(1, &rb);
    this->DepthRenderbufferId = 0;
  }

  this->SetContextId(NULL);
  this->SetPixelFormat(NULL);

  this->SetWindowId(NULL);
  this->SetParentId(NULL);
  this->SetRootWindow(NULL);
}

int vtkIOSRenderWindow::ReadPixels(
  const vtkRecti& rect, int front, int glFormat, int glType, void* data, int right)
{
  if (glFormat != GL_RGB || glType != GL_UNSIGNED_BYTE)
  {
    return this->Superclass::ReadPixels(rect, front, glFormat, glType, data, right);
  }

  // iOS has issues with getting RGB so we get RGBA
  unsigned char* uc4data = new unsigned char[rect.GetWidth() * rect.GetHeight() * 4];
  int retVal = this->Superclass::ReadPixels(rect, front, GL_RGBA, GL_UNSIGNED_BYTE, uc4data, right);

  unsigned char* dPtr = reinterpret_cast<unsigned char*>(data);
  const unsigned char* lPtr = uc4data;
  for (int i = 0, height = rect.GetHeight(); i < height; i++)
  {
    for (int j = 0, width = rect.GetWidth(); j < width; j++)
    {
      *(dPtr++) = *(lPtr++);
      *(dPtr++) = *(lPtr++);
      *(dPtr++) = *(lPtr++);
      lPtr++;
    }
  }
  delete[] uc4data;
  return retVal;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetWindowName(const char* _arg)
{
  vtkWindow::SetWindowName(_arg);
}

//----------------------------------------------------------------------------
bool vtkIOSRenderWindow::InitializeFromCurrentContext()
{
  // NSOpenGLContext* currentContext = [NSOpenGLContext currentContext];
  // if (currentContext != nullptr)
  // {
  //   this->SetContextId(currentContext);
  //   this->SetPixelFormat([currentContext pixelFormat]);
  //
  //   return this->Superclass::InitializeFromCurrentContext();
  //}
  return false;
}

//----------------------------------------------------------------------------
vtkTypeBool vtkIOSRenderWindow::GetEventPending()
{
  return 0;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::MakeCurrent()
{
  if (this->GetContextId())
  {
    [EAGLContext setCurrentContext:(__bridge EAGLContext*)this->GetContextId()];
  }
}

// ----------------------------------------------------------------------------
// Description:
// Tells if this window is the current OpenGL context for the calling thread.
bool vtkIOSRenderWindow::IsCurrent()
{
  if (!this->GetContextId())
  {
    return false;
  }
  return [EAGLContext currentContext] == (__bridge EAGLContext*)this->GetContextId();
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::UpdateContext() {}

//----------------------------------------------------------------------------
const char* vtkIOSRenderWindow::ReportCapabilities()
{
  this->MakeCurrent();

  const char* glVendor = (const char*)glGetString(GL_VENDOR);
  const char* glRenderer = (const char*)glGetString(GL_RENDERER);
  const char* glVersion = (const char*)glGetString(GL_VERSION);
  const char* glExtensions = (const char*)glGetString(GL_EXTENSIONS);

  std::ostringstream strm;
  strm << "OpenGL vendor string:  " << glVendor << "\nOpenGL renderer string:  " << glRenderer
       << "\nOpenGL version string:  " << glVersion << "\nOpenGL extensions:  " << glExtensions
       << endl;

  delete[] this->Capabilities;

  size_t len = strm.str().length() + 1;
  this->Capabilities = new char[len];
  strlcpy(this->Capabilities, strm.str().c_str(), len);

  return this->Capabilities;
}

//----------------------------------------------------------------------------
int vtkIOSRenderWindow::SupportsOpenGL()
{
  this->MakeCurrent();
  if (!this->GetContextId() || !this->GetPixelFormat())
  {
    return 0;
  }
  return 1;
}

//----------------------------------------------------------------------------
vtkTypeBool vtkIOSRenderWindow::IsDirect()
{
  this->MakeCurrent();
  if (!this->GetContextId() || !this->GetPixelFormat())
  {
    return 0;
  }
  return 1;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetSize(int width, int height)
{
  if ((this->Size[0] != width) || (this->Size[1] != height) || this->GetParentId())
  {
    this->Modified();
    this->Size[0] = width;
    this->Size[1] = height;
  }
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetForceMakeCurrent()
{
  this->ForceMakeCurrent = 1;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetPosition(int x, int y)
{
  if ((this->Position[0] != x) || (this->Position[1] != y) || this->GetParentId())
  {
    this->Modified();
    this->Position[0] = x;
    this->Position[1] = y;
  }
}

//----------------------------------------------------------------------------
// End the rendering process and display the image.
void vtkIOSRenderWindow::Frame()
{
  this->MakeCurrent();
  this->Superclass::Frame();

  if (this->GetContextId())
  {
    GLuint colorRenderbuffer = (GLuint)(uintptr_t)this->GetPixelFormat();
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    [(__bridge EAGLContext*)this->GetContextId() presentRenderbuffer:GL_RENDERBUFFER];
  }
}


//----------------------------------------------------------------------------
// Specify various window parameters.
void vtkIOSRenderWindow::WindowConfigure()
{
  // this is all handled by the desiredVisualInfo method
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetupPixelFormat(void*, void*, int, int, int)
{
  vtkErrorMacro(<< "vtkIOSRenderWindow::SetupPixelFormat - IMPLEMENT");
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetupPalette(void*)
{
  vtkErrorMacro(<< "vtkIOSRenderWindow::SetupPalette - IMPLEMENT");
}

//----------------------------------------------------------------------------
// Initialize the window for rendering.
void vtkIOSRenderWindow::CreateAWindow()
{
  this->CreateGLContext();

  this->MakeCurrent();

  // wipe out any existing display lists
  vtkRenderer* renderer = NULL;
  vtkCollectionSimpleIterator rsit;

  for (this->Renderers->InitTraversal(rsit); (renderer = this->Renderers->GetNextRenderer(rsit));)
  {
    renderer->SetRenderWindow(0);
    renderer->SetRenderWindow(this);
  }
  this->OpenGLInit();
  this->Mapped = 1;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::CreateGLContext()
{
  if (this->GetContextId())
  {
    return;
  }

  UIView* view = (__bridge UIView*)this->GetWindowId();
  if (!view)
  {
    UIView* parent = (__bridge UIView*)this->GetParentId();
    CGRect frame = parent ? parent.bounds : CGRectMake(0, 0, this->Size[0], this->Size[1]);
    vtkIOSGLView* glView = [[vtkIOSGLView alloc] initWithFrame:frame];
    view = glView;
    if (parent)
    {
      view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      [parent addSubview:view];
    }
    this->SetWindowId((__bridge void*)view);
  }

  // Ensure correct backing scale
  if (view.window)
  {
    view.contentScaleFactor = view.window.screen.scale;
  }
  else
  {
    view.contentScaleFactor = [UIScreen mainScreen].scale;
  }

  // Make the view's layer an EAGL layer.
  CAEAGLLayer* eaglLayer = (CAEAGLLayer*)view.layer;
  eaglLayer.opaque = YES;
  eaglLayer.contentsScale = view.contentScaleFactor;
  eaglLayer.drawableProperties = @{
    kEAGLDrawablePropertyRetainedBacking : @NO,
    kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8
  };

  EAGLContext* context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
  if (!context)
  {
    context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
  }
  CFRetain((__bridge CFTypeRef)context);
  this->SetContextId((__bridge void*)context);
  [EAGLContext setCurrentContext:context];

  GLuint colorRenderbuffer = 0;
  GLuint depthRenderbuffer = 0;
  GLuint framebuffer = 0;
  glGenRenderbuffers(1, &colorRenderbuffer);
  glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
  [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:eaglLayer];
  GLint rbWidth = 0;
  GLint rbHeight = 0;
  glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &rbWidth);
  glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &rbHeight);

  glGenRenderbuffers(1, &depthRenderbuffer);
  glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, (GLsizei)(view.bounds.size.width * view.contentScaleFactor), (GLsizei)(view.bounds.size.height * view.contentScaleFactor));

  glGenFramebuffers(1, &framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);

  this->FramebufferId = framebuffer;
  this->DepthRenderbufferId = depthRenderbuffer;

  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  (void)status;

  this->SetPixelFormat(reinterpret_cast<void*>((uintptr_t)colorRenderbuffer));
  this->SetRootWindow((__bridge void*)view.window);
  this->OwnContext = 1;
  this->WindowCreated = 1;
  this->ViewCreated = 1;
}



//----------------------------------------------------------------------------
// Initialize the rendering window.
void vtkIOSRenderWindow::Initialize()
{
  this->CreateGLContext();
  this->MakeCurrent();
  if (this->FramebufferId != 0)
  {
    glBindFramebuffer(GL_FRAMEBUFFER, this->FramebufferId);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, this->FramebufferId);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, this->FramebufferId);
  }
  this->OpenGLInit();
  this->Mapped = 1;
}

//-----------------------------------------------------------------------------
void vtkIOSRenderWindow::DestroyOffScreenWindow() {}

//----------------------------------------------------------------------------
// Get the current size of the window.
int* vtkIOSRenderWindow::GetSize()
{
  // if we aren't mapped then just return call super
  if (!this->Mapped)
  {
    return this->Superclass::GetSize();
  }

  return this->Superclass::GetSize();
}

//----------------------------------------------------------------------------
// Get the current size of the screen in pixels.
int* vtkIOSRenderWindow::GetScreenSize()
{
  // TODO: use UISceen to actually determine screen size.

  return this->ScreenSize;
}

//----------------------------------------------------------------------------
// Get the position in screen coordinates of the window.
int* vtkIOSRenderWindow::GetPosition()
{
  return this->Position;
}

//----------------------------------------------------------------------------
// Change the window to fill the entire screen.
void vtkIOSRenderWindow::SetFullScreen(vtkTypeBool arg) {}

//----------------------------------------------------------------------------
//
// Set the variable that indicates that we want a stereo capable window
// be created. This method can only be called before a window is realized.
//
void vtkIOSRenderWindow::SetStereoCapableWindow(vtkTypeBool capable)
{
  if (this->GetContextId() == 0)
  {
    vtkRenderWindow::SetStereoCapableWindow(capable);
  }
  else
  {
    vtkWarningMacro(<< "Requesting a StereoCapableWindow must be performed "
                    << "before the window is realized, i.e. before a render.");
  }
}

//----------------------------------------------------------------------------
// Set the preferred window size to full screen.
void vtkIOSRenderWindow::PrefFullScreen()
{
  const int* size = this->GetScreenSize();
  vtkWarningMacro(<< "Can only set FullScreen before showing window: " << size[0] << 'x' << size[1]
                  << ".");
}

//----------------------------------------------------------------------------
// Remap the window.
void vtkIOSRenderWindow::WindowRemap()
{
  vtkWarningMacro(<< "Can't remap the window.");
  // Acquire the display and capture the screen.
  // Create the full-screen window.
  // Add the context.
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::PrintSelf(ostream& os, vtkIndent indent)
{
  this->Superclass::PrintSelf(os, indent);

  os << indent << "RootWindow (UIWindow): " << this->GetRootWindow() << endl;
  os << indent << "WindowId (UIView): " << this->GetWindowId() << endl;
  os << indent << "ParentId: " << this->GetParentId() << endl;
  os << indent << "ContextId: " << this->GetContextId() << endl;
  os << indent << "PixelFormat: " << this->GetPixelFormat() << endl;
  os << indent << "WindowCreated: " << (this->WindowCreated ? "Yes" : "No") << endl;
  os << indent << "ViewCreated: " << (this->ViewCreated ? "Yes" : "No") << endl;
}

//----------------------------------------------------------------------------
int vtkIOSRenderWindow::GetDepthBufferSize()
{
  if (this->Mapped)
  {
    GLint size = 0;
    glGetIntegerv(GL_DEPTH_BITS, &size);
    return (int)size;
  }
  else
  {
    vtkDebugMacro(<< "Window is not mapped yet!");
    return 24;
  }
}

//----------------------------------------------------------------------------
int vtkIOSRenderWindow::GetColorBufferSizes(int* rgba)
{
  if (rgba == nullptr)
  {
    return 0;
  }
  rgba[0] = 0;
  rgba[1] = 0;
  rgba[2] = 0;
  rgba[3] = 0;

  if (!this->Initialized)
  {
    return 0;
  }

  this->MakeCurrent();
  GLint size = 0;

  while (glGetError() != GL_NO_ERROR)
  {
  }

  glGetFramebufferAttachmentParameteriv(
    GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE, &size);
  if (!glGetError())
  {
    rgba[0] = static_cast<int>(size);
  }
  glGetFramebufferAttachmentParameteriv(
    GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_GREEN_SIZE, &size);
  if (!glGetError())
  {
    rgba[1] = static_cast<int>(size);
  }
  glGetFramebufferAttachmentParameteriv(
    GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_BLUE_SIZE, &size);
  if (!glGetError())
  {
    rgba[2] = static_cast<int>(size);
  }
  glGetFramebufferAttachmentParameteriv(
    GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE, &size);
  if (!glGetError())
  {
    rgba[3] = static_cast<int>(size);
  }

  return 1;
}

//----------------------------------------------------------------------------
// Returns the UIWindow* associated with this vtkRenderWindow.
void* vtkIOSRenderWindow::GetRootWindow()
{
  return this->RootWindow;
}

//----------------------------------------------------------------------------
// Sets the UIWindow* associated with this vtkRenderWindow.
void vtkIOSRenderWindow::SetRootWindow(void* arg)
{
  this->RootWindow = arg;
}

//----------------------------------------------------------------------------
// Returns the UIView* associated with this vtkRenderWindow.
void* vtkIOSRenderWindow::GetWindowId()
{
  return this->WindowId;
}

//----------------------------------------------------------------------------
// Sets the UIView* associated with this vtkRenderWindow.
void vtkIOSRenderWindow::SetWindowId(void* arg)
{
  this->WindowId = arg;
}

//----------------------------------------------------------------------------
// Returns the UIView* that is the parent of this vtkRenderWindow.
void* vtkIOSRenderWindow::GetParentId()
{
  return this->ParentId;
}

//----------------------------------------------------------------------------
// Sets the UIView* that this vtkRenderWindow should use as a parent.
void vtkIOSRenderWindow::SetParentId(void* arg)
{
  this->ParentId = arg;
}

//----------------------------------------------------------------------------
// Sets the NSOpenGLContext* associated with this vtkRenderWindow.
void vtkIOSRenderWindow::SetContextId(void* contextId)
{
  this->ContextId = contextId;
}

//----------------------------------------------------------------------------
// Returns the NSOpenGLContext* associated with this vtkRenderWindow.
void* vtkIOSRenderWindow::GetContextId()
{
  return this->ContextId;
}

//----------------------------------------------------------------------------
// Sets the NSOpenGLPixelFormat* associated with this vtkRenderWindow.
void vtkIOSRenderWindow::SetPixelFormat(void* pixelFormat)
{
  this->PixelFormat = pixelFormat;
}

//----------------------------------------------------------------------------
// Returns the NSOpenGLPixelFormat* associated with this vtkRenderWindow.
void* vtkIOSRenderWindow::GetPixelFormat()
{
  return this->PixelFormat;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetWindowInfo(const char* info)
{
  // The parameter is an ASCII string of a decimal number representing
  // a pointer to the window. Convert it back to a pointer.
  ptrdiff_t tmp = 0;
  if (info)
  {
    vtk::from_chars(info, tmp);
  }

  this->SetWindowId(reinterpret_cast<void*>(tmp));
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetParentInfo(const char* info)
{
  // The parameter is an ASCII string of a decimal number representing
  // a pointer to the window. Convert it back to a pointer.
  ptrdiff_t tmp = 0;
  if (info)
  {
    vtk::from_chars(info, tmp);
  }

  this->SetParentId(reinterpret_cast<void*>(tmp));
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::HideCursor()
{
  if (this->CursorHidden)
  {
    return;
  }
  this->CursorHidden = 1;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::ShowCursor()
{
  if (!this->CursorHidden)
  {
    return;
  }
  this->CursorHidden = 0;
}

// ---------------------------------------------------------------------------
int vtkIOSRenderWindow::GetWindowCreated()
{
  return this->WindowCreated;
}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetCursorPosition(int x, int y) {}

//----------------------------------------------------------------------------
void vtkIOSRenderWindow::SetCurrentCursor(int shape)
{
  if (this->InvokeEvent(vtkCommand::CursorChangedEvent, &shape))
  {
    return;
  }
  this->Superclass::SetCurrentCursor(shape);
}
VTK_ABI_NAMESPACE_END
