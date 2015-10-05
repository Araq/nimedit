
# Handling of styles.

import sdl2, sdl2/ttf
from strutils import parseHexInt, toLower
import languages, common

type
  MarkerClass* = enum
    mcSelected, mcHighlighted, mcBreakPoint

  AFont = object
    name: string
    size: byte
    fonts: array[FontStyle, FontPtr]
  FontManager* = seq[AFont]

  FontAttr* = object
    color*: Color
    style*: FontStyle
    size*: byte

  Style* = object
    font*: FontPtr
    attr*: FontAttr

  StyleManager* = object
    a*: array[TokenClass, Style]
    b*: array[MarkerClass, Color]

const
  FontStyleToSuffix: array[FontStyle, string] = ["", "bd", "i", "bi"]

proc fatal*(msg: string) {.noReturn.} =
  sdl2.quit()
  quit(msg)

proc parseColor*(hex: string): Color =
  let x = parseHexInt(hex)
  result = color(x shr 16 and 0xff, x shr 8 and 0xff, x and 0xff, 0)

proc colorFromInt*(x: BiggestInt): Color =
  let x = x.int
  result = color(x shr 16 and 0xff, x shr 8 and 0xff, x and 0xff, 0)

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
    elif defined(macosx):
      location = r"/System/Library/Fonts/"
      result = openFont(location & name & ".ttf", size.cint)
    elif defined(linux):
      location = r"/usr/share/fonts/truetype/msttcorefonts"
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

when false:
  proc findFont*(m: var FontManager; size: byte; style=FontStyle.Normal): FontPtr =
    fontByName(m, "DejaVuSansMono", size, style)

  proc setStyle*(s: var StyleManager; m: var FontManager;
                 idx: TokenClass; attr: FontAttr) =
    s.a[idx] = Style(font: findFont(m, attr.size, attr.style), attr: attr)

proc getStyle*(s: StyleManager; i: TokenClass): Style {.inline.} =
  result = s.a[i]
