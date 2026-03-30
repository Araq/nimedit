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
    keyCapslock,

  EventKind* = enum
    evNone,
    evKeyDown, evKeyUp, evTextInput,
    evMouseDown, evMouseUp, evMouseMove, evMouseWheel,
    evWindowResize, evWindowClose

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
    button*: MouseButton
    clicks*: int           ## number of consecutive clicks (double-click = 2)

var pollEventHook*: proc (e: var Event): bool {.nimcall.} =
  proc (e: var Event): bool = false
var getClipboardTextHook*: proc (): string {.nimcall.} =
  proc (): string = ""
var putClipboardTextHook*: proc (text: string) {.nimcall.} =
  proc (text: string) = discard

proc pollEvent*(e: var Event): bool = pollEventHook(e)
proc getClipboardText*(): string = getClipboardTextHook()
proc putClipboardText*(text: string) = putClipboardTextHook(text)
