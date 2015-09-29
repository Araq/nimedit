
const
  #ContinueLineMarker = "\xE2\xA4\xB8\x00"
  Ellipsis = "\xE2\x80\xA6\x00"
  CharBufSize = 80

proc drawTexture(r: RendererPtr; font: FontPtr; msg: cstring;
                 fg, bg: Color): TexturePtr =
  assert font != nil
  assert msg[0] != '\0'
  var surf: SurfacePtr = renderUtf8Shaded(font, msg, fg, bg)
  if surf == nil:
    echo("TTF_RenderText failed")
    return
  result = createTextureFromSurface(r, surf)
  if result == nil:
    echo("CreateTexture failed")
  freeSurface(surf)

proc whichColumn(b: Buffer; i: int; dim: Rect; font: FontPtr;
                 msg: cstring): int =
  var buffer: array[CharBufSize, char]
  var j = i
  var r = 0
  let ending = i+msg.len
  while j < ending:
    var L = graphemeLen(b, j)
    for k in 0..<L:
      buffer[r] = b[k+j]
      inc r
    buffer[r] = '\0'
    var w: cint
    discard sizeUtf8(font, buffer, addr w, nil)
    if dim.x+w >= b.mouseX-1:
      return r
    inc j, L

proc mouseSelectWholeLine(b: Buffer) =
  var first = b.cursor
  while first > 0 and b[first-1] != '\L': dec first
  b.selected = Marker(a: first, b: b.cursor, s: mcSelected)

proc mouseSelectCurrentToken(b: Buffer) =
  const Letters = {'a'..'z', 'A'..'Z', '0'..'9', '_', '\128'..'\255'}
  var first = b.cursor
  var last = b.cursor
  if b[b.cursor] in Letters:
    while first > 0 and b[first-1] in Letters: dec first
    while last < b.len and b[last+1] in Letters: inc last
  else:
    while first > 0 and b.getCell(first-1).s == b.getCell(b.cursor).s and
                        b.getCell(first-1).c != '\L':
      dec first
    while last < b.len and b.getCell(last+1).s == b.getCell(b.cursor).s:
      inc last
  b.cursor = first
  b.selected = Marker(a: first, b: last, s: mcSelected)

proc mouseAfterNewLine(b: Buffer; i: int; dim: Rect; maxh: byte) =
  # requested cursor update?
  if b.clicks > 0:
    if b.mouseX > dim.x and dim.y+maxh.cint > b.mouseY:
      b.cursor = i
      b.currentLine = max(b.firstLine + b.span, 0)
      if b.clicks > 1: mouseSelectWholeLine(b)
      b.clicks = 0

proc blit(r: RendererPtr; b: Buffer; i: int; tex: TexturePtr; dim: Rect;
          font: FontPtr; msg: cstring) =
  var d = dim
  queryTexture(tex, nil, nil, addr(d.w), addr(d.h))

  # requested cursor update?
  if b.clicks > 0:
    let p = point(b.mouseX, b.mouseY)
    if d.contains(p):
      b.cursor = i - len(msg) + whichColumn(b, i-len(msg), d, font, msg)
      b.currentLine = max(b.firstLine + b.span, 0)
      mouseSelectCurrentToken(b)
      b.clicks = 0

  r.copy(tex, nil, addr d)

proc drawText(r: RendererPtr; b: Buffer; i: int; dim: var Rect; oldX: cint;
              font: FontPtr; msg: cstring; fg, bg: Color) =
  assert font != nil
  #echo "drawText ", msg
  let text = r.drawTexture(font, msg, fg, bg)
  var w, h: cint
  queryTexture(text, nil, nil, addr(w), addr(h))

  if dim.x + w > dim.w+oldX:
    # draw line continuation and contine in the next line:
    let cont = r.drawTexture(font, Ellipsis, fg, bg)
    r.blit(b, i, cont, dim, font, msg)
    destroy cont
    dim.x = oldX
    dim.y += h+2
    let dots = r.drawTexture(font, Ellipsis, fg, bg)
    var dotsW: cint
    queryTexture(dots, nil, nil, addr(dotsW), nil)
    r.blit(b, i, dots, dim, font, msg)
    destroy dots
    dim.x += dotsW

  r.blit(b, i, text, dim, font, msg)
  dim.x += w
  destroy text

proc drawCursor(r: RendererPtr; dim: Rect; bg, color: Color; h: cint) =
  r.setDrawColor(color)
  var d = rect(dim.x, dim.y, 2, h)
  r.fillRect(d)
  r.setDrawColor(bg)

proc tabFill(b: Buffer; buffer: var array[CharBufSize, char]; bufres: var int;
             j: int) {.noinline.} =
  var i = j
  while i > 0 and b[i-1] != '\L':
    dec i
  var col = 0
  while i < j:
    i += graphemeLen(b, i)
    inc col
  buffer[bufres] = ' '
  inc bufres
  inc col
  while (col mod b.tabSize) != 0 and bufres < high(buffer):
    buffer[bufres] = ' '
    inc bufres
    inc col
  buffer[bufres] = '\0'

proc getBg(b: Buffer; i: int; bg: Color): Color =
  if i <= b.selected.b and b.selected.a <= i: return b.mgr.b[mcSelected]
  for m in items(b.markers):
    if m.a <= i and i <= m.b:
      return b.mgr.b[m.s]
  return bg

proc drawLine(r: RendererPtr; b: Buffer; i: int;
              dim: var Rect; bg, cursor: Color;
              blink: bool): int =
  var j = i
  var style = b.mgr[].getStyle(getCell(b, j).s)
  var styleBg = getBg(b, j, bg)
  var maxh = style.attr.size
  let oldX = dim.x

  var cursorDim: Rect

  var buffer: array[CharBufSize, char]
  var cb = true
  template cursorCheck(): expr = cb and j == b.cursor
  block outerLoop:
    while true:
      var bufres = 0
      while true:
        let cell = getCell(b, j)

        if cell.c == '\L':
          buffer[bufres] = '\0'
          if bufres >= 1:
            r.drawText(b, j, dim, oldX, style.font, buffer, style.attr.color,
                       styleBg)
          mouseAfterNewLine(b, j, dim, maxh)
          if cursorCheck(): cursorDim = dim
          break outerLoop

        if cursorCheck(): cursorDim = dim
        if b.mgr[].getStyle(cell.s) != style or getBg(b, j, bg) != styleBg:
          break
        elif bufres == high(buffer) or cursorCheck():
          break

        if cell.c == '\t':
          tabFill(b, buffer, bufres, j)
        else:
          buffer[bufres] = cell.c
          inc bufres
        inc j

      buffer[bufres] = '\0'
      if bufres >= 1:
        r.drawText(b, j, dim, oldX, style.font, buffer, style.attr.color,
                   styleBg)
        style = b.mgr[].getStyle(getCell(b, j).s)
        styleBg = getBg(b, j, bg)
        maxh = max(maxh, style.attr.size)

      if j == b.cursor:
        cursorDim = dim
        cb = false
  dim.y += maxh.cint+2
  dim.x = oldX
  if cursorDim.h > 0 and blink:
    r.drawCursor(cursorDim, bg, cursor, maxh.cint)
  result = j+1

proc getLineOffset(b: Buffer; lines: Natural): int =
  var lines = lines
  if lines == 0: return 0
  while true:
    var cell = getCell(b, result)
    if cell.c == '\L':
      dec lines
      if lines == 0:
        inc result
        break
    inc result

proc setCursorFromMouse*(b: Buffer; dim: Rect; mouse: Point; clicks: int) =
  b.mouseX = mouse.x
  b.mouseY = mouse.y
  b.clicks = clicks
  # unselect on single mouse click:
  if clicks < 2:
    b.selected.b = -1
  when false:
    var i = 0
    while i < b.markers.len:
      if b.markers[i].s == mcSelected:
        b.markers.del i
      else:
        inc i

proc draw*(r: RendererPtr; b: Buffer; dim: Rect; bg, cursor: Color;
           blink: bool) =
  let realOffset = getLineOffset(b, b.firstLine)
  if b.firstLineOffset != realOffset:
    # XXX make this a real assertion when tested well
    echo "real offset ", realOffset, " wrong ", b.firstLineOffset
    assert false
  var i = b.firstLineOffset
  var dim = dim
  b.span = 0
  i = r.drawLine(b, i, dim, bg, cursor, blink)
  inc b.span
  while dim.y < dim.h and i <= len(b):
    i = r.drawLine(b, i, dim, bg, cursor, blink)
    inc b.span
  # we need to tell the buffer how many lines *can* be shown to prevent
  # that scrolling is triggered way too early:
  while dim.y < dim.h:
    inc dim.y, FontSize+2
    inc b.span
  # if not found, ignore mouse request anyway:
  b.clicks = 0
