

import buffertype, themes
import basetypes, screen, input, prims

type
  TabBar* = object
    first*, last*: Buffer

proc drawBorder*(t: InternalTheme; x, y, w, h: int; b: bool; arc=8) =
  let p = Pixel(col: t.active[b], thickness: 2,
                gradient: color(0xff, 0xff, 0xff, 0))
  roundedRect(x, y, x+w-1, y+h-1, arc, p)

proc roundedBox*(t: InternalTheme; x, y, w, h: int; arc=8) =
  prims.roundedBox(x, y, x+w-1, y+h-1, arc, t.bg)

proc drawBox*(t: InternalTheme; r: Rect; b: bool; arc=8) =
  prims.roundedBox(r.x, r.y, r.x+r.w-1, r.y+r.h-1, arc, t.active[b])

proc drawBorder*(t: InternalTheme; rect: Rect; active: bool; arc=8) =
  let yGap = t.uiYGap
  let xGap = t.uiXGap
  t.drawBorder(rect.x.int - xGap, rect.y.int - yGap,
               rect.w.int + xGap, rect.h.int + yGap, active, arc)

proc drawBorder*(t: InternalTheme; rect: Rect; c: Color; arc=8) =
  let p = Pixel(col: c, thickness: 0, gradient: c)
  let yGap = t.uiYGap
  let xGap = t.uiXGap
  roundedRect(rect.x.int - xGap, rect.y.int - yGap,
              rect.w.int + rect.x.int - 1 + xGap,
              rect.h.int + rect.y.int - 1 + yGap, arc, p)

proc drawBorderBox*(t: InternalTheme; rect: Rect; active: bool; arc=8) =
  let yGap = t.uiYGap
  let xGap = t.uiXGap
  t.roundedBox(rect.x.int - xGap, rect.y.int - yGap,
               rect.w.int + xGap, rect.h.int + yGap, arc)
  t.drawBorder(rect.x.int - xGap, rect.y.int - yGap,
               rect.w.int + xGap, rect.h.int + yGap, active, arc)

proc drawTextWithBorder*(t: InternalTheme; text: string; active: bool;
                         x, y, screenW: cint): Rect =
  let ext = drawTextShaded(t.uiFontHandle, x, y, cstring(text), t.fg, t.bg)
  let iW = ext.w.cint
  let iH = ext.h.cint
  if iW+x < screenW:
    result = Rect(x: x + 3, y: y + 3, w: iW + 3, h: iH + 2)
    drawBorder(t, result, active, 4)

proc swapBuffers(a, b: Buffer) =
  if a != b:
    if a.prev == b:
      if b.prev != a:
        swapBuffers(b, a)
      return
    let pa = a.prev
    let sb = b.next
    pa.next = a.next
    pa.next.prev = pa
    sb.prev = b.prev
    sb.prev.next = sb
    a.prev = sb.prev
    a.next = sb
    a.prev.next = a
    a.next.prev = a
    b.next = pa.next
    b.prev = pa
    b.prev.next = b
    b.next.prev = b

proc drawButtonList*(buttons: openArray[string]; t: Internaltheme;
                     x, y, screenW: cint; e: var Event; active = -1): int =
  var xx = x
  for i in 0..buttons.high:
    let b = buttons[i]
    let rect = drawTextWithBorder(t, b, i == active, xx, y, screenW)
    if e.kind == evMouseDown:
      if e.clicks >= 1:
        let p = point(e.x.cint, e.y.cint)
        if rect.contains(p):
          result = i
    inc xx, rect.w + t.uiXGap.cint*2

proc drawTabBar*(tabs: var TabBar; t: InternalTheme;
                 x, screenW: cint; events: seq[Event];
                 active: Buffer): Buffer =
  var it = tabs.first
  var activeDrawn = false
  var xx = x
  let yy = t.uiYGap.cint
  while true:
    let header = it.heading & (if it.changed: "*" else: "")
    let rect = drawTextWithBorder(t, header,
                                  it == active, xx, yy, screenW)
    if rect.w == 0:
      if not activeDrawn:
        if it.prev != tabs.first:
          tabs.first = it.prev
          return drawTabBar(tabs, t, x, screenW, events, active)
      break

    activeDrawn = activeDrawn or it == active
    for e in events:
      if e.kind == evMouseDown:
        if e.clicks >= 1:
          let p = point(e.x.cint, e.y.cint)
          if rect.contains(p):
            result = it
      elif e.kind == evMouseMove:
        # check for drag (button held)
        if modShift in getModState() or e.clicks > 0:
          discard # TODO: tab reorder via drag

    inc xx, rect.w + t.uiXGap.cint*2
    if it == tabs.last: break
    it = it.next
    if it == tabs.first: break
