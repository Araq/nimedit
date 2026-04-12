# WinAPI (GDI) backend driver. Sets all hooks from core/input and core/screen.
# Uses a double-buffered GDI approach: draw to an off-screen bitmap,
# BitBlt to window on refresh.

import basetypes, input, screen
import std/[widestrs, strutils, os]

{.passL: "-lgdi32 -luser32 -lkernel32".}

# ---- Win32 type definitions ----

type
  UINT = uint32
  DWORD = uint32
  LONG = int32
  BOOL = int32
  BYTE = uint8
  WORD = uint16
  WPARAM = uint
  LPARAM = int
  LRESULT = int
  ATOM = WORD
  HANDLE = pointer
  HWND = HANDLE
  HDC = HANDLE
  HINSTANCE = HANDLE
  HBRUSH = HANDLE
  HBITMAP = HANDLE
  HFONT = HANDLE
  HCURSOR = HANDLE
  HICON = HANDLE
  HGDIOBJ = HANDLE
  HMENU = HANDLE
  HRGN = HANDLE
  HGLOBAL = HANDLE
  COLORREF = DWORD

  WNDCLASSEXW {.pure.} = object
    cbSize: UINT
    style: UINT
    lpfnWndProc: proc (hwnd: HWND; msg: UINT; wp: WPARAM; lp: LPARAM): LRESULT {.stdcall.}
    cbClsExtra: int32
    cbWndExtra: int32
    hInstance: HINSTANCE
    hIcon: HICON
    hCursor: HCURSOR
    hbrBackground: HBRUSH
    lpszMenuName: ptr uint16
    lpszClassName: ptr uint16
    hIconSm: HICON

  MSG {.pure.} = object
    hwnd: HWND
    message: UINT
    wParam: WPARAM
    lParam: LPARAM
    time: DWORD
    x: LONG
    y: LONG

  WINAPIPOINT {.pure.} = object
    x, y: LONG

  WINAPIRECT {.pure.} = object
    left, top, right, bottom: LONG

  PAINTSTRUCT {.pure.} = object
    hdc: HDC
    fErase: BOOL
    rcPaint: WINAPIRECT
    fRestore: BOOL
    fIncUpdate: BOOL
    rgbReserved: array[32, BYTE]

  TEXTMETRICW {.pure.} = object
    tmHeight: LONG
    tmAscent: LONG
    tmDescent: LONG
    tmInternalLeading: LONG
    tmExternalLeading: LONG
    tmAveCharWidth: LONG
    tmMaxCharWidth: LONG
    tmWeight: LONG
    tmOverhang: LONG
    tmDigitizedAspectX: LONG
    tmDigitizedAspectY: LONG
    tmFirstChar: uint16
    tmLastChar: uint16
    tmDefaultChar: uint16
    tmBreakChar: uint16
    tmItalic: BYTE
    tmUnderlined: BYTE
    tmStruckOut: BYTE
    tmPitchAndFamily: BYTE
    tmCharSet: BYTE

  SIZE {.pure.} = object
    cx, cy: LONG

# ---- Win32 constants ----

const
  CS_HREDRAW = 0x0002'u32
  CS_VREDRAW = 0x0001'u32
  WS_OVERLAPPEDWINDOW = 0x00CF0000'u32
  WS_VISIBLE = 0x10000000'u32

  WM_DESTROY = 0x0002'u32
  WM_SIZE = 0x0005'u32
  WM_PAINT = 0x000F'u32
  WM_CLOSE = 0x0010'u32
  WM_QUIT = 0x0012'u32
  WM_ERASEBKGND = 0x0014'u32
  WM_KEYDOWN = 0x0100'u32
  WM_KEYUP = 0x0101'u32
  WM_CHAR = 0x0102'u32
  WM_MOUSEMOVE = 0x0200'u32
  WM_LBUTTONDOWN = 0x0201'u32
  WM_LBUTTONUP = 0x0202'u32
  WM_RBUTTONDOWN = 0x0204'u32
  WM_RBUTTONUP = 0x0205'u32
  WM_MBUTTONDOWN = 0x0207'u32
  WM_MBUTTONUP = 0x0208'u32
  WM_MOUSEWHEEL = 0x020A'u32
  WM_SETFOCUS = 0x0007'u32
  WM_KILLFOCUS = 0x0008'u32

  PM_REMOVE = 0x0001'u32
  INFINITE = 0xFFFFFFFF'u32

  MK_LBUTTON = 0x0001'u32
  MK_RBUTTON = 0x0002'u32
  MK_MBUTTON = 0x0010'u32

  SW_SHOW = 5'i32
  TRANSPARENT = 1
  OPAQUE = 2

  SRCCOPY = 0x00CC0020'u32
  DIB_RGB_COLORS = 0'u32

  IDC_ARROW = cast[ptr uint16](32512)
  IDC_IBEAM = cast[ptr uint16](32513)
  IDC_WAIT = cast[ptr uint16](32514)
  IDC_CROSS = cast[ptr uint16](32515)
  IDC_HAND = cast[ptr uint16](32649)
  IDC_SIZENS = cast[ptr uint16](32645)
  IDC_SIZEWE = cast[ptr uint16](32644)

  VK_BACK = 0x08'u32
  VK_TAB = 0x09'u32
  VK_RETURN = 0x0D'u32
  VK_ESCAPE = 0x1B'u32
  VK_SPACE = 0x20'u32
  VK_DELETE = 0x2E'u32
  VK_INSERT = 0x2D'u32
  VK_LEFT = 0x25'u32
  VK_UP = 0x26'u32
  VK_RIGHT = 0x27'u32
  VK_DOWN = 0x28'u32
  VK_PRIOR = 0x21'u32  # Page Up
  VK_NEXT = 0x22'u32   # Page Down
  VK_HOME = 0x24'u32
  VK_END = 0x23'u32
  VK_CAPITAL = 0x14'u32
  VK_F1 = 0x70'u32
  VK_F12 = 0x7B'u32
  VK_OEM_COMMA = 0xBC'u32
  VK_OEM_PERIOD = 0xBE'u32
  VK_SHIFT = 0x10'u32
  VK_CONTROL = 0x11'u32
  VK_MENU = 0x12'u32   # Alt

  FW_NORMAL = 400'i32
  DEFAULT_CHARSET = 1'u8
  OUT_TT_PRECIS = 4'u32
  CLIP_DEFAULT_PRECIS = 0'u32
  CLEARTYPE_QUALITY = 5'u32
  FF_DONTCARE = 0'u32
  DEFAULT_PITCH = 0'u32

  CF_UNICODETEXT = 13'u32
  GMEM_MOVEABLE = 0x0002'u32

  WAIT_TIMEOUT = 258'u32
  QS_ALLINPUT = 0x04FF'u32

# ---- Win32 API imports ----

proc GetModuleHandleW(lpModuleName: ptr uint16): HINSTANCE
  {.stdcall, dynlib: "kernel32", importc.}
proc GetLastError(): DWORD
  {.stdcall, dynlib: "kernel32", importc.}
proc GetTickCount(): DWORD
  {.stdcall, dynlib: "kernel32", importc.}
proc Sleep(dwMilliseconds: DWORD)
  {.stdcall, dynlib: "kernel32", importc.}
proc GlobalAlloc(uFlags: UINT; dwBytes: uint): HGLOBAL
  {.stdcall, dynlib: "kernel32", importc.}
proc GlobalLock(hMem: HGLOBAL): pointer
  {.stdcall, dynlib: "kernel32", importc.}
proc GlobalUnlock(hMem: HGLOBAL): BOOL
  {.stdcall, dynlib: "kernel32", importc.}
proc GlobalSize(hMem: HGLOBAL): uint
  {.stdcall, dynlib: "kernel32", importc.}

proc RegisterClassExW(lpwcx: ptr WNDCLASSEXW): ATOM
  {.stdcall, dynlib: "user32", importc.}
proc CreateWindowExW(dwExStyle: DWORD; lpClassName, lpWindowName: ptr uint16;
  dwStyle: DWORD; x, y, nWidth, nHeight: int32;
  hWndParent: HWND; hMenu: HMENU; hInstance: HINSTANCE;
  lpParam: pointer): HWND
  {.stdcall, dynlib: "user32", importc.}
proc ShowWindow(hWnd: HWND; nCmdShow: int32): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc UpdateWindow(hWnd: HWND): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc DestroyWindow(hWnd: HWND): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc PostQuitMessage(nExitCode: int32)
  {.stdcall, dynlib: "user32", importc.}
proc DefWindowProcW(hWnd: HWND; msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT
  {.stdcall, dynlib: "user32", importc.}
proc PeekMessageW(lpMsg: ptr MSG; hWnd: HWND; wMsgFilterMin, wMsgFilterMax: UINT;
  wRemoveMsg: UINT): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc TranslateMessage(lpMsg: ptr MSG): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc DispatchMessageW(lpMsg: ptr MSG): LRESULT
  {.stdcall, dynlib: "user32", importc.}
proc GetClientRect(hWnd: HWND; lpRect: ptr WINAPIRECT): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc InvalidateRect(hWnd: HWND; lpRect: ptr WINAPIRECT; bErase: BOOL): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc BeginPaint(hWnd: HWND; lpPaint: ptr PAINTSTRUCT): HDC
  {.stdcall, dynlib: "user32", importc.}
proc EndPaint(hWnd: HWND; lpPaint: ptr PAINTSTRUCT): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc GetDC(hWnd: HWND): HDC
  {.stdcall, dynlib: "user32", importc.}
proc ReleaseDC(hWnd: HWND; hDC: HDC): int32
  {.stdcall, dynlib: "user32", importc.}
proc SetWindowTextW(hWnd: HWND; lpString: ptr uint16): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc LoadCursorW(hInstance: HINSTANCE; lpCursorName: ptr uint16): HCURSOR
  {.stdcall, dynlib: "user32", importc.}
proc SetCursorWin(hCursor: HCURSOR): HCURSOR
  {.stdcall, dynlib: "user32", importc: "SetCursor".}
proc GetKeyState(nVirtKey: int32): int16
  {.stdcall, dynlib: "user32", importc.}
proc OpenClipboard(hWndNewOwner: HWND): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc CloseClipboard(): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc EmptyClipboard(): BOOL
  {.stdcall, dynlib: "user32", importc.}
proc GetClipboardData(uFormat: UINT): HANDLE
  {.stdcall, dynlib: "user32", importc.}
proc SetClipboardData(uFormat: UINT; hMem: HANDLE): HANDLE
  {.stdcall, dynlib: "user32", importc.}
proc MsgWaitForMultipleObjects(nCount: DWORD; pHandles: pointer;
  fWaitAll: BOOL; dwMilliseconds: DWORD; dwWakeMask: DWORD): DWORD
  {.stdcall, dynlib: "user32", importc.}

proc CreateCompatibleDC(hdc: HDC): HDC
  {.stdcall, dynlib: "gdi32", importc.}
proc CreateCompatibleBitmap(hdc: HDC; cx, cy: int32): HBITMAP
  {.stdcall, dynlib: "gdi32", importc.}
proc SelectObject(hdc: HDC; h: HGDIOBJ): HGDIOBJ
  {.stdcall, dynlib: "gdi32", importc.}
proc DeleteObject(ho: HGDIOBJ): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc DeleteDC(hdc: HDC): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc BitBlt(hdc: HDC; x, y, cx, cy: int32; hdcSrc: HDC;
  x1, y1: int32; rop: DWORD): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc SetBkMode(hdc: HDC; mode: int32): int32
  {.stdcall, dynlib: "gdi32", importc.}
proc SetBkColor(hdc: HDC; color: COLORREF): COLORREF
  {.stdcall, dynlib: "gdi32", importc.}
proc SetTextColor(hdc: HDC; color: COLORREF): COLORREF
  {.stdcall, dynlib: "gdi32", importc.}
proc TextOutW(hdc: HDC; x, y: int32; lpString: ptr uint16; c: int32): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc GetTextExtentPoint32W(hdc: HDC; lpString: ptr uint16; c: int32;
  lpSize: ptr SIZE): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc GetTextMetricsW(hdc: HDC; lptm: ptr TEXTMETRICW): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc CreateFontW(cHeight, cWidth, cEscapement, cOrientation, cWeight: int32;
  bItalic, bUnderline, bStrikeOut: DWORD;
  iCharSet: DWORD; iOutPrecision, iClipPrecision, iQuality: DWORD;
  iPitchAndFamily: DWORD; pszFaceName: ptr uint16): HFONT
  {.stdcall, dynlib: "gdi32", importc.}
proc CreateSolidBrush(color: COLORREF): HBRUSH
  {.stdcall, dynlib: "gdi32", importc.}
proc FillRectGdi(hDC: HDC; lprc: ptr WINAPIRECT; hbr: HBRUSH): int32
  {.stdcall, dynlib: "user32", importc: "FillRect".}
proc MoveToEx(hdc: HDC; x, y: int32; lppt: ptr WINAPIPOINT): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc LineTo(hdc: HDC; x, y: int32): BOOL
  {.stdcall, dynlib: "gdi32", importc.}
proc CreatePen(iStyle, cWidth: int32; color: COLORREF): HGDIOBJ
  {.stdcall, dynlib: "gdi32", importc.}
proc SetPixel(hdc: HDC; x, y: int32; color: COLORREF): COLORREF
  {.stdcall, dynlib: "gdi32", importc.}
proc IntersectClipRect(hdc: HDC; left, top, right, bottom: int32): int32
  {.stdcall, dynlib: "gdi32", importc.}
proc SelectClipRgn(hdc: HDC; hrgn: HRGN): int32
  {.stdcall, dynlib: "gdi32", importc.}
proc CreateRectRgn(x1, y1, x2, y2: int32): HRGN
  {.stdcall, dynlib: "gdi32", importc.}
proc AddFontResourceExW(name: ptr uint16; fl: DWORD; res: pointer): int32
  {.stdcall, dynlib: "gdi32", importc.}

# ---- Helpers ----

proc rgb(c: screen.Color): COLORREF {.inline.} =
  COLORREF(c.r.uint32 or (c.g.uint32 shl 8) or (c.b.uint32 shl 16))

proc loWord(lp: LPARAM): int {.inline.} = int(lp and 0xFFFF)
proc hiWord(lp: LPARAM): int {.inline.} = int((lp shr 16) and 0xFFFF)
proc signedHiWord(wp: WPARAM): int {.inline.} =
  ## For WM_MOUSEWHEEL: wParam high word is signed
  cast[int16](uint16((wp shr 16) and 0xFFFF)).int

# ---- Font handle management ----

type
  FontSlot = object
    hFont: HFONT
    metrics: FontMetrics
    faceName: string
    size: int

var fonts: seq[FontSlot]

proc getFontHandle(f: screen.Font): HFONT {.inline.} =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].hFont
  else: nil

# ---- Driver state ----

var
  gHwnd: HWND
  gHinstance: HINSTANCE
  gBackDC: HDC        # off-screen DC for double buffering
  gBackBmp: HBITMAP   # off-screen bitmap
  gOldBmp: HGDIOBJ    # original bitmap selected into gBackDC
  gWidth, gHeight: int32
  gQuitFlag: bool
  gSavedClipRgn: HRGN

# Event queue: WndProc pushes events, pollEvent/waitEvent consumes them
var eventQueue: seq[input.Event]

proc pushEvent(e: input.Event) =
  eventQueue.add e

# ---- Back-buffer management ----

proc recreateBackBuffer() =
  let screenDC = GetDC(gHwnd)
  let newBmp = CreateCompatibleBitmap(screenDC, gWidth, gHeight)
  if gBackDC == nil:
    gBackDC = CreateCompatibleDC(screenDC)
  if gBackBmp != nil:
    discard SelectObject(gBackDC, cast[HGDIOBJ](newBmp))
    discard DeleteObject(cast[HGDIOBJ](gBackBmp))
  else:
    gOldBmp = SelectObject(gBackDC, cast[HGDIOBJ](newBmp))
  gBackBmp = newBmp
  # Clear to opaque black -- CreateCompatibleBitmap inits to all zeros which
  # DWM interprets as fully transparent on 32-bit displays.
  var rc = WINAPIRECT(left: 0, top: 0, right: gWidth, bottom: gHeight)
  let blackBrush = CreateSolidBrush(0x00000000'u32)
  discard FillRectGdi(gBackDC, addr rc, blackBrush)
  discard DeleteObject(cast[HGDIOBJ](blackBrush))
  discard ReleaseDC(gHwnd, screenDC)

# ---- WndProc ----

proc translateVK(vk: WPARAM): input.KeyCode =
  let vk = vk.uint32
  if vk >= ord('A').uint32 and vk <= ord('Z').uint32:
    return input.KeyCode(ord(KeyA) + (vk.int - ord('A')))
  if vk >= ord('0').uint32 and vk <= ord('9').uint32:
    return input.KeyCode(ord(Key0) + (vk.int - ord('0')))
  if vk >= VK_F1 and vk <= VK_F12:
    return input.KeyCode(ord(KeyF1) + (vk.int - VK_F1.int))
  case vk
  of VK_RETURN: KeyEnter
  of VK_SPACE: KeySpace
  of VK_ESCAPE: KeyEsc
  of VK_TAB: KeyTab
  of VK_BACK: KeyBackspace
  of VK_DELETE: KeyDelete
  of VK_INSERT: KeyInsert
  of VK_LEFT: KeyLeft
  of VK_RIGHT: KeyRight
  of VK_UP: KeyUp
  of VK_DOWN: KeyDown
  of VK_PRIOR: KeyPageUp
  of VK_NEXT: KeyPageDown
  of VK_HOME: KeyHome
  of VK_END: KeyEnd
  of VK_CAPITAL: KeyCapslock
  of VK_OEM_COMMA: KeyComma
  of VK_OEM_PERIOD: KeyPeriod
  else: KeyNone

proc getModifiers(): set[Modifier] =
  if GetKeyState(VK_SHIFT.int32) < 0: result.incl ShiftPressed
  if GetKeyState(VK_CONTROL.int32) < 0: result.incl CtrlPressed
  if GetKeyState(VK_MENU.int32) < 0: result.incl AltPressed

proc getMouseButtons(wp: WPARAM): set[MouseButton] =
  let flags = wp.uint32
  if (flags and MK_LBUTTON) != 0: result.incl LeftButton
  if (flags and MK_RBUTTON) != 0: result.incl RightButton
  if (flags and MK_MBUTTON) != 0: result.incl MiddleButton

var lastClickTime: DWORD
var lastClickX, lastClickY: int
var clickCount: int

proc pumpMessages() =
  ## Drain Win32 message queue. Must be called frequently to prevent
  ## the "Not Responding" ghost window (Windows triggers it after ~5s
  ## of not processing sent messages).
  var msg: MSG
  while PeekMessageW(addr msg, nil, 0, 0, PM_REMOVE) != 0:
    discard TranslateMessage(addr msg)
    discard DispatchMessageW(addr msg)
    if msg.message == WM_QUIT:
      pushEvent(input.Event(kind: QuitEvent))

proc wndProc(hwnd: HWND; msg: UINT; wp: WPARAM; lp: LPARAM): LRESULT {.stdcall.} =
  # Capture gHwnd from the first message -- WM_SIZE etc. arrive
  # during CreateWindowExW, *before* it returns and assigns gHwnd.
  if gHwnd == nil and hwnd != nil:
    gHwnd = hwnd
  case msg
  of WM_DESTROY:
    PostQuitMessage(0)
    pushEvent(input.Event(kind: QuitEvent))
    return 0

  of WM_CLOSE:
    pushEvent(input.Event(kind: WindowCloseEvent))
    return 0  # don't call DestroyWindow yet; let the app decide

  of WM_ERASEBKGND:
    return 1  # we handle erasing via double buffer

  of WM_SIZE:
    let newW = loWord(lp).int32
    let newH = hiWord(lp).int32
    if newW > 0 and newH > 0 and (newW != gWidth or newH != gHeight):
      gWidth = newW
      gHeight = newH
      recreateBackBuffer()
      var e = input.Event(kind: WindowResizeEvent)
      e.x = gWidth
      e.y = gHeight
      pushEvent(e)
    return 0

  of WM_PAINT:
    var ps: PAINTSTRUCT
    let hdc = BeginPaint(hwnd, addr ps)
    if gBackDC != nil:
      discard BitBlt(hdc, 0, 0, gWidth, gHeight, gBackDC, 0, 0, SRCCOPY)
    discard EndPaint(hwnd, addr ps)
    return 0

  of WM_KEYDOWN:
    var e = input.Event(kind: KeyDownEvent)
    e.key = translateVK(wp)
    e.mods = getModifiers()
    pushEvent(e)
    return 0

  of WM_KEYUP:
    var e = input.Event(kind: KeyUpEvent)
    e.key = translateVK(wp)
    e.mods = getModifiers()
    pushEvent(e)
    return 0

  of WM_CHAR:
    # wp is a UTF-16 code unit. For BMP characters, emit TextInputEvent.
    let ch = wp.uint16
    if ch >= 32 and ch != 127:
      var e = input.Event(kind: TextInputEvent)
      # Convert UTF-16 to UTF-8 into e.text[0..3]
      let codepoint = ch.uint32
      if codepoint < 0x80:
        e.text[0] = chr(codepoint)
      elif codepoint < 0x800:
        e.text[0] = chr(0xC0 or (codepoint shr 6))
        e.text[1] = chr(0x80 or (codepoint and 0x3F))
      else:
        e.text[0] = chr(0xE0 or (codepoint shr 12))
        e.text[1] = chr(0x80 or ((codepoint shr 6) and 0x3F))
        e.text[2] = chr(0x80 or (codepoint and 0x3F))
      pushEvent(e)
    return 0

  of WM_SETFOCUS:
    pushEvent(input.Event(kind: WindowFocusGainedEvent))
    return 0

  of WM_KILLFOCUS:
    pushEvent(input.Event(kind: WindowFocusLostEvent))
    return 0

  of WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
    var e = input.Event(kind: MouseDownEvent)
    e.x = loWord(lp)
    e.y = hiWord(lp)
    e.mods = getModifiers()
    case msg
    of WM_LBUTTONDOWN: e.button = LeftButton
    of WM_RBUTTONDOWN: e.button = RightButton
    else: e.button = MiddleButton
    # Track click count for double/triple click
    let now = GetTickCount()
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
    return 0

  of WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP:
    var e = input.Event(kind: MouseUpEvent)
    e.x = loWord(lp)
    e.y = hiWord(lp)
    case msg
    of WM_LBUTTONUP: e.button = LeftButton
    of WM_RBUTTONUP: e.button = RightButton
    else: e.button = MiddleButton
    pushEvent(e)
    return 0

  of WM_MOUSEMOVE:
    var e = input.Event(kind: MouseMoveEvent)
    e.x = loWord(lp)
    e.y = hiWord(lp)
    e.buttons = getMouseButtons(wp)
    pushEvent(e)
    return 0

  of WM_MOUSEWHEEL:
    var e = input.Event(kind: MouseWheelEvent)
    let delta = signedHiWord(wp)
    e.y = delta div 120  # standard wheel delta
    var pt = WINAPIPOINT(x: loWord(lp).LONG, y: hiWord(lp).LONG)
    # wheel coords are screen-relative; could ScreenToClient but
    # Nimedit only uses e.y for scroll direction
    pushEvent(e)
    return 0

  else:
    discard

  return DefWindowProcW(hwnd, msg, wp, lp)

# ---- Screen hook implementations ----

proc winCreateWindow(layout: var ScreenLayout) =
  gHinstance = GetModuleHandleW(nil)
  let className = newWideCString("NimEditWinAPI")

  var wc: WNDCLASSEXW
  wc.cbSize = UINT(sizeof(WNDCLASSEXW))
  wc.style = CS_HREDRAW or CS_VREDRAW
  wc.lpfnWndProc = wndProc
  wc.hInstance = gHinstance
  wc.hCursor = LoadCursorW(nil, IDC_ARROW)
  wc.lpszClassName = cast[ptr uint16](className[0].addr)

  discard RegisterClassExW(addr wc)

  let title = newWideCString("NimEdit")
  gHwnd = CreateWindowExW(
    0,
    cast[ptr uint16](className[0].addr),
    cast[ptr uint16](title[0].addr),
    WS_OVERLAPPEDWINDOW or WS_VISIBLE,
    0x80000000'i32, 0x80000000'i32, # CW_USEDEFAULT
    layout.width.int32, layout.height.int32,
    nil, nil, gHinstance, nil)

  if gHwnd == nil:
    quit("CreateWindowExW failed")

  discard ShowWindow(gHwnd, SW_SHOW)
  discard UpdateWindow(gHwnd)

  var rc: WINAPIRECT
  discard GetClientRect(gHwnd, addr rc)
  gWidth = rc.right - rc.left
  gHeight = rc.bottom - rc.top
  layout.width = gWidth
  layout.height = gHeight
  layout.scaleX = 1
  layout.scaleY = 1

  recreateBackBuffer()

proc winRefresh() =
  discard InvalidateRect(gHwnd, nil, 0)
  discard UpdateWindow(gHwnd)

proc winSaveState() =
  # Save current clip region
  gSavedClipRgn = CreateRectRgn(0, 0, 0, 0)
  # GetClipRgn not easily available; we just reset to full on restore
  discard

proc winRestoreState() =
  # Restore by removing clip region
  if gBackDC != nil:
    discard SelectClipRgn(gBackDC, nil)
  if gSavedClipRgn != nil:
    discard DeleteObject(cast[HGDIOBJ](gSavedClipRgn))
    gSavedClipRgn = nil

proc winSetClipRect(r: basetypes.Rect) =
  if gBackDC != nil:
    # Reset clip region first, then set new one
    discard SelectClipRgn(gBackDC, nil)
    discard IntersectClipRect(gBackDC,
      r.x.int32, r.y.int32, (r.x + r.w).int32, (r.y + r.h).int32)

proc winOpenFont(path: string; size: int;
                 metrics: var FontMetrics): screen.Font =
  # Ensure the font file is available as a private resource (needed for
  # fonts outside C:\Windows\Fonts, harmless for system-installed ones).
  let wpath = newWideCString(path)
  let FR_PRIVATE = 0x10'u32
  discard AddFontResourceExW(cast[ptr uint16](wpath[0].addr), FR_PRIVATE, nil)

  # Detect bold/italic from filename
  let lpath = path.toLowerAscii()
  let isBold = "bold" in lpath
  let isItalic = "italic" in lpath or "oblique" in lpath
  let weight = if isBold: 700'i32 else: FW_NORMAL
  let italic = if isItalic: 1'u32 else: 0'u32
  let FIXED_PITCH = 1'u32

  # Map known font filenames to their GDI face names.
  # Consolas is the safe default -- ships since Vista with excellent
  # ClearType hinting.
  var faceName = "Consolas"
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
  elif "segoe" in baseName:
    faceName = "Segoe UI"
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
  else:
    # Unknown font -- use the filename stem as face name
    var stem = path.extractFilename
    let dot = stem.rfind('.')
    if dot >= 0: stem = stem[0 ..< dot]
    for suffix in ["-BoldOblique", "-BoldItalic", "-Bold", "-Oblique",
                   "-Italic", "-Regular"]:
      if stem.endsWith(suffix):
        stem = stem[0 ..< stem.len - suffix.len]
        break
    faceName = stem

  let wface = newWideCString(faceName)
  let hf = CreateFontW(
    -size.int32,          # negative = character height in pixels
    0, 0, 0,              # width, escapement, orientation
    weight,
    italic, 0, 0,         # italic, underline, strikeout
    DEFAULT_CHARSET.DWORD,
    OUT_TT_PRECIS,
    CLIP_DEFAULT_PRECIS,
    CLEARTYPE_QUALITY,
    FIXED_PITCH or FF_DONTCARE,
    cast[ptr uint16](wface[0].addr)
  )

  if hf == nil:
    return screen.Font(0)

  # Get font metrics
  let oldFont = SelectObject(gBackDC, cast[HGDIOBJ](hf))
  var tm: TEXTMETRICW
  discard GetTextMetricsW(gBackDC, addr tm)
  discard SelectObject(gBackDC, oldFont)

  metrics.ascent = tm.tmAscent.int
  metrics.descent = tm.tmDescent.int
  metrics.lineHeight = tm.tmHeight.int + tm.tmExternalLeading.int

  fonts.add FontSlot(hFont: hf, metrics: metrics, faceName: path, size: size)
  result = screen.Font(fonts.len)

proc winCloseFont(f: screen.Font) =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len and fonts[idx].hFont != nil:
    discard DeleteObject(cast[HGDIOBJ](fonts[idx].hFont))
    fonts[idx].hFont = nil

proc winMeasureText(f: screen.Font; text: string): TextExtent =
  let hf = getFontHandle(f)
  if hf == nil or text.len == 0: return
  let oldFont = SelectObject(gBackDC, cast[HGDIOBJ](hf))
  let wtext = newWideCString(text)
  var sz: SIZE
  discard GetTextExtentPoint32W(gBackDC, cast[ptr uint16](wtext[0].addr),
    wtext.len.int32, addr sz)
  discard SelectObject(gBackDC, oldFont)
  result = TextExtent(w: sz.cx.int, h: sz.cy.int)

proc winDrawText(f: screen.Font; x, y: int; text: string;
                 fg, bg: screen.Color): TextExtent =
  let hf = getFontHandle(f)
  if hf == nil or text.len == 0: return
  let oldFont = SelectObject(gBackDC, cast[HGDIOBJ](hf))
  discard SetBkMode(gBackDC, OPAQUE)
  discard SetBkColor(gBackDC, rgb(bg))
  discard SetTextColor(gBackDC, rgb(fg))
  let wtext = newWideCString(text)
  let wlen = wtext.len.int32
  discard TextOutW(gBackDC, x.int32, y.int32,
    cast[ptr uint16](wtext[0].addr), wlen)
  var sz: SIZE
  discard GetTextExtentPoint32W(gBackDC, cast[ptr uint16](wtext[0].addr),
    wlen, addr sz)
  discard SelectObject(gBackDC, oldFont)
  result = TextExtent(w: sz.cx.int, h: sz.cy.int)

proc winGetFontMetrics(f: screen.Font): FontMetrics =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].metrics
  else: screen.FontMetrics()

proc winFillRect(r: basetypes.Rect; color: screen.Color) =
  let brush = CreateSolidBrush(rgb(color))
  var wr = WINAPIRECT(
    left: r.x.int32, top: r.y.int32,
    right: (r.x + r.w).int32, bottom: (r.y + r.h).int32)
  discard FillRectGdi(gBackDC, addr wr, brush)
  discard DeleteObject(cast[HGDIOBJ](brush))

proc winDrawLine(x1, y1, x2, y2: int; color: screen.Color) =
  let pen = CreatePen(0, 1, rgb(color)) # PS_SOLID = 0
  let oldPen = SelectObject(gBackDC, pen)
  discard MoveToEx(gBackDC, x1.int32, y1.int32, nil)
  discard LineTo(gBackDC, x2.int32, y2.int32)
  discard SelectObject(gBackDC, oldPen)
  discard DeleteObject(pen)

proc winDrawPoint(x, y: int; color: screen.Color) =
  discard SetPixel(gBackDC, x.int32, y.int32, rgb(color))

proc winSetCursor(c: CursorKind) =
  let id = case c
    of curDefault, curArrow: IDC_ARROW
    of curIbeam: IDC_IBEAM
    of curWait: IDC_WAIT
    of curCrosshair: IDC_CROSS
    of curHand: IDC_HAND
    of curSizeNS: IDC_SIZENS
    of curSizeWE: IDC_SIZEWE
  let cur = LoadCursorW(nil, id)
  discard SetCursorWin(cur)

proc winSetWindowTitle(title: string) =
  if gHwnd != nil:
    let wtitle = newWideCString(title)
    discard SetWindowTextW(gHwnd, cast[ptr uint16](wtitle[0].addr))

# ---- Input hook implementations ----

proc winPollEvent(e: var input.Event; flags: set[InputFlag]): bool =
  pumpMessages()
  if eventQueue.len > 0:
    e = eventQueue[0]
    eventQueue.delete(0)
    return true
  return false

proc winWaitEvent(e: var input.Event; timeoutMs: int;
                  flags: set[InputFlag]): bool =
  # Check already-queued events first
  if eventQueue.len > 0:
    e = eventQueue[0]
    eventQueue.delete(0)
    return true
  # Drain any pending Win32 messages before blocking
  if winPollEvent(e, flags):
    return true
  # Pump messages in a loop with short sleeps, like SDL does internally.
  # A single MWFMO(INFINITE) would block the thread entirely, causing
  # Windows to show the "Not Responding" ghost window after ~5 seconds
  # which then intercepts all user input -- deadlock.
  let deadline = if timeoutMs < 0: uint32.high
                 else: GetTickCount() + timeoutMs.uint32
  while true:
    let now = GetTickCount()
    if now >= deadline: return false
    let remaining = if timeoutMs < 0: 100'u32
                    else: min(deadline - now, 100'u32)
    let res = MsgWaitForMultipleObjects(0, nil, 0, remaining, QS_ALLINPUT)
    if res != WAIT_TIMEOUT:
      if winPollEvent(e, flags): return true
    elif timeoutMs >= 0:
      # Finite timeout: check if expired
      if GetTickCount() >= deadline: return false

proc winGetClipboardText(): string =
  if OpenClipboard(gHwnd) == 0: return ""
  let hData = GetClipboardData(CF_UNICODETEXT)
  if hData != nil:
    let p = cast[ptr UncheckedArray[uint16]](GlobalLock(cast[HGLOBAL](hData)))
    if p != nil:
      var wlen = 0
      while p[wlen] != 0: inc wlen
      var ws = newWideCString("", wlen)
      copyMem(addr ws[0], p, wlen * 2)
      result = $ws
      discard GlobalUnlock(cast[HGLOBAL](hData))
  discard CloseClipboard()

proc winPutClipboardText(text: string) =
  if OpenClipboard(gHwnd) == 0: return
  discard EmptyClipboard()
  let ws = newWideCString(text)
  let bytes = (ws.len + 1) * 2
  let hMem = GlobalAlloc(GMEM_MOVEABLE, bytes.uint)
  if hMem != nil:
    let p = GlobalLock(hMem)
    if p != nil:
      copyMem(p, addr ws[0], bytes)
      discard GlobalUnlock(hMem)
      discard SetClipboardData(CF_UNICODETEXT, cast[HANDLE](hMem))
  discard CloseClipboard()

proc winGetTicks(): int = GetTickCount().int
proc winDelay(ms: int) =
  let msU = ms.DWORD
  let deadline = GetTickCount() + msU
  while true:
    let now = GetTickCount()
    if now >= deadline: break
    let remaining = min(deadline - now, msU)
    discard MsgWaitForMultipleObjects(0, nil, 0, remaining, QS_ALLINPUT)
    pumpMessages()
proc winQuitRequest() =
  gQuitFlag = true
  if gHwnd != nil:
    discard DestroyWindow(gHwnd)

# ---- Init ----

proc setDpiAware() =
  # Try the modern API first (Windows 10 1703+), fall back to older ones.
  # Without this, Windows bitmap-scales the window on high-DPI displays,
  # causing blurry/pixelated rendering.
  type DPI_AWARENESS_CONTEXT = HANDLE
  try:
    proc SetProcessDpiAwarenessContext(value: DPI_AWARENESS_CONTEXT): BOOL
      {.stdcall, dynlib: "user32", importc.}
    let DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = cast[DPI_AWARENESS_CONTEXT](-4)
    if SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) != 0:
      return
  except: discard
  try:
    proc SetProcessDPIAware(): BOOL
      {.stdcall, dynlib: "user32", importc.}
    discard SetProcessDPIAware()
  except: discard

proc initWinapiDriver*() =
  setDpiAware()
  windowRelays = WindowRelays(
    createWindow: winCreateWindow, refresh: winRefresh,
    saveState: winSaveState, restoreState: winRestoreState,
    setClipRect: winSetClipRect, setCursor: winSetCursor,
    setWindowTitle: winSetWindowTitle)
  fontRelays = FontRelays(
    openFont: winOpenFont, closeFont: winCloseFont,
    getFontMetrics: winGetFontMetrics, measureText: winMeasureText,
    drawText: winDrawText)
  drawRelays = DrawRelays(
    fillRect: winFillRect, drawLine: winDrawLine, drawPoint: winDrawPoint)
  inputRelays = InputRelays(
    pollEvent: winPollEvent, waitEvent: winWaitEvent,
    getTicks: winGetTicks, delay: winDelay,
    quitRequest: winQuitRequest)
  clipboardRelays = ClipboardRelays(
    getText: winGetClipboardText, putText: winPutClipboardText)
