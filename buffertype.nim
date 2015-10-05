
import styles, languages, common

type
  ActionKind* = enum
    ins, insFinished, dele, delFinished

  Action* = object  # we group undo actions by a document version, so that
                    # operations like 'indent' which consist of multiple
                    # deletes and inserts are undone by a single undo command.
    k*: ActionKind
    pos*, version*: int
    word*: string
  Cell* = object
    c*: char
    s*: TokenClass
  Marker* = object
    a*, b*: int
    replacement*: string

  Buffer* = ref object
    cursor*: Natural
    firstLine*, currentLine*, desiredCol*, numberOfLines*: Natural
    span*: int
    firstLineOffset*: Natural
    bracketToHighlight*: int
    mouseX*, mouseY*, clicks*, readOnly*: int
    version*: int  # document version; used to group undo actions
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
