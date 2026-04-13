
import uirelays/[coords, screen]
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
  for octAPosition in octantAPoints(radius):
    for oct in octs:
      let offset = octAPosition.transformFor(oct)
      pixel(x + offset.x, y + offset.y, p)


type
  RoundedRect = tuple
    left, top, right, bottom, rad: int

func normalize(x1, y1, x2, y2, rad: sink int): RoundedRect {.inline.} =
  assert x1 != x2
  assert y1 != y2

  result.left = x1
  result.right = x2
  result.top = y1
  result.bottom = y2
  if result.left > result.right: swap result.left, result.right
  if result.top > result.bottom: swap result.top, result.bottom

  let
    width = result.right - result.left
    height = result.bottom - result.top
  result.rad = rad
  if (result.rad * 2) > width: result.rad = width div 2
  if (result.rad * 2) > height: result.rad = height div 2

proc roundedRect*(x1, y1, x2, y2, rad: int; p: Pixel) =
  let r = normalize(x1, y1, x2, y2, rad)

  let
    leftArcCenter = r.left + r.rad
    rightArcCenter = r.right - r.rad
    topArcCenter = r.top + r.rad
    bottomArcCenter = r.bottom - r.rad
  arc(leftArcCenter, topArcCenter, r.rad, [octE, octF], p)
  arc(rightArcCenter, topArcCenter, r.rad, [octG, octH], p)
  arc(leftArcCenter, bottomArcCenter, r.rad, [octC, octD], p)
  arc(rightArcCenter, bottomArcCenter, r.rad, [octA, octB], p)

  hline(leftArcCenter, rightArcCenter, r.top, p)
  hline(leftArcCenter, rightArcCenter, r.bottom, p)
  vline(r.left, topArcCenter, bottomArcCenter, p)
  vline(r.right, topArcCenter, bottomArcCenter, p)


proc fillArc(x, y, radius: int; octs: openArray[Octant]; color: Color) =
  for octAPosition in octantAPoints(radius):
    for oct in octs:
      let (dx, dy) = octAPosition.transformFor(oct)
      hline(x, x + dx, y + dy, color)


proc roundedBox*(x1: int; y1: int; x2: int;
                    y2: int; rad: int; c: Color) =
  let r = normalize(x1, y1, x2, y2, rad)

  let
    leftArcCenter = r.left + r.rad
    rightArcCenter = r.right - r.rad
    topArcCenter = r.top + r.rad
    bottomArcCenter = r.bottom - r.rad

  fillArc(leftArcCenter, topArcCenter, r.rad, [octE, octF], c)
  fillArc(rightArcCenter, topArcCenter, r.rad, [octG, octH], c)
  fillArc(leftArcCenter, bottomArcCenter, r.rad, [octC, octD], c)
  fillArc(rightArcCenter, bottomArcCenter, r.rad, [octA, octB], c)


  # We'll divide the area into three rectangles.
  let
    topBox = Rect(x: leftArcCenter, y: r.top, w: rightArcCenter - leftArcCenter,
      h: r.rad)
    middleBox = Rect(x: r.left, y: topArcCenter, w: r.right - r.left,
      h: bottomArcCenter - topArcCenter)
    bottomBox = Rect(x: leftArcCenter, y: bottomArcCenter, w: topBox.w,
      h: topBox.h)

  fillRect(topBox, c)
  fillRect(middleBox, c)
  fillRect(bottomBox, c)