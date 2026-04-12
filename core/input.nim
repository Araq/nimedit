# Platform-independent input events and relays.
# Part of the core stdlib abstraction (plan.md).


type
  KeyCode* = enum
    keyNone,
    keyA, keyB, keyC, keyD, keyE, keyF, keyG, keyH, keyI, keyJ,
    keyK, keyL, keyM, keyN, keyO, keyP, keyQ, keyR, keyS, keyT,
    keyU, keyV, keyW, keyX, keyY, keyZ,
    key0, key1, key2, key3, key4, key5, key6, key7, key8, key9,
    keyF1, keyF2, keyF3, keyF4, keyF5, keyF6,
    keyF7, keyF8, keyF9, keyF10, keyF11, keyF12,
    keyEnter, keySpace, keyEsc, keyTab,
    keyBackspace, keyDelete, keyInsert,
    keyLeft, keyRight, keyUp, keyDown,
    keyPageUp, keyPageDown, keyHome, keyEnd,
    keyCapslock, keyComma, keyPeriod,

  EventKind* = enum
    evNone,
    evKeyDown, evKeyUp, evTextInput,
    evMouseDown, evMouseUp, evMouseMove, evMouseWheel,
    evWindowResize, evWindowClose,
    evWindowFocusGained, evWindowFocusLost,
    evQuit

  Modifier* = enum
    modShift, modCtrl, modAlt, modGui

  MouseButton* = enum
    mbLeft, mbRight, mbMiddle

  Event* = object
    kind*: EventKind
    key*: KeyCode
    mods*: set[Modifier]
    text*: array[4, char]  ## evTextInput: one UTF-8 codepoint, no alloc
    x*, y*: int            ## mouse position, scroll delta, or new window size
    xrel*, yrel*: int      ## evMouseMove: relative motion
    button*: MouseButton
    buttons*: set[MouseButton]  ## evMouseMove: which buttons are held
    clicks*: int           ## number of consecutive clicks (double-click = 2)

  ClipboardRelays* = object
    getText*: proc (): string {.nimcall.}
    putText*: proc (text: string) {.nimcall.}

  InputRelays* = object
    pollEvent*: proc (e: var Event): bool {.nimcall.}
    waitEvent*: proc (e: var Event; timeoutMs: int): bool {.nimcall.}
    getTicks*: proc (): int {.nimcall.}
    delay*: proc (ms: int) {.nimcall.}
    startTextInput*: proc () {.nimcall.}
    quitRequest*: proc () {.nimcall.}

var clipboardRelays* = ClipboardRelays(
  getText: proc (): string = "",
  putText: proc (text: string) = discard)

var inputRelays* = InputRelays(
  pollEvent: proc (e: var Event): bool = false,
  waitEvent: proc (e: var Event; timeoutMs: int): bool = false,
  getTicks: proc (): int = 0,
  delay: proc (ms: int) = discard,
  startTextInput: proc () = discard,
  quitRequest: proc () = discard)

proc pollEvent*(e: var Event): bool = inputRelays.pollEvent(e)
proc waitEvent*(e: var Event; timeoutMs: int = -1): bool =
  inputRelays.waitEvent(e, timeoutMs)
proc getClipboardText*(): string = clipboardRelays.getText()
proc putClipboardText*(text: string) = clipboardRelays.putText(text)
proc getTicks*(): int = inputRelays.getTicks()
proc delay*(ms: int) = inputRelays.delay(ms)
proc startTextInput*() = inputRelays.startTextInput()
proc quitRequest*() = inputRelays.quitRequest()
