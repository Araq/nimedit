
const
  ContinueLineMarker = "\xE2\xA4\xB8\x00"
  Ellipsis = "\xE2\x80\xA6\x00"

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

proc blit(r: RendererPtr; tex: TexturePtr; dim: Rect) =
  var d = dim
  queryTexture(tex, nil, nil, addr(d.w), addr(d.h))
  r.copy(tex, nil, addr d)

proc drawText(r: RendererPtr; dim: var Rect; oldX: cint;
              font: FontPtr; msg: cstring; fg, bg: Color) =
  assert font != nil
  #echo "drawText ", msg
  let text = r.drawTexture(font, msg, fg, bg)
  var w, h: cint
  queryTexture(text, nil, nil, addr(w), addr(h))

  if dim.x + w > dim.w:
    # draw line continuation and contine in the next line:
    let cont = r.drawTexture(font, Ellipsis, fg, bg)
    r.blit(cont, dim)
    destroy cont
    dim.x = oldX
    dim.y += h+2
    let dots = r.drawTexture(font, Ellipsis, fg, bg)
    var dotsW: cint
    queryTexture(dots, nil, nil, addr(dotsW), nil)
    r.blit(dots, dim)
    destroy dots
    dim.x += dotsW

  r.blit(text, dim)
  dim.x += w
  destroy text

proc drawCursor(r: RendererPtr; dim: Rect; bg, color: Color; h: cint) =
  r.setDrawColor(color)
  var d = rect(dim.x, dim.y, 2, h)
  r.fillRect(d)
  r.setDrawColor(bg)

proc drawLine(r: RendererPtr; b: Buffer; i: int;
              dim: var Rect; bg, cursor: Color;
              blink: bool): int =
  var j = i
  var style = b.mgr[].getStyle(getCell(b, j).s)
  var maxh = style.attr.size
  let oldX = dim.x

  var cursorDim: Rect

  var buffer: array[80, char]
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
            r.drawText(dim, oldX, style.font, buffer, style.attr.color, bg)
          if cursorCheck(): cursorDim = dim
          break outerLoop

        if cursorCheck(): cursorDim = dim
        if b.mgr[].getStyle(cell.s) != style:
          break
        elif bufres == high(buffer) or cursorCheck():
          break

        buffer[bufres] = cell.c
        inc bufres
        inc j

      buffer[bufres] = '\0'
      if bufres >= 1:
        r.drawText(dim, oldX, style.font, buffer, style.attr.color, bg)
        style = b.mgr[].getStyle(getCell(b, j).s)
        maxh = max(maxh, style.attr.size)

      if j == b.cursor:
        cursorDim = dim
        cb = false
  dim.y += maxh.cint+2
  dim.x = oldX
  #echo dim
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
  while dim.y < dim.h and i <= len(b):
    i = r.drawLine(b, i, dim, bg, cursor, blink)
    inc b.span
