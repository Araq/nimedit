# Platform-independent input events and hooks.
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

var pollEventHook*: proc (e: var Event): bool {.nimcall.} =
  proc (e: var Event): bool = false
var getClipboardTextHook*: proc (): string {.nimcall.} =
  proc (): string = ""
var putClipboardTextHook*: proc (text: string) {.nimcall.} =
  proc (text: string) = discard

var waitEventHook*: proc (e: var Event; timeoutMs: int): bool {.nimcall.} =
  proc (e: var Event; timeoutMs: int): bool = false
var getModStateHook*: proc (): set[Modifier] {.nimcall.} =
  proc (): set[Modifier] = {}
var getTicksHook*: proc (): uint32 {.nimcall.} =
  proc (): uint32 = 0
var delayHook*: proc (ms: uint32) {.nimcall.} =
  proc (ms: uint32) = discard
var startTextInputHook*: proc () {.nimcall.} =
  proc () = discard
var quitRequestHook*: proc () {.nimcall.} =
  proc () = discard

proc pollEvent*(e: var Event): bool = pollEventHook(e)
proc waitEvent*(e: var Event; timeoutMs: int = -1): bool = waitEventHook(e, timeoutMs)
proc getClipboardText*(): string = getClipboardTextHook()
proc putClipboardText*(text: string) = putClipboardTextHook(text)
proc getModState*(): set[Modifier] = getModStateHook()
proc getTicks*(): uint32 = getTicksHook()
proc delay*(ms: uint32) = delayHook(ms)
proc startTextInput*() = startTextInputHook()
proc quitRequest*() = quitRequestHook()
