
from sdl2 import Color, RendererPtr
from sdl2/ttf import FontPtr

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
    consoleWidth*: Natural
    renderer*: RendererPtr
    uiFontPtr*: FontPtr
