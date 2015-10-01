
import styles, languages, common

type
  ActionKind* = enum
    ins, insFinished, dele, delFinished

  Action* = object
    k*: ActionKind
    pos*: int
    word*: string
  Cell* = object
    c*: char
    s*: TokenClass
  Marker* = object
    a*, b*: int
    replacement*: string

  Buffer* = ref object
    cursor*: Natural
    firstLine*, span*, numberOfLines*, currentLine*, desiredCol*: int
    firstLineOffset*: Natural
    mouseX*, mouseY*, clicks*, readOnly*: int
    front*, back*: seq[Cell]
    mgr*: ptr StyleManager
    actions*: seq[Action]
    undoIdx*: int
    changed*: bool
    tabSize*: int8  # we detect the tabsize on loading a document
    selected*: tuple[a, b: int]
    markers*: seq[Marker]
    activeMarker*: int
    heading*: string
    filename*: string
    lang*: SourceLanguage
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
      result = Cell(c: '\L')

proc setCellStyle*(b: Buffer; i: Natural; s: TokenClass) =
  if i < b.front.len:
    b.front[i].s = s
  else:
    let i = i-b.front.len
    if i <= b.back.high:
      b.back[b.back.high-i].s = s

proc `[]`*(b: Buffer; i: Natural): char {.inline.} = getCell(b, i).c

proc len*(b: Buffer): int {.inline.} = b.front.len+b.back.len
