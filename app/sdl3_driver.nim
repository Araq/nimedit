# SDL3 backend driver. Sets all hooks from core/input and core/screen.

import sdl3
import sdl3_ttf
import basetypes, input, screen

# --- Font handle management ---

type
  FontSlot = object
    ttfFont: sdl3_ttf.Font
    metrics: FontMetrics

var fonts: seq[FontSlot]

proc toColor(c: screen.Color): sdl3.Color {.inline.} =
  sdl3.Color(r: c.r, g: c.g, b: c.b, a: c.a)

proc getFontPtr(f: screen.Font): sdl3_ttf.Font {.inline.} =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].ttfFont
  else: nil

# --- SDL driver state ---

var
  win: sdl3.Window
  ren: sdl3.Renderer

# --- Screen hook implementations ---

proc sdlCreateWindow(layout: var ScreenLayout) =
  discard createWindowAndRenderer(cstring"NimEdit",
    layout.width.cint, layout.height.cint, WINDOW_RESIZABLE, win, ren)
  discard startTextInput(win)
  var w, h: cint
  discard getWindowSize(win, w, h)
  layout.width = w
  layout.height = h
  layout.scaleX = 1
  layout.scaleY = 1

proc sdlRefresh() =
  discard renderPresent(ren)

proc sdlSaveState() = discard
proc sdlRestoreState() = discard

proc sdlSetClipRect(r: basetypes.Rect) =
  var sr = sdl3.Rect(x: r.x.cint, y: r.y.cint, w: r.w.cint, h: r.h.cint)
  discard setRenderClipRect(ren, addr sr)

proc sdlOpenFont(path: string; size: int;
                 metrics: var FontMetrics): screen.Font =
  let f = sdl3_ttf.openFont(cstring(path), size.cfloat)
  if f == nil: return screen.Font(0)
  sdl3_ttf.setFontHinting(f, sdl3_ttf.hintingLightSubpixel)
  metrics.ascent = sdl3_ttf.getFontAscent(f)
  metrics.descent = sdl3_ttf.getFontDescent(f)
  metrics.lineHeight = sdl3_ttf.getFontLineSkip(f)
  fonts.add FontSlot(ttfFont: f, metrics: metrics)
  result = screen.Font(fonts.len)

proc sdlCloseFont(f: screen.Font) =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len and fonts[idx].ttfFont != nil:
    sdl3_ttf.closeFont(fonts[idx].ttfFont)
    fonts[idx].ttfFont = nil

proc sdlMeasureText(f: screen.Font; text: string): TextExtent =
  let fp = getFontPtr(f)
  if fp != nil and text != "":
    var w, h: cint
    discard sdl3_ttf.getStringSize(fp, cstring(text), 0, w, h)
    result = TextExtent(w: w, h: h)

proc sdlDrawText(f: screen.Font; x, y: int; text: string;
                 fg, bg: screen.Color): TextExtent =
  let fp = getFontPtr(f)
  if fp == nil or text == "": return
  # Fill background, then draw blended text on top
  let ext0 = sdlMeasureText(f, text)
  var bgRect = FRect(x: x.cfloat, y: y.cfloat,
                     w: ext0.w.cfloat, h: ext0.h.cfloat)
  discard setRenderDrawColor(ren, bg.r, bg.g, bg.b, bg.a)
  discard renderFillRect(ren, addr bgRect)
  let surf = sdl3_ttf.renderTextBlended(fp, cstring(text), 0, toColor(fg))
  if surf == nil: return
  let tex = createTextureFromSurface(ren, surf)
  if tex == nil:
    destroySurface(surf)
    return
  discard setTextureBlendMode(tex, BLENDMODE_BLEND)
  var tw, th: cfloat
  discard getTextureSize(tex, tw, th)
  var src = FRect(x: 0, y: 0, w: tw, h: th)
  var dst = FRect(x: x.cfloat, y: y.cfloat, w: tw, h: th)
  discard renderTexture(ren, tex, addr src, addr dst)
  result = TextExtent(w: tw.int, h: th.int)
  destroySurface(surf)
  destroyTexture(tex)

proc sdlGetFontMetrics(f: screen.Font): FontMetrics =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].metrics
  else: screen.FontMetrics()

proc sdlFillRect(r: basetypes.Rect; color: screen.Color) =
  discard setRenderDrawColor(ren, color.r, color.g, color.b, color.a)
  var fr = FRect(x: r.x.cfloat, y: r.y.cfloat,
                 w: r.w.cfloat, h: r.h.cfloat)
  discard renderFillRect(ren, addr fr)

proc sdlDrawLine(x1, y1, x2, y2: int; color: screen.Color) =
  discard setRenderDrawColor(ren, color.r, color.g, color.b, color.a)
  discard renderLine(ren, x1.cfloat, y1.cfloat, x2.cfloat, y2.cfloat)

proc sdlDrawPoint(x, y: int; color: screen.Color) =
  discard setRenderDrawColor(ren, color.r, color.g, color.b, color.a)
  discard renderPoint(ren, x.cfloat, y.cfloat)

proc sdlSetCursor(c: CursorKind) =
  let sc = case c
    of curDefault, curArrow: SYSTEM_CURSOR_DEFAULT
    of curIbeam: SYSTEM_CURSOR_TEXT
    of curWait: SYSTEM_CURSOR_WAIT
    of curCrosshair: SYSTEM_CURSOR_CROSSHAIR
    of curHand: SYSTEM_CURSOR_POINTER
    of curSizeNS: SYSTEM_CURSOR_NS_RESIZE
    of curSizeWE: SYSTEM_CURSOR_EW_RESIZE
  let cur = sdl3.createSystemCursor(sc)
  discard sdl3.setCursor(cur)

proc sdlSetWindowTitle(title: string) =
  if win != nil:
    discard setWindowTitle(win, cstring(title))

# --- Input hook implementations ---

proc sdlGetClipboardText(): string =
  let t = sdl3.getClipboardText()
  if t != nil: result = $t
  else: result = ""

proc sdlPutClipboardText(text: string) =
  discard setClipboardText(cstring(text))

proc translateScancode(sc: Scancode): input.KeyCode =
  case sc
  of SCANCODE_A: KeyA
  of SCANCODE_B: KeyB
  of SCANCODE_C: KeyC
  of SCANCODE_D: KeyD
  of SCANCODE_E: KeyE
  of SCANCODE_F: KeyF
  of SCANCODE_G: KeyG
  of SCANCODE_H: KeyH
  of SCANCODE_I: KeyI
  of SCANCODE_J: KeyJ
  of SCANCODE_K: KeyK
  of SCANCODE_L: KeyL
  of SCANCODE_M: KeyM
  of SCANCODE_N: KeyN
  of SCANCODE_O: KeyO
  of SCANCODE_P: KeyP
  of SCANCODE_Q: KeyQ
  of SCANCODE_R: KeyR
  of SCANCODE_S: KeyS
  of SCANCODE_T: KeyT
  of SCANCODE_U: KeyU
  of SCANCODE_V: KeyV
  of SCANCODE_W: KeyW
  of SCANCODE_X: KeyX
  of SCANCODE_Y: KeyY
  of SCANCODE_Z: KeyZ
  of SCANCODE_1: Key1
  of SCANCODE_2: Key2
  of SCANCODE_3: Key3
  of SCANCODE_4: Key4
  of SCANCODE_5: Key5
  of SCANCODE_6: Key6
  of SCANCODE_7: Key7
  of SCANCODE_8: Key8
  of SCANCODE_9: Key9
  of SCANCODE_0: Key0
  of SCANCODE_F1: KeyF1
  of SCANCODE_F2: KeyF2
  of SCANCODE_F3: KeyF3
  of SCANCODE_F4: KeyF4
  of SCANCODE_F5: KeyF5
  of SCANCODE_F6: KeyF6
  of SCANCODE_F7: KeyF7
  of SCANCODE_F8: KeyF8
  of SCANCODE_F9: KeyF9
  of SCANCODE_F10: KeyF10
  of SCANCODE_F11: KeyF11
  of SCANCODE_F12: KeyF12
  of SCANCODE_RETURN: KeyEnter
  of SCANCODE_SPACE: KeySpace
  of SCANCODE_ESCAPE: KeyEsc
  of SCANCODE_TAB: KeyTab
  of SCANCODE_BACKSPACE: KeyBackspace
  of SCANCODE_DELETE: KeyDelete
  of SCANCODE_INSERT: KeyInsert
  of SCANCODE_LEFT: KeyLeft
  of SCANCODE_RIGHT: KeyRight
  of SCANCODE_UP: KeyUp
  of SCANCODE_DOWN: KeyDown
  of SCANCODE_PAGEUP: KeyPageUp
  of SCANCODE_PAGEDOWN: KeyPageDown
  of SCANCODE_HOME: KeyHome
  of SCANCODE_END: KeyEnd
  of SCANCODE_CAPSLOCK: KeyCapslock
  of SCANCODE_COMMA: KeyComma
  of SCANCODE_PERIOD: KeyPeriod
  else: KeyNone

proc translateMods(m: Keymod): set[Modifier] =
  let m = m.uint32
  if (m and KMOD_SHIFT) != 0: result.incl ShiftPressed
  if (m and KMOD_CTRL) != 0: result.incl CtrlPressed
  if (m and KMOD_ALT) != 0: result.incl AltPressed
  if (m and KMOD_GUI) != 0: result.incl GuiPressed

proc translateEvent(sdlEvent: sdl3.Event; e: var input.Event) =
  e = input.Event(kind: NoEvent)
  let evType = uint32(sdlEvent.common.`type`)
  if evType == uint32(EVENT_QUIT):
    e.kind = QuitEvent
  elif evType == uint32(EVENT_WINDOW_RESIZED):
    e.kind = WindowResizeEvent
    e.x = sdlEvent.window.data1
    e.y = sdlEvent.window.data2
  elif evType == uint32(EVENT_WINDOW_CLOSE_REQUESTED):
    e.kind = WindowCloseEvent
  elif evType == uint32(EVENT_WINDOW_FOCUS_GAINED):
    e.kind = WindowFocusGainedEvent
  elif evType == uint32(EVENT_WINDOW_FOCUS_LOST):
    e.kind = WindowFocusLostEvent
  elif evType == uint32(EVENT_KEY_DOWN):
    e.kind = KeyDownEvent
    e.key = translateScancode(sdlEvent.key.scancode)
    e.mods = translateMods(sdlEvent.key.`mod`)
  elif evType == uint32(EVENT_KEY_UP):
    e.kind = KeyUpEvent
    e.key = translateScancode(sdlEvent.key.scancode)
    e.mods = translateMods(sdlEvent.key.`mod`)
  elif evType == uint32(EVENT_TEXT_INPUT):
    e.kind = TextInputEvent
    if sdlEvent.text.text != nil:
      for i in 0..3:
        if sdlEvent.text.text[i] == '\0':
          e.text[i] = '\0'
          break
        e.text[i] = sdlEvent.text.text[i]
  elif evType == uint32(EVENT_MOUSE_BUTTON_DOWN):
    e.kind = MouseDownEvent
    e.x = sdlEvent.button.x.int
    e.y = sdlEvent.button.y.int
    e.clicks = sdlEvent.button.clicks.int
    case sdlEvent.button.button
    of BUTTON_LEFT: e.button = LeftButton
    of BUTTON_RIGHT: e.button = RightButton
    of BUTTON_MIDDLE: e.button = MiddleButton
    else: e.button = LeftButton
  elif evType == uint32(EVENT_MOUSE_BUTTON_UP):
    e.kind = MouseUpEvent
    e.x = sdlEvent.button.x.int
    e.y = sdlEvent.button.y.int
    case sdlEvent.button.button
    of BUTTON_LEFT: e.button = LeftButton
    of BUTTON_RIGHT: e.button = RightButton
    of BUTTON_MIDDLE: e.button = MiddleButton
    else: e.button = LeftButton
  elif evType == uint32(EVENT_MOUSE_MOTION):
    e.kind = MouseMoveEvent
    e.x = sdlEvent.motion.x.int
    e.y = sdlEvent.motion.y.int
  elif evType == uint32(EVENT_MOUSE_WHEEL):
    e.kind = MouseWheelEvent
    e.x = sdlEvent.wheel.x.int
    e.y = sdlEvent.wheel.y.int

proc sdlPollEvent(e: var input.Event; flags: set[InputFlag]): bool =
  var sdlEvent: sdl3.Event
  if not pollEvent(sdlEvent):
    return false
  translateEvent(sdlEvent, e)
  result = true

proc sdlWaitEvent(e: var input.Event; timeoutMs: int;
                  flags: set[InputFlag]): bool =
  var sdlEvent: sdl3.Event
  let ok = if timeoutMs < 0: waitEvent(sdlEvent)
           else: waitEventTimeout(sdlEvent, timeoutMs.int32)
  if not ok: return false
  translateEvent(sdlEvent, e)
  result = true

proc sdlGetTicks(): int = sdl3.getTicks().int
proc sdlDelay(ms: int) = sdl3.delay(ms.uint32)
proc sdlQuitRequest() = sdl3.quit()

# --- Init ---

proc initSdl3Driver*() =
  if not sdl3.init(INIT_VIDEO or INIT_EVENTS):
    quit("SDL3 init failed")
  if not sdl3_ttf.init():
    quit("TTF3 init failed")
  windowRelays = WindowRelays(
    createWindow: sdlCreateWindow, refresh: sdlRefresh,
    saveState: sdlSaveState, restoreState: sdlRestoreState,
    setClipRect: sdlSetClipRect, setCursor: sdlSetCursor,
    setWindowTitle: sdlSetWindowTitle)
  fontRelays = FontRelays(
    openFont: sdlOpenFont, closeFont: sdlCloseFont,
    getFontMetrics: sdlGetFontMetrics, measureText: sdlMeasureText,
    drawText: sdlDrawText)
  drawRelays = DrawRelays(
    fillRect: sdlFillRect, drawLine: sdlDrawLine, drawPoint: sdlDrawPoint)
  inputRelays = InputRelays(
    pollEvent: sdlPollEvent, waitEvent: sdlWaitEvent,
    getTicks: sdlGetTicks, delay: sdlDelay,
    quitRequest: sdlQuitRequest)
  clipboardRelays = ClipboardRelays(
    getText: sdlGetClipboardText, putText: sdlPutClipboardText)
