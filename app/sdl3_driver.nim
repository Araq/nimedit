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

proc sdlMeasureText(f: screen.Font; text: cstring): TextExtent =
  let fp = getFontPtr(f)
  if fp != nil and text[0] != '\0':
    var w, h: cint
    discard sdl3_ttf.getStringSize(fp, text, 0, w, h)
    result = TextExtent(w: w, h: h)

proc sdlDrawTextShaded(f: screen.Font; x, y: int; text: cstring;
                       fg, bg: screen.Color): TextExtent =
  let fp = getFontPtr(f)
  if fp == nil or text[0] == '\0': return
  # Fill background, then draw blended text on top
  let ext0 = sdlMeasureText(f, text)
  var bgRect = FRect(x: x.cfloat, y: y.cfloat,
                     w: ext0.w.cfloat, h: ext0.h.cfloat)
  discard setRenderDrawColor(ren, bg.r, bg.g, bg.b, bg.a)
  discard renderFillRect(ren, addr bgRect)
  let surf = sdl3_ttf.renderTextBlended(fp, text, 0, toColor(fg))
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
  of SCANCODE_A: keyA
  of SCANCODE_B: keyB
  of SCANCODE_C: keyC
  of SCANCODE_D: keyD
  of SCANCODE_E: keyE
  of SCANCODE_F: keyF
  of SCANCODE_G: keyG
  of SCANCODE_H: keyH
  of SCANCODE_I: keyI
  of SCANCODE_J: keyJ
  of SCANCODE_K: keyK
  of SCANCODE_L: keyL
  of SCANCODE_M: keyM
  of SCANCODE_N: keyN
  of SCANCODE_O: keyO
  of SCANCODE_P: keyP
  of SCANCODE_Q: keyQ
  of SCANCODE_R: keyR
  of SCANCODE_S: keyS
  of SCANCODE_T: keyT
  of SCANCODE_U: keyU
  of SCANCODE_V: keyV
  of SCANCODE_W: keyW
  of SCANCODE_X: keyX
  of SCANCODE_Y: keyY
  of SCANCODE_Z: keyZ
  of SCANCODE_1: key1
  of SCANCODE_2: key2
  of SCANCODE_3: key3
  of SCANCODE_4: key4
  of SCANCODE_5: key5
  of SCANCODE_6: key6
  of SCANCODE_7: key7
  of SCANCODE_8: key8
  of SCANCODE_9: key9
  of SCANCODE_0: key0
  of SCANCODE_F1: keyF1
  of SCANCODE_F2: keyF2
  of SCANCODE_F3: keyF3
  of SCANCODE_F4: keyF4
  of SCANCODE_F5: keyF5
  of SCANCODE_F6: keyF6
  of SCANCODE_F7: keyF7
  of SCANCODE_F8: keyF8
  of SCANCODE_F9: keyF9
  of SCANCODE_F10: keyF10
  of SCANCODE_F11: keyF11
  of SCANCODE_F12: keyF12
  of SCANCODE_RETURN: keyEnter
  of SCANCODE_SPACE: keySpace
  of SCANCODE_ESCAPE: keyEsc
  of SCANCODE_TAB: keyTab
  of SCANCODE_BACKSPACE: keyBackspace
  of SCANCODE_DELETE: keyDelete
  of SCANCODE_INSERT: keyInsert
  of SCANCODE_LEFT: keyLeft
  of SCANCODE_RIGHT: keyRight
  of SCANCODE_UP: keyUp
  of SCANCODE_DOWN: keyDown
  of SCANCODE_PAGEUP: keyPageUp
  of SCANCODE_PAGEDOWN: keyPageDown
  of SCANCODE_HOME: keyHome
  of SCANCODE_END: keyEnd
  of SCANCODE_CAPSLOCK: keyCapslock
  of SCANCODE_COMMA: keyComma
  of SCANCODE_PERIOD: keyPeriod
  else: keyNone

proc translateMods(m: Keymod): set[Modifier] =
  let m = m.uint32
  if (m and KMOD_SHIFT) != 0: result.incl modShift
  if (m and KMOD_CTRL) != 0: result.incl modCtrl
  if (m and KMOD_ALT) != 0: result.incl modAlt
  if (m and KMOD_GUI) != 0: result.incl modGui

proc translateEvent(sdlEvent: sdl3.Event; e: var input.Event) =
  e = input.Event(kind: evNone)
  let evType = uint32(sdlEvent.common.`type`)
  if evType == uint32(EVENT_QUIT):
    e.kind = evQuit
  elif evType == uint32(EVENT_WINDOW_RESIZED):
    e.kind = evWindowResize
    e.x = sdlEvent.window.data1
    e.y = sdlEvent.window.data2
  elif evType == uint32(EVENT_WINDOW_CLOSE_REQUESTED):
    e.kind = evWindowClose
  elif evType == uint32(EVENT_WINDOW_FOCUS_GAINED):
    e.kind = evWindowFocusGained
  elif evType == uint32(EVENT_WINDOW_FOCUS_LOST):
    e.kind = evWindowFocusLost
  elif evType == uint32(EVENT_KEY_DOWN):
    e.kind = evKeyDown
    e.key = translateScancode(sdlEvent.key.scancode)
    e.mods = translateMods(sdlEvent.key.`mod`)
  elif evType == uint32(EVENT_KEY_UP):
    e.kind = evKeyUp
    e.key = translateScancode(sdlEvent.key.scancode)
    e.mods = translateMods(sdlEvent.key.`mod`)
  elif evType == uint32(EVENT_TEXT_INPUT):
    e.kind = evTextInput
    if sdlEvent.text.text != nil:
      for i in 0..3:
        if sdlEvent.text.text[i] == '\0':
          e.text[i] = '\0'
          break
        e.text[i] = sdlEvent.text.text[i]
  elif evType == uint32(EVENT_MOUSE_BUTTON_DOWN):
    e.kind = evMouseDown
    e.x = sdlEvent.button.x.int
    e.y = sdlEvent.button.y.int
    e.clicks = sdlEvent.button.clicks.int
    case sdlEvent.button.button
    of BUTTON_LEFT: e.button = mbLeft
    of BUTTON_RIGHT: e.button = mbRight
    of BUTTON_MIDDLE: e.button = mbMiddle
    else: e.button = mbLeft
  elif evType == uint32(EVENT_MOUSE_BUTTON_UP):
    e.kind = evMouseUp
    e.x = sdlEvent.button.x.int
    e.y = sdlEvent.button.y.int
    case sdlEvent.button.button
    of BUTTON_LEFT: e.button = mbLeft
    of BUTTON_RIGHT: e.button = mbRight
    of BUTTON_MIDDLE: e.button = mbMiddle
    else: e.button = mbLeft
  elif evType == uint32(EVENT_MOUSE_MOTION):
    e.kind = evMouseMove
    e.x = sdlEvent.motion.x.int
    e.y = sdlEvent.motion.y.int
    e.xrel = sdlEvent.motion.xrel.int
    e.yrel = sdlEvent.motion.yrel.int
    if (sdlEvent.motion.state and BUTTON_LMASK) != 0:
      e.buttons.incl mbLeft
    if (sdlEvent.motion.state and BUTTON_RMASK) != 0:
      e.buttons.incl mbRight
  elif evType == uint32(EVENT_MOUSE_WHEEL):
    e.kind = evMouseWheel
    e.x = sdlEvent.wheel.x.int
    e.y = sdlEvent.wheel.y.int

proc sdlPollEvent(e: var input.Event): bool =
  var sdlEvent: sdl3.Event
  if not pollEvent(sdlEvent):
    return false
  translateEvent(sdlEvent, e)
  result = true

proc sdlWaitEvent(e: var input.Event; timeoutMs: int): bool =
  var sdlEvent: sdl3.Event
  let ok = if timeoutMs < 0: waitEvent(sdlEvent)
           else: waitEventTimeout(sdlEvent, timeoutMs.int32)
  if not ok: return false
  translateEvent(sdlEvent, e)
  result = true

proc sdlGetModState(): set[Modifier] =
  translateMods(sdl3.getModState())

proc sdlGetTicks(): uint32 = uint32(sdl3.getTicks())
proc sdlDelay(ms: uint32) = sdl3.delay(ms)
proc sdlStartTextInput() = discard startTextInput(win)
proc sdlQuitRequest() = sdl3.quit()

# --- Init ---

proc initSdl3Driver*() =
  if not sdl3.init(INIT_VIDEO or INIT_EVENTS):
    quit("SDL3 init failed")
  if not sdl3_ttf.init():
    quit("TTF3 init failed")
  # Screen hooks
  createWindowHook = sdlCreateWindow
  refreshHook = sdlRefresh
  saveStateHook = sdlSaveState
  restoreStateHook = sdlRestoreState
  setClipRectHook = sdlSetClipRect
  openFontHook = sdlOpenFont
  closeFontHook = sdlCloseFont
  measureTextHook = sdlMeasureText
  drawTextShadedHook = sdlDrawTextShaded
  getFontMetricsHook = sdlGetFontMetrics
  fillRectHook = sdlFillRect
  drawLineHook = sdlDrawLine
  drawPointHook = sdlDrawPoint
  setCursorHook = sdlSetCursor
  setWindowTitleHook = sdlSetWindowTitle
  # Input hooks
  pollEventHook = sdlPollEvent
  waitEventHook = sdlWaitEvent
  getClipboardTextHook = sdlGetClipboardText
  putClipboardTextHook = sdlPutClipboardText
  getModStateHook = sdlGetModState
  getTicksHook = sdlGetTicks
  delayHook = sdlDelay
  startTextInputHook = sdlStartTextInput
  quitRequestHook = sdlQuitRequest
