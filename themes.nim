
from sdl2 import Color

type
  InternalTheme* = object
    bg*, fg*, cursor*: Color
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
