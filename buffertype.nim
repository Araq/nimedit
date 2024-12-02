
import styles, nimscript/common, intsets, compiler/ast, tables
from times import Time
from sdl2 import Rect

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

  Indexer* = object ## information that an indexer requires per buffer
    version*: int   # the version of the document that was indexed
    currentlyIndexing*: int # the version we're currently indexing. Need to
                            # start from scratch if the buffer changed in
                            # between.
    position*: int  # the position where it left off

  ScrollBarState* = object
    case usingScrollbar*: bool ## if the user is dragging the scrollbar or not
    of true:
      initiallyGrippedAt*: cint ##[the relative y position from the top of the
        scrollbar that the user first clicked on.]##
    of false:
      discard

  Buffer* = ref object
    cursor*: Natural
    firstLine*, currentLine*, desiredCol*, numberOfLines*, runningLine*: Natural
    span*: int
    firstLineOffset*: Natural
    bracketToHighlightA*, bracketToHighlightB*: int
    mouseX*, mouseY*, clicks*, readOnly*: int
    version*: int  # document version; used to group undo actions
    front*, back*: seq[Cell]
    mgr*: ptr StyleManager
    actions*: seq[Action]
    undoIdx*: int
    changed*: bool
    filterLines*: bool
    isSmall*: bool
    tabSize*: int8  # we detect the tabsize on loading a document
    selected*: tuple[a, b: int]
    markers*: seq[Marker]
    activeMarker*: int
    heading*: string
    filename*: string
    lang*: SourceLanguage
    next*, prev*: Buffer
    lineending*: string # CR-LF, CR or LF
    indexer*, highlighter*: Indexer
    cursorDim*: tuple[x, y, h: int]
    timestamp*: Time
    activeLines*: IntSet
    minimapVersion*: int
    posHint*: Rect
    symtab*: TStrTable
    offsetToLineCache*: array[20, tuple[version, offset, line: int]]
    breakpoints*: Table[int, TokenClass]
    scrollState*: ScrollBarState

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
