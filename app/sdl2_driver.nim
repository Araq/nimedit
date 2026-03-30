# SDL2 backend driver. Sets all hooks from core/input and core/screen.
# This is the ONLY file that should import sdl2.

import sdl2 except Rect, Point
import sdl2/ttf
import basetypes, input, screen

# --- Font handle management ---

type
  FontSlot = object
    sdlFont: FontPtr
    path: string
    size: int

var fonts: seq[FontSlot]

proc toSdlColor(c: screen.Color): sdl2.Color =
  result.r = c.r
  result.g = c.g
  result.b = c.b
  result.a = c.a

proc fromSdlColor*(c: sdl2.Color): screen.Color =
  screen.Color(r: c.r, g: c.g, b: c.b, a: c.a)

proc toSdlRect(r: Rect): sdl2.Rect =
  (r.x, r.y, r.w, r.h)

# --- SDL driver state ---

var
  window: WindowPtr
  renderer: RendererPtr

# --- Hook implementations ---

proc sdlCreateWindow(layout: var ScreenLayout) =
  if sdl2.init(INIT_VIDEO or INIT_EVENTS) != SdlSuccess:
    quit("SDL init failed")
  if ttfInit() != SdlSuccess:
    quit("TTF init failed")

  let flags = SDL_WINDOW_RESIZABLE or SDL_WINDOW_SHOWN
  window = createWindow("NimEdit",
    SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
    layout.width.cint, layout.height.cint, flags)
  renderer = createRenderer(window, -1,
    Renderer_Accelerated or Renderer_PresentVsync)

  var w, h: cint
  window.getSize(w, h)
  layout.width = w
  layout.height = h
  layout.scaleX = 1
  layout.scaleY = 1

proc sdlRefresh() =
  renderer.present()
  renderer.setDrawColor(0, 0, 0, 255)
  renderer.clear()

proc sdlSaveState() =
  discard # TODO: push clip rect stack

proc sdlRestoreState() =
  discard # TODO: pop clip rect stack

proc sdlSetClipRect(r: Rect) =
  var sdlRect = toSdlRect(r)
  discard renderer.setClipRect(addr sdlRect)

proc sdlOpenFont(path: string; size: int;
                 metrics: var FontMetrics): Font =
  let f = openFont(cstring(path), size.cint)
  if f == nil: return Font(0)
  metrics.ascent = fontAscent(f)
  metrics.descent = fontDescent(f)
  metrics.lineHeight = fontLineSkip(f)
  fonts.add FontSlot(sdlFont: f, path: path, size: size)
  result = Font(fonts.len)  # 1-based index

proc sdlCloseFont(f: Font) =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len and fonts[idx].sdlFont != nil:
    close(fonts[idx].sdlFont)
    fonts[idx].sdlFont = nil

proc sdlMeasureText(f: Font; text: string): TextExtent =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len and fonts[idx].sdlFont != nil:
    var w, h: cint
    discard sizeUtf8(fonts[idx].sdlFont, cstring(text), addr w, addr h)
    result = TextExtent(w: w, h: h)

proc sdlDrawText(f: Font; x, y: cint; text: string;
                 color: screen.Color): TextExtent =
  let idx = f.int - 1
  if idx < 0 or idx >= fonts.len or fonts[idx].sdlFont == nil:
    return
  if text.len == 0: return
  let surf = renderUtf8Blended(fonts[idx].sdlFont, cstring(text),
                                toSdlColor(color))
  if surf == nil: return
  let tex = renderer.createTextureFromSurface(surf)
  if tex == nil:
    freeSurface(surf)
    return
  var src = (0.cint, 0.cint, surf.w, surf.h)
  var dst = (x, y, surf.w, surf.h)
  renderer.copy(tex, addr src, addr dst)
  result = TextExtent(w: surf.w, h: surf.h)
  freeSurface(surf)
  destroy(tex)

proc sdlFillRect(r: Rect; color: screen.Color) =
  renderer.setDrawColor(color.r, color.g, color.b, color.a)
  var sdlRect = toSdlRect(r)
  discard renderer.fillRect(sdlRect)

proc sdlDrawLine(x1, y1, x2, y2: cint; color: screen.Color) =
  renderer.setDrawColor(color.r, color.g, color.b, color.a)
  renderer.drawLine(x1, y1, x2, y2)

proc sdlSetCursor(c: CursorKind) =
  let sdlCursor = case c
    of curDefault, curArrow: SDL_SYSTEM_CURSOR_ARROW
    of curIbeam: SDL_SYSTEM_CURSOR_IBEAM
    of curWait: SDL_SYSTEM_CURSOR_WAIT
    of curCrosshair: SDL_SYSTEM_CURSOR_CROSSHAIR
    of curHand: SDL_SYSTEM_CURSOR_HAND
    of curSizeNS: SDL_SYSTEM_CURSOR_SIZENS
    of curSizeWE: SDL_SYSTEM_CURSOR_SIZEWE
  let cur = createSystemCursor(sdlCursor)
  setCursor(cur)

proc sdlSetWindowTitle(title: string) =
  if window != nil:
    window.setTitle(cstring(title))

proc sdlGetClipboardText(): string =
  let t = sdl2.getClipboardText()
  result = $t
  freeClipboardText(t)

proc sdlPutClipboardText(text: string) =
  discard sdl2.setClipboardText(cstring(text))

# --- Expose SDL-specific state for legacy code ---

proc getRenderer*(): RendererPtr = renderer
proc getWindow*(): WindowPtr = window
proc getSdlFont*(f: Font): FontPtr =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].sdlFont
  else: nil

# --- Init ---

proc initSdl2Driver*() =
  createWindowHook = sdlCreateWindow
  refreshHook = sdlRefresh
  saveStateHook = sdlSaveState
  restoreStateHook = sdlRestoreState
  setClipRectHook = sdlSetClipRect
  openFontHook = sdlOpenFont
  closeFontHook = sdlCloseFont
  measureTextHook = sdlMeasureText
  drawTextHook = sdlDrawText
  fillRectHook = sdlFillRect
  drawLineHook = sdlDrawLine
  setCursorHook = sdlSetCursor
  setWindowTitleHook = sdlSetWindowTitle
  getClipboardTextHook = sdlGetClipboardText
  putClipboardTextHook = sdlPutClipboardText
