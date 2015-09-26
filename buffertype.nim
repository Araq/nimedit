
import styles, languages

type
  ActionKind* = enum
    ins, insFinished, dele, delFinished

  Action* = object
    k*: ActionKind
    pos*: int
    word*: string
  Cell* = object
    c*: char
    s*: StyleIdx

  Buffer* = ref object
    cursor*: int
    firstLine*, span*, numberOfLines*, currentLine*, desiredCol*: int
    mouseX*, mouseY*, readOnly*: int
    front*, back*: seq[Cell]
    mgr*: ptr StyleManager
    #lines: seq[Line]
    actions*: seq[Action]
    undoIdx*: int
    changed*: bool
    heading*: string
    filename*: string
    lang*: SourceLanguage
    eofChar*: char
    next*, prev*: Buffer
    lineending*: string # CR-LF, CR or LF

proc getCell*(b: Buffer; i: Natural): Cell =
  if i < b.front.len:
    result = b.front[i]
  else:
    let i = i-b.front.len
    if i <= b.back.high:
      result = b.back[b.back.high-i]
    else:
      result = Cell(c: b.eofChar, s: StyleIdx(0))

proc setCellStyle*(b: Buffer; i: Natural; s: StyleIdx) =
  if i < b.front.len:
    b.front[i].s = s
  else:
    let i = i-b.front.len
    if i <= b.back.high:
      b.back[b.back.high-i].s = s

proc `[]`*(b: Buffer; i: Natural): char {.inline.} = getCell(b, i).c

proc len*(b: Buffer): int = b.front.len+b.back.len
