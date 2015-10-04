## Draws a vertical scrollbar for a buffer.

import buffertype, themes
import sdl2, sdl2/ttf, prims, tabbar

const width = 15

proc scrollBarWidth*(b: Buffer): cint =
  if b.span >= b.numberOfLines: return 0
  return width

proc drawScrollBar*(b: Buffer; t: InternalTheme; e: var Event;
                    bufferRect: Rect): int =
  ## returns -1 if no scrolling was requested.
  # if the whole screen fits, do not show a scrollbar:
  result = -1
  let width = scrollBarWidth(b)
  if width == 0: return

  var rect = bufferRect
  rect.w = width
  rect.x = bufferRect.x + bufferRect.w - width

  let screens = b.numberOfLines.cint div b.span.cint + 1
  let pixelsPerScreen = bufferRect.h div screens + 1
  var active = false
  if e.kind == MouseButtonDown:
    let w = e.button
    if w.clicks.int >= 1:
      let p = point(w.x, w.y)
      if rect.contains(p):
        result = clamp((p.y-rect.y) div ((bufferRect.h div b.numberOfLines.cint)+1),
                       0, b.numberOfLines)
        active = true
  else:
    var p: Point
    discard getMouseState(p.x, p.y)
    if rect.contains(p):
      active = true

  # draw the bar:
  #drawBorder(t, rect, active)

  # draw the circle:
  template toPix(x): untyped =
    x.cint * ((bufferRect.h div b.numberOfLines.cint)+1)

  rect.x -= 1
  rect.w -= 2
  rect.h = max(8, bufferRect.h div screens) # (b.numberOfLines).toPix)
  rect.y = clamp(b.firstLine.toPix, bufferRect.y,
                 bufferRect.y + bufferRect.h - rect.h)
  drawBox(t, rect, active, 4)
