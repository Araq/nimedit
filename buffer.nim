# Implementation uses a gap buffer with explicit undo stack.

import strutils, unicode
import styles, highlighters, common, themes
import sdl2, sdl2/ttf
import buffertype, unihelp, languages
from os import splitFile

const
  tabWidth = 2
  Letters* = {'a'..'z', 'A'..'Z', '0'..'9', '_', '\128'..'\255'}

proc cursorMoved(b: Buffer) =
  proc forwards(b: Buffer; le, ri: char) =
    var i = b.cursor+1
    let tc = b.getCell(b.cursor).s
    var counter = 0
    while i < b.len:
      if b.getCell(i).s == tc:
        if b[i] == ri:
          if counter <= 0:
            b.bracketToHighlight = i
            break
          dec counter
        elif b[i] == le:
          inc counter
      inc i

  proc backwards(b: Buffer; le, ri: char) =
    var i = b.cursor.int-1
    let tc = b.getCell(b.cursor).s
    var counter = 0
    while i >= 0:
      if b.getCell(i).s == tc:
        if b[i] == le:
          if counter <= 0:
            b.bracketToHighlight = i
            break
          dec counter
        elif b[i] == ri:
          inc counter
      dec i

  const brackets = {'(', '{', '[', ']', '}', ')'}
  b.bracketToHighlight = -1
  # fast check that is likely false:
  if b[b.cursor] in brackets:
    case b[b.cursor]
    of '(': forwards(b, '(', ')')
    of '[': forwards(b, '[', ']')
    of '{': forwards(b, '{', '}')
    of ')': backwards(b, '(', ')')
    of ']': backwards(b, '[', ']')
    of '}': backwards(b, '{', '}')
    else: discard

include drawbuffer

proc newBuffer*(heading: string; mgr: ptr StyleManager): Buffer =
  new(result)
  result.front = @[]
  result.back = @[]
  result.filename = ""
  result.heading = heading
  result.actions = @[]
  result.mgr = mgr
  result.readOnly = -1
  result.tabSize = tabWidth
  result.markers = @[]
  result.selected.a = -1
  result.selected.b = -1
  result.bracketToHighlight = -1

proc clear*(result: Buffer) =
  result.front.setLen 0
  result.back.setLen 0
  result.actions.setLen 0
  result.markers.setLen 0
  result.currentLine = 0
  result.firstLine = 0
  result.numberOfLines = 0
  result.desiredCol = 0
  result.cursor = 0
  result.selected.a = -1
  result.selected.b = -1
  result.bracketToHighlight = -1
  result.span = 0
  result.firstLineOffset = 0
  result.readOnly = -1
  result.clicks = 0
  result.undoIdx = 0
  result.activeMarker = 0
  result.cursorDim = (0, 0, 0)

proc fullText*(b: Buffer): string =
  result = newStringOfCap(b.front.len + b.back.len)
  for i in 0..<b.front.len:
    result.add b.front[i].c
  for i in countdown(b.back.len-1, 0):
    result.add b.back[i].c

template edit(b: Buffer) =
  b.undoIdx = b.actions.len-1

proc prepareForEdit(b: Buffer) =
  if b.cursor < b.front.len:
    for i in countdown(b.front.len-1, b.cursor):
      b.back.add(b.front[i])
    setLen(b.front, b.cursor)
  elif b.cursor > b.front.len:
    let chars = max(b.cursor - b.front.len, 0)
    var took = 0
    for i in countdown(b.back.len-1, max(b.back.len-chars, 0)):
      b.front.add(b.back[i])
      inc took
    setLen(b.back, b.back.len - took)
    #if b.cursor != b.front.len:
    #  echo b.cursor, " ", b.front.len, " ", took
    b.cursor = b.front.len
  assert b.cursor == b.front.len
  b.changed = true

proc upFirstLineOffset(b: Buffer) =
  if b.firstLineOffset == 0: return
  assert b.firstLineOffset > 0
  assert b[b.firstLineOffset-1] == '\L'
  var i = b.firstLineOffset-1
  while i > 0 and b[i-1] != '\L': dec i
  b.firstLineOffset = max(0, i)

proc downFirstLineOffset(b: Buffer) =
  assert b.firstLineOffset == 0 or b[b.firstLineOffset-1] == '\L'
  var i = b.firstLineOffset
  while b[i] != '\L': inc i
  b.firstLineOffset = i+1

proc scrollLines*(b: Buffer; amount: int) =
  let oldFirstLine = b.firstLine
  b.firstLine = clamp(b.firstLine+amount, 0, max(0, b.numberOfLines-1))
  # compute the real amount:
  var amount = b.firstLine - oldFirstLine
  if amount < 0:
    while amount < 0:
      upFirstLineOffset(b)
      inc amount
  elif amount > 0:
    while amount > 0:
      downFirstLineOffset(b)
      dec amount
  inc b.firstLine, amount

proc scroll(b: Buffer; amount: int) =
  assert amount == 1 or amount == -1
  # the cursor can be detached from the scroll position, so we need to perform
  # a general scrollLines:
  inc b.currentLine, amount
  if b.currentLine < b.firstLine:
    # bring into view:
    scrollLines(b, b.currentLine-b.firstLine)
  elif b.currentLine > b.firstLine + b.span-2:
    scrollLines(b, b.currentLine - (b.firstLine + b.span-2))
  when false:
    inc b.currentLine, amount
    if b.currentLine < b.firstLine:
      assert b.firstLine == b.currentLine+1
      dec b.firstLine
      upFirstLineOffset(b)
    elif b.currentLine > b.firstLine + b.span-2:
      inc b.firstLine
      downFirstLineOffset(b)

proc getLine*(b: Buffer): int = b.currentLine
proc getColumn*(b: Buffer): int =
  var i = b.cursor
  while i > 0 and b[i-1] != '\L':
    dec i
  while i < b.cursor and b[i] != '\L':
    i += graphemeLen(b, i)
    inc result

proc getCurrentLine*(b: Buffer): string =
  var i = b.cursor #b.len
  while i > 0 and b[i-1] != '\L': dec i
  result = ""
  while i < b.len and b[i] != '\L':
    result.add b[i]
    inc i

proc getCurrentWord*(b: Buffer): string =
  var i = b.cursor
  while i > 0 and b[i-1] in Letters: dec i
  result = ""
  while b[i] in Letters:
    result.add b[i]
    inc i

proc getWordPrefix*(b: Buffer): string =
  result = ""
  var i = b.cursor-1
  while i > 0 and b[i-1] in Letters:
    dec i
  while i < b.cursor:
    result.add b[i]
    inc i

proc rawLeft*(b: Buffer) =
  if b.cursor > 0:
    let r = lastRune(b, b.cursor-1)
    if r[0] == Rune('\L'):
      scroll(b, -1)
    b.cursor -= r[1]
    b.desiredCol = getColumn(b)

proc left*(b: Buffer; jump: bool) =
  rawLeft(b)
  if jump and b.cursor > 0:
    var i = b.cursor-1
    if b[i] in Letters:
      while i > 0 and b[i-1] in Letters: dec i
    else:
      while i > 0 and b.getCell(i-1).s == b.getCell(b.cursor-1).s and
                      b.getCell(i-1).c != '\L':
        dec i
    b.cursor = i
    #while b.cursor > 0 and b[b.cursor] notin WhiteSpace: rawLeft(b)
    #while b.cursor > 1 and b[b.cursor-1] in WhiteSpace: rawLeft(b)
  cursorMoved(b)

proc rawRight(b: Buffer) =
  if b.cursor < b.len:
    if b[b.cursor] == '\L':
      scroll(b, 1)
    b.cursor += graphemeLen(b, b.cursor)
    b.desiredCol = getColumn(b)

proc right*(b: Buffer; jump: bool) =
  rawRight(b)
  if jump:
    #while b.cursor < b.len and b[b.cursor] in WhiteSpace: rawRight(b)
    #while b.cursor < b.len and b[b.cursor] notin WhiteSpace: rawRight(b)
    var i = b.cursor
    if b[i] in Letters:
      while i < b.len and b[i] in Letters: inc i
    else:
      while i < b.len and b.getCell(i).s == b.getCell(b.cursor).s and
                      b.getCell(i).c != '\L':
        inc i
    b.cursor = i
  cursorMoved(b)

proc up*(b: Buffer; jump: bool) =
  var col = b.desiredCol
  var i = b.cursor

  # move to the *start* of this line
  while i >= 1 and b[i-1] != '\L': dec i
  if i >= 1 and b[i-1] == '\L':
    # move up 1 line:
    dec i
    # move to the *start* of this line
    while i >= 1 and b[i-1] != '\L': dec i
    # move to the desired column:
    while i >= 0 and col > 0 and b[i] != '\L':
      i += graphemeLen(b, i)
      dec col
    scroll(b, -1)
  b.cursor = max(0, i)
  cursorMoved(b)

proc down*(b: Buffer; jump: bool) =
  var col = b.desiredCol

  let L = b.front.len+b.back.len
  while b.cursor < L:
    if b[b.cursor] == '\L':
      scroll(b, 1)
      break
    b.cursor += 1
  b.cursor += 1

  while b.cursor < L and col > 0:
    if b[b.cursor] == '\L': break
    dec col
    b.cursor += 1
  if b.cursor > L: b.cursor = L
  if b.cursor < 0: b.cursor = 0
  cursorMoved(b)

proc updateMarkers(b: Buffer; cursorMovement: int) =
  for x in mitems(b.markers):
    if x.b < b.cursor+cursorMovement:
      discard
    elif b.cursor+cursorMovement in x.a..x.b:
      x.b += cursorMovement
    else:
      x.a += cursorMovement
      x.b += cursorMovement

proc filterForInsert(s: string): string =
  result = newStringOfCap(s.len)
  for i in 0..<s.len:
    case s[i]
    of '\C': discard
    of '\t':
      for j in 1..tabWidth: result.add(' ')
    else: result.add(s[i])

proc rawInsert*(b: Buffer; c: char) =
  case c
  of '\L':
    b.front.add Cell(c: '\L')
    inc b.numberOfLines
    scroll(b, 1)
    updateMarkers(b, 1)
    inc b.cursor
  of '\C': discard
  of '\t':
    for i in 1..tabWidth:
      b.front.add Cell(c: ' ')
      updateMarkers(b, 1)
      inc b.cursor
  of '\0':
    b.front.add Cell(c: '_')
    updateMarkers(b, 1)
    inc b.cursor
  else:
    b.front.add Cell(c: c)
    updateMarkers(b, 1)
    inc b.cursor

proc rawInsert*(b: Buffer; s: string) =
  for i in 0..<s.len: rawInsert(b, s[i])

proc loadFromFile*(b: Buffer; filename: string) =
  template detectTabSize() =
    if b.tabSize < 0:
      var j = i+1
      while j < s.len and s[j] == ' ':
        if b.tabSize < 0: b.tabSize = 1
        else: inc b.tabSize
        inc j

  clear(b)
  inc b.version
  b.filename = filename
  b.lang = fileExtToLanguage(splitFile(filename).ext)
  let s = readFile(filename)
  # detect tabSize from file:
  b.tabSize = -1
  for i in 0..<s.len:
    case s[i]
    of '\L':
      b.front.add Cell(c: '\L')
      inc b.numberOfLines
      if b.lineending.isNil:
        b.lineending = "\L"
      detectTabSize()
    of '\C':
      if i < s.len-1 and s[i+1] != '\L':
        b.front.add Cell(c: '\L')
        inc b.numberOfLines
        if b.lineending.isNil:
          b.lineending = "\C"
      elif b.lineending.isNil:
        b.lineending = "\C\L"
    of '\t':
      if i > 0 and s[i-1] == ' ': b.tabSize = 8'i8
      b.front.add Cell(c: '\t')
    else:
      b.front.add Cell(c: s[i])
  if b.tabSize < 0: b.tabSize = tabWidth
  highlightEverything(b)
  b.timestamp = os.getLastModificationTime(b.filename)
  b.changed = false

proc saveAsTemp*(b: Buffer; filename: string) =
  if b.lineending.isNil or b.lineending.len == 0:
    b.lineending = "\L"
  let L = b.len
  var i = 0
  let f = open(filename, fmWrite)
  while i < L:
    let ch = b[i]
    if ch > ' ':
      f.write(ch)
    elif ch == ' ':
      let j = i
      while b[i] == ' ': inc i
      if b[i] == '\L':
        f.write(b.lineending)
      else:
        for ii in j..i-1:
          f.write(' ')
        dec i
    elif ch == '\L':
      f.write(b.lineending)
    else:
      f.write(ch)
    inc(i)
  f.close

proc save*(b: Buffer) =
  if b.filename.len == 0: b.filename = b.heading
  saveAsTemp(b, b.filename)
  b.changed = false
  b.timestamp = os.getLastModificationTime(b.filename)

proc saveAs*(b: Buffer; filename: string) =
  b.filename = filename
  b.heading = os.extractFilename(filename)
  let newlang = fileExtToLanguage(splitFile(filename).ext)
  if b.lang != newlang:
    b.lang = newlang
    highlightEverything(b)
  save(b)

proc rawBackspace(b: Buffer; overrideUtf8=false; undoAction: var string) =
  assert b.cursor == b.front.len
  var x = 0
  let ch = b.front[b.cursor-1].c
  if ch.ord < 128 or overrideUtf8:
    x = 1
    if ch == '\L':
      dec b.numberOfLines
      scroll(b, -1)
  else:
    while true:
      let (r, L) = lastRune(b, b.cursor-1-x)
      inc(x, L)
      if L > 1 and isCombining(r): discard
      else: break
  # we need to reverse this string here:
  if not undoAction.isNil:
    for i in countdown(b.front.len-1, b.front.len-x):
      undoAction.add b.front[i].c
  updateMarkers(b, -x)
  b.cursor -= x
  b.front.setLen(b.cursor)

proc backspaceNoSelect(b: Buffer; overrideUtf8=false) =
  if b.cursor <= 0: return
  if b.cursor-1 <= b.readOnly: return
  let oldCursor = b.cursor
  prepareForEdit(b)
  setLen(b.actions, clamp(b.undoIdx+1, 0, b.actions.len))
  var ah = b.actions.high
  if ah == -1 or b.actions[ah].k != dele:
    setLen(b.actions, ah+2)
    inc ah
    b.actions[ah].word = ""
    b.actions[ah].k = dele
    b.actions[ah].version = b.version
  b.rawBackspace(overrideUtf8, b.actions[ah].word)
  b.actions[ah].pos = b.cursor
  edit(b)
  if b.actions[ah].word.len == 1 and b.actions[ah].word[0] in Whitespace:
    b.actions[ah].k = delFinished
  b.desiredCol = getColumn(b)
  highlightLine(b, oldCursor)

proc selectAll*(b: Buffer) =
  b.selected = (0, b.len-1)

proc getSelectedText*(b: Buffer): string =
  if b.selected.b < 0: return ""
  result = newStringOfCap(b.selected.b - b.selected.a + 1)
  for i in b.selected.a .. b.selected.b:
    result.add b[i]

proc getLineFromOffset(b: Buffer; pos: int): Natural =
  result = 0
  var pos = pos
  # do not count the newline at the very end at b[pos]:
  if pos >= 0 and b[pos] == '\L': dec pos
  while pos >= 0:
    if b[pos] == '\L': inc result
    dec pos

proc setCaret*(b: Buffer; pos: int) =
  b.cursor = pos
  b.currentLine = getLineFromOffset(b, b.cursor)

proc removeSelectedText(b: Buffer; selectedA, selectedB: var int) =
  if selectedB < 0: return
  b.setCaret(selectedB+1)
  let oldCursor = b.cursor
  setLen(b.actions, clamp(b.undoIdx+1, 0, b.actions.len))
  b.actions.add(Action(k: delFinished, pos: b.cursor, word: "",
                       version: b.version))
  edit(b)
  while b.cursor > selectedA:
    if b.cursor <= 0: break
    if b.cursor-1 <= b.readOnly: break
    prepareForEdit(b)
    b.rawBackspace(overrideUtf8=true, b.actions[^1].word)
    b.actions[^1].pos = b.cursor
  b.desiredCol = getColumn(b)
  highlightLine(b, oldCursor)
  selectedB = -1

proc removeSelectedText*(b: Buffer) =
  removeSelectedText(b, b.selected.a, b.selected.b)

proc deselect*(b: Buffer) {.inline.} = b.selected.b = -1

proc select(b: Buffer; oldPos, newPos: int; left: bool) =
  # cursor moved into the current selection?
  if b.cursor >= b.selected.a and b.cursor <= b.selected.b:
    # then deselect this piece:
    if left:
      let (_, L) = lastRune(b, newPos-1)
      b.selected.b = newPos-L
    else:
      b.selected.a = newPos
  else:
    # else select this piece:
    if b.selected.b < 0:
      if oldPos <= newPos:
        b.selected.a = oldPos
        let (_, L) = lastRune(b, newPos-1)
        b.selected.b = newPos-L
      else:
        b.selected.a = newPos
        let (_, L) = lastRune(b, oldPos-1)
        b.selected.b = oldPos-L
    else:
      if left:
        b.selected.a = newPos
      else:
        let (_, L) = lastRune(b, newPos-1)
        b.selected.b = newPos-L
  if b.selected.b < b.selected.a: deselect(b)

proc selectLeft*(b: Buffer; jump: bool) =
  if b.cursor > 0:
    let old = b.cursor
    left(b, jump)
    select(b, old, b.cursor, true)

proc selectUp*(b: Buffer; jump: bool) =
  if b.cursor > 0:
    let old = b.cursor
    up(b, jump)
    select(b, old, b.cursor, true)

proc selectRight*(b: Buffer; jump: bool) =
  if b.cursor < b.len:
    let old = b.cursor
    right(b, jump)
    select(b, old, b.cursor, false)

proc selectDown*(b: Buffer; jump: bool) =
  if b.cursor < b.len:
    let old = b.cursor
    down(b, jump)
    select(b, old, b.cursor, false)

proc backspace*(b: Buffer; overrideUtf8=false) =
  inc b.version
  if b.selected.b < 0:
    backspaceNoSelect(b, overrideUtf8)
  else:
    removeSelectedText(b)
  cursorMoved(b)

proc deleteKey*(b: Buffer) =
  if b.selected.b < 0:
    if b.cursor >= b.len: return
    let (_, L) = lastRune(b, b.cursor+1)
    inc(b.cursor, L)
    backspace(b)
  else:
    removeSelectedText(b)
  cursorMoved(b)

proc insertNoSelect(b: Buffer; s: string; singleUndoOp=false) =
  if b.cursor <= b.readOnly or s.len == 0: return
  let oldCursor = b.cursor
  prepareForEdit(b)
  setLen(b.actions, clamp(b.undoIdx+1, 0, b.actions.len))
  if b.actions.len > 0 and b.actions[^1].k == ins and not singleUndoOp:
    b.actions[^1].word.add s.filterForInsert
  else:
    b.actions.add(Action(k: ins, pos: b.cursor, word: s.filterForInsert,
                         version: b.version))
  if s[^1] in Whitespace or singleUndoOp: b.actions[^1].k = insFinished
  edit(b)
  rawInsert(b, s)
  b.desiredCol = getColumn(b)
  highlightLine(b, oldCursor)

proc insertSingleKey*(b: Buffer; s: string) =
  inc b.version
  if b.selected.b >= 0 and s[0] in {'(', '[', '{', '\'', '`', '"'}:
    var x: string
    case s[0]
    of '(': x = "(" & getSelectedText(b) & ")"
    of '[': x = "[" & getSelectedText(b) & "]"
    of '{': x = "{" & getSelectedText(b) & "}"
    of '\'': x = "'" & getSelectedText(b) & "'"
    of '"': x = "\"" & getSelectedText(b) & "\""
    of '`': x = "`" & getSelectedText(b) & "`"
    else: discard
    removeSelectedText(b)
    insertNoSelect(b, x)
  else:
    removeSelectedText(b)
    insertNoSelect(b, s)
  cursorMoved(b)

proc insert*(b: Buffer; s: string) =
  inc b.version
  removeSelectedText(b)
  insertNoSelect(b, s, true)

include finder

proc dedentSingleLine(b: Buffer; i: int) =
  if b[i] == '\t':
    b.setCaret(i+1)
    backspaceNoSelect(b)
    if b.selected.b >= 0: dec b.selected.b
  elif b[i] == ' ':
    var spaces = 1
    while spaces < b.tabSize and b[i+spaces] == ' ':
      inc spaces
    b.setCaret i+spaces
    for j in 1..spaces:
      backspaceNoSelect(b)
      if b.selected.b >= 0: dec b.selected.b

proc dedent*(b: Buffer) =
  inc b.version
  if b.selected.b < 0:
    var i = b.cursor
    while i >= 1 and b[i-1] != '\L': dec i
    dedentSingleLine(b, i)
  else:
    var i = b.selected.a
    while i >= 1 and b[i-1] != '\L': dec i
    while i <= b.selected.b:
      dedentSingleLine(b, i)
      inc i
      while i < b.len-1 and b[i] != '\L': inc i
      if b[i] == '\L': inc i

proc indentSingleLine(b: Buffer; i: int) =
  b.setCaret i
  for j in 1..b.tabSize:
    insertNoSelect(b, " ")
    assert b.selected.b >= 0
    inc b.selected.b

proc indent*(b: Buffer) =
  inc b.version
  if b.selected.b < 0:
    for j in 1..b.tabSize:
      insertNoSelect(b, " ")
  else:
    var i = b.selected.a
    while i >= 1 and b[i-1] != '\L': dec i
    while i <= b.selected.b and i < b.len:
      indentSingleLine(b, i)
      inc i
      while i < b.len and b[i] != '\L': inc i
      if b[i] == '\L': inc i

proc gotoPos*(b: Buffer; pos: int) =
  let pos = clamp(pos, 0, b.len)
  b.cursor = pos
  b.currentLine = getLineFromOffset(b, pos)
  # don't jump needlessly around if the line is still in the view:
  if b.currentLine >= b.firstLine+1 and b.currentLine < b.firstLine + b.span-1:
    discard "still in view"
  else:
    b.firstLine = max(0, b.currentLine - (b.span div 2))
    b.firstLineOffset = getLineOffset(b, b.firstLine)

proc gotoFirstMarker*(b: Buffer): bool =
  b.activeMarker = 0
  if b.activeMarker < b.markers.len:
    gotoPos(b, b.markers[b.activeMarker].b+1)
    result = true

proc gotoNextMarker*(b: Buffer) =
  inc b.activeMarker
  if b.activeMarker >= b.markers.len:
    b.activeMarker = 0
  if b.activeMarker < b.markers.len:
    gotoPos(b, b.markers[b.activeMarker].b+1)

proc gotoPrevMarker*(b: Buffer) =
  dec b.activeMarker
  if b.activeMarker > 0:
    b.activeMarker = b.markers.high
  if b.activeMarker < b.markers.len:
    gotoPos(b, b.markers[b.activeMarker].b+1)

proc tabPressed*(b: Buffer) =
  #if b.markers.len == 0:
  indent(b)
  #else:
  #  gotoNextMarker(b)

proc shiftTabPressed*(b: Buffer) =
  #if b.markers.len == 0:
  dedent(b)
  #else:
  #  gotoPrevMarker(b)

proc insertEnter*(b: Buffer; smartIndent=true) =
  # move to the *start* of this line
  var i = b.cursor
  while i >= 1 and b[i-1] != '\L': dec i
  var toInsert = "\L"
  if smartIndent:
    while true:
      let c = b[i]
      if c == ' ' or c == '\t':
        toInsert.add c
      else:
        break
      inc i
    if b.cursor > 0 and b[b.cursor-1] in additionalIndentChars[b.lang]:
      for i in 1..b.tabSize: toInsert.add ' '
  b.insert(toInsert)

proc gotoLine*(b: Buffer; line, col: int) =
  let line = clamp(line-1, 0, b.numberOfLines-1)
  b.cursor = getLineOffset(b, line)
  b.currentLine = line
  # if span has not been computed yet, take a guess:
  let span = if b.span > 0: b.span else: 30
  b.firstLine = max(0, line - (span div 2))
  b.firstLineOffset = getLineOffset(b, b.firstLine)
  if col > 0:
    var c = 1
    while c <= col and b[b.cursor] != '\L':
      rawRight(b)
      inc c

proc insertReadonly*(b: Buffer; s: string) =
  b.readOnly = -1
  b.insert(s)
  b.readOnly = b.len-1

proc applyUndo(b: Buffer; a: Action) =
  let oldCursor = b.cursor
  if a.k <= insFinished:
    gotoPos(b, a.pos + a.word.len)
    prepareForEdit(b)
    # reverse op of insert is delete:
    var dummy: string = nil
    for i in 1..a.word.len:
      b.rawBackspace(overrideUtf8=true, dummy)
  else:
    gotoPos(b, a.pos)
    prepareForEdit(b)
    # reverse op of delete is insert:
    for i in countdown(a.word.len-1, 0):
      b.rawInsert a.word[i]
  highlightLine(b, oldCursor)

proc applyRedo(b: Buffer; a: Action) =
  let oldCursor = b.cursor
  if a.k <= insFinished:
    gotoPos(b, a.pos)
    prepareForEdit(b)
    # reverse op of delete is insert:
    for i in countup(0, a.word.len-1):
      b.rawInsert a.word[i]
  else:
    gotoPos(b, a.pos + a.word.len)
    prepareForEdit(b)
    # reverse op of insert is delete:
    var dummy: string = nil
    for i in 1..a.word.len:
      b.rawBackspace(overrideUtf8=true, dummy)
  highlightLine(b, oldCursor)

template canUndo(): untyped = (b.undoIdx >= 0 and b.undoIdx < b.actions.len)

proc undo*(b: Buffer) =
  when defined(debugUndo):
    echo "undo ----------------------------------------"
    for i, x in b.actions:
      if i == b.undoIdx:
        echo x, "*"
      else:
        echo x

  if canUndo():
    let v = b.actions[b.undoIdx].version
    applyUndo(b, b.actions[b.undoIdx])
    dec(b.undoIdx)
    while canUndo() and b.actions[b.undoIdx].version == v:
      applyUndo(b, b.actions[b.undoIdx])
      dec(b.undoIdx)

proc redo*(b: Buffer) =
  inc(b.undoIdx)
  when defined(debugUndo):
    echo "redo ----------------------------------------"
    for i, x in b.actions:
      if i == b.undoIdx:
        echo x, "*"
      else:
        echo x
  if canUndo():
    let v = b.actions[b.undoIdx].version
    applyRedo(b, b.actions[b.undoIdx])
    while b.undoIdx+1 >= 0 and b.undoIdx+1 < b.actions.len and
        b.actions[b.undoIdx+1].version == v:
      inc(b.undoIdx)
      applyRedo(b, b.actions[b.undoIdx])
  else:
    dec b.undoIdx
