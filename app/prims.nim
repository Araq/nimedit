
import basetypes, screen
from math import sin, cos, PI

type
  Pixel* = object
    col*: Color
    thickness*: cint
    gradient*: Color

proc brightness*(c: Color): int = 299*c.r.int + 587*c.g.int + 114*c.b.int

proc pixel*(x: int; y: int; p: Pixel) =
  if p.thickness <= 1:
    drawPoint(x.cint, y.cint, p.col)
  else:
    fillRect(Rect(x: x.cint, y: y.cint, w: p.thickness, h: p.thickness), p.col)

proc pixel*(x: int; y: int; c: Color) =
  drawPoint(x.cint, y.cint, c)

template hasGradient(p: Pixel): bool = p.gradient != p.col

template nextColor(r, w, i): untyped =
  uint8(clamp(oldp.col.r.float + (p.gradient.r.int - oldp.col.r.int) / w * i.float, 0d, 255d))

template prevColor(r, w, i): untyped =
  uint8(clamp(p.gradient.r.float - (p.gradient.r.int - oldp.col.r.int) / w * i.float, 0d, 255d))

proc hlineGradient(x, y, w: int; oldp: Pixel) =
  var p = oldp
  for i in 0..w-1:
    if p.thickness <= 1:
      drawPoint((x+i).cint, y.cint, p.col)
    else:
      fillRect(Rect(x: (x+i).cint, y: y.cint, w: 1, h: p.thickness), p.col)
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

proc vlineGradient(x, y, h: int; p: Pixel) =
  var p = p
  for i in 0..h-1:
    if p.thickness <= 1:
      drawPoint(x.cint, (y+i).cint, p.col)
    else:
      fillRect(Rect(x: x.cint, y: (y+i).cint, w: p.thickness, h: 1), p.col)

proc hline*(x1: int; x2: int; y: int; p: Pixel) =
  if not hasGradient(p):
    drawLine(x1.cint, y.cint, x2.cint, y.cint, p.col)
    for i in 1..p.thickness:
      drawLine(x1.cint, (y+i).cint, x2.cint, (y+i).cint, p.col)
  else:
    hLineGradient(x1.cint, y.cint, (x2-x1+1).cint, p)

proc hline*(x1: int; x2: int; y: int; c: Color) =
  drawLine(x1.cint, y.cint, x2.cint, y.cint, c)

proc vline*(x: int; y1: int; y2: int; p: Pixel) =
  if not hasGradient(p):
    drawLine(x.cint, y1.cint, x.cint, y2.cint, p.col)
    for i in 1..p.thickness:
      drawLine((x+i).cint, y1.cint, (x+i).cint, y2.cint, p.col)
  else:
    vLineGradient(x.cint, y1.cint, (y2-y1+1).cint, p)

proc vlineDotted*(x: int; y1: int; y2: int; c: Color) =
  var i = y1
  while i <= y2:
    drawPoint(x.cint, i.cint, c)
    inc i, 2

proc hlineDotted*(x1: int; x2: int; y: int; c: Color) =
  var i = x1
  while i <= x2:
    drawPoint(i.cint, y.cint, c)
    inc i, 2

proc vline*(x: int; y1: int; y2: int; c: Color) =
  drawLine(x.cint, y1.cint, x.cint, y2.cint, c)

proc box*(x1: int; y1: int; x2: int; y2: int; c: Color) =
  var x1 = x1
  var x2 = x2
  var y1 = y1
  var y2 = y2
  if x1 > x2: swap x1, x2
  if y1 > y2: swap y1, y2
  fillRect(Rect(x: x1.cint, y: y1.cint, w: cint(x2 - x1 + 1), h: cint(y2 - y1 + 1)), c)

proc arc*(x: int; y: int; rad: int; start: int;
          `end`: int; p: Pixel) =
  var cx: int = 0
  var cy: int = rad
  var df: int = 1 - rad
  var dE: int = 3
  var dSe: int = - (2 * rad) + 5
  var xpcx, xmcx, xpcy, xmcy: int
  var ypcy, ymcy, ypcx, ymcx: int
  var drawoct: uint8
  var startoct, endoct, oct: cint
  var stopvalStart: cint = 0
  var stopvalEnd: cint = 0
  var dstart, dend: cdouble
  var temp: cdouble = 0.0
  assert rad >= 0
  if rad == 0:
    pixel(x, y, p)
    return
  drawoct = 0
  var start = start mod 360
  var `end` = `end` mod 360
  while start < 0: inc(start, 360)
  while `end` < 0: inc(`end`, 360)
  start = start mod 360
  `end` = `end` mod 360
  startoct = start.int32 div 45i32
  endoct = `end`.int32 div 45i32
  oct = startoct - 1
  while true:
    oct = (oct + 1) mod 8
    if oct == startoct:
      dstart = cdouble(start)
      case oct
      of 0, 3: temp = sin(dstart * Pi / 180.0)
      of 1, 6: temp = cos(dstart * Pi / 180.0)
      of 2, 5: temp = - cos(dstart * Pi / 180.0)
      of 4, 7: temp = - sin(dstart * Pi / 180.0)
      else: discard
      temp = temp * rad.float
      stopvalStart = cint(temp)
      if oct mod 2 != 0: drawoct = drawoct or uint8(1 shl oct)
      else: drawoct = drawoct and uint8(255 - (1 shl oct))
    if oct == endoct:
      dend = cdouble(`end`)
      case oct
      of 0, 3: temp = sin(dend * Pi / 180.0)
      of 1, 6: temp = cos(dend * Pi / 180.0)
      of 2, 5: temp = - cos(dend * Pi / 180.0)
      of 4, 7: temp = - sin(dend * Pi / 180.0)
      else: discard
      temp = temp * rad.float
      stopvalEnd = cint(temp)
      if startoct == endoct:
        if start > `end`: drawoct = 255
        else: drawoct = drawoct and uint8(255 - (1 shl oct))
      elif oct mod 2 != 0:
        drawoct = drawoct and uint8(255 - (1 shl oct))
      else:
        drawoct = drawoct or uint8(1 shl oct)
    elif oct != startoct:
      drawoct = drawoct or uint8(1 shl oct)
    if oct == endoct: break
  while true:
    ypcy = y + cy
    ymcy = y - cy
    if cx > 0:
      xpcx = x + cx
      xmcx = x - cx
      if (drawoct and 4) != 0: pixel(xmcx, ypcy, p)
      if (drawoct and 2) != 0: pixel(xpcx, ypcy, p)
      if (drawoct and 32) != 0: pixel(xmcx, ymcy, p)
      if (drawoct and 64) != 0: pixel(xpcx, ymcy, p)
    else:
      if (drawoct and 96) != 0: pixel(x, ymcy, p)
      if (drawoct and 6) != 0: pixel(x, ypcy, p)
    xpcy = x + cy
    xmcy = x - cy
    if cx > 0 and cx != cy:
      ypcx = y + cx
      ymcx = y - cx
      if (drawoct and 8) != 0: pixel(xmcy, ypcx, p)
      if (drawoct and 1) != 0: pixel(xpcy, ypcx, p)
      if (drawoct and 16) != 0: pixel(xmcy, ymcx, p)
      if (drawoct and 128) != 0: pixel(xpcy, ymcx, p)
    elif cx == 0:
      if (drawoct and 24) != 0: pixel(xmcy, y, p)
      if (drawoct and 129) != 0: pixel(xpcy, y, p)
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

proc roundedRect*(x1, y1, x2, y2, rad: int; p: Pixel) =
  var w, h: int
  var xx1, xx2, yy1, yy2: int
  assert rad >= 0
  if rad <= 1: return
  if x1 == x2:
    if y1 == y2: pixel(x1, y1, p)
    else: vline(x1, y1, y2, p)
    return
  else:
    if y1 == y2:
      hline(x1, x2, y1, p)
      return
  var x1 = x1; var x2 = x2; var y1 = y1; var y2 = y2
  if x1 > x2: swap x1, x2
  if y1 > y2: swap y1, y2
  w = x2 - x1; h = y2 - y1
  var rad = rad
  if (rad * 2) > w: rad = w div 2
  if (rad * 2) > h: rad = h div 2
  xx1 = x1 + rad; xx2 = x2 - rad
  yy1 = y1 + rad; yy2 = y2 - rad
  arc(xx1, yy1, rad, 180, 270, p)
  arc(xx2, yy1, rad, 270, 360, p)
  arc(xx1, yy2, rad, 90, 180, p)
  arc(xx2, yy2, rad, 0, 90, p)
  if xx1 <= xx2:
    hline(xx1, xx2, y1, p)
    hline(xx1, xx2, y2, p)
  if yy1 <= yy2:
    vline(x1, yy1, yy2, p)
    vline(x2, yy1, yy2, p)

proc roundedBox*(x1: int; y1: int; x2: int;
                    y2: int; rad: int; c: Color) =
  var w, h, r2: int
  var cx: int = 0
  var cy: int = rad
  var ocx: int = -1
  var ocy: int = -1
  var df: int = 1 - rad
  var dE: int = 3
  var dSe: int = - (2 * rad) + 5
  var xpcx, xmcx, xpcy, xmcy: int
  var ypcy, ymcy, ypcx, ymcx: int
  var x, y, dx, dy: int
  assert rad >= 0
  if rad <= 1: return
  if x1 == x2:
    if y1 == y2: pixel(x1, y1, c)
    else: vline(x1, y1, y2, c)
    return
  else:
    if y1 == y2:
      hline(x1, x2, y1, c)
      return
  var x1 = x1; var x2 = x2; var y1 = y1; var y2 = y2
  if x1 > x2: swap x1, x2
  if y1 > y2: swap y1, y2
  w = x2 - x1 + 1; h = y2 - y1 + 1
  r2 = rad + rad
  var rad = rad
  if r2 > w: rad = w div 2; r2 = rad + rad
  if r2 > h: rad = h div 2
  x = x1 + rad; y = y1 + rad
  dx = x2 - x1 - rad - rad; dy = y2 - y1 - rad - rad
  while true:
    xpcx = x + cx; xmcx = x - cx
    xpcy = x + cy; xmcy = x - cy
    if ocy != cy:
      if cy > 0:
        ypcy = y + cy; ymcy = y - cy
        hline(xmcx, xpcx + dx, ypcy + dy, c)
        hline(xmcx, xpcx + dx, ymcy, c)
      else:
        hline(xmcx, xpcx + dx, y, c)
      ocy = cy
    if ocx != cx:
      if cx != cy:
        if cx > 0:
          ypcx = y + cx; ymcx = y - cx
          hline(xmcy, xpcy + dx, ymcx, c)
          hline(xmcy, xpcy + dx, ypcx + dy, c)
        else:
          hline(xmcy, xpcy + dx, y, c)
      ocx = cx
    if df < 0:
      inc(df, dE); inc(dE, 2); inc(dSe, 2)
    else:
      inc(df, dSe); inc(dE, 2); inc(dSe, 4); dec(cy)
    inc(cx)
    if cx > cy: break
  if dx > 0 and dy > 0:
    box(x1, y1 + rad + 1, x2, y2 - rad, c)
