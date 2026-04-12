# Platform-independent screen/drawing relays.
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
var createWindowRelay*: proc (layout: var ScreenLayout) {.nimcall.} =
  proc (layout: var ScreenLayout) = discard
var refreshRelay*: proc () {.nimcall.} =
  proc () = discard

# Graphics state
var saveStateRelay*: proc () {.nimcall.} =
  proc () = discard
var restoreStateRelay*: proc () {.nimcall.} =
  proc () = discard
var setClipRectRelay*: proc (r: Rect) {.nimcall.} =
  proc (r: Rect) = discard

# Font management
var openFontRelay*: proc (path: string; size: int;
                         metrics: var FontMetrics): Font {.nimcall.} =
  proc (path: string; size: int; metrics: var FontMetrics): Font = Font(0)
var closeFontRelay*: proc (f: Font) {.nimcall.} =
  proc (f: Font) = discard

# Text
var measureTextRelay*: proc (f: Font; text: string): TextExtent {.nimcall.} =
  proc (f: Font; text: string): TextExtent = TextExtent()
var drawTextRelay*: proc (f: Font; x, y: int; text: string;
                               fg, bg: Color): TextExtent {.nimcall.} =
  proc (f: Font; x, y: int; text: string; fg, bg: Color): TextExtent =
    TextExtent()
var getFontMetricsRelay*: proc (f: Font): FontMetrics {.nimcall.} =
  proc (f: Font): FontMetrics = FontMetrics()

# Drawing primitives
var fillRectRelay*: proc (r: Rect; color: Color) {.nimcall.} =
  proc (r: Rect; color: Color) = discard
var drawLineRelay*: proc (x1, y1, x2, y2: int; color: Color) {.nimcall.} =
  proc (x1, y1, x2, y2: int; color: Color) = discard
var drawPointRelay*: proc (x, y: int; color: Color) {.nimcall.} =
  proc (x, y: int; color: Color) = discard

# Images
var loadImageRelay*: proc (path: string): Image {.nimcall.} =
  proc (path: string): Image = Image(0)
var freeImageRelay*: proc (img: Image) {.nimcall.} =
  proc (img: Image) = discard
var drawImageRelay*: proc (img: Image; src, dst: Rect) {.nimcall.} =
  proc (img: Image; src, dst: Rect) = discard

# Cursor and window
var setCursorRelay*: proc (c: CursorKind) {.nimcall.} =
  proc (c: CursorKind) = discard
var setWindowTitleRelay*: proc (title: string) {.nimcall.} =
  proc (title: string) = discard

# Convenience wrappers
proc createWindow*(requestedW, requestedH: int): ScreenLayout =
  result = ScreenLayout(width: requestedW, height: requestedH)
  createWindowRelay(result)

proc refresh*() = refreshRelay()
proc saveState*() = saveStateRelay()
proc restoreState*() = restoreStateRelay()
proc setClipRect*(r: Rect) = setClipRectRelay(r)
proc openFont*(path: string; size: int; metrics: var FontMetrics): Font =
  openFontRelay(path, size, metrics)
proc closeFont*(f: Font) = closeFontRelay(f)
proc measureText*(f: Font; text: string): TextExtent = measureTextRelay(f, text)
proc drawText*(f: Font; x, y: int; text: string; fg, bg: Color): TextExtent =
  drawTextRelay(f, x, y, text, fg, bg)
proc getFontMetrics*(f: Font): FontMetrics = getFontMetricsRelay(f)
proc fontLineSkip*(f: Font): int = getFontMetricsRelay(f).lineHeight
proc fillRect*(r: Rect; color: Color) = fillRectRelay(r, color)
proc drawLine*(x1, y1, x2, y2: int; color: Color) =
  drawLineRelay(x1, y1, x2, y2, color)
proc drawPoint*(x, y: int; color: Color) = drawPointRelay(x, y, color)
proc loadImage*(path: string): Image = loadImageRelay(path)
proc freeImage*(img: Image) = freeImageRelay(img)
proc drawImage*(img: Image; src, dst: Rect) = drawImageRelay(img, src, dst)
proc setCursor*(c: CursorKind) = setCursorRelay(c)
proc setWindowTitle*(title: string) = setWindowTitleRelay(title)

# Color constructors
proc color*(r, g, b: uint8; a: uint8 = 255): Color =
  Color(r: r, g: g, b: b, a: a)
