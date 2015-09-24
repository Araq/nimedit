# Implementation uses a gap buffer with explicit undo stack.

import strutils
from unicode import reversed, lastRune, isCombining
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
    firstLine*, numberOfLines*, line*: int
    front, back: seq[Cell]
    mgr: ptr StyleManager
    #lines: seq[Line]
    actions: seq[Action]
    undoIdx: int
    next*, prev*: Buffer
    changed*: bool
    heading*: string
    filename*: string

proc getCell(b: Buffer; i: int): Cell =
  if i < b.front.len:
    result = b.front[i]
  else:
    let i = i-b.front.len
    if i <= b.back.high:
      result = b.back[b.back.high-i]
    else:
      result = Cell(c: '\L', s: StyleIdx(0))

proc length(b: Buffer): int = b.front.len+b.back.len

include drawbuffer

proc newBuffer*(heading: string; mgr: ptr StyleManager): Buffer =
  new(result)
  result.front = @[]
  result.back = @[]
  result.filename = ""
  result.heading = heading
  result.actions = @[]
  result.mgr = mgr

proc loadFromFile*(b: Buffer; filename: string) =
  b.filename = filename

proc clear*(result: Buffer) =
  result.front.setLen 0
  result.back.setLen 0
  result.actions.setLen 0

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
    for i in countup(b.cursor, b.front.len-1):
      b.back.add(b.front[i])
    setLen(b.front, b.cursor)
  elif b.cursor > b.front.len:
    let chars = max(b.cursor - b.front.len, 0)
    var took = 0
    for i in countdown(b.back.len-1, max(b.back.len-chars, 0)):
      b.front.add(b.back[i])
      inc took
    setLen(b.back, b.back.len - took)

proc left*(b: Buffer; jump: bool) =
  if b.cursor > 0:
    b.cursor -= 1
    #prepareForEdit(b)

proc right*(b: Buffer; jump: bool) =
  if b.cursor < b.front.len+b.back.len:
    b.cursor += 1
    #prepareForEdit(b)

proc getColumn*(b: Buffer): int =
  # XXX care about Unicode here
  var i = b.cursor
  while i >= 0:
    if b.getCell(i).c == '\L': break
    dec i
    inc result

proc up*(b: Buffer; jump: bool) =
  var col = getColumn(b)
  while b.cursor >= 0:
    if b.getCell(b.cursor).c == '\L': break
    b.cursor -= 1
  b.cursor -= 1
  while b.cursor >= 0 and col > 0:
    if b.getCell(b.cursor).c == '\L': break
    b.cursor -= 1
    dec col
  if b.cursor < 0: b.cursor = 0
  #prepareForEdit(b)

proc down*(b: Buffer; jump: bool) =
  var col = getColumn(b)

  let L = b.front.len+b.back.len
  while b.cursor < L:
    if b.getCell(b.cursor).c == '\L': break
    b.cursor += 1
  b.cursor += 1

  while b.cursor < L and col > 0:
    if b.getCell(b.cursor).c == '\L': break
    dec col
    b.cursor += 1
  if b.cursor >= L: b.cursor = L-1

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
  var x = 0
  let ch = b.front[^1].c
  if ch.ord < 128:
    x = 1
    if ch == '\L': dec b.numberOfLines
  else:
    var bf = newStringOfCap(20)
    for i in b.front.len-20 .. b.front.len-1:
      if i >= 0 and i < b.front.len:
        bf.add b.front[i].c
    while true:
      let (r, L) = lastRune(bf, bf.len-1-x)
      inc(x, L)
      if L > 1 and isCombining(r): discard
      else: break
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
