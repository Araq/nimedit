
# Handling of styles.

import sdl2, sdl2/ttf
from strutils import parseHexInt, toLower
import languages

const
  FontSize* = 15

type
  FontStyle* {.pure.} = enum
    Normal, Bold, Italic, BoldItalic
  AFont* = object
    name: string
    size: byte
    fonts: array[FontStyle, FontPtr]
  FontManager* = seq[AFont]

  StyleIdx* = TokenClass
  FontAttr* = object
    color*: Color
    style*: FontStyle
    size*: byte

  Style* = object
    font*: FontPtr
    attr*: FontAttr

  StyleManager* = array[TokenClass, Style]

const
  FontStyleToSuffix: array[FontStyle, string] = ["", "bd", "i", "bi"]

proc fatal*(msg: string) {.noReturn.} =
  sdl2.quit()
  quit(msg)

proc parseColor*(hex: string): Color =
  let x = case hex.toLower
          of "white": 0xffffff
          of "orange": 0xFFA500
          of "blue": 0x00FFFF
          of "red": 0xFF0000
          of "yellow": 0xFFFF00
          of "pink": 0xFF00FF
          of "gray": 0x808080
          of "green": 0x00FF00
          of "deeppink": 0xFF1493
          else: parseHexInt(hex)
  result = color(x shr 16 and 0xff, x shr 8 and 0xff, x and 0xff, 0)

proc loadFont(path: string; size: byte): FontPtr =
  result = openFont(path, size.cint)
  if result.isNil:
    fatal("cannot load font " & path)

proc fontByName*(m: var FontManager; name: string; size: byte;
                 style=FontStyle.Normal): FontPtr =
  for f in m:
    if f.name == name and f.size == size: return f.fonts[style]
  var location = "fonts/"
  result = openFont(location & name & ".ttf", size.cint)
  if result.isNil:
    when defined(windows):
      location = r"C:\Windows\Fonts\"
      result = openFont(location & name & ".ttf", size.cint)
    else:
      discard "XXX implement for other OSes"
  if result.isNil:
    fatal("cannot load font: " & name)
  m.setLen m.len+1
  var p = addr m[^1]
  p.name = name
  p.size = size
  p.fonts[FontStyle.Normal] = result
  # now try to load the italic, bold etc versions, but if this fails, we
  # map the missing style to the normal style:
  for i in FontStyle.Bold .. FontStyle.BoldItalic:
    p.fonts[i] = openFont(location & name & FontStyleToSuffix[i] & ".ttf",
                          size.cint)
    if p.fonts[i].isNil: p.fonts[i] = result
  result = p.fonts[style]

proc freeFonts*(m: FontManager) =
  for f in m:
    for i in FontStyle.Bold .. FontStyle.BoldItalic:
      # if italic etc is not simply mapped to normal, free it
      if f.fonts[i] != f.fonts[FontStyle.Normal]: close(f.fonts[i])
    close(f.fonts[FontStyle.Normal])

proc findFont*(m: var FontManager; size: byte; style=FontStyle.Normal): FontPtr =
  fontByName(m, "DejaVuSansMono", size, style)

proc setStyle*(s: var StyleManager; m: var FontManager;
               idx: StyleIdx; attr: FontAttr) =
  s[idx] = Style(font: findFont(m, attr.size, attr.style), attr: attr)

proc getStyle*(s: StyleManager; i: StyleIdx): Style {.inline.} =
  result = s[i]
