# Loads NimEdit configuration from a .cfg file using parsecfg.

import std/[parsecfg, streams, strutils]
import nimscript/common, nimscript/keydefs
import styles, themes

proc parseHexColor(s: string): int =
  if s.startsWith("0x") or s.startsWith("0X"):
    result = parseHexInt(s)
  else:
    result = parseHexInt("0x" & s)

proc parseTokenValue(val: string): (int, FontStyle) =
  ## Parses "0xRRGGBB" or "0xRRGGBB, Style"
  let parts = val.split(',')
  result[0] = parseHexColor(parts[0].strip)
  if parts.len > 1:
    case parts[1].strip.toLowerAscii
    of "bold": result[1] = FontStyle.Bold
    of "italic": result[1] = FontStyle.Italic
    of "bolditalic": result[1] = FontStyle.BoldItalic
    else: result[1] = FontStyle.Normal
  else:
    result[1] = FontStyle.Normal

proc parseKeyName(name: string): Key =
  case name.toLowerAscii
  of "a": Key.A
  of "b": Key.B
  of "c": Key.C
  of "d": Key.D
  of "e": Key.E
  of "f": Key.F
  of "g": Key.G
  of "h": Key.H
  of "i": Key.I
  of "j": Key.J
  of "k": Key.K
  of "l": Key.L
  of "m": Key.M
  of "n": Key.N
  of "o": Key.O
  of "p": Key.P
  of "q": Key.Q
  of "r": Key.R
  of "s": Key.S
  of "t": Key.T
  of "u": Key.U
  of "v": Key.V
  of "w": Key.W
  of "x": Key.X
  of "y": Key.Y
  of "z": Key.Z
  of "n0", "0": Key.N0
  of "n1", "1": Key.N1
  of "n2", "2": Key.N2
  of "n3", "3": Key.N3
  of "n4", "4": Key.N4
  of "n5", "5": Key.N5
  of "n6", "6": Key.N6
  of "n7", "7": Key.N7
  of "n8", "8": Key.N8
  of "n9", "9": Key.N9
  of "f1": Key.F1
  of "f2": Key.F2
  of "f3": Key.F3
  of "f4": Key.F4
  of "f5": Key.F5
  of "f6": Key.F6
  of "f7": Key.F7
  of "f8": Key.F8
  of "f9": Key.F9
  of "f10": Key.F10
  of "f11": Key.F11
  of "f12": Key.F12
  of "enter", "return": Key.Enter
  of "space": Key.Space
  of "esc", "escape": Key.Esc
  of "shift": Key.Shift
  of "ctrl", "control": Key.Ctrl
  of "alt": Key.Alt
  of "apple", "cmd", "command", "super": Key.Apple
  of "del", "delete": Key.Del
  of "backspace": Key.Backspace
  of "ins", "insert": Key.Ins
  of "pageup": Key.PageUp
  of "pagedown": Key.PageDown
  of "left": Key.Left
  of "right": Key.Right
  of "up": Key.Up
  of "down": Key.Down
  of "capslock": Key.Capslock
  of "tab": Key.Tab
  of "comma": Key.Comma
  of "period": Key.Period
  of "keyreleased": Key.KeyReleased
  else:
    raise newException(ValueError, "unknown key: " & name)

proc parseKeyCombination(s: string): set[Key] =
  ## Parses "Ctrl+Shift+A" into {Ctrl, Shift, A}
  result = {}
  for part in s.split('+'):
    let p = part.strip
    if p.len > 0:
      result.incl parseKeyName(p)

proc parseActionValue(val: string): (Action, string) =
  ## Parses "ActionName" or "ActionName arg"
  let val = val.strip
  let spacePos = val.find(' ')
  if spacePos >= 0:
    let actionStr = val[0 ..< spacePos]
    result[0] = parseEnum[Action](actionStr)
    result[1] = val[spacePos + 1 .. ^1]
  else:
    result[0] = parseEnum[Action](val)
    result[1] = ""

type
  CfgTheme* = object
    editorFont*: string
    editorFontSize*: int
    uiFont*: string
    uiFontSize*: int
    foreground*, background*: int
    selected*, highlighted*: int
    cursor*: int
    cursorWidth*: int
    uiActiveElement*, uiInactiveElement*: int
    tabWidth*: int
    uiXGap*, uiYGap*: int
    consoleAfter*: int
    consoleWidth*: int
    lines*: int
    showLines*: bool
    bracket*: int
    showBracket*: bool
    showIndentation*: bool
    indentation*: int
    showMinimap*: bool
    showLigatures*: bool
    nimsuggestPath*: string

  CfgTokenStyle* = object
    color*: int
    style*: FontStyle

  CfgKeyBinding* = object
    keys*: set[Key]
    action*: Action
    arg*: string

  NimEditCfg* = object
    theme*: CfgTheme
    tokens*: array[TokenClass, CfgTokenStyle]
    keybindings*: seq[CfgKeyBinding]

proc initCfgTheme(): CfgTheme =
  result = CfgTheme(
    editorFont: "DejaVuSansMono",
    editorFontSize: 15,
    uiFont: "FreeSans",
    uiFontSize: 12,
    foreground: 0xfafafa,
    background: 0x292929,
    cursor: 0xfafafa,
    cursorWidth: 2,
    uiActiveElement: 0xFFA500,
    uiInactiveElement: 0xC0C0C0,
    tabWidth: 2,
    uiXGap: 5,
    uiYGap: 5,
    consoleAfter: 900,
    consoleWidth: 40,
    lines: 0x898989,
    selected: 0x000000,
    highlighted: 0x440000,
    showLines: true,
    showBracket: true,
    showIndentation: true,
    indentation: 0x898989,
    showMinimap: true,
    bracket: 0xFF1493,
    nimsuggestPath: ""
  )

proc loadCfg*(filename: string): NimEditCfg =
  result.theme = initCfgTheme()
  # default all tokens to white
  for tc in TokenClass:
    result.tokens[tc] = CfgTokenStyle(color: 0xffffff, style: FontStyle.Normal)

  var f = newFileStream(filename, fmRead)
  if f == nil:
    raise newException(IOError, "cannot open: " & filename)
  defer: f.close()

  var p: CfgParser
  open(p, f, filename)
  defer: close(p)

  var section = ""
  while true:
    var e = next(p)
    case e.kind
    of cfgEof: break
    of cfgSectionStart:
      section = e.section.toLowerAscii
    of cfgKeyValuePair:
      case section
      of "theme":
        let key = e.key
        let val = e.value
        case key.toLowerAscii
        of "editorfont": result.theme.editorFont = val
        of "editorfontsize": result.theme.editorFontSize = parseInt(val)
        of "uifont": result.theme.uiFont = val
        of "uifontsize": result.theme.uiFontSize = parseInt(val)
        of "uixgap": result.theme.uiXGap = parseInt(val)
        of "uiygap": result.theme.uiYGap = parseInt(val)
        of "uiactiveelement": result.theme.uiActiveElement = parseHexColor(val)
        of "uiinactiveelement": result.theme.uiInactiveElement = parseHexColor(val)
        of "background": result.theme.background = parseHexColor(val)
        of "foreground": result.theme.foreground = parseHexColor(val)
        of "cursor": result.theme.cursor = parseHexColor(val)
        of "cursorwidth": result.theme.cursorWidth = parseInt(val)
        of "lines": result.theme.lines = parseHexColor(val)
        of "selected": result.theme.selected = parseHexColor(val)
        of "highlighted": result.theme.highlighted = parseHexColor(val)
        of "showlines": result.theme.showLines = parseBool(val)
        of "showindentation": result.theme.showIndentation = parseBool(val)
        of "indentation": result.theme.indentation = parseHexColor(val)
        of "tabwidth": result.theme.tabWidth = parseInt(val)
        of "showbracket": result.theme.showBracket = parseBool(val)
        of "showminimap": result.theme.showMinimap = parseBool(val)
        of "bracket": result.theme.bracket = parseHexColor(val)
        of "consoleafter": result.theme.consoleAfter = parseInt(val)
        of "consolewidth": result.theme.consoleWidth = parseInt(val)
        of "showligatures": result.theme.showLigatures = parseBool(val)
        of "nimsuggestpath": result.theme.nimsuggestPath = val
        else: discard
      of "tokens":
        let tc = parseEnum[TokenClass](e.key)
        let (color, style) = parseTokenValue(e.value)
        result.tokens[tc] = CfgTokenStyle(color: color, style: style)
      of "keys":
        let keys = parseKeyCombination(e.key)
        let (action, arg) = parseActionValue(e.value)
        result.keybindings.add CfgKeyBinding(keys: keys, action: action, arg: arg)
      else: discard
    of cfgOption:
      discard
    of cfgError:
      raise newException(ValueError, e.msg)

proc applyTheme*(cfg: NimEditCfg; result: var InternalTheme;
                 sm: var StyleManager; fm: var FontManager) =
  let t = cfg.theme
  result.editorFont = t.editorFont
  result.editorFontSize = byte(t.editorFontSize)
  result.uiFont = t.uiFont
  result.uiFontSize = byte(t.uiFontSize)
  result.bg = colorFromInt(t.background)
  result.fg = colorFromInt(t.foreground)
  result.cursor = colorFromInt(t.cursor)
  result.cursorWidth = t.cursorWidth
  result.active[true] = colorFromInt(t.uiActiveElement)
  result.active[false] = colorFromInt(t.uiInactiveElement)
  result.uiXGap = t.uiXGap
  result.uiYGap = t.uiYGap
  result.tabWidth = t.tabWidth
  result.consoleAfter = t.consoleAfter
  result.consoleWidth = t.consoleWidth
  result.lines = colorFromInt(t.lines)
  result.showLines = t.showLines
  result.bracket = colorFromInt(t.bracket)
  result.showBracket = t.showBracket
  result.showIndentation = t.showIndentation
  result.indentation = colorFromInt(t.indentation)
  result.showMinimap = t.showMinimap
  result.showLigatures = t.showLigatures
  result.nimsuggestPath = t.nimsuggestPath

  sm.b[mcSelected] = colorFromInt(t.selected)
  sm.b[mcHighlighted] = colorFromInt(t.highlighted)

  let fontName = if t.editorFont.len > 0: t.editorFont
                 else: "DejaVuSansMono"
  let fontSize = byte(t.editorFontSize)
  for tc in TokenClass:
    let s = cfg.tokens[tc]
    let style = s.style
    sm.a[tc] = Style(
      font: fontByName(fm, fontName, fontSize, style),
      attr: FontAttr(color: colorFromInt(s.color),
                     style: style,
                     size: fontSize))
