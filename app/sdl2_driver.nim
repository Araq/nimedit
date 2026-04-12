# SDL2 backend driver. Sets all hooks from core/input and core/screen.
# This is the ONLY file that should import sdl2.

import sdl2 except Rect, Point
import sdl2/ttf
import basetypes, input, screen

# --- Font handle management ---

type
  FontSlot = object
    sdlFont: FontPtr
    metrics: FontMetrics

var fonts: seq[FontSlot]

proc toSdlColor(c: screen.Color): sdl2.Color =
  result.r = c.r
  result.g = c.g
  result.b = c.b
  result.a = c.a

proc toSdlRect(r: basetypes.Rect): sdl2.Rect {.inline.} =
  (r.x, r.y, r.w, r.h)

proc getFontPtr(f: Font): FontPtr {.inline.} =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].sdlFont
  else: nil

# --- SDL driver state ---

var
  window: WindowPtr
  renderer: RendererPtr

# --- Screen hook implementations ---

proc sdlCreateWindow(layout: var ScreenLayout) =
  let flags = SDL_WINDOW_RESIZABLE or SDL_WINDOW_SHOWN
  window = createWindow("NimEdit",
    SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
    layout.width.cint, layout.height.cint, flags)
  renderer = createRenderer(window, -1, Renderer_Software)
  var w, h: cint
  window.getSize(w, h)
  layout.width = w
  layout.height = h
  layout.scaleX = 1
  layout.scaleY = 1
  sdl2.startTextInput()

proc sdlRefresh() =
  renderer.present()

proc sdlSaveState() =
  discard # TODO: push clip rect stack

proc sdlRestoreState() =
  discard # TODO: pop clip rect stack

proc sdlSetClipRect(r: basetypes.Rect) =
  var sdlRect = toSdlRect(r)
  discard renderer.setClipRect(addr sdlRect)

proc sdlOpenFont(path: string; size: int;
                 metrics: var FontMetrics): Font =
  let f = openFont(cstring(path), size.cint)
  if f == nil: return Font(0)
  metrics.ascent = fontAscent(f)
  metrics.descent = fontDescent(f)
  metrics.lineHeight = fontLineSkip(f)
  fonts.add FontSlot(sdlFont: f, metrics: metrics)
  result = Font(fonts.len)  # 1-based

proc sdlCloseFont(f: Font) =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len and fonts[idx].sdlFont != nil:
    close(fonts[idx].sdlFont)
    fonts[idx].sdlFont = nil

proc sdlMeasureText(f: Font; text: cstring): TextExtent =
  let fp = getFontPtr(f)
  if fp != nil and text[0] != '\0':
    var w, h: cint
    discard sizeUtf8(fp, text, addr w, addr h)
    result = TextExtent(w: w, h: h)

proc sdlDrawTextShaded(f: Font; x, y: cint; text: cstring;
                       fg, bg: screen.Color): TextExtent =
  let fp = getFontPtr(f)
  if fp == nil or text[0] == '\0': return
  let surf = renderUtf8Shaded(fp, text, toSdlColor(fg), toSdlColor(bg))
  if surf == nil: return
  let tex = renderer.createTextureFromSurface(surf)
  if tex == nil:
    freeSurface(surf)
    return
  var src: sdl2.Rect = (0.cint, 0.cint, surf.w, surf.h)
  var dst: sdl2.Rect = (x, y, surf.w, surf.h)
  renderer.copy(tex, addr src, addr dst)
  result = TextExtent(w: surf.w, h: surf.h)
  freeSurface(surf)
  destroy(tex)

proc sdlGetFontMetrics(f: Font): FontMetrics =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].metrics
  else: FontMetrics()

proc sdlFillRect(r: basetypes.Rect; color: screen.Color) =
  renderer.setDrawColor(color.r, color.g, color.b, color.a)
  var sdlRect = toSdlRect(r)
  discard renderer.fillRect(sdlRect)

proc sdlDrawLine(x1, y1, x2, y2: cint; color: screen.Color) =
  renderer.setDrawColor(color.r, color.g, color.b, color.a)
  renderer.drawLine(x1, y1, x2, y2)

proc sdlDrawPoint(x, y: cint; color: screen.Color) =
  renderer.setDrawColor(color.r, color.g, color.b, color.a)
  renderer.drawPoint(x, y)

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

# --- Input hook implementations ---

proc sdlGetClipboardText(): string =
  let t = sdl2.getClipboardText()
  result = $t
  freeClipboardText(t)

proc sdlPutClipboardText(text: string) =
  discard sdl2.setClipboardText(cstring(text))

proc translateScancode(sc: Scancode): KeyCode =
  case sc
  of SDL_SCANCODE_A: KeyA
  of SDL_SCANCODE_B: KeyB
  of SDL_SCANCODE_C: KeyC
  of SDL_SCANCODE_D: KeyD
  of SDL_SCANCODE_E: KeyE
  of SDL_SCANCODE_F: KeyF
  of SDL_SCANCODE_G: KeyG
  of SDL_SCANCODE_H: KeyH
  of SDL_SCANCODE_I: KeyI
  of SDL_SCANCODE_J: KeyJ
  of SDL_SCANCODE_K: KeyK
  of SDL_SCANCODE_L: KeyL
  of SDL_SCANCODE_M: KeyM
  of SDL_SCANCODE_N: KeyN
  of SDL_SCANCODE_O: KeyO
  of SDL_SCANCODE_P: KeyP
  of SDL_SCANCODE_Q: KeyQ
  of SDL_SCANCODE_R: KeyR
  of SDL_SCANCODE_S: KeyS
  of SDL_SCANCODE_T: KeyT
  of SDL_SCANCODE_U: KeyU
  of SDL_SCANCODE_V: KeyV
  of SDL_SCANCODE_W: KeyW
  of SDL_SCANCODE_X: KeyX
  of SDL_SCANCODE_Y: KeyY
  of SDL_SCANCODE_Z: KeyZ
  of SDL_SCANCODE_1: Key1
  of SDL_SCANCODE_2: Key2
  of SDL_SCANCODE_3: Key3
  of SDL_SCANCODE_4: Key4
  of SDL_SCANCODE_5: Key5
  of SDL_SCANCODE_6: Key6
  of SDL_SCANCODE_7: Key7
  of SDL_SCANCODE_8: Key8
  of SDL_SCANCODE_9: Key9
  of SDL_SCANCODE_0: Key0
  of SDL_SCANCODE_F1: KeyF1
  of SDL_SCANCODE_F2: KeyF2
  of SDL_SCANCODE_F3: KeyF3
  of SDL_SCANCODE_F4: KeyF4
  of SDL_SCANCODE_F5: KeyF5
  of SDL_SCANCODE_F6: KeyF6
  of SDL_SCANCODE_F7: KeyF7
  of SDL_SCANCODE_F8: KeyF8
  of SDL_SCANCODE_F9: KeyF9
  of SDL_SCANCODE_F10: KeyF10
  of SDL_SCANCODE_F11: KeyF11
  of SDL_SCANCODE_F12: KeyF12
  of SDL_SCANCODE_RETURN: KeyEnter
  of SDL_SCANCODE_SPACE: KeySpace
  of SDL_SCANCODE_ESCAPE: KeyEsc
  of SDL_SCANCODE_TAB: KeyTab
  of SDL_SCANCODE_BACKSPACE: KeyBackspace
  of SDL_SCANCODE_DELETE: KeyDelete
  of SDL_SCANCODE_INSERT: KeyInsert
  of SDL_SCANCODE_LEFT: KeyLeft
  of SDL_SCANCODE_RIGHT: KeyRight
  of SDL_SCANCODE_UP: KeyUp
  of SDL_SCANCODE_DOWN: KeyDown
  of SDL_SCANCODE_PAGEUP: KeyPageUp
  of SDL_SCANCODE_PAGEDOWN: KeyPageDown
  of SDL_SCANCODE_HOME: KeyHome
  of SDL_SCANCODE_END: KeyEnd
  of SDL_SCANCODE_CAPSLOCK: KeyCapslock
  of SDL_SCANCODE_COMMA: KeyComma
  of SDL_SCANCODE_PERIOD: KeyPeriod
  else: KeyNone

proc translateMods(m: int16): set[Modifier] =
  let m = m.int32
  if (m and KMOD_SHIFT) != 0: result.incl ShiftPressed
  if (m and KMOD_CTRL) != 0: result.incl CtrlPressed
  if (m and KMOD_ALT) != 0: result.incl AltPressed
  if (m and KMOD_GUI) != 0: result.incl GuiPressed

proc sdlPollEvent(e: var input.Event; flags: set[InputFlag]): bool =
  var sdlEvent: sdl2.Event
  if not sdl2.pollEvent(sdlEvent):
    return false
  result = true
  e = input.Event(kind: NoEvent)
  case sdlEvent.kind
  of QuitEvent:
    e.kind = input.QuitEvent
  of WindowEvent:
    let wev = sdlEvent.window
    case wev.event
    of WindowEvent_Resized, WindowEvent_SizeChanged:
      e.kind = WindowResizeEvent
      e.x = wev.data1
      e.y = wev.data2
    of WindowEvent_Close:
      e.kind = WindowCloseEvent
    of WindowEvent_FocusGained:
      e.kind = WindowFocusGainedEvent
    of WindowEvent_FocusLost:
      e.kind = WindowFocusLostEvent
    else:
      e.kind = NoEvent
  of KeyDown:
    e.kind = KeyDownEvent
    e.key = translateScancode(sdlEvent.key.keysym.scancode)
    e.mods = translateMods(sdlEvent.key.keysym.modstate)
  of KeyUp:
    e.kind = KeyUpEvent
    e.key = translateScancode(sdlEvent.key.keysym.scancode)
    e.mods = translateMods(sdlEvent.key.keysym.modstate)
  of TextInput:
    e.kind = TextInputEvent
    for i in 0..3:
      e.text[i] = sdlEvent.text.text[i]
  of MouseButtonDown:
    e.kind = MouseDownEvent
    e.x = sdlEvent.button.x
    e.y = sdlEvent.button.y
    e.clicks = sdlEvent.button.clicks.int
    case sdlEvent.button.button
    of BUTTON_LEFT: e.button = LeftButton
    of BUTTON_RIGHT: e.button = RightButton
    of BUTTON_MIDDLE: e.button = MiddleButton
    else: e.button = LeftButton
  of MouseButtonUp:
    e.kind = MouseUpEvent
    e.x = sdlEvent.button.x
    e.y = sdlEvent.button.y
    case sdlEvent.button.button
    of BUTTON_LEFT: e.button = LeftButton
    of BUTTON_RIGHT: e.button = RightButton
    of BUTTON_MIDDLE: e.button = MiddleButton
    else: e.button = LeftButton
  of MouseMotion:
    e.kind = MouseMoveEvent
    e.x = sdlEvent.motion.x
    e.y = sdlEvent.motion.y
  of MouseWheel:
    e.kind = MouseWheelEvent
    e.x = sdlEvent.wheel.x
    e.y = sdlEvent.wheel.y
  else:
    e.kind = NoEvent

proc sdlWaitEvent(e: var input.Event; timeoutMs: int;
                  flags: set[InputFlag]): bool =
  # Use pollEvent with delay for timeout behavior
  if timeoutMs < 0:
    # Block until event
    while true:
      if sdlPollEvent(e, flags): return true
      sdl2.delay(10)
  elif timeoutMs == 0:
    return sdlPollEvent(e, flags)
  else:
    let start = sdl2.getTicks()
    while sdl2.getTicks() - start < timeoutMs.uint32:
      if sdlPollEvent(e, flags): return true
      sdl2.delay(10)
    return false

proc sdlGetTicks(): int = sdl2.getTicks().int

proc sdlDelay(ms: int) = sdl2.delay(ms.uint32)

proc sdlQuitRequest() = sdl2.quit()

# --- Init ---

proc initSdl2Driver*() =
  if sdl2.init(INIT_VIDEO or INIT_EVENTS) != SdlSuccess:
    quit("SDL init failed")
  if ttfInit() != SdlSuccess:
    quit("TTF init failed")
  windowRelays = WindowRelays(
    createWindow: sdlCreateWindow, refresh: sdlRefresh,
    saveState: sdlSaveState, restoreState: sdlRestoreState,
    setClipRect: sdlSetClipRect, setCursor: sdlSetCursor,
    setWindowTitle: sdlSetWindowTitle)
  fontRelays = FontRelays(
    openFont: sdlOpenFont, closeFont: sdlCloseFont,
    getFontMetrics: sdlGetFontMetrics, measureText: sdlMeasureText,
    drawText: sdlDrawTextShaded)
  drawRelays = DrawRelays(
    fillRect: sdlFillRect, drawLine: sdlDrawLine, drawPoint: sdlDrawPoint)
  inputRelays = InputRelays(
    pollEvent: sdlPollEvent, waitEvent: sdlWaitEvent,
    getTicks: sdlGetTicks, delay: sdlDelay,
    quitRequest: sdlQuitRequest)
  clipboardRelays = ClipboardRelays(
    getText: sdlGetClipboardText, putText: sdlPutClipboardText)
