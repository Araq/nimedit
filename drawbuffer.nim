
const
  #ContinueLineMarker = "\xE2\xA4\xB8\x00"
  Ellipsis = "\xE2\x80\xA6\x00"
  CharBufSize = 80

proc drawTexture(r: RendererPtr; font: FontPtr; msg: cstring;
                 fg, bg: Color): TexturePtr =
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

proc mouseAfterNewLine(b: Buffer; i: int; dim: Rect; maxh: byte) =
  # requested cursor update?
  if b.mouseX > 0:
    if b.mouseX > dim.x and dim.y+maxh.cint > b.mouseY:
      b.cursor = i
      b.currentLine = max(b.firstLine + b.span, 0)
      b.mouseX = 0

proc blit(r: RendererPtr; b: Buffer; i: int; tex: TexturePtr; dim: Rect;
          font: FontPtr; msg: cstring) =
  var d = dim
  queryTexture(tex, nil, nil, addr(d.w), addr(d.h))

  # requested cursor update?
  if b.mouseX > 0:
    let p = point(b.mouseX, b.mouseY)
    if d.contains(p):
      b.cursor = i - len(msg) + whichColumn(b, i-len(msg), d, font, msg)
      b.currentLine = max(b.firstLine + b.span, 0)
      b.mouseX = 0

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

proc drawLine(r: RendererPtr; b: Buffer; i: int;
              dim: var Rect; bg, cursor: Color;
              blink: bool): int =
  var j = i
  var style = b.mgr[].getStyle(getCell(b, j).s)
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
            r.drawText(b, j, dim, oldX, style.font, buffer, style.attr.color, bg)
          mouseAfterNewLine(b, j, dim, maxh)
          if cursorCheck(): cursorDim = dim
          break outerLoop

        if cursorCheck(): cursorDim = dim
        if b.mgr[].getStyle(cell.s) != style:
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
        r.drawText(b, j, dim, oldX, style.font, buffer, style.attr.color, bg)
        style = b.mgr[].getStyle(getCell(b, j).s)
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

proc setCursorFromMouse*(b: Buffer; dim: Rect; mouse: Point) =
  #let line =  FontSize+2
  b.mouseX = mouse.x
  b.mouseY = mouse.y

proc draw*(r: RendererPtr; b: Buffer; dim: Rect; bg, cursor: Color;
           blink: bool) =
  # correct scrolling commands. Because of line continuations the maximal
  # view is (dim.h div FontSize+2) div 2
  b.firstLine = clamp(b.firstLine, 0,
                      max(0, b.numberOfLines - (dim.h div (FontSize+2)) div 2))
  #echo "FIRSTLINE ", b.firstLine, " ", b.numberOfLines
  # XXX cache line information
  var i = getLineOffset(b, b.firstLine) # b.lines[b.firstLine].offset
  var dim = dim
  b.span = 0
  i = r.drawLine(b, i, dim, bg, cursor, blink)
  inc b.span
  while dim.y < dim.h and i <= len(b):
    i = r.drawLine(b, i, dim, bg, cursor, blink)
    inc b.span
  # if not found, ignore mouse request anyway:
  b.mouseX = 0
