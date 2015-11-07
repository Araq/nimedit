
const
  #ContinueLineMarker = "\xE2\xA4\xB8\x00"
  Ellipsis = "\xE2\x80\xA6\x00"
  CharBufSize = 80
  RoomForMargin = 8'i32

proc getLineFromOffset(b: Buffer; pos: int): Natural =
  # example:
  #   0: offset:  45   line 3
  #   1: offset:  66   line 4
  #   2: offset:  99   line 8
  # question: which line at offset 77?
  # The best entry is 1 because 66 is the *biggest* offset that is still < pos!
  result = 0
  var p = pos
  var e = 0

  # check cache:
  for ce in mitems(b.offsetToLineCache):
    if ce.version == b.version:
      if ce.offset == pos:
        return ce.line
      if ce.offset < pos and ce.offset > e:
        e = ce.offset
        result = ce.line

  # do not count the newline at the very end at b[pos]:
  if p >= 0 and b[p] == '\L': dec p
  while p >= e:
    if b[p] == '\L': inc result
    dec p

  # we need to store the start of the line:
  p = pos
  while p > 0 and b[p-1] != '\L': dec p

  # find best cache entry to replace:
  var idx = 0
  for ce in mitems(b.offsetToLineCache):
    if ce.version != b.version or idx == high(b.offsetToLineCache) or
       ce.offset >= pos:
      ce = (version: b.version, offset: p, line: result)
      break
    inc idx

proc getLineOffset(b: Buffer; lines: Natural): int =
  var y = lines
  if y == 0: return 0

  # check cache:
  for ce in mitems(b.offsetToLineCache):
    if ce.version == b.version:
      if ce.line == lines:
        return ce.offset

  while true:
    if b[result] == '\L':
      dec y
      if y == 0:
        inc result
        break
    inc result

  # find best cache entry to replace:
  var idx = 0
  for ce in mitems(b.offsetToLineCache):
    if ce.version != b.version or idx == high(b.offsetToLineCache) or
       ce.offset >= result:
      ce = (version: b.version, offset: result, line: lines)
      break
    inc idx


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

proc drawNumberBegin*(t: InternalTheme; number, current: int; w, y: cint) =
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
  if number == current:
    t.renderer.setDrawColor(t.fg)
    t.renderer.drawLine(1, y-1, 1+w, y-1)

proc drawNumberEnd*(t: InternalTheme; number, current: int; w, y: cint) =
  if number == current:
    t.renderer.setDrawColor(t.fg)
    t.renderer.drawLine(1, y-1, 1+w, y-1)

proc textSize*(font: FontPtr; buffer: cstring): cint =
  discard sizeUtf8(font, buffer, addr result, nil)

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

proc setCurrentLine(b: Buffer) =
  if b.filterLines:
    b.currentLine = getLineFromOffset(b, b.cursor)
  else:
    b.currentLine = max(b.firstLine + b.span, 0)
  b.currentLine = clamp(b.currentLine, 0, b.numberOfLines)

proc mouseAfterNewLine(b: Buffer; i: int; dim: Rect; maxh: cint) =
  # requested cursor update?
  if b.clicks > 0:
    if b.mouseX > dim.x and dim.y+maxh > b.mouseY:
      b.cursor = i
      setCurrentLine(b)
      if b.clicks > 1: mouseSelectWholeLine(b)
      b.clicks = 0
      cursorMoved(b)

type
  DrawBuffer = object
    b: Buffer
    dim, cursorDim: Rect
    i, charsLen: int
    font: FontPtr
    oldX, maxY, lineH, spaceWidth: cint
    ra, rb, startedWith: int
    chars: array[CharBufSize, char]
    toCursor: array[CharBufSize, int]

proc minimapCandidate(r: RendererPtr; db: DrawBuffer; minimapDim: var Rect) =
  # we like a strike of 4 lines where a third of the allowed width
  # was not used. This rect is then later used to draw a minimap.
  let w = db.dim.w - db.oldX
  #r.pixel(db.dim.x, db.dim.y, color(0x00, 0xff, 0xff, 0xff))
  #r.pixel(db.oldX + w - (w div 3), db.dim.y, color(0xff, 0x00, 0x00, 0xff))
  if db.dim.x <= db.oldX + w - (w div 3):
    if minimapDim.w == 0:
      minimapDim.w = w div 3
      minimapDim.x = db.oldX + w - (w div 3)
      minimapDim.y = db.dim.y
      minimapDim.h = fontLineSkip(db.font)
    elif minimapDim.y > 0:
      minimapDim.h += fontLineSkip(db.font)
  elif minimapDim.h < fontLineSkip(db.font)*4:
    # latest candidate was not long enough :-(, reset:
    minimapDim.w = 0
  else:
    # mark as finished:
    minimapDim.y = -abs(minimapDim.y)

proc blit(r: RendererPtr; tex: TexturePtr; dim: Rect) =
  var d = dim
  queryTexture(tex, nil, nil, addr(d.w), addr(d.h))
  r.copy(tex, nil, addr d)

proc whichColumn(db: var DrawBuffer; ra, rb: int): int =
  var buffer: array[CharBufSize, char]
  var j = db.toCursor[ra] # db.i - db.charsLen + ra
  var r = 0
  let ending = db.toCursor[rb] # j+(rb-ra+1)
  while j < ending:
    var L = graphemeLen(db.b, j)
    for k in 0..<L:
      buffer[r] = db.b[k+j]
      inc r
    buffer[r] = '\0'
    let w = textSize(db.font, buffer)
    if db.dim.x+w >= db.b.mouseX-1:
      return r
    inc j, L

proc drawSubtoken(r: RendererPtr; db: var DrawBuffer; tex: TexturePtr;
                  ra, rb: int) =
  # Draws the part of the token that actually still fits in the line. Also
  # does the click checking and the cursor tracking.
  var d = db.dim
  queryTexture(tex, nil, nil, addr(d.w), addr(d.h))

  # requested cursor update?
  let i = db.toCursor[ra] # db.i - db.charsLen
  if db.b.clicks > 0:
    let p = point(db.b.mouseX, db.b.mouseY)
    if d.contains(p):
      db.b.cursor = i + whichColumn(db, ra, rb)
      setCurrentLine(db.b)
      if db.b.clicks > 1: mouseSelectCurrentToken(db.b)
      db.b.clicks = 0
      cursorMoved(db.b)
  # track where to draw the cursor:
  if db.cursorDim.h == 0 and
      db.toCursor[ra] <= db.b.cursor and db.b.cursor <= db.toCursor[rb+1]:
    #  ra+i <= db.b.cursor and db.b.cursor <= rb+i+1:
    var i = ra
    if db.toCursor[i] == db.b.cursor:
      db.cursorDim = d
    else:
      while db.toCursor[i] != db.b.cursor: inc i
      #while i <= rb and db.toCursor[i+1] == db.b.cursor: inc i
      let j = i
      let ch = db.chars[j]
      db.chars[j] = '\0'
      db.cursorDim = d
      db.cursorDim.x += textSize(db.font, addr db.chars[ra])
      db.chars[j] = ch
  r.copy(tex, nil, addr d)

proc indWidth(db: DrawBuffer): cint =
  var
    i = db.startedWith
    r = 0.cint
    b = db.b
  while b[i] in {'\t', ' '}:
    if b[i] == '\t': inc r, b.tabsize
    else: inc r
    inc i
  if r > 0 or db.b.isSmall:
    inc r, b.tabSize
  elif db.b.lang notin {langNone, langConsole}:
    while true:
      case b[i]
      of '(', '{', '[', ',', ';':
        r = cint(i - db.startedWith)
        break
      of '\L': break
      else: inc i
  result = textSize(db.font, " ").cint * r

proc smartWrap(db: DrawBuffer; origP: int; critical: bool): int =
  # search for a nice split position, but don't go back too much:
  var p = origP
  var broke = false
  while p > db.ra+1:
    if (db.chars[p] in Letters) != (db.chars[p-1] in Letters):
      return p
    dec p
  # cannot find a good positions, give up: We could also return -1 but this
  # risks endless loops for pathological cases (full buffer consists of Letters)
  return if critical: origP else: -1

proc translateToken(db: var DrawBuffer) =
  if db.chars[0] == '{' and db.chars[1] == '.' and db.chars[2] == '\0':
    # left curly bracket middle piece
    db.chars[0] = '\xE2'
    db.chars[1] = '\x8E'
    db.chars[2] = '\xA8'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3
  elif db.chars[0] == '.' and db.chars[1] == '}' and db.chars[2] == '\0':
    # right curly bracket middle piece
    db.chars[0] = '\xE2'
    db.chars[1] = '\x8E'
    db.chars[2] = '\xAC'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3
  elif db.chars[0] == '[' and db.chars[1] == '.' and db.chars[2] == '\0':
    # LEFT WHITE SQUARE BRACKET
    # left square bracket with quill
    db.chars[0] = '\xE2'  #'\xE3'
    db.chars[1] = '\x81' #'\x80'
    db.chars[2] = '\x85' #'\x9A'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3
  elif db.chars[0] == '.' and db.chars[1] == ']' and db.chars[2] == '\0':
    # MATHEMATICAL RIGHT WHITE SQUARE BRACKET
    # right square bracket with quill
    db.chars[0] = '\xE2'
    db.chars[1] = '\x81' #'\x9F'
    db.chars[2] = '\x86' #'\xA7'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3

proc drawToken(t: InternalTheme; db: var DrawBuffer; fg, bg: Color) =
  # Draws a single token, potentially splitting it up over multiple lines.
  if t.showLigatures:
    translateToken(db)
  assert db.font != nil
  if db.dim.y+db.lineH > db.maxY: return
  let r = t.renderer
  let text = r.drawTexture(db.font, db.chars, fg, bg)
  var w, h: cint
  queryTexture(text, nil, nil, addr(w), addr(h))

  #r.pixel(db.dim.w, db.dim.y, color(0x00, 0xff, 0xff, 0xff))
  if db.dim.x + w + db.spaceWidth <= db.dim.w:
    # fast common case: the token still fits:
    r.drawSubtoken(db, text, 0, db.charsLen-1)
    db.dim.x += w
  else:
    # slow uncommon case: we have to wrap the line.
    # * split the buffer and see how many still fit into the current line.
    # * don't draw over the valid rectangle
    # * consider the current cursor just like in the main loop
    # * XXX Unicode support!
    db.ra = 0
    db.rb = 0
    var iters = 0
    while db.ra < db.charsLen:
      inc iters
      var start = cstring(addr db.chars[db.ra])
      assert start[0] != '\0'

      var probe = db.ra
      var dotsrequired = false
      while probe < db.charsLen:
        let ch = db.chars[probe]
        db.chars[probe] = '\0'
        let w2 = db.font.textSize(start)
        db.chars[probe] = ch
        if db.dim.x + db.spaceWidth + w2 > db.dim.w:
          dec probe
          probe = smartWrap(db, probe, iters > db.b.span)
          dotsrequired = true
          break
        inc probe
      if probe <= 0:
        # not successful, try the next line:
        discard
      else:
        # draw until we still have room:
        let ch = db.chars[probe]
        db.chars[probe] = '\0'
        assert start[0] != '\0'
        let text = r.drawTexture(db.font, start, fg, bg)
        db.rb = probe-1
        db.chars[probe] = ch
        var w, h: cint
        queryTexture(text, nil, nil, addr(w), addr(h))
        r.drawSubtoken(db, text, db.ra, db.rb)
        db.ra = probe
        db.dim.x += w
        destroy text
      if not dotsRequired: break
      # draw line continuation and continue in the next line:
      let cont = r.drawTexture(db.font, Ellipsis, fg, bg)
      r.blit(cont, db.dim)
      destroy cont
      db.dim.x = db.oldX
      db.dim.y += db.lineH
      if db.dim.y+db.lineH > db.maxY: break
      # indent the wrapped line properly, but don't overdo it:
      db.dim.x += min(indWidth(db), (db.dim.w - db.oldX) div 2)
      let dots = r.drawTexture(db.font, Ellipsis, fg, bg)
      var dotsW: cint
      queryTexture(dots, nil, nil, addr(dotsW), nil)
      r.blit(dots, db.dim)
      destroy dots
      db.dim.x += dotsW
  destroy text

proc drawCursor(t: InternalTheme; dim: Rect; h: cint) =
  t.renderer.setDrawColor(t.cursor)
  var d = rect(dim.x, dim.y, t.cursorWidth, h)
  t.renderer.fillRect(d)
  t.renderer.setDrawColor(t.bg)

proc tabFill(db: var DrawBuffer; j: int) {.noinline.} =
  var i = j
  while i > 0 and db.b[i-1] != '\L':
    dec i
  var col = 0
  while i < j:
    if db.b[i] == '\t' or col == db.b.tabSize: col = 0
    else: inc col
    i += graphemeLen(db.b, i)
  db.chars[db.charsLen] = ' '
  db.toCursor[db.charsLen] = j
  inc db.charsLen
  inc col
  while col < db.b.tabSize and db.charsLen < high(db.chars):
    db.chars[db.charsLen] = ' '
    db.toCursor[db.charsLen] = j
    inc db.charsLen
    inc col
  db.chars[db.charsLen] = '\0'

proc getBg(b: Buffer; i: int; t: InternalTheme): Color =
  if i <= b.selected.b and b.selected.a <= i: return b.mgr.b[mcSelected]
  for m in items(b.markers):
    if m.a <= i and i <= m.b:
      return b.mgr.b[mcHighlighted]
  if t.showBracket and i <= b.bracketToHighlightB and b.bracketToHighlightA <= i:
    return t.bracket
  return t.bg

proc drawTextLine(t: InternalTheme; b: Buffer; i: int; dim: var Rect;
                  blink: bool): int =
  var tokenClass = getCell(b, i).s
  var style = b.mgr[].getStyle(tokenClass)
  var styleBg = getBg(b, i, t)

  var db: DrawBuffer
  db.oldX = dim.x
  db.maxY = dim.h
  db.dim = dim
  db.font = style.font
  db.b = b
  db.i = i
  db.startedWith = i
  db.lineH = fontLineSkip(db.font)
  db.spaceWidth = textSize(db.font, " ")

  block outerLoop:
    while db.dim.y+db.lineH <= db.maxY:
      db.charsLen = 0
      while true:
        let cell = getCell(b, db.i)

        if cell.c == '\L':
          db.chars[db.charsLen] = '\0'
          db.toCursor[db.charsLen] = db.i
          if db.charsLen >= 1:
            t.drawToken(db, style.attr.color, styleBg)
          elif db.i == b.cursor:
            db.cursorDim = db.dim
          mouseAfterNewLine(b, db.i, dim, db.lineH)
          minimapCandidate(t.renderer, db, b.posHint)
          break outerLoop

        if cell.s != tokenClass or getBg(b, db.i, t) != styleBg:
          break
        elif db.charsLen == high(db.chars):
          break

        if cell.c == '\t':
          tabFill(db, db.i)
        else:
          db.chars[db.charsLen] = cell.c
          db.toCursor[db.charsLen] = db.i
          inc db.charsLen
        inc db.i

      db.chars[db.charsLen] = '\0'
      db.toCursor[db.charsLen] = db.i
      if db.charsLen >= 1:
        t.drawToken(db, style.attr.color, styleBg)
        tokenClass = getCell(b, db.i).s
        style = b.mgr[].getStyle(tokenClass)
        styleBg = getBg(b, db.i, t)
        db.font = style.font

  if t.showIndentation and b.lang notin {langNone, langConsole}:
    var
      i = i
      w = db.spaceWidth
      r = 0
    while b[i] in {'\t', ' '}:
      if r mod b.tabSize == 0 and r > 1:
        vlineDotted(t.renderer, w*r+db.oldX, dim.y, dim.y+db.lineH,
                    t.indentation)
      if b[i] == '\t': inc r, b.tabsize
      else: inc r
      inc i

  dim = db.dim
  dim.y += fontLineSkip(t.editorFontPtr)
  dim.x = db.oldX
  if db.cursorDim.h > 0:
    if blink: t.drawCursor(db.cursorDim, db.lineH)
    b.cursorDim = (db.cursorDim.x.int, db.cursorDim.y.int, db.lineH.int)
  result = db.i+1

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
    result = (b.numberOfLines+1).log10 * textSize(t.editorFontPtr, " ")

proc nextLineOffset(b: Buffer; line: var int; start: int): int =
  result = start
  if b.filterLines:
    while line < b.numberOfLines and line notin b.activeLines:
      while b[result] != '\L': inc result
      inc result
      inc line

type
  DrawOption* = enum
    showLines,
    showGaps

proc draw*(t: InternalTheme; b: Buffer; dim: Rect; blink: bool;
           options: set[DrawOption] = {}): cint {.discardable.} =
  b.posHint.w = 0
  b.posHint.h = 0
  b.cursorDim.h = 0
  let realOffset = getLineOffset(b, b.firstLine)
  if b.firstLineOffset != realOffset:
    # XXX make this a real assertion when tested well
    echo "real offset ", realOffset, " wrong ", b.firstLineOffset
    assert false
  var renderLine = b.firstLine
  var i = nextLineOffset(b, renderLine, b.firstLineOffset)
  let endY = dim.y + dim.h - 1
  let endX = dim.x + dim.w - 1
  var dim = dim
  dim.w = endX
  dim.h = endY
  let spl = cint(spaceForLines(b, t))

  template drawCurrent() =
    if showLines in options:
      t.drawNumberBegin(renderLine+1, b.currentLine+1, spl, dim.y)
    i = t.drawTextLine(b, i, dim, blink)
    if showLines in options:
      t.drawNumberEnd(renderLine+1, b.currentLine+1, spl, dim.y)

  if showLines in options: dim.x = spl + RoomForMargin
  b.span = 0
  drawCurrent()
  inc b.span
  let fontSize = t.editorFontSize.cint
  let lineH = fontLineSkip(t.editorFontPtr)
  while dim.y+fontSize < endY and i <= len(b):
    inc renderLine
    let expectedLine = renderLine
    i = nextLineOffset(b, renderLine, i)
    if expectedLine != renderLine or showGaps in options:
      # show the gap:
      hlineDotted(t.renderer, dim.x, endX, dim.y+lineH div 4, t.indentation)
      dim.y += lineH div 2

    drawCurrent()
    inc b.span
  result = dim.y
  # we need to tell the buffer how many lines *can* be shown to prevent
  # that scrolling is triggered way too early:
  while dim.y+fontSize < endY:
    inc dim.y, lineH
    inc b.span
  # if not found, set the cursor to the last possible position (this is
  # required when the screen is not completely filled with text lines):
  mouseAfterNewLine(b, min(i, b.len),
    (x: cint(b.mouseX-1), y: 100_000i32, w: 0'i32, h: 0'i32), lineH)
  if b.posHint.h < lineH*4:
    b.posHint.w = 0
    b.posHint.h = 0
  else:
    b.posHint.y = abs(b.posHint.y)

proc drawAutoComplete*(t: InternalTheme; b: Buffer; dim: Rect) =
  let realOffset = getLineOffset(b, b.firstLine)
  if b.firstLineOffset != realOffset:
    # XXX make this a real assertion when tested well
    echo "real offset ", realOffset, " wrong ", b.firstLineOffset
    assert false
  var i = b.firstLineOffset
  let originalX = dim.x
  let endX = dim.x + dim.w - 1
  let endY = dim.y + dim.h - 1
  var dim = dim
  b.span = 0
  dim.w = endX
  dim.h = endY

  template drawCurrent =
    let y = dim.y
    i = t.drawTextLine(b, i, dim, false)
    if  b.firstline+b.span == b.currentLine or
        b.firstline+b.span == b.currentLine+1:
      t.renderer.setDrawColor(t.fg)
      t.renderer.drawLine(originalX, y, endX, y)

  drawCurrent()
  inc b.span
  let fontSize = t.editorFontSize.cint
  while dim.y+fontSize < endY and i <= len(b):
    drawCurrent()
    inc b.span
  # we need to tell the buffer how many lines *can* be shown to prevent
  # that scrolling is triggered way too early:
  let lineH = fontLineSkip(t.editorFontPtr)
  while dim.y+fontSize < endY:
    inc dim.y, lineH
    inc b.span
  # if not found, ignore mouse request anyway:
  b.clicks = 0
