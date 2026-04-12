# Platform-independent input events and relays.
# Part of the core stdlib abstraction.

type
  KeyCode* = enum
    KeyNone,
    KeyA, KeyB, KeyC, KeyD, KeyE, KeyF, KeyG, KeyH, KeyI, KeyJ,
    KeyK, KeyL, KeyM, KeyN, KeyO, KeyP, KeyQ, KeyR, KeyS, KeyT,
    KeyU, KeyV, KeyW, KeyX, KeyY, KeyZ,
    Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9,
    KeyF1, KeyF2, KeyF3, KeyF4, KeyF5, KeyF6,
    KeyF7, KeyF8, KeyF9, KeyF10, KeyF11, KeyF12,
    KeyEnter, KeySpace, KeyEsc, KeyTab,
    KeyBackspace, KeyDelete, KeyInsert,
    KeyLeft, KeyRight, KeyUp, KeyDown,
    KeyPageUp, KeyPageDown, KeyHome, KeyEnd,
    KeyCapslock, KeyComma, KeyPeriod,

  EventKind* = enum
    NoEvent,
    KeyDownEvent, KeyUpEvent, TextInputEvent,
    MouseDownEvent, MouseUpEvent, MouseMoveEvent, MouseWheelEvent,
    WindowResizeEvent, WindowCloseEvent,
    WindowFocusGainedEvent, WindowFocusLostEvent,
    QuitEvent

  Modifier* = enum
    ShiftPressed, CtrlPressed, AltPressed, GuiPressed

  MouseButton* = enum
    LeftButton, RightButton, MiddleButton

  InputFlag* = enum
    WantTextInput   ## show on-screen keyboard / enable IME

  Event* = object
    kind*: EventKind
    key*: KeyCode
    mods*: set[Modifier]
    text*: array[4, char]  ## TextInputEvent: one UTF-8 codepoint, no alloc
    x*, y*: int            ## mouse position, scroll delta, or new window size
    button*: MouseButton   ## MouseDownEvent/MouseUpEvent: which button
    clicks*: int           ## number of consecutive clicks (double-click = 2)

  ClipboardRelays* = object
    getText*: proc (): string {.nimcall.}
    putText*: proc (text: string) {.nimcall.}

  InputRelays* = object
    pollEvent*: proc (e: var Event; flags: set[InputFlag]): bool {.nimcall.}
    waitEvent*: proc (e: var Event; timeoutMs: int;
                      flags: set[InputFlag]): bool {.nimcall.}
    getTicks*: proc (): int {.nimcall.}
    delay*: proc (ms: int) {.nimcall.}
    quitRequest*: proc () {.nimcall.}

var clipboardRelays* = ClipboardRelays(
  getText: proc (): string = "",
  putText: proc (text: string) = discard)

var inputRelays* = InputRelays(
  pollEvent: proc (e: var Event; flags: set[InputFlag]): bool = false,
  waitEvent: proc (e: var Event; timeoutMs: int;
                   flags: set[InputFlag]): bool = false,
  getTicks: proc (): int = 0,
  delay: proc (ms: int) = discard,
  quitRequest: proc () = discard)

proc pollEvent*(e: var Event; flags: set[InputFlag] = {}): bool =
  inputRelays.pollEvent(e, flags)
proc waitEvent*(e: var Event; timeoutMs: int = -1;
                flags: set[InputFlag] = {}): bool =
  inputRelays.waitEvent(e, timeoutMs, flags)
proc getClipboardText*(): string = clipboardRelays.getText()
proc putClipboardText*(text: string) = clipboardRelays.putText(text)
proc getTicks*(): int = inputRelays.getTicks()
proc delay*(ms: int) = inputRelays.delay(ms)
proc quitRequest*() = inputRelays.quitRequest()
