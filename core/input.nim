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

var pollEventRelay*: proc (e: var Event): bool {.nimcall.} =
  proc (e: var Event): bool = false
var getClipboardTextRelay*: proc (): string {.nimcall.} =
  proc (): string = ""
var putClipboardTextRelay*: proc (text: string) {.nimcall.} =
  proc (text: string) = discard

var waitEventRelay*: proc (e: var Event; timeoutMs: int): bool {.nimcall.} =
  proc (e: var Event; timeoutMs: int): bool = false
var getModStateRelay*: proc (): set[Modifier] {.nimcall.} =
  proc (): set[Modifier] = {}
var getTicksRelay*: proc (): uint32 {.nimcall.} =
  proc (): uint32 = 0
var delayRelay*: proc (ms: uint32) {.nimcall.} =
  proc (ms: uint32) = discard
var startTextInputRelay*: proc () {.nimcall.} =
  proc () = discard
var quitRequestRelay*: proc () {.nimcall.} =
  proc () = discard

proc pollEvent*(e: var Event): bool = pollEventRelay(e)
proc waitEvent*(e: var Event; timeoutMs: int = -1): bool = waitEventRelay(e, timeoutMs)
proc getClipboardText*(): string = getClipboardTextRelay()
proc putClipboardText*(text: string) = putClipboardTextRelay(text)
proc getModState*(): set[Modifier] = getModStateRelay()
proc getTicks*(): uint32 = getTicksRelay()
proc delay*(ms: uint32) = delayRelay(ms)
proc startTextInput*() = startTextInputRelay()
proc quitRequest*() = quitRequestRelay()
