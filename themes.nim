
import textrenderer
from sdl2 import nil

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
    renderer*: RendererPtr
    uiFontPtr*: FontPtr
    editorFontPtr*: FontPtr
    showLines*: bool
    bracket*: Color
    showBracket*, showIndentation*: bool
    indentation*: Color
    showMinimap*: bool
    showLigatures*: bool
    nimsuggestPath*: string

proc sdlrend*(x: InternalTheme): sdl2.RendererPtr =
  when defined(useNimx):
    x.renderer.sd
  else:
    x.renderer
