#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Source highlighter for programming or markup languages.
## Currently only few languages are supported, other languages may be added.
## The interface supports one language nested in another.

import
  strutils, buffertype, styles, languages

from sdl2 import Color

type
  GeneralTokenizer* = object
    kind*: TokenClass
    start*, length*: int
    buf: Buffer
    pos: int
    state: TokenClass

const
  # The following list comes from doc/keywords.txt, make sure it is
  # synchronized with this array by running the module itself as a test case.
  nimKeywords = ["addr", "and", "as", "asm", "atomic", "bind", "block",
    "break", "case", "cast", "concept", "const", "continue", "converter",
    "defer", "discard", "distinct", "div", "do",
    "elif", "else", "end", "enum", "except", "export",
    "finally", "for", "from", "func",
    "generic", "if", "import", "in", "include",
    "interface", "is", "isnot", "iterator", "let", "macro", "method",
    "mixin", "mod", "nil", "not", "notin", "object", "of", "or", "out", "proc",
    "ptr", "raise", "ref", "return", "shl", "shr", "static",
    "template", "try", "tuple", "type", "using", "var", "when", "while", "with",
    "without", "xor", "yield"]

proc nimGetKeyword(id: string): TokenClass =
  for k in nimKeywords:
    if cmpIgnoreStyle(id, k) == 0: return gtKeyword
  result = gtIdentifier

proc nimNumberPostfix(g: var GeneralTokenizer, position: int): int =
  var pos = position
  if g.buf[pos] == '\'': inc(pos)
  case g.buf[pos]
  of 'd', 'D':
    g.kind = gtFloatNumber
    inc(pos)
  of 'f', 'F':
    g.kind = gtFloatNumber
    inc(pos)
    if g.buf[pos] in {'0'..'9'}: inc(pos)
    if g.buf[pos] in {'0'..'9'}: inc(pos)
  of 'i', 'I', 'u', 'U':
    inc(pos)
    if g.buf[pos] in {'0'..'9'}: inc(pos)
    if g.buf[pos] in {'0'..'9'}: inc(pos)
  else:
    discard
  result = pos

proc nimNumber(g: var GeneralTokenizer, position: int): int =
  const decChars = {'0'..'9', '_'}
  var pos = position
  g.kind = gtDecNumber
  while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] == '.':
    if g.buf[pos+1] == '.': return pos
    g.kind = gtFloatNumber
    inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] in {'e', 'E'}:
    g.kind = gtFloatNumber
    inc(pos)
    if g.buf[pos] in {'+', '-'}: inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  result = nimNumberPostfix(g, pos)

const
  OpChars  = {'+', '-', '*', '/', '\\', '<', '>', '!', '?', '^', '.',
              '|', '=', '%', '&', '$', '@', '~', ':', '\x80'..'\xFF'}

proc nimNextToken(g: var GeneralTokenizer) =
  const
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f', '_'}
    octChars = {'0'..'7', '_'}
    binChars = {'0'..'1', '_'}
    SymChars = {'a'..'z', 'A'..'Z', '0'..'9', '\x80'..'\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit:
    g.kind = gtStringLit
    while pos < g.buf.len:
      case g.buf[pos]
      of '\\':
        g.kind = gtEscapeSequence
        inc(pos)
        case g.buf[pos]
        of 'x', 'X':
          inc(pos)
          if g.buf[pos] in hexChars: inc(pos)
          if g.buf[pos] in hexChars: inc(pos)
        of '0'..'9':
          while g.buf[pos] in {'0'..'9'}: inc(pos)
        else: inc(pos)
        break
      of '\L', '\C':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else:
        inc(pos)
  elif g.state == gtLongStringLit:
    g.kind = gtLongStringLit
    while pos < g.buf.len:
      if g.buf[pos] == '\"':
        inc(pos)
        if g.buf[pos] == '\"' and g.buf[pos+1] == '\"' and
            g.buf[pos+2] != '\"':
          inc(pos, 2)
          break
      else:
        inc(pos)
    g.state = gtNone
  else:
    case g.buf[pos]
    of ' ', '\x09'..'\x0D':
      g.kind = gtWhitespace
      while pos < g.buf.len and g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
    of '#':
      if g.buf[pos+1] == '#': g.kind = gtLongComment
      else: g.kind = gtComment
      while g.buf[pos] != '\L': inc(pos)
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in SymChars + {'_'}:
        add(id, g.buf[pos])
        inc(pos)
      if (g.buf[pos] == '\"'):
        if (g.buf[pos + 1] == '\"') and (g.buf[pos + 2] == '\"'):
          inc(pos, 3)
          g.kind = gtLongStringLit
          while pos < g.buf.len:
            if g.buf[pos] == '\"':
              inc(pos)
              if g.buf[pos] == '\"' and g.buf[pos+1] == '\"' and
                  g.buf[pos+2] != '\"':
                inc(pos, 2)
                break
            else:
              inc(pos)
        else:
          g.kind = gtRawData
          inc(pos)
          while g.buf[pos] != '\L':
            if g.buf[pos] == '"' and g.buf[pos+1] != '"': break
            inc(pos)
          if g.buf[pos] == '\"': inc(pos)
      else:
        g.kind = nimGetKeyword(id)
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        inc(pos)
        while g.buf[pos] in binChars: inc(pos)
        pos = nimNumberPostfix(g, pos)
      of 'x', 'X':
        inc(pos)
        while g.buf[pos] in hexChars: inc(pos)
        pos = nimNumberPostfix(g, pos)
      of 'o', 'O':
        inc(pos)
        while g.buf[pos] in octChars: inc(pos)
        pos = nimNumberPostfix(g, pos)
      else: pos = nimNumber(g, pos)
    of '1'..'9':
      pos = nimNumber(g, pos)
    of '\'':
      inc(pos)
      g.kind = gtCharLit
      while true:
        case g.buf[pos]
        of '\L':
          break
        of '\'':
          inc(pos)
          break
        of '\\':
          inc(pos, 2)
        else:
          inc(pos)
    of '\"':
      inc(pos)
      if (g.buf[pos] == '\"') and (g.buf[pos + 1] == '\"'):
        inc(pos, 2)
        g.kind = gtLongStringLit
        while pos < g.buf.len:
          if g.buf[pos] == '\"':
            inc(pos)
            if g.buf[pos] == '\"' and g.buf[pos+1] == '\"' and
                g.buf[pos+2] != '\"':
              inc(pos, 2)
              break
          else:
            inc(pos)
      else:
        g.kind = gtStringLit
        while true:
          case g.buf[pos]
          of '\L':
            break
          of '\"':
            inc(pos)
            break
          of '\\':
            g.state = g.kind
            break
          else:
            inc(pos)
    of '(', ')', '[', ']', '{', '}', '`', ':', ',', ';':
      inc(pos)
      g.kind = gtPunctuation
    else:
      if g.buf[pos] in OpChars:
        g.kind = gtOperator
        while g.buf[pos] in OpChars: inc(pos)
      else:
        if pos < g.buf.len: inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  g.pos = pos

proc generalNumber(g: var GeneralTokenizer, position: int): int =
  const decChars = {'0'..'9'}
  var pos = position
  g.kind = gtDecNumber
  while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] == '.':
    g.kind = gtFloatNumber
    inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] in {'e', 'E'}:
    g.kind = gtFloatNumber
    inc(pos)
    if g.buf[pos] in {'+', '-'}: inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  result = pos

proc generalStrLit(g: var GeneralTokenizer, position: int): int =
  const
    decChars = {'0'..'9'}
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f'}
  var pos = position
  g.kind = gtStringLit
  var c = g.buf[pos]
  inc(pos)                    # skip " or '
  while pos < g.buf.len:
    case g.buf[pos]
    of '\\':
      inc(pos)
      case g.buf[pos]
      of '0'..'9':
        while g.buf[pos] in decChars: inc(pos)
      of 'x', 'X':
        inc(pos)
        if g.buf[pos] in hexChars: inc(pos)
        if g.buf[pos] in hexChars: inc(pos)
      else:
        inc(pos, 2)
    else:
      if g.buf[pos] == c:
        inc(pos)
        break
      else:
        inc(pos)
  result = pos

proc isKeyword(x: openArray[string], y: string): int =
  var a = 0
  var b = len(x) - 1
  while a <= b:
    var mid = (a + b) div 2
    var c = cmp(x[mid], y)
    if c < 0:
      a = mid + 1
    elif c > 0:
      b = mid - 1
    else:
      return mid
  result = - 1

proc isKeywordIgnoreCase(x: openArray[string], y: string): int =
  var a = 0
  var b = len(x) - 1
  while a <= b:
    var mid = (a + b) div 2
    var c = cmpIgnoreCase(x[mid], y)
    if c < 0:
      a = mid + 1
    elif c > 0:
      b = mid - 1
    else:
      return mid
  result = - 1

type
  TokenizerFlag = enum
    hasPreprocessor, hasNestedComments
  TokenizerFlags = set[TokenizerFlag]

proc clikeNextToken(g: var GeneralTokenizer, keywords: openArray[string],
                    flags: TokenizerFlags) =
  const
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f'}
    octChars = {'0'..'7'}
    binChars = {'0'..'1'}
    symChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '\x80'..'\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit:
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\\':
        g.kind = gtEscapeSequence
        inc(pos)
        case g.buf[pos]
        of 'x', 'X':
          inc(pos)
          if g.buf[pos] in hexChars: inc(pos)
          if g.buf[pos] in hexChars: inc(pos)
        of '0'..'9':
          while g.buf[pos] in {'0'..'9'}: inc(pos)
        else: inc(pos)
        break
      of '\L':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else: inc(pos)
  elif g.state == gtLongComment:
    var nested = 0
    g.kind = gtLongComment
    while pos < g.buf.len:
      case g.buf[pos]
      of '*':
        inc(pos)
        if g.buf[pos] == '/':
          inc(pos)
          if nested == 0: break
      of '/':
        inc(pos)
        if g.buf[pos] == '*':
          inc(pos)
          if hasNestedComments in flags: inc(nested)
      else: inc(pos)
    g.state = gtNone
  else:
    case g.buf[pos]
    of ' ', '\x09'..'\x0D':
      g.kind = gtWhitespace
      while pos < g.buf.len and g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
    of '/':
      inc(pos)
      if g.buf[pos] == '/':
        g.kind = gtComment
        while g.buf[pos] != '\L': inc(pos)
      elif g.buf[pos] == '*':
        g.kind = gtLongComment
        var nested = 0
        inc(pos)
        while pos < g.buf.len:
          case g.buf[pos]
          of '*':
            inc(pos)
            if g.buf[pos] == '/':
              inc(pos)
              if nested == 0: break
          of '/':
            inc(pos)
            if g.buf[pos] == '*':
              inc(pos)
              if hasNestedComments in flags: inc(nested)
          else: inc(pos)
    of '#':
      inc(pos)
      if hasPreprocessor in flags:
        g.kind = gtPreprocessor
        while g.buf[pos] in {' ', '\t'}: inc(pos)
        while g.buf[pos] in symChars: inc(pos)
      else:
        g.kind = gtOperator
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(keywords, id) >= 0: g.kind = gtKeyword
      else: g.kind = gtIdentifier
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        inc(pos)
        while g.buf[pos] in binChars: inc(pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
      of 'x', 'X':
        inc(pos)
        while g.buf[pos] in hexChars: inc(pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
      of '0'..'7':
        inc(pos)
        while g.buf[pos] in octChars: inc(pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
      else:
        pos = generalNumber(g, pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
    of '1'..'9':
      pos = generalNumber(g, pos)
      if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
    of '\'':
      pos = generalStrLit(g, pos)
      g.kind = gtCharLit
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      while pos < g.buf.len:
        case g.buf[pos]
        of '\"':
          inc(pos)
          break
        of '\\':
          g.state = g.kind
          break
        else:
          inc(pos)
    of '(', ')', '[', ']', '{', '}', ':', ',', ';', '.':
      inc(pos)
      g.kind = gtPunctuation
    else:
      if g.buf[pos] in OpChars:
        g.kind = gtOperator
        while g.buf[pos] in OpChars: inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  g.pos = pos

proc consoleNextToken(g: var GeneralTokenizer) =
  template fallback() =
    g.kind = gtNone
    if pos < g.buf.len: inc pos

  template diff(col) =
    if pos > 0 and g.buf[pos-1] == '\L':
      g.kind = col
      while g.buf[pos] != '\L': inc pos
    else:
      fallback()

  const symChars = {'A'..'Z', 'a'..'z', '0'..'9', '_'}
  var pos = g.pos
  g.start = g.pos
  let c = g.buf[pos]
  case c
  of 'a'..'z', 'A'..'Z', '_', '/', '\\', '\x80'..'\xFF':
    var id = $c.toLower
    inc pos
    var dotPos = -1
    while true:
      let c = g.buf[pos]
      if c == '.':
        dotPos = pos
        add(id, '.')
        inc(pos)
      elif c in (symChars+{'/','\\',':','\x80'..'\xFF'}):
        add(id, c.toLower)
        inc(pos)
      else:
        break
    case id
    of "error:", "fatal:": g.kind = gtRed
    of "warning:": g.kind = gtYellow
    of "hint:": g.kind = gtGreen
    else:
      if dotpos >= 0 and dotpos < pos-1:
        g.kind = gtLink
        # filenames can also have optional line information like (line, pos):
        if g.buf[pos] == '(':
          var p = pos+1
          if g.buf[p] in Digits:
            while g.buf[p] in Digits: inc p
            if g.buf[p] == ',':
              inc p
              while g.buf[p] == ' ': inc p
              while g.buf[p] in Digits: inc p
            if g.buf[p] == ')': pos = p+1
      else:
        g.kind = gtIdentifier
  of '[':
    if pos > 0 and g.buf[pos-1] == ' ' and g.buf[pos+1] in Letters:
      inc pos
      let rollback = pos
      while g.buf[pos] in Letters: inc pos
      if g.buf[pos] == ']':
        inc pos
        g.kind = gtRule
      else:
        g.kind = gtNone
        pos = rollback
    else:
      fallback()
  of '+': diff(gtGreen)
  of '-': diff(gtRed)
  of '@':
    if g.buf[pos+1] == '@':
      g.kind = gtDirective
      inc pos, 2
      while g.buf[pos] != '\L':
        if g.buf[pos] == '@' and g.buf[pos+1] == '@':
          inc pos, 2
          break
        inc pos
    else:
      fallback()
  else:
    fallback()
  g.length = pos - g.pos
  g.pos = pos


proc cNextToken(g: var GeneralTokenizer) =
  const
    keywords: array[0..36, string] = ["_Bool", "_Complex", "_Imaginary", "auto",
      "break", "case", "char", "const", "continue", "default", "do", "double",
      "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int",
      "long", "register", "restrict", "return", "short", "signed", "sizeof",
      "static", "struct", "switch", "typedef", "union", "unsigned", "void",
      "volatile", "while"]
  clikeNextToken(g, keywords, {hasPreprocessor})

proc cppNextToken(g: var GeneralTokenizer) =
  const
    keywords: array[0..47, string] = ["asm", "auto", "break", "case", "catch",
      "char", "class", "const", "continue", "default", "delete", "do", "double",
      "else", "enum", "extern", "float", "for", "friend", "goto", "if",
      "inline", "int", "long", "new", "operator", "private", "protected",
      "public", "register", "return", "short", "signed", "sizeof", "static",
      "struct", "switch", "template", "this", "throw", "try", "typedef",
      "union", "unsigned", "virtual", "void", "volatile", "while"]
  clikeNextToken(g, keywords, {hasPreprocessor})

proc csharpNextToken(g: var GeneralTokenizer) =
  const
    keywords: array[0..76, string] = ["abstract", "as", "base", "bool", "break",
      "byte", "case", "catch", "char", "checked", "class", "const", "continue",
      "decimal", "default", "delegate", "do", "double", "else", "enum", "event",
      "explicit", "extern", "false", "finally", "fixed", "float", "for",
      "foreach", "goto", "if", "implicit", "in", "int", "interface", "internal",
      "is", "lock", "long", "namespace", "new", "null", "object", "operator",
      "out", "override", "params", "private", "protected", "public", "readonly",
      "ref", "return", "sbyte", "sealed", "short", "sizeof", "stackalloc",
      "static", "string", "struct", "switch", "this", "throw", "true", "try",
      "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using",
      "virtual", "void", "volatile", "while"]
  clikeNextToken(g, keywords, {hasPreprocessor})

proc javaNextToken(g: var GeneralTokenizer) =
  const
    keywords: array[0..52, string] = ["abstract", "assert", "boolean", "break",
      "byte", "case", "catch", "char", "class", "const", "continue", "default",
      "do", "double", "else", "enum", "extends", "false", "final", "finally",
      "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
      "interface", "long", "native", "new", "null", "package", "private",
      "protected", "public", "return", "short", "static", "strictfp", "super",
      "switch", "synchronized", "this", "throw", "throws", "transient", "true",
      "try", "void", "volatile", "while"]
  clikeNextToken(g, keywords, {})

proc getNextToken(g: var GeneralTokenizer, lang: SourceLanguage) =
  case lang
  of langNone: assert false
  of langNim, langNimrod: nimNextToken(g)
  of langCpp: cppNextToken(g)
  of langCsharp: csharpNextToken(g)
  of langC: cNextToken(g)
  of langJava: javaNextToken(g)
  of langConsole: consoleNextToken(g)

proc setStyle(s: var StyleManager; m: var FontManager;
              cls: TokenClass; col: string; style: FontStyle) =
  s.setStyle m, cls, FontAttr(color: parseColor(col),
                              style: style, size: FontSize)

proc setStyles*(s: var StyleManager; m: var FontManager) =
  template ss(key, val; style = FontStyle.Normal) =
    s.setStyle m, key, val, style

  ss gtNone, "White"
  ss gtWhitespace, "White"
  ss gtDecNumber, "Blue"
  ss gtBinNumber, "Blue"
  ss gtHexNumber, "Blue"
  ss gtOctNumber, "Blue"
  ss gtFloatNumber, "Blue"
  ss gtIdentifier, "White"
  ss gtKeyword, "White", FontStyle.Bold
  ss gtStringLit, "Orange"
  ss gtLongStringLit, "Orange"
  ss gtCharLit, "Orange"
  ss gtEscapeSequence, "Gray"
  ss gtOperator, "White"
  ss gtPunctuation, "White"
  ss gtComment, "Green", FontStyle.Italic
  ss gtLongComment, "DeepPink"
  ss gtRegularExpression, "Pink"
  ss gtTagStart, "Yellow"
  ss gtTagEnd, "Yellow"
  ss gtKey, "White"
  ss gtValue, "Blue"
  ss gtRawData, "Pink"
  ss gtAssembler, "Pink"
  ss gtPreprocessor, "Yellow"
  ss gtDirective, "Yellow"
  ss gtCommand, "Yellow"
  ss gtRule, "Yellow"
  ss gtLink, "Blue", FontStyle.Bold
  ss gtLabel, "Blue"
  ss gtReference, "Blue"
  ss gtOther, "White"
  ss gtRed, "Red"
  ss gtGreen, "Green"
  ss gtYellow, "Yellow"


proc highlight(b: Buffer; first, last: int;
               initialState: TokenClass) =
  var g: GeneralTokenizer
  g.buf = b
  g.kind = low(TokenClass)
  g.start = first
  g.length = 0
  g.state = initialState
  g.pos = first
  while g.pos <= last:
    getNextToken(g, b.lang)
    if g.length == 0: break
    for i in 0 ..< g.length:
      b.setCellStyle(g.start+i, g.kind)

proc isCriticalDelete*(b: Buffer; deleted: seq[Cell]) =
  discard

proc highlightLine*(b: Buffer; oldCursor: int) =
  # Updating everything turned out to be way too slow even for files of
  # moderate size.
  if b.lang != langNone:
    # move to the *start* of this line
    var i = oldCursor
    while i >= 1 and b[i-1] != '\L': dec i
    let first = i
    i = b.cursor-1
    while b[i] != '\L': inc i
    let last = i
    let initialState = if first == 0: gtNone else: getCell(b, first-1).s
    highlight(b, first, last, initialState)

proc highlightEverything*(b: Buffer) =
  if b.lang != langNone:
    highlight(b, 0, b.len-1, gtNone)


when isMainModule:
  var keywords: seq[string]
  # Try to work running in both the subdir or at the root.
  for filename in ["doc/keywords.txt", "../../../doc/keywords.txt"]:
    try:
      let input = string(readFile(filename))
      keywords = input.split()
      break
    except:
      echo filename, " not found"
  doAssert(not keywords.isNil, "Couldn't read any keywords.txt file!")
  doAssert keywords.len == nimKeywords.len, "No matching lengths"
  for i in 0..keywords.len-1:
    #echo keywords[i], " == ", nimKeywords[i]
    doAssert keywords[i] == nimKeywords[i], "Unexpected keyword"
