
import sdl2
from math import sin, cos, PI

type
  Pixel* = object
    col*: Color
    thickness*: cint
    gradient*: Color

proc brightness*(c: Color): int = 299*c.r.int + 587*c.g.int + 114*c.b.int

proc pixel*(renderer: RendererPtr; x: int; y: int; p: Pixel) =
  #setDrawBlendMode(renderer,
  #      if c.a == 255: Blendmode_None else: Blendmode_Blend)
  setDrawColor(renderer, p.col)
  if p.thickness <= 1:
    drawPoint(renderer, x.cint, y.cint)
  else:
    var rect: Rect
    rect.x = x.cint
    rect.y = y.cint
    rect.w = p.thickness
    rect.h = p.thickness
    drawRect(renderer, rect)
  #drawPoint(renderer, x+1, y)
  #drawPoint(renderer, x, y+1)
  #drawPoint(renderer, x+1, y+1)

proc pixel*(renderer: RendererPtr; x: int; y: int; c: Color) =
  setDrawColor(renderer, c)
  drawPoint(renderer, x.cint, y.cint)

template hasGradient(p: Pixel): bool = p.gradient != p.col

# 10  14   over 4 steps
#   (14-10) div 4 --> 1
#   (10-14) div 4 --> -1

template nextColor(r, w, i): untyped =
  uint8(clamp(oldp.col.r.float + (p.gradient.r.int - oldp.col.r.int) / w * i.float, 0d, 255d))
  #uint8(clamp(p.col.r + 1, 0, 255))

template prevColor(r, w, i): untyped =
  uint8(clamp(p.gradient.r.float - (p.gradient.r.int - oldp.col.r.int) / w * i.float, 0d, 255d))
  #uint8(clamp(p.col.r - 1, 0, 255))

proc hlineGradient(renderer: RendererPtr; x, y, w: int; oldp: Pixel) =
  var j = 1
  var p = oldp
  for i in 0..w-1:
    setDrawColor(renderer, p.col)
    if p.thickness <= 1:
      drawPoint(renderer, x.cint+i.cint, y.cint)
    else:
      var rect: Rect
      rect.x = (x+i).cint
      rect.y = y.cint
      rect.w = 1
      rect.h = p.thickness
      drawRect(renderer, rect)
    if i > w-40:
      let strength = i-w+40
      p.col.r = prevColor(r, 40, strength)
      p.col.g = prevColor(g, 40, strength)
      p.col.b = prevColor(b, 40, strength)
    elif i > w-80:
      let strength = i-w+80
      p.col.r = nextColor(r, 40, strength)
      p.col.g = nextColor(g, 40, strength)
      p.col.b = nextColor(b, 40, strength)

proc vlineGradient(renderer: RendererPtr; x, y, h: int; p: Pixel) =
  let w = h
  var p = p
  for i in 0..h-1:
    setDrawColor(renderer, p.col)
    if p.thickness <= 1:
      drawPoint(renderer, x.cint, y.cint+h.cint)
    else:
      var rect: Rect
      rect.x = x.cint
      rect.y = (y+i).cint
      rect.w = p.thickness
      rect.h = 1
      drawRect(renderer, rect)
    #p.col.r = nextColor(r)
    #p.col.g = nextColor(g)
    #p.col.b = nextColor(b)

proc hline*(renderer: RendererPtr; x1: int; x2: int; y: int; p: Pixel) =
  setDrawColor(renderer, p.col)
  if not hasGradient(p):
    drawLine(renderer, x1.cint, y.cint, x2.cint, y.cint)
    for i in 1..p.thickness:
      drawLine(renderer, x1.cint, (y+i).cint, x2.cint, (y+i).cint)
  else:
    hLineGradient(renderer, x1.cint, y.cint, (x2-x1+1).cint, p)

proc hline*(renderer: RendererPtr; x1: int; x2: int; y: int; c: Color) =
  setDrawColor(renderer, c)
  drawLine(renderer, x1.cint, y.cint, x2.cint, y.cint)

proc vline*(renderer: RendererPtr; x: int; y1: int; y2: int; p: Pixel) =
  setDrawColor(renderer, p.col)
  if not hasGradient(p):
    drawLine(renderer, x.cint, y1.cint, x.cint, y2.cint)
    for i in 1..p.thickness:
      drawLine(renderer, (x+i).cint, y1.cint, (x+i).cint, y2.cint)
  else:
    vLineGradient(renderer, x.cint, y1.cint, (y2-y1+1).cint, p)

proc vlineDotted*(renderer: RendererPtr; x: int; y1: int; y2: int; c: Color) =
  setDrawColor(renderer, c)
  var i = y1
  while i <= y2:
    drawPoint(renderer, x.cint, i.cint)
    inc i, 2

proc hlineDotted*(renderer: RendererPtr; x1: int; x2: int; y: int; c: Color) =
  setDrawColor(renderer, c)
  var i = x1
  while i <= x2:
    drawPoint(renderer, i.cint, y.cint)
    inc i, 2

proc vline*(renderer: RendererPtr; x: int; y1: int; y2: int; c: Color) =
  setDrawColor(renderer, c)
  drawLine(renderer, x.cint, y1.cint, x.cint, y2.cint)

when false:
  proc rectangle*(renderer: RendererPtr; x1, y1, x2, y2: int; c: Color) =
    var rect: Rect
    if x1 == x2:
      if y1 == y2:
        pixel(renderer, x1, y1, c)
      else:
        vline(renderer, x1, y1, y2, c)
      return
    else:
      if y1 == y2:
        hline(renderer, x1, x2, y1, c)
        return
    var x1 = x1
    var x2 = x2
    var y1 = y1
    var y2 = y2
    if x1 > x2:
      swap x1, x2
    if y1 > y2:
      swap y1, y2
    rect.x = x1.cint
    rect.y = y1.cint
    rect.w = cint(x2 - x1)
    rect.h = cint(y2 - y1)
    #setDrawBlendMode(renderer, if c.a == 255: Blendmode_None else: Blendmode_Blend)
    setDrawColor(renderer, c)
    drawRect(renderer, rect)

proc arc*(renderer: RendererPtr; x: int; y: int; rad: int; start: int;
             `end`: int; p: Pixel) =
  var cx: int = 0
  var cy: int = rad
  var df: int = 1 - rad
  var dE: int = 3
  var dSe: int = - (2 * rad) + 5
  var
    xpcx: int
    xmcx: int
    xpcy: int
    xmcy: int
  var
    ypcy: int
    ymcy: int
    ypcx: int
    ymcx: int
  var drawoct: uint8
  var
    startoct: cint
    endoct: cint
    oct: cint
    stopvalStart: cint = 0
    stopvalEnd: cint = 0
  var
    dstart: cdouble
    dend: cdouble
    temp: cdouble = 0.0
  assert rad >= 0
  if rad == 0:
    pixel(renderer, x, y, p)
    return
  drawoct = 0
  var start = start mod 360
  var `end` = `end` mod 360
  while start < 0: inc(start, 360)
  while `end` < 0: inc(`end`, 360)
  start = start mod 360
  `end` = `end` mod 360
  startoct = start div 45
  endoct = `end` div 45
  oct = startoct - 1
  while true:
    oct = (oct + 1) mod 8
    if oct == startoct:
      dstart = cdouble(start)
      case oct
      of 0, 3:
        temp = sin(dstart * Pi / 180.0)
      of 1, 6:
        temp = cos(dstart * Pi / 180.0)
      of 2, 5:
        temp = - cos(dstart * Pi / 180.0)
      of 4, 7:
        temp = - sin(dstart * Pi / 180.0)
      else: discard
      temp = temp * rad.float
      stopvalStart = cint(temp)
      if oct mod 2 != 0: drawoct = drawoct or uint8(1 shl oct)
      else: drawoct = drawoct and uint8(255 - (1 shl oct))
    if oct == endoct:
      dend = cdouble(`end`)
      case oct
      of 0, 3:
        temp = sin(dend * Pi / 180.0)
      of 1, 6:
        temp = cos(dend * Pi / 180.0)
      of 2, 5:
        temp = - cos(dend * Pi / 180.0)
      of 4, 7:
        temp = - sin(dend * Pi / 180.0)
      else: discard
      temp = temp * rad.float
      stopvalEnd = cint(temp)
      if startoct == endoct:
        if start > `end`:
          drawoct = 255
        else:
          drawoct = drawoct and uint8(255 - (1 shl oct))
      elif oct mod 2 != 0:
        drawoct = drawoct and uint8(255 - (1 shl oct))
      else:
        drawoct = drawoct or uint8(1 shl oct)
    elif oct != startoct:
      drawoct = drawoct or uint8(1 shl oct)
    if oct == endoct: break
  #setDrawBlendMode(renderer, if c.a == 255: Blendmode_None else: Blendmode_Blend)
  setDrawColor(renderer, p.col)
  while true:
    ypcy = y + cy
    ymcy = y - cy
    if cx > 0:
      xpcx = x + cx
      xmcx = x - cx
      if (drawoct and 4) != 0: pixel(renderer, xmcx, ypcy, p)
      if (drawoct and 2) != 0: pixel(renderer, xpcx, ypcy, p)
      if (drawoct and 32) != 0: pixel(renderer, xmcx, ymcy, p)
      if (drawoct and 64) != 0: pixel(renderer, xpcx, ymcy, p)
    else:
      if (drawoct and 96) != 0: pixel(renderer, x, ymcy, p)
      if (drawoct and 6) != 0: pixel(renderer, x, ypcy, p)
    xpcy = x + cy
    xmcy = x - cy
    if cx > 0 and cx != cy:
      ypcx = y + cx
      ymcx = y - cx
      if (drawoct and 8) != 0: pixel(renderer, xmcy, ypcx, p)
      if (drawoct and 1) != 0: pixel(renderer, xpcy, ypcx, p)
      if (drawoct and 16) != 0: pixel(renderer, xmcy, ymcx, p)
      if (drawoct and 128) != 0: pixel(renderer, xpcy, ymcx, p)
    elif cx == 0:
      if (drawoct and 24) != 0: pixel(renderer, xmcy, y, p)
      if (drawoct and 129) != 0: pixel(renderer, xpcy, y, p)
    if stopvalStart == cx:
      if (drawoct and uint8(1 shl startoct)) != 0:
        drawoct = drawoct and uint8(255 - (1 shl startoct))
      else:
        drawoct = drawoct or uint8(1 shl startoct)
    if stopvalEnd == cx:
      if (drawoct and uint8(1 shl endoct)) != 0:
        drawoct = drawoct and uint8(255 - (1 shl endoct))
      else:
        drawoct = drawoct or uint8(1 shl endoct)
    if df < 0:
      inc(df, dE)
      inc(dE, 2)
      inc(dSe, 2)
    else:
      inc(df, dSe)
      inc(dE, 2)
      inc(dSe, 4)
      dec(cy)
    inc(cx)
    if cx > cy: break

proc roundedRect*(renderer: RendererPtr; x1, y1, x2, y2, rad: int; p: Pixel) =
  var
    w: int
    h: int
  var
    xx1: int
    xx2: int
  var
    yy1: int
    yy2: int
  assert rad >= 0
  if rad <= 1:
    #rectangle(renderer, x1, y1, x2, y2, p)
    return
  if x1 == x2:
    if y1 == y2:
      pixel(renderer, x1, y1, p)
    else:
      vline(renderer, x1, y1, y2, p)
    return
  else:
    if y1 == y2:
      hline(renderer, x1, x2, y1, p)
      return
  var x1 = x1
  var x2 = x2
  var y1 = y1
  var y2 = y2
  if x1 > x2:
    swap x1, x2
  if y1 > y2:
    swap y1, y2

  w = x2 - x1
  h = y2 - y1
  var rad = rad
  if (rad * 2) > w:
    rad = w div 2
  if (rad * 2) > h:
    rad = h div 2
  xx1 = x1 + rad
  xx2 = x2 - rad
  yy1 = y1 + rad
  yy2 = y2 - rad
  arc(renderer, xx1, yy1, rad, 180, 270, p)
  arc(renderer, xx2, yy1, rad, 270, 360, p)
  arc(renderer, xx1, yy2, rad, 90, 180, p)
  arc(renderer, xx2, yy2, rad, 0, 90, p)
  if xx1 <= xx2:
    hline(renderer, xx1, xx2, y1, p)
    hline(renderer, xx1, xx2, y2, p)
  if yy1 <= yy2:
    vline(renderer, x1, yy1, yy2, p)
    vline(renderer, x2, yy1, yy2, p)

proc box*(renderer: RendererPtr; x1: int; y1: int; x2: int; y2: int;
          c: Color) =
  when false:
    var rect: Rect
    if x1 == x2:
      if y1 == y2:
        pixel(renderer, x1, y1, c)
      else:
        vline(renderer, x1, y1, y2, c)
      return
    else:
      if y1 == y2:
        hline(renderer, x1, x2, y1, c)
        return
  var x1 = x1
  var x2 = x2
  var y1 = y1
  var y2 = y2
  if x1 > x2:
    swap x1, x2
  if y1 > y2:
    swap y1, y2
  var rect: Rect
  rect.x = x1.cint
  rect.y = y1.cint
  rect.w = cint(x2 - x1 + 1)
  rect.h = cint(y2 - y1 + 1)
  #setDrawBlendMode(renderer, if c.a == 255: Blendmode_None else: Blendmode_Blend)
  setDrawColor(renderer, c)
  fillRect(renderer, rect)

proc roundedBox*(renderer: RendererPtr; x1: int; y1: int; x2: int;
                    y2: int; rad: int; c: Color) =
  var
    w: int
    h: int
    r2: int
    tmp: int
  var cx: int = 0
  var cy: int = rad
  var ocx: int = -1
  var ocy: int = -1
  var df: int = 1 - rad
  var dE: int = 3
  var dSe: int = - (2 * rad) + 5
  var
    xpcx: int
    xmcx: int
    xpcy: int
    xmcy: int
  var
    ypcy: int
    ymcy: int
    ypcx: int
    ymcx: int
  var
    x: int
    y: int
    dx: int
    dy: int
  assert rad >= 0
  if rad <= 1:
    #rectangle(renderer, x1, y1, x2, y2, c)
    return
  if x1 == x2:
    if y1 == y2:
      pixel(renderer, x1, y1, c)
    else:
      vline(renderer, x1, y1, y2, c)
    return
  else:
    if y1 == y2:
      hline(renderer, x1, x2, y1, c)
      return

  var x1 = x1
  var x2 = x2
  var y1 = y1
  var y2 = y2
  if x1 > x2:
    swap x1, x2
  if y1 > y2:
    swap y1, y2

  w = x2 - x1 + 1
  h = y2 - y1 + 1
  r2 = rad + rad
  var rad = rad
  if r2 > w:
    rad = w div 2
    r2 = rad + rad
  if r2 > h:
    rad = h div 2
  x = x1 + rad
  y = y1 + rad
  dx = x2 - x1 - rad - rad
  dy = y2 - y1 - rad - rad
  #setDrawBlendMode(renderer, if c.a == 255: Blendmode_None else: Blendmode_Blend)
  setDrawColor(renderer, c)
  while true:
    xpcx = x + cx
    xmcx = x - cx
    xpcy = x + cy
    xmcy = x - cy
    if ocy != cy:
      if cy > 0:
        ypcy = y + cy
        ymcy = y - cy
        hline(renderer, xmcx, xpcx + dx, ypcy + dy, c)
        hline(renderer, xmcx, xpcx + dx, ymcy, c)
      else:
        hline(renderer, xmcx, xpcx + dx, y, c)
      ocy = cy
    if ocx != cx:
      if cx != cy:
        if cx > 0:
          ypcx = y + cx
          ymcx = y - cx
          hline(renderer, xmcy, xpcy + dx, ymcx, c)
          hline(renderer, xmcy, xpcy + dx, ypcx + dy, c)
        else:
          hline(renderer, xmcy, xpcy + dx, y, c)
      ocx = cx
    if df < 0:
      inc(df, dE)
      inc(dE, 2)
      inc(dSe, 2)
    else:
      inc(df, dSe)
      inc(dE, 2)
      inc(dSe, 4)
      dec(cy)
    inc(cx)
    if cx > cy: break
  if dx > 0 and dy > 0:
    box(renderer, x1, y1 + rad + 1, x2, y2 - rad, c)
