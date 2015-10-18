
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
    consoleAfter*: int
    consoleWidth*: Natural
    lines*: Color
    showLines*: bool
    bracket*: Color
    showBracket*: bool
    showIndentation*: bool
    indentation*: Color

var
  theme* {.exportNims.}: Theme
  tokens* {.exportNims.}: array[TokenClass, (Color, FontStyle)]
