
# Handling of styles.

import std/[strformat, strutils, decls]
import sdl2, sdl2/ttf
# from strutils import parseHexInt, toLower
import nimscript/common

when NimMajor >= 2:
  import std/[paths, dirs, files]
else:
  import std/os
  type Path = string

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

proc findFontFile(name: string): Path =
  ##[Returns the absolute path of the font file named `name`.tff.
     Otherwise, raises `IOError`.]##
  const AllFonts = when defined(linux): Path"/usr/share/fonts/truetype/"
    elif defined(windows): Path r"C:\Windows\Fonts\"
    elif defined(openIndiana): Path"/usr/share/fonts/TrueType/"
    else: quit "need to implement"
  once:
    if not AllFonts.dirExists:
      raise newException(IOError,
        fmt"Could not find system's font folder! '{AllFonts.string}' " &
          "doesn't exist.")

  let toMatch = name.Path.addFileExt("ttf")
  for file in AllFonts.walkDirRec():
    if file.extractFilename == toMatch.extractFilename: return file

  raise newException(IOError, fmt"Could not find font file '{toMatch.string}'!")

proc findStyledFontFile(mainFontFile: Path; style: FontStyle): Path =
  ##[Searches the directory that `mainFontFile` is in for a file that matches
     the given style `style`.
     If one cannot be found, raises an IOError.]##
  assert mainFontFile.fileExists, fmt"Bad font file '{mainFontFile.string}'"

  const Suffixes = [FontStyle.Normal: @[""], @["Bold"], @["Oblique", "Italic"],
    @["BoldOblique", "BoldItalic"]]

  let (mainDir, mainName, _) = mainFontFile.splitFile
  for file in mainDir.walkDirRec():
    let (_, currentName, _) = file.splitFile
    if mainName.string in currentName.string:
      for suffix in Suffixes[style]:
        if suffix in currentName.string: return file

  raise newException(IOError,
                     fmt"Could not find font file that matches style {style}!")

proc fatal*(msg: string) {.noReturn.} =
  sdl2.quit()
  quit(msg)

proc parseColor*(hex: string): Color =
  let x = parseHexInt(hex)
  result = color(x shr 16 and 0xff, x shr 8 and 0xff, x and 0xff, 0)

proc colorFromInt*(x: BiggestInt): Color =
  let x = x.int
  result = color(x shr 16 and 0xff, x shr 8 and 0xff, x and 0xff, 0)

proc openFont(p: Path; s: byte): FontPtr {.inline.} =
  ## Wrapper for `sdl2/ttf.openfont` with better typing.
  result = openFont(cstring(p), cint(s))

proc fontByName*(m: var FontManager; name: string; size: byte;
                 style=FontStyle.Normal): FontPtr =


  for f in m:
    if f.name == name and f.size == size: return f.fonts[style]

  let mainFontPath = findFontFile(name)

  result = openFont(mainFontPath, size)

  m.setLen m.len+1
  var p {.byAddr.} = m[^1]
  p.name = name
  p.size = size
  p.fonts[FontStyle.Normal] = result
  # now try to load the italic, bold etc versions, but if this fails, we
  # map the missing style to the normal style:
  for s, font in p.fonts.mpairs:
    try:
      font = openFont(findStyledFontFile(mainFontPath, s), size)
    except IOError:
      font = result
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
