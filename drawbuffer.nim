
proc drawText(r: RendererPtr; dim: Rect; font: FontPtr; msg: cstring;
              fg, bg: Color): cint =
  assert font != nil
  var surf: SurfacePtr = renderUtf8Shaded(font, msg, fg, bg)
  if surf == nil:
    echo("TTF_RenderText")
    return
  var texture: TexturePtr = createTextureFromSurface(r, surf)
  if texture == nil:
    echo("CreateTexture")
  freeSurface(surf)

  var d = dim
  queryTexture(texture, nil, nil, addr(d.w), addr(d.h))

  r.copy(texture, nil, addr d)
  destroy texture
  result = d.w


proc drawCursor(r: RendererPtr; dim: Rect; bg, color: Color; h: cint) =
  r.setDrawColor(color)
  var d = rect(dim.x, dim.y, 2, h)
  r.fillRect(d)
  r.setDrawColor(bg)

proc drawLine(r: RendererPtr; b: Buffer; i: int;
              dim: var Rect; bg, cursor: Color;
              blink: bool): int =
  var i = i
  var j = i+1

  var cell = getCell(b, i)
  var style = b.mgr[].getStyle(cell.s)
  var maxh = style.attr.size
  let oldX = dim.x

  var cursorDim: Rect
  if i == b.cursor: cursorDim = dim

  var buffer: array[120, char]
  block outerLoop:
    while true:
      var bufres = 0
      while true:

        if cell.c == '\L':
          buffer[bufres] = '\0'
          if bufres >= 1:
            dim.x += r.drawText(dim, style.font, buffer, style.attr.color, bg)
          if j == b.cursor: cursorDim = dim
          break outerLoop

        buffer[bufres] = cell.c
        inc bufres
        inc j

        cell = getCell(b, j)
        if b.mgr[].getStyle(cell.s) != style:
          style = b.mgr[].getStyle(cell.s)
          maxh = max(maxh, style.attr.size)
          break
        elif bufres == high(buffer) or j == b.cursor:
          break

      buffer[bufres] = '\0'
      if bufres >= 1:
        dim.x += r.drawText(dim, style.font, buffer, style.attr.color, bg)
      if j == b.cursor: cursorDim = dim
  dim.y += maxh.cint+2
  dim.x = oldX
  #echo dim
  if cursorDim.h > 0 and blink:
    r.drawCursor(cursorDim, bg, cursor, maxh.cint)
  result = j

proc getLineOffset(b: Buffer; lines: int): int =
  var lines = lines
  if lines == 0: return 0
  while true:
    var cell = getCell(b, result)
    if cell.c == '\L':
      dec lines
      if lines == 0: break
    inc result

proc draw*(r: RendererPtr; b: Buffer; dim: Rect; bg, cursor: Color;
           blink: bool) =
  # correct scrolling commands:
  b.firstLine = clamp(b.firstLine, 0, b.lines.len)
  # XXX cache line information
  var i = getLineOffset(b, b.firstLine) # b.lines[b.firstLine].offset
  var dim = dim
  i = r.drawLine(b, i, dim, bg, cursor, blink)
  while dim.y < dim.h and not atEnd(b, i):
    i = r.drawLine(b, i, dim, bg, cursor, blink)
