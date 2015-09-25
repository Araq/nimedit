# Implementation uses a gap buffer with explicit undo stack.

import strutils, unicode
import styles
import sdl2, sdl2/ttf

const
  tabWidth = 2

type
  ActionKind = enum
    ins, insFinished, del, delFinished

  Action = object
    k: ActionKind
    pos: int
    word: string
  Cell = object
    c: char
    s: StyleIdx
  Line = object
    offset: int
    parsingState: int

  Buffer* = ref object
    cursor: int
    firstLine*, numberOfLines*, currentLine*: int
    front, back: seq[Cell]
    mgr: ptr StyleManager
    #lines: seq[Line]
    actions: seq[Action]
    undoIdx: int
    next*, prev*: Buffer
    changed*: bool
    heading*: string
    filename*: string
    lineending: string # CR-LF, CR or LF

proc getCell(b: Buffer; i: Natural): Cell =
  if i < b.front.len:
    result = b.front[i]
  else:
    let i = i-b.front.len
    if i <= b.back.high:
      result = b.back[b.back.high-i]
    else:
      result = Cell(c: '\L', s: StyleIdx(0))

proc `[]`(b: Buffer; i: Natural): char {.inline.} = getCell(b, i).c

proc len(b: Buffer): int = b.front.len+b.back.len

include unihelp
include drawbuffer

proc newBuffer*(heading: string; mgr: ptr StyleManager): Buffer =
  new(result)
  result.front = @[]
  result.back = @[]
  result.filename = ""
  result.heading = heading
  result.actions = @[]
  result.mgr = mgr

proc clear*(result: Buffer) =
  result.front.setLen 0
  result.back.setLen 0
  result.actions.setLen 0
  result.currentLine = 0

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
    if b.cursor != b.front.len:
      echo "cursor ", b.cursor, " ", b.front.len
  assert b.cursor == b.front.len
  b.changed = true

proc left*(b: Buffer; jump: bool) =
  if b.cursor > 0:
    let r = lastRune(b, b.cursor-1)
    b.cursor -= r[1]

proc right*(b: Buffer; jump: bool) =
  if b.cursor < b.front.len+b.back.len:
    b.cursor += graphemeLen(b, b.cursor)

proc getColumn*(b: Buffer): int =
  var i = b.cursor
  while i > 0 and b[i-1] != '\L':
    dec i
  while i < b.cursor and b[i] != '\L':
    i += graphemeLen(b, i)
    inc result

proc getLine*(b: Buffer): int = b.currentLine

proc up*(b: Buffer; jump: bool) =
  var col = getColumn(b)
  echo "UP   COL ", col
  b.cursor -= 1
  while b.cursor >= 0:
    if b.getCell(b.cursor).c == '\L': break
    b.cursor -= 1
  while b.cursor >= 0:
    if b.getCell(b.cursor).c == '\L': break
    b.cursor -= 1
  while col > 0:
    b.cursor += 1
    dec col
  if b.cursor < 0: b.cursor = 0
  #prepareForEdit(b)

proc down*(b: Buffer; jump: bool) =
  var col = getColumn(b)
  echo "DOWN COL ", col

  let L = b.front.len+b.back.len
  while b.cursor < L:
    if b.getCell(b.cursor).c == '\L': break
    b.cursor += 1
  b.cursor += 1

  while b.cursor < L and col > 0:
    if b.getCell(b.cursor).c == '\L': break
    dec col
    b.cursor += 1
  if b.cursor > L: b.cursor = L
  if b.cursor < 0: b.cursor = 0

proc rawInsert*(b: Buffer; s: string) =
  for i in 0..<s.len:
    case s[i]
    of '\L':
      b.front.add Cell(c: '\L')
      inc b.numberOfLines
    of '\C':
      if i < s.len-1 and s[i+1] != '\L':
        b.front.add Cell(c: '\L')
        inc b.numberOfLines
    of '\t':
      for i in 1..tabWidth:
        b.front.add Cell(c: ' ')
    else:
      b.front.add Cell(c: s[i])
  b.cursor += s.len

proc loadFromFile*(b: Buffer; filename: string) =
  b.filename = filename
  clear(b)
  let s = readFile(filename)
  for i in 0..<s.len:
    case s[i]
    of '\L':
      b.front.add Cell(c: '\L')
      inc b.numberOfLines
      if b.lineending.isNil:
        b.lineending = "\L"
    of '\C':
      if i < s.len-1 and s[i+1] != '\L':
        b.front.add Cell(c: '\L')
        inc b.numberOfLines
        if b.lineending.isNil:
          b.lineending = "\C"
      elif b.lineending.isNil:
        b.lineending = "\C\L"
    of '\t':
      for i in 1..tabWidth:
        b.front.add Cell(c: ' ')
    else:
      b.front.add Cell(c: s[i])

proc save*(b: Buffer) =
  if b.filename.len == 0: b.filename = b.heading
  let f = open(b.filename, fmWrite)
  if b.lineending.isNil:
    b.lineending = "\L"
  let L = b.len
  var i = 0
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
  b.changed = false

proc saveAs*(b: Buffer; filename: string) =
  b.filename = filename
  save(b)

proc insert*(b: Buffer; s: string) =
  prepareForEdit(b)
  setLen(b.actions, clamp(b.undoIdx+1, 0, b.actions.len))
  if b.actions.len > 0 and b.actions[^1].k == ins:
    b.actions[^1].word.add s
  else:
    b.actions.add(Action(k: ins, pos: b.cursor, word: s))
  if s[^1] in Whitespace: b.actions[^1].k = insFinished
  edit(b)
  rawInsert(b, s)

proc rawBackspace(b: Buffer): string =
  assert b.cursor == b.front.len
  var x = 0
  let ch = b.front[b.cursor-1].c
  if ch.ord < 128:
    x = 1
    if ch == '\L': dec b.numberOfLines
  else:
    while true:
      let (r, L) = lastRune(b, b.cursor-1-x)
      inc(x, L)
      if L > 1 and isCombining(r): discard
      else: break
  echo "DELETING ", b.cursor, " len ", x
  # we need to reverse this string here:
  result = newString(x)
  var j = 0
  for i in countdown(b.front.len-1, b.front.len-x):
    result[j] = b.front[i].c
    inc j
  b.cursor -= result.len
  b.front.setLen(b.cursor)

proc backspace*(b: Buffer) =
  if b.cursor <= 0: return
  prepareForEdit(b)
  setLen(b.actions, clamp(b.undoIdx+1, 0, b.actions.len))
  let ch = b.rawBackspace
  if b.actions.len > 0 and b.actions[^1].k == del:
    b.actions[^1].word.add ch
  else:
    b.actions.add(Action(k: del, pos: b.cursor, word: ch))
  edit(b)
  if ch.len == 1 and ch[0] in Whitespace: b.actions[^1].k = delFinished

proc applyUndo(b: Buffer; a: Action) =
  if a.k <= insFinished:
    b.cursor = a.pos + a.word.len
    prepareForEdit(b)
    b.cursor = a.pos
    # reverse op of insert is delete:
    b.front.setLen(b.cursor)
  else:
    b.cursor = a.pos
    prepareForEdit(b)
    # reverse op of delete is insert:
    for i in countdown(a.word.len-1, 0):
      b.front.add Cell(c: a.word[i])
    b.cursor += a.word.len

proc applyRedo(b: Buffer; a: Action) =
  if a.k <= insFinished:
    b.cursor = a.pos
    prepareForEdit(b)
    # reverse op of delete is insert:
    for i in countup(0, a.word.len-1):
      b.front.add Cell(c: a.word[i])
    b.cursor += a.word.len
  else:
    b.cursor = a.pos + a.word.len
    prepareForEdit(b)
    b.cursor = a.pos
    # reverse op of insert is delete:
    b.front.setLen(b.cursor)

proc undo*(b: Buffer) =
  when defined(debugUndo):
    echo "undo ----------------------------------------"
    for i, x in b.actions:
      if i == b.undoIdx:
        echo x, "*"
      else:
        echo x
  if b.undoIdx >= 0 and b.undoIdx < b.actions.len:
    applyUndo(b, b.actions[b.undoIdx])
    dec(b.undoIdx)

proc redo*(b: Buffer) =
  when defined(debugUndo):
    echo "redo ----------------------------------------"
    inc(b.undoIdx)
    for i, x in b.actions:
      if i == b.undoIdx:
        echo x, "*"
      else:
        echo x
  if b.undoIdx >= 0 and b.undoIdx < b.actions.len:
    applyRedo(b, b.actions[b.undoIdx])
  else:
    dec b.undoIdx
