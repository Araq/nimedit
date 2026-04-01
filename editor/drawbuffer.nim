
const
  #ContinueLineMarker = "\xE2\xA4\xB8\x00"
  Ellipsis = "\xE2\x80\xA6\x00"
  CharBufSize = 80
  RoomForMargin = 8'i32

proc textSize*(font: Font; buffer: cstring): int =
  measureText(font, buffer).w

proc drawNumberBegin*(t: InternalTheme; b: Buffer; number, current: int; w, y: int) =
  proc sprintf(buf, frmt: cstring) {.header: "<stdio.h>",
    importc: "sprintf", varargs, noSideEffect.}
  var buf {.noinit.}: array[25, char]
  sprintf(cast[cstring](addr buf), "%ld", number)

  let br = b.breakpoints.getOrDefault(number)
  let col = if number == b.runningLine: b.mgr[].getStyle(TokenClass.LineActive).attr.color
            elif br != TokenClass.None: b.mgr[].getStyle(br).attr.color
            elif number == current: t.fg
            else: t.lines
  let ext = drawTextShaded(t.editorFontHandle, 1, y, cast[cstring](addr buf), col, t.bg)

  # requested breakpoint update?
  if b.clicks > 0:
    let p = point(b.mouseX, b.mouseY)
    if Rect(x: 1, y: y, w: w, h: ext.h).contains(p):
      b.clicks = 0
      let nextState = case br
                      of TokenClass.None: TokenClass.Breakpoint1
                      of TokenClass.Breakpoint1: TokenClass.Breakpoint2
                      else: TokenClass.None
      b.breakpoints[number] = nextState
  if number == current or br != TokenClass.None or number == b.runningLine:
    screen.drawLine(1, y-1, 1+w, y-1, col)

proc drawNumberEnd*(t: InternalTheme; b: Buffer; number, current: int; w, y: int) =
  if number == b.runningLine:
    screen.drawLine(1, y-1, 1+w, y-1,
      b.mgr[].getStyle(TokenClass.LineActive).attr.color)
  else:
    let br = b.breakpoints.getOrDefault(number)
    if br != TokenClass.None:
      screen.drawLine(1, y-1, 1+w, y-1, b.mgr[].getStyle(br).attr.color)
    elif number == current:
      screen.drawLine(1, y-1, 1+w, y-1, t.fg)

proc mouseAfterNewLine(b: Buffer; i: int; dim: Rect; maxh: int) =
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
    font: Font
    oldX, maxY, lineH, spaceWidth: int
    ra, rb, startedWith: int
    chars: array[CharBufSize, char]
    toCursor: array[CharBufSize, int]

proc minimapCandidate(db: DrawBuffer; minimapDim: var Rect) =
  let w = db.dim.w - db.oldX
  if db.dim.x <= db.oldX + w - (w div 3):
    if minimapDim.w == 0:
      minimapDim.w = w div 3
      minimapDim.x = db.oldX + w - (w div 3)
      minimapDim.y = db.dim.y
      minimapDim.h = screen.fontLineSkip(db.font)
    elif minimapDim.y > 0:
      minimapDim.h += screen.fontLineSkip(db.font)
  elif minimapDim.h < screen.fontLineSkip(db.font)*4:
    minimapDim.w = 0
  else:
    minimapDim.y = -abs(minimapDim.y)

proc whichColumn(db: var DrawBuffer; ra, rb: int): int =
  var buffer: array[CharBufSize, char]
  var j = db.toCursor[ra]
  var r = 0
  let ending = db.toCursor[rb]
  while j < ending:
    var L = graphemeLen(db.b, j)
    for k in 0..<int(L):
      buffer[r] = db.b[k+j]
      inc r
    buffer[r] = '\0'
    let w = textSize(db.font, cast[cstring](addr buffer))
    if db.dim.x+w >= db.b.mouseX-1:
      return r
    inc j, L

proc drawSubtoken(db: var DrawBuffer; ra, rb: int; fg, bg: Color) =
  # Draws the part of the token that actually still fits in the line. Also
  # does the click checking and the cursor tracking.
  let text = cast[cstring](addr db.chars[ra])
  let savedCh = db.chars[rb+1]
  db.chars[rb+1] = '\0'
  let ext = measureText(db.font, text)
  db.chars[rb+1] = savedCh

  var d = db.dim
  d.w = ext.w
  d.h = ext.h

  # requested cursor update?
  let i = db.toCursor[ra]
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
    var i = ra
    if db.toCursor[i] == db.b.cursor:
      db.cursorDim = d
    else:
      while db.toCursor[i] != db.b.cursor: inc i
      let j = i
      let ch = db.chars[j]
      db.chars[j] = '\0'
      db.cursorDim = d
      db.cursorDim.x += textSize(db.font, cast[cstring](addr db.chars[ra]))
      db.chars[j] = ch

  # Actually draw
  db.chars[rb+1] = '\0'
  discard drawTextShaded(db.font, d.x, d.y, text, fg, bg)
  db.chars[rb+1] = savedCh

proc indWidth(db: DrawBuffer): int =
  var
    i = db.startedWith
    r = 0
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
        r = i - db.startedWith
        break
      of '\L': break
      else: inc i
  result = textSize(db.font, " ") * r

proc smartWrap(db: DrawBuffer; origP: int; critical: bool): int =
  var p = origP
  while p > db.ra+1:
    if (db.chars[p] in Letters) != (db.chars[p-1] in Letters):
      return p
    dec p
  return if critical: origP else: -1

proc translateToken(db: var DrawBuffer) =
  if db.chars[0] == '{' and db.chars[1] == '.' and db.chars[2] == '\0':
    db.chars[0] = '\xE2'
    db.chars[1] = '\x8E'
    db.chars[2] = '\xA8'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3
  elif db.chars[0] == '.' and db.chars[1] == '}' and db.chars[2] == '\0':
    db.chars[0] = '\xE2'
    db.chars[1] = '\x8E'
    db.chars[2] = '\xAC'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3
  elif db.chars[0] == '[' and db.chars[1] == '.' and db.chars[2] == '\0':
    db.chars[0] = '\xE2'
    db.chars[1] = '\x81'
    db.chars[2] = '\x85'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3
  elif db.chars[0] == '.' and db.chars[1] == ']' and db.chars[2] == '\0':
    db.chars[0] = '\xE2'
    db.chars[1] = '\x81'
    db.chars[2] = '\x86'
    db.chars[3] = '\0'
    db.toCursor[2] = db.toCursor[1]
    db.toCursor[3] = db.toCursor[1]
    db.charsLen = 3

proc drawToken(t: InternalTheme; db: var DrawBuffer; fg, bg: Color) =
  if t.showLigatures:
    translateToken(db)
  if db.dim.y+db.lineH > db.maxY: return
  let text = cast[cstring](addr db.chars)
  let ext = measureText(db.font, text)
  let w = ext.w

  if db.dim.x + w + db.spaceWidth <= db.dim.w:
    # fast common case: the token still fits:
    drawSubtoken(db, 0, db.charsLen-1, fg, bg)
    db.dim.x += w
  else:
    # slow uncommon case: we have to wrap the line.
    db.ra = 0
    db.rb = 0
    var iters = 0
    while db.ra < db.charsLen:
      inc iters
      var start = cast[cstring](addr db.chars[db.ra])
      assert start[0] != '\0'

      var probe = db.ra
      var dotsrequired = false
      while probe < db.charsLen:
        let ch = db.chars[probe]
        db.chars[probe] = '\0'
        let w2 = textSize(db.font, start)
        db.chars[probe] = ch
        if db.dim.x + db.spaceWidth + w2 > db.dim.w:
          dec probe
          probe = smartWrap(db, probe, iters > db.b.span)
          dotsrequired = true
          break
        inc probe
      if probe <= 0:
        discard
      else:
        let ch = db.chars[probe]
        db.chars[probe] = '\0'
        assert start[0] != '\0'
        let ext2 = measureText(db.font, start)
        db.rb = probe-1
        db.chars[probe] = ch
        drawSubtoken(db, db.ra, db.rb, fg, bg)
        db.ra = probe
        db.dim.x += ext2.w
      if not dotsRequired: break
      # draw line continuation and continue in the next line:
      let dotsExt = drawTextShaded(db.font, db.dim.x, db.dim.y,
                                    Ellipsis, fg, bg)
      db.dim.x = db.oldX
      db.dim.y += db.lineH
      if db.dim.y+db.lineH > db.maxY: break
      db.dim.x += min(indWidth(db), (db.dim.w - db.oldX) div 2)
      let dotsExt2 = drawTextShaded(db.font, db.dim.x, db.dim.y,
                                     Ellipsis, fg, bg)
      db.dim.x += dotsExt2.w

proc drawCursor(t: InternalTheme; dim: Rect; h: int) =
  screen.fillRect(Rect(x: dim.x, y: dim.y, w: t.cursorWidth, h: h), t.cursor)

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
  db.lineH = screen.fontLineSkip(db.font)
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
          minimapCandidate(db, b.posHint)
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
        vlineDotted(w*r+db.oldX, dim.y, dim.y+db.lineH, t.indentation)
      if b[i] == '\t': inc r, b.tabsize
      else: inc r
      inc i

  dim = db.dim
  dim.y += screen.fontLineSkip(t.editorFontHandle)
  dim.x = db.oldX
  if db.cursorDim.h > 0:
    if blink: t.drawCursor(db.cursorDim, db.lineH)
    b.cursorDim = (db.cursorDim.x.int, db.cursorDim.y.int, db.lineH.int)
  result = db.i+1

proc setCursorFromMouse*(b: Buffer; dim: Rect; mouse: Point; clicks: int) =
  b.mouseX = mouse.x
  b.mouseY = mouse.y
  b.clicks = clicks
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
    result = (b.numberOfLines+1).log10 * textSize(t.editorFontHandle, " ")

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
           options: set[DrawOption] = {}): int {.discardable.} =
  b.posHint.w = 0
  b.posHint.h = 0
  b.cursorDim.h = 0
  let realOffset = getLineOffset(b, b.firstLine)
  if b.firstLineOffset != realOffset:
    echo "real offset ", realOffset, " wrong ", b.firstLineOffset
    echo "char at real offset ", b[realOffset].ord, " wrong ",
      b[b.firstLineOffset]
    assert false
  var renderLine = b.firstLine
  var i = nextLineOffset(b, renderLine, b.firstLineOffset)
  let endY = dim.y + dim.h - 1
  let endX = dim.x + dim.w - 1
  var dim = dim
  dim.w = endX
  dim.h = endY
  let spl = spaceForLines(b, t)

  template drawCurrent() =
    if showLines in options:
      t.drawNumberBegin(b, renderLine+1, b.currentLine+1, spl, dim.y)
    i = t.drawTextLine(b, i, dim, blink)
    if showLines in options:
      t.drawNumberEnd(b, renderLine+1, b.currentLine+1, spl, dim.y)

  if showLines in options: dim.x = spl + RoomForMargin
  b.span = 0
  drawCurrent()
  inc b.span
  let fontSize = t.editorFontSize.int
  let lineH = screen.fontLineSkip(t.editorFontHandle)
  while dim.y+fontSize < endY and i <= len(b):
    inc renderLine
    let expectedLine = renderLine
    i = nextLineOffset(b, renderLine, i)
    if expectedLine != renderLine or showGaps in options:
      hlineDotted(dim.x, endX, dim.y+lineH div 4, t.indentation)
      dim.y += lineH div 2

    drawCurrent()
    inc b.span
  result = dim.y
  while dim.y+fontSize < endY:
    inc dim.y, lineH
    inc b.span
  mouseAfterNewLine(b, min(i, b.len),
    Rect(x: dim.x, y: 100_000i32, w: 0'i32, h: 0'i32), lineH)
  if b.posHint.h < lineH*4:
    b.posHint.w = 0
    b.posHint.h = 0
  else:
    b.posHint.y = abs(b.posHint.y)

proc drawAutoComplete*(t: InternalTheme; b: Buffer; dim: Rect) =
  let realOffset = getLineOffset(b, b.firstLine)
  if b.firstLineOffset != realOffset:
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
      screen.drawLine(originalX, y, endX, y, t.fg)

  drawCurrent()
  inc b.span
  let fontSize = t.editorFontSize.int
  while dim.y+fontSize < endY and i <= len(b):
    drawCurrent()
    inc b.span
  let lineH = screen.fontLineSkip(t.editorFontHandle)
  while dim.y+fontSize < endY:
    inc dim.y, lineH
    inc b.span
  b.clicks = 0
