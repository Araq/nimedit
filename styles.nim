
# Handling of styles. Up to 255 different styles are supported.

import sdl2, sdl2/ttf
from strutils import parseHexInt

const
  FontSize* = 15

type
  StyleIdx* = distinct byte
  FontAttr* = object
    bold*, italic*: bool
    size*: byte
    color*: Color

  Style* = object
    font*: FontPtr
    attr*: FontAttr

  StyleManager* = object
    a: array[0..255, Style]
    L: int

proc fatal*(msg: string) {.noReturn.} =
  sdl2.quit()
  quit(msg)

proc parseColor*(hex: string): Color =
  let x = parseHexInt(hex)
  result = color(x shr 16 and 0xff, x shr 8 and 0xff, x and 0xff, 0)

proc loadFont*(path: string; size: byte): FontPtr =
  result = openFont(path, size.cint)
  if result.isNil:
    fatal("cannot load font " & path)

proc getStyle*(s: var StyleManager; font: FontPtr; attr: FontAttr): StyleIdx =
  for i in 0..<s.L:
    let x = addr(s.a[i])
    if x.font == font and x.attr == attr: return StyleIdx(i)
  doAssert(s.L < 254, "too many different styles requested")
  result = StyleIdx(s.L)
  s.a[s.L] = Style(font: font, attr: attr)
  inc s.L

proc getStyle*(s: var StyleManager; attr: FontAttr): StyleIdx =
  for i in 0..<s.L:
    let x = addr(s.a[i])
    if x.attr == attr: return StyleIdx(i)
  doAssert(s.L < 254, "too many different styles requested")
  result = StyleIdx(s.L)
  let suffix = if attr.bold and attr.italic:
                 "-BoldOblique.ttf"
               elif attr.bold:
                 "-Bold.ttf"
               elif attr.italic:
                 "-Oblique.ttf"
               else:
                 ".ttf"
  let font = loadFont("fonts/DejaVuSansMono" & suffix, attr.size)
  s.a[s.L] = Style(font: font, attr: attr)
  inc s.L

proc getStyle*(s: StyleManager; i: StyleIdx): Style {.inline.} =
  assert i.int < s.L
  result = s.a[i.int]

proc freeFonts*(s: StyleManager) =
  for i in 0..<s.L: close(s.a[i].font)
