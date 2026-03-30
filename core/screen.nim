# Platform-independent screen/drawing hooks.
# Part of the core stdlib abstraction (plan.md).

import basetypes

type
  Color* = object
    r*, g*, b*, a*: uint8

  Font* = distinct int    ## opaque handle; 0 = invalid
  Image* = distinct int   ## opaque handle; 0 = invalid

  TextExtent* = object
    w*, h*: int

  FontMetrics* = object
    ascent*, descent*, lineHeight*: int

  ScreenLayout* = object
    width*, height*: int
    pitch*: int
    scaleX*, scaleY*: int
    fullScreen*: bool

  CursorKind* = enum
    curDefault, curArrow, curIbeam, curWait,
    curCrosshair, curHand, curSizeNS, curSizeWE

proc `==`*(a, b: Font): bool {.borrow.}
proc `==`*(a, b: Image): bool {.borrow.}

# Window lifecycle
var createWindowHook*: proc (layout: var ScreenLayout) {.nimcall.} =
  proc (layout: var ScreenLayout) = discard
var refreshHook*: proc () {.nimcall.} =
  proc () = discard

# Graphics state
var saveStateHook*: proc () {.nimcall.} =
  proc () = discard
var restoreStateHook*: proc () {.nimcall.} =
  proc () = discard
var setClipRectHook*: proc (r: Rect) {.nimcall.} =
  proc (r: Rect) = discard

# Font management
var openFontHook*: proc (path: string; size: int;
                         metrics: var FontMetrics): Font {.nimcall.} =
  proc (path: string; size: int; metrics: var FontMetrics): Font = Font(0)
var closeFontHook*: proc (f: Font) {.nimcall.} =
  proc (f: Font) = discard

# Text
var measureTextHook*: proc (f: Font; text: string): TextExtent {.nimcall.} =
  proc (f: Font; text: string): TextExtent = TextExtent()
var drawTextHook*: proc (f: Font; x, y: cint; text: string;
                         color: Color): TextExtent {.nimcall.} =
  proc (f: Font; x, y: cint; text: string; color: Color): TextExtent =
    TextExtent()

# Drawing primitives
var fillRectHook*: proc (r: Rect; color: Color) {.nimcall.} =
  proc (r: Rect; color: Color) = discard
var drawLineHook*: proc (x1, y1, x2, y2: cint; color: Color) {.nimcall.} =
  proc (x1, y1, x2, y2: cint; color: Color) = discard

# Images
var loadImageHook*: proc (path: string): Image {.nimcall.} =
  proc (path: string): Image = Image(0)
var freeImageHook*: proc (img: Image) {.nimcall.} =
  proc (img: Image) = discard
var drawImageHook*: proc (img: Image; src, dst: Rect) {.nimcall.} =
  proc (img: Image; src, dst: Rect) = discard

# Cursor and window
var setCursorHook*: proc (c: CursorKind) {.nimcall.} =
  proc (c: CursorKind) = discard
var setWindowTitleHook*: proc (title: string) {.nimcall.} =
  proc (title: string) = discard

# Convenience wrappers
proc createWindow*(requestedW, requestedH: int): ScreenLayout =
  result = ScreenLayout(width: requestedW, height: requestedH)
  createWindowHook(result)

proc refresh*() = refreshHook()
proc saveState*() = saveStateHook()
proc restoreState*() = restoreStateHook()
proc setClipRect*(r: Rect) = setClipRectHook(r)
proc openFont*(path: string; size: int; metrics: var FontMetrics): Font =
  openFontHook(path, size, metrics)
proc closeFont*(f: Font) = closeFontHook(f)
proc measureText*(f: Font; text: string): TextExtent = measureTextHook(f, text)
proc drawText*(f: Font; x, y: cint; text: string; color: Color): TextExtent =
  drawTextHook(f, x, y, text, color)
proc fillRect*(r: Rect; color: Color) = fillRectHook(r, color)
proc drawLine*(x1, y1, x2, y2: cint; color: Color) =
  drawLineHook(x1, y1, x2, y2, color)
proc loadImage*(path: string): Image = loadImageHook(path)
proc freeImage*(img: Image) = freeImageHook(img)
proc drawImage*(img: Image; src, dst: Rect) = drawImageHook(img, src, dst)
proc setCursor*(c: CursorKind) = setCursorHook(c)
proc setWindowTitle*(title: string) = setWindowTitleHook(title)

# Color constructors
proc color*(r, g, b: uint8; a: uint8 = 255): Color =
  Color(r: r, g: g, b: b, a: a)

proc parseColor*(s: string): Color =
  ## Parse "#RRGGBB" hex color string.
  if s.len == 7 and s[0] == '#':
    proc hexVal(c: char): uint8 =
      case c
      of '0'..'9': uint8(ord(c) - ord('0'))
      of 'a'..'f': uint8(ord(c) - ord('a') + 10)
      of 'A'..'F': uint8(ord(c) - ord('A') + 10)
      else: 0
    result.r = hexVal(s[1]) shl 4 or hexVal(s[2])
    result.g = hexVal(s[3]) shl 4 or hexVal(s[4])
    result.b = hexVal(s[5]) shl 4 or hexVal(s[6])
    result.a = 255
