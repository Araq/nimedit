
# Handling of styles.

import std/[strformat, strutils, decls]
import uirelays/[screen, input]
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
    fonts: array[FontStyle, Font]
  FontManager* = seq[AFont]

  FontAttr* = object
    color*: Color
    style*: FontStyle
    size*: byte

  Style* = object
    font*: Font
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
    elif defined(macosx): Path"/Library/Fonts/"
    else: quit "need to implement"
  once:
    if not AllFonts.dirExists:
      raise newException(IOError,
        fmt"Could not find system's font folder! '{AllFonts.string}' " &
          "doesn't exist.")

  let toMatch = name.Path.addFileExt("ttf")
  for file in AllFonts.walkDirRec({pcFile, pcLinkToFile}):
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
  quitRequest()
  quit(msg)

proc parseColor*(hex: string): Color =
  let x = parseHexInt(hex)
  color(uint8(x shr 16 and 0xff), uint8(x shr 8 and 0xff), uint8(x and 0xff), 255)

proc colorFromInt*(x: BiggestInt): Color =
  let x = x.int
  color(uint8(x shr 16 and 0xff), uint8(x shr 8 and 0xff), uint8(x and 0xff), 255)

proc openFontFromPath(p: Path; s: byte): Font {.inline.} =
  var metrics: FontMetrics
  screen.openFont(string(p), s.int, metrics)

proc fontByName*(m: var FontManager; name: string; size: byte;
                 style=FontStyle.Normal): Font =
  for f in m:
    if f.name == name and f.size == size: return f.fonts[style]

  let mainFontPath = findFontFile(name)
  result = openFontFromPath(mainFontPath, size)

  m.setLen m.len+1
  var p {.byAddr.} = m[^1]
  p.name = name
  p.size = size
  p.fonts[FontStyle.Normal] = result
  # now try to load the italic, bold etc versions, but if this fails, we
  # map the missing style to the normal style:
  for s, font in p.fonts.mpairs:
    if s == FontStyle.Normal: continue  # already loaded above
    try:
      font = openFontFromPath(findStyledFontFile(mainFontPath, s), size)
    except IOError:
      font = result
  result = p.fonts[style]

proc freeFonts*(m: FontManager) =
  for f in m:
    for i in FontStyle.Bold .. FontStyle.BoldItalic:
      if f.fonts[i] != f.fonts[FontStyle.Normal]: closeFont(f.fonts[i])
    closeFont(f.fonts[FontStyle.Normal])

proc getStyle*(s: StyleManager; i: TokenClass): Style {.inline.} =
  result = s.a[i]
