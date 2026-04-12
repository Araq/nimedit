
import basetypes, screen
from math import sin, cos, PI

type
  Pixel* = object
    col*: Color
    gradient*: Color
    thickness*: int

proc brightness*(c: Color): int = 299*c.r.int + 587*c.g.int + 114*c.b.int

proc pixel*(x: int; y: int; p: Pixel) =
  if p.thickness <= 1:
    drawPoint(x, y, p.col)
  else:
    fillRect(Rect(x: x, y: y, w: p.thickness, h: p.thickness), p.col)

proc pixel*(x: int; y: int; c: Color) =
  drawPoint(x, y, c)

template hasGradient(p: Pixel): bool = p.gradient != p.col

template nextColor(r, w, i): untyped =
  uint8(clamp(oldp.col.r.float + (p.gradient.r.int - oldp.col.r.int) / w * i.float, 0d, 255d))

template prevColor(r, w, i): untyped =
  uint8(clamp(p.gradient.r.float - (p.gradient.r.int - oldp.col.r.int) / w * i.float, 0d, 255d))

proc hlineGradient(x, y, w: int; oldp: Pixel) =
  var p = oldp
  for i in 0..w-1:
    if p.thickness <= 1:
      drawPoint(x+i, y, p.col)
    else:
      fillRect(Rect(x: x+i, y: y, w: 1, h: p.thickness), p.col)
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
      drawPoint(x, y+i, p.col)
    else:
      fillRect(Rect(x: x, y: y+i, w: p.thickness, h: 1), p.col)

proc hline*(x1: int; x2: int; y: int; p: Pixel) =
  if not hasGradient(p):
    drawLine(x1, y, x2, y, p.col)
    for i in 1..p.thickness:
      drawLine(x1, y+i, x2, y+i, p.col)
  else:
    hLineGradient(x1, y, (x2-x1+1), p)

proc hline*(x1: int; x2: int; y: int; c: Color) =
  drawLine(x1, y, x2, y, c)

proc vline*(x: int; y1: int; y2: int; p: Pixel) =
  if not hasGradient(p):
    drawLine(x, y1, x, y2, p.col)
    for i in 1..p.thickness:
      drawLine(x+i, y1, x+i, y2, p.col)
  else:
    vLineGradient(x, y1, (y2-y1+1), p)

proc vlineDotted*(x: int; y1: int; y2: int; c: Color) =
  var i = y1
  while i <= y2:
    drawPoint(x, i, c)
    inc i, 2

proc hlineDotted*(x1: int; x2: int; y: int; c: Color) =
  var i = x1
  while i <= x2:
    drawPoint(i, y, c)
    inc i, 2

proc vline*(x: int; y1: int; y2: int; c: Color) =
  drawLine(x, y1, x, y2, c)

proc box*(x1: int; y1: int; x2: int; y2: int; c: Color) =
  var x1 = x1
  var x2 = x2
  var y1 = y1
  var y2 = y2
  if x1 > x2: swap x1, x2
  if y1 > y2: swap y1, y2
  fillRect(Rect(x: x1, y: y1, w: x2 - x1 + 1, h: y2 - y1 + 1), c)

type Octant* = enum
  octA, octB, octC, octD, octE, octF, octG, octH

#[
     oct F |270
           | oct G
           |
  oct E    |     oct H
180 --------------- 0   -> +x
  oct D    |     oct A
           |
     oct C |  oct B
           |90

           |
           v
          +y
]#

iterator octantAPoints(radius: int): tuple[x, y: int] =
  ##[Used to iterate over every position on `octA`'s arc segment.

  The yielded values are the offset from the center of the arc to a position
  between 0 and 45 degrees, starting at 0 and ending at 45.

  The first values yielded will be `(0, radius)`.
  The last values will be approximately `(radius / sqrt(2), radius / sqrt(2))`.

  If you want to iterate over an octant that isn't `octA`, you'll have to
  mirror, rotate, or apply some other transformation to the results.
  ]##
  # Uses the midpoint circle algorithm.
  var
    df = 4 - radius
    dE = 5
    dSe = - (2 * radius) + 7
    currentPos = (x: radius, y: 0)

  while currentPos.y <= currentPos.x:
    yield currentPos

    if df < 0:
      df.inc dE
      dSe.inc 2
    else:
      df.inc dSe
      dSe.inc 4
      currentPos.x.dec
    dE.inc 2
    currentPos.y.inc

func transformFor(
    octantAPoint: tuple[x, y: int]; desiredOctant: Octant
  ): tuple[x, y: int] {.inline.} =
  ##Transforms a point on `octA`'s arc to lie upon the input octant.
  const CloserToYAxis = {octB, octC, octF, octG}
  var
    changeInX = octantAPoint.x
    changeInY = octantAPoint.y
  if desiredOctant in CloserToYAxis: swap changeInX, changeInY

  const
    Northern = {octE..octH}
    Western = {octC..octF}
  result.x = changeInX
  if desiredOctant in Western: result.x *= -1

  result.y = changeInY
  if desiredOctant in Northern: result.y *= -1


proc arc*(x, y: int; radius: int; octs: openArray[Octant]; p: Pixel) =
  assert radius > 0
  for progressor in octantAPoints(radius):
    for oct in octs:
      let offset = progressor.transformFor(oct)
      pixel(x + offset.x, y + offset.y, p)

proc roundedRect*(x1, y1, x2, y2, rad: int; p: Pixel) =
  assert x1 != x2
  assert y1 != y2

  var
    left = x1
    right = x2
    top = y1
    bottom = y2
  if left > right: swap left, right
  if top > bottom: swap top, bottom

  let
    width = right - left
    height = bottom - top
  var rad = rad
  if (rad * 2) > width: rad = width div 2
  if (rad * 2) > height: rad = height div 2

  let
    leftArcCenter = left + rad
    rightArcCenter = right - rad
    topArcCenter = top + rad
    bottomArcCenter = bottom - rad
  arc(leftArcCenter, topArcCenter, rad, [octE, octF], p)
  arc(rightArcCenter, topArcCenter, rad, [octG, octH], p)
  arc(leftArcCenter, bottomArcCenter, rad, [octC, octD], p)
  arc(rightArcCenter, bottomArcCenter, rad, [octA, octB], p)

  hline(leftArcCenter, rightArcCenter, top, p)
  hline(leftArcCenter, rightArcCenter, bottom, p)
  vline(left, topArcCenter, bottomArcCenter, p)
  vline(right, topArcCenter, bottomArcCenter, p)

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
