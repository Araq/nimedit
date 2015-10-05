
const
  #ContinueLineMarker = "\xE2\xA4\xB8\x00"
  Ellipsis = "\xE2\x80\xA6\x00"
  CharBufSize = 80
  RoomForMargin = 8

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

proc drawNumber*(t: InternalTheme; number, current: int; w, y: cint) =
  let w = w - RoomForMargin
  proc sprintf(buf, frmt: cstring) {.header: "<stdio.h>",
    importc: "sprintf", varargs, noSideEffect.}
  var buf {.noinit.}: array[25, char]
  sprintf(buf, "%ld", number)

  let tex = drawTexture(t.renderer, t.editorFontPtr, buf,
                        if number == current: t.fg else: t.lines, t.bg)
  var d: Rect
  d.x = 1
  d.y = y
  queryTexture(tex, nil, nil, addr(d.w), addr(d.h))
  t.renderer.copy(tex, nil, addr d)
  destroy tex
  if number == current or number == current+1:
    t.renderer.setDrawColor(t.fg)
    t.renderer.drawLine(1, y-1, 1+w, y-1)

proc textSize*(font: FontPtr; buffer: cstring): cint =
  discard sizeUtf8(font, buffer, addr result, nil)

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
    let w = textSize(font, buffer)
    if dim.x+w >= b.mouseX-1:
      return r
    inc j, L

proc mouseSelectWholeLine(b: Buffer) =
  var first = b.cursor
  while first > 0 and b[first-1] != '\L': dec first
  b.selected = (first, b.cursor)

proc mouseSelectCurrentToken(b: Buffer) =
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
  b.selected = (first, last)
  cursorMoved(b)

proc mouseAfterNewLine(b: Buffer; i: int; dim: Rect; maxh: byte) =
  # requested cursor update?
  if b.clicks > 0:
    if b.mouseX > dim.x and dim.y+maxh.cint > b.mouseY:
      b.cursor = i
      b.currentLine = max(b.firstLine + b.span, 0)
      if b.clicks > 1: mouseSelectWholeLine(b)
      b.clicks = 0
      cursorMoved(b)

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
      cursorMoved(b)

  r.copy(tex, nil, addr d)

proc drawText(t: InternalTheme; b: Buffer; i: int; dim: var Rect; oldX: cint;
              font: FontPtr; msg: cstring; fg, bg: Color) =
  assert font != nil
  let r = t.renderer
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

proc drawCursor(t: InternalTheme; dim: Rect; h: cint) =
  t.renderer.setDrawColor(t.cursor)
  var d = rect(dim.x, dim.y, 2, h)
  t.renderer.fillRect(d)
  t.renderer.setDrawColor(t.bg)

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

proc getBg(b: Buffer; i: int; t: InternalTheme): Color =
  if i <= b.selected.b and b.selected.a <= i: return b.mgr.b[mcSelected]
  for m in items(b.markers):
    if m.a <= i and i <= m.b:
      return b.mgr.b[mcHighlighted]
  if t.showBracket and i == b.bracketToHighlight: return t.bracket
  return t.bg

proc drawLine(t: InternalTheme; b: Buffer; i: int; dim: var Rect;
              blink: bool): int =
  var j = i
  var style = b.mgr[].getStyle(getCell(b, j).s)
  var styleBg = getBg(b, j, t)
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
            t.drawText(b, j, dim, oldX, style.font, buffer, style.attr.color,
                       styleBg)
          mouseAfterNewLine(b, j, dim, maxh)
          if cursorCheck(): cursorDim = dim
          break outerLoop

        if cursorCheck():
          cursorDim = dim
          buffer[bufres] = '\0'
          let size = textSize(style.font, buffer)
          # overflow:
          if cursorDim.x + size > dim.w+oldX: break
          cursorDim.x += size

        if b.mgr[].getStyle(cell.s) != style or getBg(b, j, t) != styleBg:
          break
        elif bufres == high(buffer): #or cursorCheck():
          break

        if cell.c == '\t':
          tabFill(b, buffer, bufres, j)
        else:
          buffer[bufres] = cell.c
          inc bufres
        inc j

      buffer[bufres] = '\0'
      if bufres >= 1:
        t.drawText(b, j, dim, oldX, style.font, buffer, style.attr.color,
                   styleBg)
        style = b.mgr[].getStyle(getCell(b, j).s)
        styleBg = getBg(b, j, t)
        maxh = max(maxh, style.attr.size)

      if j == b.cursor:
        cursorDim = dim
        cb = false
  dim.y += maxh.cint+2
  dim.x = oldX
  if cursorDim.h > 0 and blink:
    t.drawCursor(cursorDim, maxh.cint)
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

proc log10(x: int): int =
  var x = x
  while true:
    x = x div 10
    inc result
    if x == 0: break

proc spaceForLines*(b: Buffer; t: InternalTheme): Natural =
  if t.showLines:
    result = b.numberOfLines.log10 * textSize(t.editorFontPtr, " ")

proc draw*(t: InternalTheme; b: Buffer; dim: Rect; blink: bool;
           showLines=false) =
  let realOffset = getLineOffset(b, b.firstLine)
  if b.firstLineOffset != realOffset:
    # XXX make this a real assertion when tested well
    echo "real offset ", realOffset, " wrong ", b.firstLineOffset
    assert false
  var i = b.firstLineOffset
  var dim = dim
  let spl = cint(spaceForLines(b, t) + RoomForMargin)
  if showLines:
    t.drawNumber(b.firstLine+1, b.currentLine+1, spl, dim.y)
    dim.x = spl
  b.span = 0
  i = t.drawLine(b, i, dim, blink)
  inc b.span
  while dim.y < dim.h and i <= len(b):
    if showLines:
      t.drawNumber(b.firstLine+b.span+1, b.currentLine+1, spl, dim.y)
    i = t.drawLine(b, i, dim, blink)
    inc b.span
  # we need to tell the buffer how many lines *can* be shown to prevent
  # that scrolling is triggered way too early:
  let fontSize = t.editorFontSize.int
  while dim.y < dim.h:
    inc dim.y, fontSize+2
    inc b.span
  # if not found, ignore mouse request anyway:
  b.clicks = 0
