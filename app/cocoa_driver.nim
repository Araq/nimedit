# Cocoa/AppKit backend driver for macOS.
# Sets all hooks from core/input and core/screen.
#
# Build:  nim c -d:cocoa app/nimedit.nim
# Requires macOS 10.15+ (Catalina). No external dependencies.

{.compile("cocoa_backend.m", "-fobjc-arc").}
{.passL: "-framework Cocoa -framework CoreText -framework CoreGraphics -framework QuartzCore".}

{.emit: """
typedef struct {
  int kind;
  int key;
  int mods;
  char text[4];
  int x, y;
  int xrel, yrel;
  int button;
  int buttons;
  int clicks;
} NEEvent;
""".}

import basetypes, input, screen

# --- C bindings to cocoa_backend.m ---
# All procs use {.importc.} with explicit C names to avoid Nim's
# identifier normalisation colliding with the Nim wrapper procs.

type
  NEEvent {.importc, nodecl.} = object
    kind: cint
    key: cint
    mods: cint
    text: array[4, char]
    x, y: cint
    xrel, yrel: cint
    button: cint
    buttons: cint
    clicks: cint

# Event kinds (must match cocoa_backend.m)
const
  neNone = 0.cint
  neKeyDown = 1.cint
  neKeyUp = 2.cint
  neTextInput = 3.cint
  neMouseDown = 4.cint
  neMouseUp = 5.cint
  neMouseMove = 6.cint
  neMouseWheel = 7.cint
  neWindowResize = 8.cint
  neWindowClose = 9.cint
  neWindowFocusGained = 10.cint
  neWindowFocusLost = 11.cint
  neQuit = 12.cint

  neModShift = 1.cint
  neModCtrl = 2.cint
  neModAlt = 4.cint
  neModGui = 8.cint

proc cCreateWindow(w, h: cint; outW, outH, outScaleX, outScaleY: ptr cint)
  {.importc: "cocoa_createWindow", cdecl.}
proc cRefresh() {.importc: "cocoa_refresh", cdecl.}
proc cPollEvent(ev: ptr NEEvent): cint {.importc: "cocoa_pollEvent", cdecl.}
proc cWaitEvent(ev: ptr NEEvent; timeoutMs: cint): cint {.importc: "cocoa_waitEvent", cdecl.}

proc cOpenFont(path: cstring; size: cint;
               outAsc, outDesc, outLH: ptr cint): cint {.importc: "cocoa_openFont", cdecl.}
proc cCloseFont(handle: cint) {.importc: "cocoa_closeFont", cdecl.}
proc cGetFontMetrics(handle: cint; asc, desc, lh: ptr cint) {.importc: "cocoa_getFontMetrics", cdecl.}
proc cMeasureText(handle: cint; text: cstring;
                  outW, outH: ptr cint) {.importc: "cocoa_measureText", cdecl.}
proc cDrawText(handle: cint; x, y: cint; text: cstring;
               fgR, fgG, fgB, fgA: cint;
               bgR, bgG, bgB, bgA: cint;
               outW, outH: ptr cint) {.importc: "cocoa_drawText", cdecl.}

proc cFillRect(x, y, w, h: cint; r, g, b, a: cint) {.importc: "cocoa_fillRect", cdecl.}
proc cDrawLine(x1, y1, x2, y2: cint; r, g, b, a: cint) {.importc: "cocoa_drawLine", cdecl.}
proc cDrawPoint(x, y: cint; r, g, b, a: cint) {.importc: "cocoa_drawPoint", cdecl.}

proc cSetClipRect(x, y, w, h: cint) {.importc: "cocoa_setClipRect", cdecl.}
proc cSaveState() {.importc: "cocoa_saveState", cdecl.}
proc cRestoreState() {.importc: "cocoa_restoreState", cdecl.}

proc cGetClipboardText(): cstring {.importc: "cocoa_getClipboardText", cdecl.}
proc cPutClipboardText(text: cstring) {.importc: "cocoa_putClipboardText", cdecl.}

proc cGetModState(): cint {.importc: "cocoa_getModState", cdecl.}
proc cGetTicks(): uint32 {.importc: "cocoa_getTicks", cdecl.}
proc cDelay(ms: uint32) {.importc: "cocoa_delay", cdecl.}

proc cSetCursor(kind: cint) {.importc: "cocoa_setCursor", cdecl.}
proc cSetWindowTitle(title: cstring) {.importc: "cocoa_setWindowTitle", cdecl.}
proc cStartTextInput() {.importc: "cocoa_startTextInput", cdecl.}
proc cQuitRequest() {.importc: "cocoa_quitRequest", cdecl.}

# --- Hook implementations ---

proc cocoaCreateWindow(layout: var ScreenLayout) =
  var w, h, sx, sy: cint
  cCreateWindow(layout.width.cint, layout.height.cint,
                addr w, addr h, addr sx, addr sy)
  layout.width = w
  layout.height = h
  layout.scaleX = sx
  layout.scaleY = sy

proc cocoaRefresh() = cRefresh()
proc cocoaSaveState() = cSaveState()
proc cocoaRestoreState() = cRestoreState()

proc cocoaSetClipRect(r: Rect) =
  cSetClipRect(r.x.cint, r.y.cint, r.w.cint, r.h.cint)

proc cocoaOpenFont(path: string; size: int;
                   metrics: var FontMetrics): Font =
  var asc, desc, lh: cint
  let handle = cOpenFont(cstring(path), size.cint,
                         addr asc, addr desc, addr lh)
  if handle == 0: return Font(0)
  metrics.ascent = asc
  metrics.descent = desc
  metrics.lineHeight = lh
  result = Font(handle)

proc cocoaCloseFont(f: Font) =
  cCloseFont(f.int.cint)

proc cocoaMeasureText(f: Font; text: string): TextExtent =
  if text == "": return TextExtent()
  var w, h: cint
  cMeasureText(f.int.cint, cstring(text), addr w, addr h)
  result = TextExtent(w: w, h: h)

proc cocoaDrawText(f: Font; x, y: int; text: string;
                   fg, bg: Color): TextExtent =
  if text == "": return TextExtent()
  var w, h: cint
  cDrawText(f.int.cint, x.cint, y.cint, cstring(text),
            fg.r.cint, fg.g.cint, fg.b.cint, fg.a.cint,
            bg.r.cint, bg.g.cint, bg.b.cint, bg.a.cint,
            addr w, addr h)
  result = TextExtent(w: w, h: h)

proc cocoaGetFontMetrics(f: Font): FontMetrics =
  var asc, desc, lh: cint
  cGetFontMetrics(f.int.cint, addr asc, addr desc, addr lh)
  result = FontMetrics(ascent: asc, descent: desc, lineHeight: lh)

proc cocoaFillRect(r: Rect; color: Color) =
  cFillRect(r.x.cint, r.y.cint, r.w.cint, r.h.cint,
            color.r.cint, color.g.cint, color.b.cint, color.a.cint)

proc cocoaDrawLine(x1, y1, x2, y2: int; color: Color) =
  cDrawLine(x1.cint, y1.cint, x2.cint, y2.cint,
            color.r.cint, color.g.cint, color.b.cint, color.a.cint)

proc cocoaDrawPoint(x, y: int; color: Color) =
  cDrawPoint(x.cint, y.cint,
             color.r.cint, color.g.cint, color.b.cint, color.a.cint)

proc cocoaSetCursor(c: CursorKind) =
  cSetCursor(ord(c).cint)

proc cocoaSetWindowTitle(title: string) =
  cSetWindowTitle(cstring(title))

# --- Event translation ---

proc translateNEEvent(ne: NEEvent; e: var input.Event) =
  e = input.Event(kind: evNone)
  # Translate modifiers
  if (ne.mods and neModShift) != 0: e.mods.incl modShift
  if (ne.mods and neModCtrl) != 0: e.mods.incl modCtrl
  if (ne.mods and neModAlt) != 0: e.mods.incl modAlt
  if (ne.mods and neModGui) != 0: e.mods.incl modGui

  case ne.kind
  of neQuit:
    e.kind = evQuit
  of neWindowResize:
    e.kind = evWindowResize
    e.x = ne.x
    e.y = ne.y
  of neWindowClose:
    e.kind = evWindowClose
  of neWindowFocusGained:
    e.kind = evWindowFocusGained
  of neWindowFocusLost:
    e.kind = evWindowFocusLost
  of neKeyDown:
    e.kind = evKeyDown
    e.key = KeyCode(ne.key)
  of neKeyUp:
    e.kind = evKeyUp
    e.key = KeyCode(ne.key)
  of neTextInput:
    e.kind = evTextInput
    for i in 0..3:
      e.text[i] = ne.text[i]
  of neMouseDown:
    e.kind = evMouseDown
    e.x = ne.x
    e.y = ne.y
    e.clicks = ne.clicks
    case ne.button
    of 0: e.button = mbLeft
    of 1: e.button = mbRight
    of 2: e.button = mbMiddle
    else: e.button = mbLeft
  of neMouseUp:
    e.kind = evMouseUp
    e.x = ne.x
    e.y = ne.y
    case ne.button
    of 0: e.button = mbLeft
    of 1: e.button = mbRight
    of 2: e.button = mbMiddle
    else: e.button = mbLeft
  of neMouseMove:
    e.kind = evMouseMove
    e.x = ne.x
    e.y = ne.y
    e.xrel = ne.xrel
    e.yrel = ne.yrel
    if (ne.buttons and 1) != 0: e.buttons.incl mbLeft
    if (ne.buttons and 2) != 0: e.buttons.incl mbRight
    if (ne.buttons and 4) != 0: e.buttons.incl mbMiddle
  of neMouseWheel:
    e.kind = evMouseWheel
    e.x = ne.x
    e.y = ne.y
  else: discard

proc cocoaPollEvent(e: var input.Event): bool =
  var ne: NEEvent
  if cPollEvent(addr ne) == 0:
    return false
  translateNEEvent(ne, e)
  result = true

proc cocoaWaitEvent(e: var input.Event; timeoutMs: int): bool =
  var ne: NEEvent
  if cWaitEvent(addr ne, timeoutMs.cint) == 0:
    return false
  translateNEEvent(ne, e)
  result = true

proc cocoaGetClipboardText(): string =
  let t = cGetClipboardText()
  if t != nil: result = $t
  else: result = ""

proc cocoaPutClipboardText(text: string) =
  cPutClipboardText(cstring(text))

proc cocoaGetModState(): set[Modifier] =
  let m = cGetModState()
  if (m and neModShift) != 0: result.incl modShift
  if (m and neModCtrl) != 0: result.incl modCtrl
  if (m and neModAlt) != 0: result.incl modAlt
  if (m and neModGui) != 0: result.incl modGui

proc cocoaGetTicks(): uint32 = cGetTicks()
proc cocoaDelay(ms: uint32) = cDelay(ms)
proc cocoaStartTextInput() = cStartTextInput()
proc cocoaQuitRequest() = cQuitRequest()

# --- Init ---

proc initCocoaDriver*() =
  # Screen hooks
  createWindowHook = cocoaCreateWindow
  refreshHook = cocoaRefresh
  saveStateHook = cocoaSaveState
  restoreStateHook = cocoaRestoreState
  setClipRectHook = cocoaSetClipRect
  openFontHook = cocoaOpenFont
  closeFontHook = cocoaCloseFont
  measureTextHook = cocoaMeasureText
  drawTextHook = cocoaDrawText
  getFontMetricsHook = cocoaGetFontMetrics
  fillRectHook = cocoaFillRect
  drawLineHook = cocoaDrawLine
  drawPointHook = cocoaDrawPoint
  setCursorHook = cocoaSetCursor
  setWindowTitleHook = cocoaSetWindowTitle
  # Input hooks
  pollEventHook = cocoaPollEvent
  waitEventHook = cocoaWaitEvent
  getClipboardTextHook = cocoaGetClipboardText
  putClipboardTextHook = cocoaPutClipboardText
  getModStateHook = cocoaGetModState
  getTicksHook = cocoaGetTicks
  delayHook = cocoaDelay
  startTextInputHook = cocoaStartTextInput
  quitRequestHook = cocoaQuitRequest
