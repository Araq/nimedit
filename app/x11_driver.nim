# X11 + Xft backend driver. Sets all hooks from core/input and core/screen.
# Uses Xlib for windowing/events, Xft for antialiased font rendering.
# Double-buffered via X Pixmap.

import basetypes, input, screen
import std/[strutils, os]

{.passL: "-lX11 -lXft".}

# ---- X11 type definitions ----

const
  libX11 = "libX11.so(|.6)"
  libXft = "libXft.so(|.2)"

type
  XID = culong
  Atom = culong
  XTime = culong
  XKeySym = culong
  XBool = cint
  XStatus = cint

  XRectangle {.pure.} = object
    x, y: cshort
    width, height: cushort

  XColor {.pure.} = object
    pixel: culong
    red, green, blue: cushort
    flags: uint8
    pad: uint8

  # ---- Event types ----

  XAnyEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    window: XID

  XKeyEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    window: XID
    root: XID
    subwindow: XID
    time: XTime
    x, y: cint
    x_root, y_root: cint
    state: cuint
    keycode: cuint
    same_screen: XBool

  XButtonEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    window: XID
    root: XID
    subwindow: XID
    time: XTime
    x, y: cint
    x_root, y_root: cint
    state: cuint
    button: cuint
    same_screen: XBool

  XMotionEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    window: XID
    root: XID
    subwindow: XID
    time: XTime
    x, y: cint
    x_root, y_root: cint
    state: cuint
    is_hint: uint8
    same_screen: XBool

  XConfigureEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    event: XID
    window: XID
    x, y: cint
    width, height: cint
    border_width: cint
    above: XID
    override_redirect: XBool

  XExposeEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    window: XID
    x, y: cint
    width, height: cint
    count: cint

  XClientMessageEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    window: XID
    message_type: Atom
    format: cint
    data: array[5, clong]

  XFocusChangeEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    window: XID
    mode: cint
    detail: cint

  XSelectionRequestEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    owner: XID
    requestor: XID
    selection: Atom
    target: Atom
    property: Atom
    time: XTime

  XSelectionEvent {.pure.} = object
    theType: cint
    serial: culong
    send_event: XBool
    display: pointer
    requestor: XID
    selection: Atom
    target: Atom
    property: Atom
    time: XTime

  XEvent {.union.} = object
    theType: cint
    xany: XAnyEvent
    xkey: XKeyEvent
    xbutton: XButtonEvent
    xmotion: XMotionEvent
    xconfigure: XConfigureEvent
    xexpose: XExposeEvent
    xclient: XClientMessageEvent
    xfocus: XFocusChangeEvent
    xselection: XSelectionEvent
    xselectionrequest: XSelectionRequestEvent
    pad: array[24, clong]  # XEvent is 192 bytes on 64-bit

  # ---- Xft types ----

  XRenderColor {.pure.} = object
    red, green, blue, alpha: cushort

  XftColor {.pure.} = object
    pixel: culong
    color: XRenderColor

  XftFont {.pure.} = object
    ascent: cint
    descent: cint
    height: cint
    max_advance_width: cint
    charset: pointer
    pattern: pointer

  XGlyphInfo {.pure.} = object
    width, height: cushort
    x, y: cshort
    xOff, yOff: cshort

# ---- X11 constants ----

const
  None = 0.XID
  CurrentTime = 0.XTime
  XA_ATOM = 4.Atom
  XA_STRING = 31.Atom
  PropModeReplace = 0.cint

  # Event types
  KeyPress = 2.cint
  KeyRelease = 3.cint
  ButtonPress = 4.cint
  ButtonRelease = 5.cint
  MotionNotify = 6.cint
  FocusIn = 9.cint
  FocusOut = 10.cint
  Expose = 12.cint
  ConfigureNotify = 22.cint
  SelectionNotify = 31.cint
  SelectionRequest = 30.cint
  ClientMessage = 33.cint

  # Event masks
  ExposureMask = 1 shl 15
  KeyPressMask = 1 shl 0
  KeyReleaseMask = 1 shl 1
  ButtonPressMask = 1 shl 2
  ButtonReleaseMask = 1 shl 3
  PointerMotionMask = 1 shl 6
  StructureNotifyMask = 1 shl 17
  FocusChangeMask = 1 shl 21

  # Modifier masks
  ShiftMask = 1'u32
  ControlMask = 4'u32
  Mod1Mask = 8'u32   # Alt
  Mod4Mask = 64'u32  # Super/GUI

  # Mouse buttons
  Button1 = 1'u32
  Button2 = 2'u32
  Button3 = 3'u32
  Button4 = 4'u32  # scroll up
  Button5 = 5'u32  # scroll down
  Button1Mask = 1'u32 shl 8
  Button2Mask = 1'u32 shl 9
  Button3Mask = 1'u32 shl 10

  # Cursor shapes
  XC_left_ptr = 68'u32
  XC_xterm = 152'u32
  XC_watch = 150'u32
  XC_crosshair = 34'u32
  XC_hand2 = 60'u32
  XC_sb_v_double_arrow = 116'u32
  XC_sb_h_double_arrow = 108'u32

  # KeySyms
  XK_a = 0x61'u
  XK_z = 0x7a'u
  XK_0 = 0x30'u
  XK_9 = 0x39'u
  XK_F1 = 0xffbe'u
  XK_F12 = 0xffc9'u
  XK_Return = 0xff0d'u
  XK_space = 0x20'u
  XK_Escape = 0xff1b'u
  XK_Tab = 0xff09'u
  XK_BackSpace = 0xff08'u
  XK_Delete = 0xffff'u
  XK_Insert = 0xff63'u
  XK_Left = 0xff51'u
  XK_Up = 0xff52'u
  XK_Right = 0xff53'u
  XK_Down = 0xff54'u
  XK_Page_Up = 0xff55'u
  XK_Page_Down = 0xff56'u
  XK_Home = 0xff50'u
  XK_End = 0xff57'u
  XK_Caps_Lock = 0xffe5'u
  XK_comma = 0x2c'u
  XK_period = 0x2e'u

# ---- X11 function imports ----

proc XOpenDisplay(name: cstring): pointer
  {.cdecl, dynlib: libX11, importc.}
proc XDefaultScreen(dpy: pointer): cint
  {.cdecl, dynlib: libX11, importc.}
proc XRootWindow(dpy: pointer; screen: cint): XID
  {.cdecl, dynlib: libX11, importc.}
proc XDefaultVisual(dpy: pointer; screen: cint): pointer
  {.cdecl, dynlib: libX11, importc.}
proc XDefaultColormap(dpy: pointer; screen: cint): XID
  {.cdecl, dynlib: libX11, importc.}
proc XDefaultDepth(dpy: pointer; screen: cint): cint
  {.cdecl, dynlib: libX11, importc.}
proc XBlackPixel(dpy: pointer; screen: cint): culong
  {.cdecl, dynlib: libX11, importc.}
proc XWhitePixel(dpy: pointer; screen: cint): culong
  {.cdecl, dynlib: libX11, importc.}
proc XCreateSimpleWindow(dpy: pointer; parent: XID;
  x, y: cint; w, h, border: cuint; borderColor, bgColor: culong): XID
  {.cdecl, dynlib: libX11, importc.}
proc XMapWindow(dpy: pointer; w: XID): cint
  {.cdecl, dynlib: libX11, importc.}
proc XDestroyWindow(dpy: pointer; w: XID): cint
  {.cdecl, dynlib: libX11, importc.}
proc XSelectInput(dpy: pointer; w: XID; mask: clong): cint
  {.cdecl, dynlib: libX11, importc.}
proc XCreatePixmap(dpy: pointer; d: XID; w, h, depth: cuint): XID
  {.cdecl, dynlib: libX11, importc.}
proc XFreePixmap(dpy: pointer; p: XID): cint
  {.cdecl, dynlib: libX11, importc.}
proc XCreateGC(dpy: pointer; d: XID; mask: culong; values: pointer): pointer
  {.cdecl, dynlib: libX11, importc.}
proc XFreeGC(dpy: pointer; gc: pointer): cint
  {.cdecl, dynlib: libX11, importc.}
proc XSetForeground(dpy: pointer; gc: pointer; pixel: culong): cint
  {.cdecl, dynlib: libX11, importc.}
proc XFillRectangle(dpy: pointer; d: XID; gc: pointer;
  x, y: cint; w, h: cuint): cint
  {.cdecl, dynlib: libX11, importc.}
proc XDrawLine(dpy: pointer; d: XID; gc: pointer;
  x1, y1, x2, y2: cint): cint
  {.cdecl, dynlib: libX11, importc.}
proc XDrawPoint(dpy: pointer; d: XID; gc: pointer; x, y: cint): cint
  {.cdecl, dynlib: libX11, importc.}
proc XCopyArea(dpy: pointer; src, dst: XID; gc: pointer;
  srcX, srcY: cint; w, h: cuint; dstX, dstY: cint): cint
  {.cdecl, dynlib: libX11, importc.}
proc XSetClipRectangles(dpy: pointer; gc: pointer;
  x, y: cint; rects: ptr XRectangle; n, ordering: cint): cint
  {.cdecl, dynlib: libX11, importc.}
proc XSetClipMask(dpy: pointer; gc: pointer; pixmap: XID): cint
  {.cdecl, dynlib: libX11, importc.}
proc XNextEvent(dpy: pointer; ev: ptr XEvent): cint
  {.cdecl, dynlib: libX11, importc.}
proc XPending(dpy: pointer): cint
  {.cdecl, dynlib: libX11, importc.}
proc XFlush(dpy: pointer): cint
  {.cdecl, dynlib: libX11, importc.}
proc XStoreName(dpy: pointer; w: XID; name: cstring): cint
  {.cdecl, dynlib: libX11, importc.}
proc XInternAtom(dpy: pointer; name: cstring; onlyIfExists: XBool): Atom
  {.cdecl, dynlib: libX11, importc.}
proc XSetWMProtocols(dpy: pointer; w: XID; protocols: ptr Atom; count: cint): XStatus
  {.cdecl, dynlib: libX11, importc.}
proc XCreateFontCursor(dpy: pointer; shape: cuint): XID
  {.cdecl, dynlib: libX11, importc.}
proc XDefineCursor(dpy: pointer; w: XID; cursor: XID): cint
  {.cdecl, dynlib: libX11, importc.}
proc XLookupString(ev: ptr XKeyEvent; buf: cstring; bufSize: cint;
  keysym: ptr XKeySym; compose: pointer): cint
  {.cdecl, dynlib: libX11, importc.}
proc XSetSelectionOwner(dpy: pointer; selection: Atom; owner: XID; time: XTime): cint
  {.cdecl, dynlib: libX11, importc.}
proc XConvertSelection(dpy: pointer; selection, target, property: Atom;
  requestor: XID; time: XTime): cint
  {.cdecl, dynlib: libX11, importc.}
proc XChangeProperty(dpy: pointer; w: XID; property, propType: Atom;
  format, mode: cint; data: pointer; nelements: cint): cint
  {.cdecl, dynlib: libX11, importc.}
proc XGetWindowProperty(dpy: pointer; w: XID; property: Atom;
  offset, length: clong; delete: XBool; reqType: Atom;
  actualType: ptr Atom; actualFormat: ptr cint;
  nitems, bytesAfter: ptr culong; prop: ptr pointer): cint
  {.cdecl, dynlib: libX11, importc.}
proc XSendEvent(dpy: pointer; w: XID; propagate: XBool;
  mask: clong; ev: ptr XEvent): XStatus
  {.cdecl, dynlib: libX11, importc.}
proc XFree(data: pointer): cint
  {.cdecl, dynlib: libX11, importc.}
proc XCloseDisplay(dpy: pointer): cint
  {.cdecl, dynlib: libX11, importc.}

# ---- Xft function imports ----

proc XftFontOpenName(dpy: pointer; screen: cint; name: cstring): ptr XftFont
  {.cdecl, dynlib: libXft, importc.}
proc XftFontClose(dpy: pointer; font: ptr XftFont): void
  {.cdecl, dynlib: libXft, importc.}
proc XftDrawCreate(dpy: pointer; d: XID; visual: pointer; cmap: XID): pointer
  {.cdecl, dynlib: libXft, importc.}
proc XftDrawDestroy(draw: pointer): void
  {.cdecl, dynlib: libXft, importc.}
proc XftDrawChange(draw: pointer; d: XID): void
  {.cdecl, dynlib: libXft, importc.}
proc XftDrawStringUtf8(draw: pointer; color: ptr XftColor; font: ptr XftFont;
  x, y: cint; text: cstring; len: cint): void
  {.cdecl, dynlib: libXft, importc.}
proc XftTextExtentsUtf8(dpy: pointer; font: ptr XftFont;
  text: cstring; len: cint; extents: ptr XGlyphInfo): void
  {.cdecl, dynlib: libXft, importc.}
proc XftDrawRect(draw: pointer; color: ptr XftColor;
  x, y: cint; w, h: cuint): void
  {.cdecl, dynlib: libXft, importc.}
proc XftDrawSetClipRectangles(draw: pointer; x, y: cint;
  rects: ptr XRectangle; n: cint): XBool
  {.cdecl, dynlib: libXft, importc.}
proc XftDrawSetClip(draw: pointer; region: pointer): XBool
  {.cdecl, dynlib: libXft, importc.}

# ---- Helpers ----

proc toXftColor(c: screen.Color): XftColor =
  result.pixel = (c.r.culong shl 16) or (c.g.culong shl 8) or c.b.culong
  result.color = XRenderColor(
    red: c.r.cushort * 257,
    green: c.g.cushort * 257,
    blue: c.b.cushort * 257,
    alpha: c.a.cushort * 257)

proc toPixel(c: screen.Color): culong {.inline.} =
  (c.r.culong shl 16) or (c.g.culong shl 8) or c.b.culong

# ---- Font handle management ----

type
  FontSlot = object
    xftFont: ptr XftFont
    metrics: FontMetrics

var fonts: seq[FontSlot]

proc getFontPtr(f: screen.Font): ptr XftFont {.inline.} =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].xftFont
  else: nil

# ---- Driver state ----

var
  gDisplay: pointer
  gScreen: cint
  gVisual: pointer
  gColormap: XID
  gDepth: cint
  gWindow: XID
  gGC: pointer         # Xlib GC for primitives
  gBackPixmap: XID     # double buffer
  gXftDraw: pointer    # Xft draw context on back pixmap
  gWidth, gHeight: cint
  gWmDeleteWindow: Atom
  gClipboard: Atom
  gUtf8String: Atom
  gTargets: Atom
  gClipboardText: string
  gClipProperty: Atom

var eventQueue: seq[input.Event]

proc pushEvent(e: input.Event) =
  eventQueue.add e

# ---- Back-buffer management ----

proc recreateBackBuffer() =
  if gBackPixmap != None:
    XftDrawDestroy(gXftDraw)
    discard XFreePixmap(gDisplay, gBackPixmap)
  gBackPixmap = XCreatePixmap(gDisplay, gWindow,
    gWidth.cuint, gHeight.cuint, gDepth.cuint)
  gXftDraw = XftDrawCreate(gDisplay, gBackPixmap, gVisual, gColormap)
  # Clear to black
  discard XSetForeground(gDisplay, gGC, 0)
  discard XFillRectangle(gDisplay, gBackPixmap, gGC, 0, 0,
    gWidth.cuint, gHeight.cuint)

# ---- Key translation ----

proc translateKeySym(ks: XKeySym): input.KeyCode =
  if ks >= XK_a and ks <= XK_z:
    return input.KeyCode(ord(keyA) + (ks.int - XK_a.int))
  if ks >= XK_0 and ks <= XK_9:
    return input.KeyCode(ord(key0) + (ks.int - XK_0.int))
  if ks >= XK_F1 and ks <= XK_F12:
    return input.KeyCode(ord(keyF1) + (ks.int - XK_F1.int))
  case ks.uint
  of XK_Return: keyEnter
  of XK_space: keySpace
  of XK_Escape: keyEsc
  of XK_Tab: keyTab
  of XK_BackSpace: keyBackspace
  of XK_Delete: keyDelete
  of XK_Insert: keyInsert
  of XK_Left: keyLeft
  of XK_Right: keyRight
  of XK_Up: keyUp
  of XK_Down: keyDown
  of XK_Page_Up: keyPageUp
  of XK_Page_Down: keyPageDown
  of XK_Home: keyHome
  of XK_End: keyEnd
  of XK_Caps_Lock: keyCapslock
  of XK_comma: keyComma
  of XK_period: keyPeriod
  else: keyNone

proc translateMods(state: cuint): set[Modifier] =
  if (state and ShiftMask) != 0: result.incl modShift
  if (state and ControlMask) != 0: result.incl modCtrl
  if (state and Mod1Mask) != 0: result.incl modAlt
  if (state and Mod4Mask) != 0: result.incl modGui

proc translateButton(button: cuint): MouseButton =
  case button
  of Button1: mbLeft
  of Button3: mbRight
  of Button2: mbMiddle
  else: mbLeft

proc heldButtons(state: cuint): set[MouseButton] =
  if (state and Button1Mask) != 0: result.incl mbLeft
  if (state and Button2Mask) != 0: result.incl mbMiddle
  if (state and Button3Mask) != 0: result.incl mbRight

# ---- Clipboard handling ----

proc handleSelectionRequest(req: XSelectionRequestEvent) =
  var ev: XEvent
  zeroMem(addr ev, sizeof(XEvent))
  ev.xselection.theType = SelectionNotify
  ev.xselection.requestor = req.requestor
  ev.xselection.selection = req.selection
  ev.xselection.target = req.target
  ev.xselection.time = req.time

  if req.target == gUtf8String or req.target == XA_STRING:
    discard XChangeProperty(gDisplay, req.requestor, req.property,
      gUtf8String, 8, PropModeReplace,
      cstring(gClipboardText), gClipboardText.len.cint)
    ev.xselection.property = req.property
  elif req.target == gTargets:
    var targets = [gUtf8String, XA_STRING, gTargets]
    discard XChangeProperty(gDisplay, req.requestor, req.property,
      XA_ATOM, 32, PropModeReplace,
      addr targets[0], 3)
    ev.xselection.property = req.property
  else:
    ev.xselection.property = None

  discard XSendEvent(gDisplay, req.requestor, 0, 0, addr ev)

# ---- Event processing ----

var lastClickTime: XTime
var lastClickX, lastClickY: int
var clickCount: int

proc processXEvent(xev: XEvent) =
  case xev.theType
  of Expose:
    if xev.xexpose.count == 0 and gBackPixmap != None:
      discard XCopyArea(gDisplay, gBackPixmap, gWindow, gGC,
        0, 0, gWidth.cuint, gHeight.cuint, 0, 0)

  of ConfigureNotify:
    let newW = xev.xconfigure.width
    let newH = xev.xconfigure.height
    if newW > 0 and newH > 0 and (newW != gWidth or newH != gHeight):
      gWidth = newW
      gHeight = newH
      recreateBackBuffer()
      var e = input.Event(kind: evWindowResize)
      e.x = gWidth
      e.y = gHeight
      pushEvent(e)

  of ClientMessage:
    if xev.xclient.data[0] == gWmDeleteWindow.clong:
      pushEvent(input.Event(kind: evWindowClose))

  of FocusIn:
    pushEvent(input.Event(kind: evWindowFocusGained))

  of FocusOut:
    pushEvent(input.Event(kind: evWindowFocusLost))

  of KeyPress:
    var buf: array[8, char]
    var ks: XKeySym
    let textLen = XLookupString(unsafeAddr xev.xkey, cast[cstring](addr buf[0]),
      8, addr ks, nil)
    # Key event
    var e = input.Event(kind: evKeyDown)
    e.key = translateKeySym(ks)
    e.mods = translateMods(xev.xkey.state)
    pushEvent(e)
    # Text input (if printable)
    if textLen > 0 and buf[0].uint8 >= 32 and buf[0].uint8 != 127:
      var te = input.Event(kind: evTextInput)
      for i in 0 ..< min(textLen, 4):
        te.text[i] = buf[i]
      pushEvent(te)

  of KeyRelease:
    var ks: XKeySym
    discard XLookupString(unsafeAddr xev.xkey, nil, 0, addr ks, nil)
    var e = input.Event(kind: evKeyUp)
    e.key = translateKeySym(ks)
    e.mods = translateMods(xev.xkey.state)
    pushEvent(e)

  of ButtonPress:
    let btn = xev.xbutton.button
    if btn == Button4 or btn == Button5:
      # Scroll wheel
      var e = input.Event(kind: evMouseWheel)
      e.y = if btn == Button4: 1 else: -1
      pushEvent(e)
    else:
      var e = input.Event(kind: evMouseDown)
      e.x = xev.xbutton.x
      e.y = xev.xbutton.y
      e.button = translateButton(btn)
      e.mods = translateMods(xev.xbutton.state)
      # Click counting for double/triple click
      let now = xev.xbutton.time
      if now - lastClickTime < 500 and
         abs(e.x - lastClickX) < 4 and abs(e.y - lastClickY) < 4:
        inc clickCount
      else:
        clickCount = 1
      lastClickTime = now
      lastClickX = e.x
      lastClickY = e.y
      e.clicks = clickCount
      pushEvent(e)

  of ButtonRelease:
    let btn = xev.xbutton.button
    if btn != Button4 and btn != Button5:
      var e = input.Event(kind: evMouseUp)
      e.x = xev.xbutton.x
      e.y = xev.xbutton.y
      e.button = translateButton(btn)
      pushEvent(e)

  of MotionNotify:
    var e = input.Event(kind: evMouseMove)
    e.x = xev.xmotion.x
    e.y = xev.xmotion.y
    e.buttons = heldButtons(xev.xmotion.state)
    pushEvent(e)

  of SelectionRequest:
    handleSelectionRequest(xev.xselectionrequest)

  else:
    discard

proc drainXEvents() =
  while XPending(gDisplay) > 0:
    var xev: XEvent
    discard XNextEvent(gDisplay, addr xev)
    processXEvent(xev)

# ---- Screen hook implementations ----

proc x11CreateWindow(layout: var ScreenLayout) =
  gDisplay = XOpenDisplay(nil)
  if gDisplay == nil:
    quit("Cannot open X11 display")
  gScreen = XDefaultScreen(gDisplay)
  gVisual = XDefaultVisual(gDisplay, gScreen)
  gColormap = XDefaultColormap(gDisplay, gScreen)
  gDepth = XDefaultDepth(gDisplay, gScreen)

  gWindow = XCreateSimpleWindow(gDisplay, XRootWindow(gDisplay, gScreen),
    0, 0, layout.width.cuint, layout.height.cuint, 0,
    XBlackPixel(gDisplay, gScreen), XBlackPixel(gDisplay, gScreen))

  discard XSelectInput(gDisplay, gWindow,
    (ExposureMask or KeyPressMask or KeyReleaseMask or
     ButtonPressMask or ButtonReleaseMask or PointerMotionMask or
     StructureNotifyMask or FocusChangeMask).clong)

  # Register WM_DELETE_WINDOW
  gWmDeleteWindow = XInternAtom(gDisplay, "WM_DELETE_WINDOW", 0)
  discard XSetWMProtocols(gDisplay, gWindow, addr gWmDeleteWindow, 1)

  # Clipboard atoms
  gClipboard = XInternAtom(gDisplay, "CLIPBOARD", 0)
  gUtf8String = XInternAtom(gDisplay, "UTF8_STRING", 0)
  gTargets = XInternAtom(gDisplay, "TARGETS", 0)
  gClipProperty = XInternAtom(gDisplay, "NIMEDIT_CLIP", 0)

  discard XStoreName(gDisplay, gWindow, "NimEdit")
  discard XMapWindow(gDisplay, gWindow)

  gGC = XCreateGC(gDisplay, gWindow, 0, nil)

  # Wait for the first Expose/ConfigureNotify to get actual size
  gWidth = layout.width.cint
  gHeight = layout.height.cint
  recreateBackBuffer()

  layout.scaleX = 1
  layout.scaleY = 1

proc x11Refresh() =
  if gBackPixmap != None:
    discard XCopyArea(gDisplay, gBackPixmap, gWindow, gGC,
      0, 0, gWidth.cuint, gHeight.cuint, 0, 0)
  discard XFlush(gDisplay)

proc x11SaveState() = discard
proc x11RestoreState() =
  # Reset clip on both GC and XftDraw
  discard XSetClipMask(gDisplay, gGC, None)
  discard XftDrawSetClip(gXftDraw, nil)

proc x11SetClipRect(r: basetypes.Rect) =
  var xr = XRectangle(
    x: r.x.cshort, y: r.y.cshort,
    width: r.w.cushort, height: r.h.cushort)
  discard XSetClipRectangles(gDisplay, gGC, 0, 0, addr xr, 1, 0)
  discard XftDrawSetClipRectangles(gXftDraw, 0, 0, addr xr, 1)

proc x11OpenFont(path: string; size: int;
                 metrics: var FontMetrics): screen.Font =
  # Detect bold/italic from filename
  let lpath = path.toLowerAscii()
  let isBold = "bold" in lpath
  let isItalic = "italic" in lpath or "oblique" in lpath

  # Map known font filenames to fontconfig names
  var faceName = "monospace"  # safe default
  let baseName = path.extractFilename.toLowerAscii
  if "dejavu" in baseName and "mono" in baseName:
    faceName = "DejaVu Sans Mono"
  elif "dejavu" in baseName:
    faceName = "DejaVu Sans"
  elif "consola" in baseName:
    faceName = "Consolas"
  elif "courier" in baseName:
    faceName = "Courier New"
  elif "arial" in baseName:
    faceName = "Arial"
  elif "cascadia" in baseName:
    if "mono" in baseName: faceName = "Cascadia Mono"
    else: faceName = "Cascadia Code"
  elif "hack" in baseName:
    faceName = "Hack"
  elif "fira" in baseName and "code" in baseName:
    faceName = "Fira Code"
  elif "roboto" in baseName and "mono" in baseName:
    faceName = "Roboto Mono"
  elif "source" in baseName and "code" in baseName:
    faceName = "Source Code Pro"
  elif "jetbrains" in baseName:
    faceName = "JetBrains Mono"

  # Build Xft/fontconfig pattern
  var pattern = faceName & ":pixelsize=" & $size
  if isBold: pattern &= ":weight=bold"
  if isItalic: pattern &= ":slant=italic"

  let f = XftFontOpenName(gDisplay, gScreen, cstring(pattern))
  if f == nil: return screen.Font(0)

  metrics.ascent = f.ascent
  metrics.descent = f.descent
  metrics.lineHeight = f.height
  fonts.add FontSlot(xftFont: f, metrics: metrics)
  result = screen.Font(fonts.len)

proc x11CloseFont(f: screen.Font) =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len and fonts[idx].xftFont != nil:
    XftFontClose(gDisplay, fonts[idx].xftFont)
    fonts[idx].xftFont = nil

proc x11MeasureText(f: screen.Font; text: string): TextExtent =
  let fp = getFontPtr(f)
  if fp != nil and text.len > 0:
    var extents: XGlyphInfo
    XftTextExtentsUtf8(gDisplay, fp, cstring(text), text.len.cint, addr extents)
    result = TextExtent(w: extents.xOff.int, h: fp.height.int)

proc x11DrawText(f: screen.Font; x, y: int; text: string;
                 fg, bg: screen.Color): TextExtent =
  let fp = getFontPtr(f)
  if fp == nil or text.len == 0: return
  # Measure first for background fill
  var extents: XGlyphInfo
  XftTextExtentsUtf8(gDisplay, fp, cstring(text), text.len.cint, addr extents)
  result = TextExtent(w: extents.xOff.int, h: fp.height.int)
  # Fill background
  var bgColor = toXftColor(bg)
  XftDrawRect(gXftDraw, addr bgColor, x.cint, y.cint,
    extents.xOff.cuint, fp.height.cuint)
  # Draw text (y is baseline, not top)
  var fgColor = toXftColor(fg)
  XftDrawStringUtf8(gXftDraw, addr fgColor, fp,
    x.cint, (y + fp.ascent).cint, cstring(text), text.len.cint)

proc x11GetFontMetrics(f: screen.Font): FontMetrics =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].metrics
  else: screen.FontMetrics()

proc x11FillRect(r: basetypes.Rect; color: screen.Color) =
  var c = toXftColor(color)
  XftDrawRect(gXftDraw, addr c, r.x.cint, r.y.cint, r.w.cuint, r.h.cuint)

proc x11DrawLine(x1, y1, x2, y2: int; color: screen.Color) =
  discard XSetForeground(gDisplay, gGC, toPixel(color))
  discard XDrawLine(gDisplay, gBackPixmap, gGC,
    x1.cint, y1.cint, x2.cint, y2.cint)

proc x11DrawPoint(x, y: int; color: screen.Color) =
  discard XSetForeground(gDisplay, gGC, toPixel(color))
  discard XDrawPoint(gDisplay, gBackPixmap, gGC, x.cint, y.cint)

proc x11SetCursor(c: CursorKind) =
  let shape = case c
    of curDefault, curArrow: XC_left_ptr
    of curIbeam: XC_xterm
    of curWait: XC_watch
    of curCrosshair: XC_crosshair
    of curHand: XC_hand2
    of curSizeNS: XC_sb_v_double_arrow
    of curSizeWE: XC_sb_h_double_arrow
  let cur = XCreateFontCursor(gDisplay, shape)
  discard XDefineCursor(gDisplay, gWindow, cur)

proc x11SetWindowTitle(title: string) =
  discard XStoreName(gDisplay, gWindow, cstring(title))

# ---- Input hook implementations ----

proc x11PollEvent(e: var input.Event): bool =
  drainXEvents()
  if eventQueue.len > 0:
    e = eventQueue[0]
    eventQueue.delete(0)
    return true
  return false

proc x11WaitEvent(e: var input.Event; timeoutMs: int): bool =
  if eventQueue.len > 0:
    e = eventQueue[0]
    eventQueue.delete(0)
    return true
  if x11PollEvent(e): return true

  if timeoutMs < 0:
    # Block efficiently until an X11 event arrives
    var xev: XEvent
    discard XNextEvent(gDisplay, addr xev)
    processXEvent(xev)
    # Drain any remaining
    drainXEvents()
    if eventQueue.len > 0:
      e = eventQueue[0]
      eventQueue.delete(0)
      return true
    return false
  else:
    # Poll with short sleeps
    let deadline = getTicks() + timeoutMs.uint32
    while true:
      let now = getTicks()
      if now >= deadline: return false
      os.sleep(10)
      if x11PollEvent(e): return true

proc x11GetClipboardText(): string =
  discard XConvertSelection(gDisplay, gClipboard, gUtf8String,
    gClipProperty, gWindow, CurrentTime)
  discard XFlush(gDisplay)
  # Wait for SelectionNotify (with timeout)
  let deadline = getTicks() + 500  # 500ms timeout
  while getTicks() < deadline:
    if XPending(gDisplay) > 0:
      var xev: XEvent
      discard XNextEvent(gDisplay, addr xev)
      if xev.theType == SelectionNotify:
        if xev.xselection.property != None:
          var actualType: Atom
          var actualFormat: cint
          var nitems, bytesAfter: culong
          var data: pointer
          discard XGetWindowProperty(gDisplay, gWindow, gClipProperty,
            0, 1024*1024, 1, 0, # delete=True, AnyPropertyType
            addr actualType, addr actualFormat,
            addr nitems, addr bytesAfter, addr data)
          if data != nil:
            result = $cast[cstring](data)
            discard XFree(data)
        return
      else:
        processXEvent(xev)
    else:
      os.sleep(5)

proc x11PutClipboardText(text: string) =
  gClipboardText = text
  discard XSetSelectionOwner(gDisplay, gClipboard, gWindow, CurrentTime)

proc x11GetModState(): set[Modifier] =
  # X11 doesn't have a direct "get modifier state" API outside of events.
  # Return empty; the event-level mods are more reliable.
  result = {}

# ---- POSIX imports for getTicks ----

type
  ClockId {.importc: "clockid_t", header: "<time.h>".} = distinct cint
  Timespec {.importc: "struct timespec", header: "<time.h>".} = object
    tv_sec: clong
    tv_nsec: clong

proc clock_gettime(clk: ClockId; tp: var Timespec): cint
  {.importc, header: "<time.h>".}

proc x11GetTicks(): uint32 =
  # Use POSIX clock
  var ts: Timespec
  discard clock_gettime(0.ClockId, ts)  # CLOCK_REALTIME = 0
  result = uint32(ts.tv_sec.int64 * 1000 + ts.tv_nsec.int64 div 1_000_000)

proc x11Delay(ms: uint32) =
  # Drain events during delay to stay responsive
  let deadline = x11GetTicks() + ms
  while true:
    let now = x11GetTicks()
    if now >= deadline: break
    drainXEvents()
    os.sleep(min(int(deadline - now), 10))

proc x11StartTextInput() = discard
proc x11QuitRequest() =
  if gDisplay != nil:
    discard XDestroyWindow(gDisplay, gWindow)
    discard XCloseDisplay(gDisplay)


# ---- Init ----

proc initX11Driver*() =
  # Screen hooks
  createWindowRelay = x11CreateWindow
  refreshRelay = x11Refresh
  saveStateRelay = x11SaveState
  restoreStateRelay = x11RestoreState
  setClipRectRelay = x11SetClipRect
  openFontRelay = x11OpenFont
  closeFontRelay = x11CloseFont
  measureTextRelay = x11MeasureText
  drawTextRelay = x11DrawText
  getFontMetricsRelay = x11GetFontMetrics
  fillRectRelay = x11FillRect
  drawLineRelay = x11DrawLine
  drawPointRelay = x11DrawPoint
  setCursorRelay = x11SetCursor
  setWindowTitleRelay = x11SetWindowTitle
  # Input hooks
  pollEventRelay = x11PollEvent
  waitEventRelay = x11WaitEvent
  getClipboardTextRelay = x11GetClipboardText
  putClipboardTextRelay = x11PutClipboardText
  getModStateRelay = x11GetModState
  getTicksRelay = x11GetTicks
  delayRelay = x11Delay
  startTextInputRelay = x11StartTextInput
  quitRequestRelay = x11QuitRequest
