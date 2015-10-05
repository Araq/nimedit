
include "../common"

type
  Color* = int
  Theme* = object
    editorFont*: string
    editorFontSize*: byte
    uiFont*: string
    uiFontSize*: byte
    foreground*, background*: Color
    selected*, highlighted*: Color
    cursor*: Color
    cursorWidth*: range[0..30]
    uiActiveElement*: Color
    uiInactiveElement*: Color
    tabWidth*: byte
    uiXGap*: Natural
    uiYGap*: Natural
    consoleAfter*: Natural
    consoleWidth*: Natural
    showLines*: bool

var
  theme* {.exportNims.}: Theme
  tokens* {.exportNims.}: array[TokenClass, (Color, FontStyle)]
