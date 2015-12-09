

import buffertype, themes
import sdl2, sdl2/ttf, prims

type
  TabBar* = object
    first*, last*: Buffer

proc rect*(x,y,w,h: int): Rect = sdl2.rect(x.cint, y.cint, w.cint, h.cint)

proc drawBorder*(t: InternalTheme; x, y, w, h: int; b: bool; arc=8) =
  let p = Pixel(col: t.active[b], thickness: 2,
                gradient: color(0xff, 0xff, 0xff, 0))
  t.renderer.roundedRect(x, y, x+w-1, y+h-1, arc, p)
  t.renderer.setDrawColor(t.bg)

proc roundedBox*(t: InternalTheme; x, y, w, h: int; arc=8) =
  t.renderer.roundedBox(x, y, x+w-1, y+h-1, arc, t.bg)

proc drawBox*(t: InternalTheme; r: Rect; b: bool; arc=8) =
  #let p = Pixel(col: t.active[b], thickness: 2,
  #              gradient: color(0xff, 0xff, 0xff, 0))
  t.renderer.roundedBox(r.x, r.y, r.x+r.w-1, r.y+r.h-1, arc, t.active[b])
  t.renderer.setDrawColor(t.bg)

proc renderText*(t: InternalTheme;
                message: string; font: FontPtr; color: Color): TexturePtr =
  var surf: SurfacePtr = renderUtf8Shaded(font, message, color, t.bg)
  if surf == nil:
    echo("TTF_RenderText")
    return nil
  var texture: TexturePtr = createTextureFromSurface(t.renderer, surf)
  if texture == nil:
    echo("CreateTexture")
  freeSurface(surf)
  return texture

proc draw*(renderer: RendererPtr; image: TexturePtr; x, y: int) =
  var
    iW: cint
    iH: cint
  queryTexture(image, nil, nil, addr(iW), addr(iH))
  let r = rect(x.cint, y.cint, iW, iH)
  copy(renderer, image, nil, unsafeAddr r)
  destroy image


proc drawBorder*(t: InternalTheme; rect: Rect; active: bool; arc=8) =
  let yGap = t.uiYGap
  let xGap = t.uiXGap
  t.drawBorder(rect.x - xGap, rect.y - yGap, rect.w + xGap, rect.h + yGap,
               active, arc)

proc drawBorder*(t: InternalTheme; rect: Rect; c: Color; arc=8) =
  let p = Pixel(col: c, thickness: 0,
                gradient: c) #color(0xff, 0xff, 0xff, 0))
  let yGap = t.uiYGap
  let xGap = t.uiXGap
  t.renderer.roundedRect(rect.x - xGap, rect.y - yGap,
                         rect.w + rect.x - 1 + xGap,
                         rect.h + rect.y - 1 + yGap, arc, p)

proc drawBorderBox*(t: InternalTheme; rect: Rect; active: bool; arc=8) =
  let yGap = t.uiYGap
  let xGap = t.uiXGap
  t.roundedBox(rect.x - xGap, rect.y - yGap, rect.w + xGap,
               rect.h + yGap, arc)
  t.drawBorder(rect.x - xGap, rect.y - yGap, rect.w + xGap, rect.h + yGap,
               active, arc)

proc drawTextWithBorder*(t: InternalTheme; text: string; active: bool;
                         x, y, screenW: cint): Rect =
  let image = renderText(t, text, t.uiFontPtr, t.fg)
  var
    iW: cint
    iH: cint
  queryTexture(image, nil, nil, addr(iW), addr(iH))
  if iW+x < screenW:
    result = rect(x, y, iW, iH)
    copy(t.renderer, image, nil, addr result)
    destroy image
    result.x += 3
    result.y += 3
    result.w += 3
    result.h += 2
    drawBorder(t, result, active, 4)

proc swapBuffers(a, b: Buffer) =
  #  a.prev | a | b | b.next
  #           |-->
  if a != b:
    if a.prev == b:
      if b.prev != a:
        swapBuffers(b, a)
      return

    let pa = a.prev
    let sb = b.next
    # remove a from list
    pa.next = a.next
    pa.next.prev = pa
    # remove b from list
    sb.prev = b.prev
    sb.prev.next = sb
    # add a before sb
    a.prev = sb.prev
    a.next = sb
    a.prev.next = a
    a.next.prev = a
    # add b after pa
    b.next = pa.next
    b.prev = pa
    b.prev.next = b
    b.next.prev = b

proc drawButtonList*(buttons: openArray[string]; t: Internaltheme;
                     x, y, screenW: cint; e: var Event; active = -1): int =
  var xx = x # 15.cint
  for i in 0..buttons.high:
    let b = buttons[i]
    let rect = drawTextWithBorder(t, b, i == active, xx, y, screenW)
    if e.kind == MouseButtonDown:
      let w = e.button
      if w.clicks.int >= 1:
        let p = point(w.x, w.y)
        if rect.contains(p):
          result = i
    inc xx, rect.w + t.uiXGap*2

proc drawTabBar*(tabs: var TabBar; t: InternalTheme;
                 x, screenW: cint; e: var Event;
                 active: Buffer): Buffer =
  var it = tabs.first
  var activeDrawn = false
  var xx = x # 15.cint
  let yy = t.uiYGap.cint
  while true:
    let header = it.heading & (if it.changed: "*" else: "")
    let rect = drawTextWithBorder(t, header,
                                  it == active, xx, yy, screenW)
    # if there was no room left to draw this tab:
    if rect.w == 0:
      if not activeDrawn:
        # retry the whole rendering, setting the start of the tabbar to
        # something else:
        if it.prev != tabs.first:
          tabs.first = it.prev
          return drawTabBar(tabs, t, x, screenW, e, active)
      break

    activeDrawn = activeDrawn or it == active
    if e.kind == MouseButtonDown:
      let w = e.button
      if w.clicks.int >= 1:
        let p = point(w.x, w.y)
        if rect.contains(p):
          result = it
    elif e.kind == MouseMotion:
      let w = e.motion
      if (w.state and BUTTON_LMASK) != 0:
        let p = point(w.x, w.y)
        if rect.contains(p):
          if w.xrel >= 4:
            if it == tabs.first: tabs.first = it.next
            swapBuffers(it, it.next)
          elif w.xrel <= -4:
            if it == tabs.first: tabs.first = it.prev
            swapBuffers(it.prev, it)

    inc xx, rect.w + t.uiXGap*2
    if it == tabs.last: break
    it = it.next
    if it == tabs.first: break
