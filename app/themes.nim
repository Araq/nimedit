
import uirelays/screen

type
  InternalTheme* = object
    bg*, fg*, cursor*, lines*: Color
    active*: array[bool, Color]
    uiXGap*: Natural
    uiYGap*: Natural
    editorFont*: string
    editorFontSize*: byte
    uiFont*: string
    uiFontSize*: byte
    cursorWidth*: range[0..30]
    tabWidth*: Natural
    consoleAfter*: Natural
    consoleWidth*: Natural
    uiFontHandle*: Font
    editorFontHandle*: Font
    showLines*: bool
    bracket*: Color
    showBracket*, showIndentation*: bool
    indentation*: Color
    showMinimap*: bool
    showLigatures*: bool
    nimsuggestPath*: string

