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

  WindowRelays* = object
    createWindow*: proc (layout: var ScreenLayout) {.nimcall.}
    refresh*: proc () {.nimcall.}
    saveState*: proc () {.nimcall.}
    restoreState*: proc () {.nimcall.}
    setClipRect*: proc (r: Rect) {.nimcall.}
    setCursor*: proc (c: CursorKind) {.nimcall.}
    setWindowTitle*: proc (title: string) {.nimcall.}

  FontRelays* = object
    openFont*: proc (path: string; size: int;
                     metrics: var FontMetrics): Font {.nimcall.}
    closeFont*: proc (f: Font) {.nimcall.}
    getFontMetrics*: proc (f: Font): FontMetrics {.nimcall.}
    measureText*: proc (f: Font; text: string): TextExtent {.nimcall.}
    drawText*: proc (f: Font; x, y: int; text: string;
                     fg, bg: Color): TextExtent {.nimcall.}

  DrawRelays* = object
    fillRect*: proc (r: Rect; color: Color) {.nimcall.}
    drawLine*: proc (x1, y1, x2, y2: int; color: Color) {.nimcall.}
    drawPoint*: proc (x, y: int; color: Color) {.nimcall.}
    loadImage*: proc (path: string): Image {.nimcall.}
    freeImage*: proc (img: Image) {.nimcall.}
    drawImage*: proc (img: Image; src, dst: Rect) {.nimcall.}

proc `==`*(a, b: Font): bool {.borrow.}
proc `==`*(a, b: Image): bool {.borrow.}

var windowRelays* = WindowRelays(
  createWindow: proc (layout: var ScreenLayout) = discard,
  refresh: proc () = discard,
  saveState: proc () = discard,
  restoreState: proc () = discard,
  setClipRect: proc (r: Rect) = discard,
  setCursor: proc (c: CursorKind) = discard,
  setWindowTitle: proc (title: string) = discard)

var fontRelays* = FontRelays(
  openFont: proc (path: string; size: int; metrics: var FontMetrics): Font = Font(0),
  closeFont: proc (f: Font) = discard,
  getFontMetrics: proc (f: Font): FontMetrics = FontMetrics(),
  measureText: proc (f: Font; text: string): TextExtent = TextExtent(),
  drawText: proc (f: Font; x, y: int; text: string;
                  fg, bg: Color): TextExtent = TextExtent())

var drawRelays* = DrawRelays(
  fillRect: proc (r: Rect; color: Color) = discard,
  drawLine: proc (x1, y1, x2, y2: int; color: Color) = discard,
  drawPoint: proc (x, y: int; color: Color) = discard,
  loadImage: proc (path: string): Image = Image(0),
  freeImage: proc (img: Image) = discard,
  drawImage: proc (img: Image; src, dst: Rect) = discard)

# Convenience wrappers
proc createWindow*(requestedW, requestedH: int): ScreenLayout =
  result = ScreenLayout(width: requestedW, height: requestedH)
  windowRelays.createWindow(result)

proc refresh*() = windowRelays.refresh()
proc saveState*() = windowRelays.saveState()
proc restoreState*() = windowRelays.restoreState()
proc setClipRect*(r: Rect) = windowRelays.setClipRect(r)
proc setCursor*(c: CursorKind) = windowRelays.setCursor(c)
proc setWindowTitle*(title: string) = windowRelays.setWindowTitle(title)

proc openFont*(path: string; size: int; metrics: var FontMetrics): Font =
  fontRelays.openFont(path, size, metrics)
proc closeFont*(f: Font) = fontRelays.closeFont(f)
proc getFontMetrics*(f: Font): FontMetrics = fontRelays.getFontMetrics(f)
proc fontLineSkip*(f: Font): int = fontRelays.getFontMetrics(f).lineHeight
proc measureText*(f: Font; text: string): TextExtent =
  fontRelays.measureText(f, text)
proc drawText*(f: Font; x, y: int; text: string; fg, bg: Color): TextExtent =
  fontRelays.drawText(f, x, y, text, fg, bg)

proc fillRect*(r: Rect; color: Color) = drawRelays.fillRect(r, color)
proc drawLine*(x1, y1, x2, y2: int; color: Color) =
  drawRelays.drawLine(x1, y1, x2, y2, color)
proc drawPoint*(x, y: int; color: Color) = drawRelays.drawPoint(x, y, color)
proc loadImage*(path: string): Image = drawRelays.loadImage(path)
proc freeImage*(img: Image) = drawRelays.freeImage(img)
proc drawImage*(img: Image; src, dst: Rect) = drawRelays.drawImage(img, src, dst)

# Color constructors
proc color*(r, g, b: uint8; a: uint8 = 255): Color =
  Color(r: r, g: g, b: b, a: a)
