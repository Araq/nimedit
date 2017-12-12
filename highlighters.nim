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
  strutils, buffertype, styles, languages, nimscript/common

from sdl2 import Color

type
  GeneralTokenizer* = object
    kind*: TokenClass
    start*, length*: int
    buf: Buffer
    pos: int
    state: TokenClass

include "highlighters/xml"

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
    if cmpIgnoreStyle(id, k) == 0: return TokenClass.Keyword
  result = TokenClass.Identifier

proc nimNumberPostfix(g: var GeneralTokenizer, position: int): int =
  var pos = position
  if g.buf[pos] == '\'': inc(pos)
  case g.buf[pos]
  of 'd', 'D':
    g.kind = TokenClass.FloatNumber
    inc(pos)
  of 'f', 'F':
    g.kind = TokenClass.FloatNumber
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
  g.kind = TokenClass.DecNumber
  while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] == '.':
    if g.buf[pos+1] == '.': return pos
    g.kind = TokenClass.FloatNumber
    inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] in {'e', 'E'}:
    g.kind = TokenClass.FloatNumber
    inc(pos)
    if g.buf[pos] in {'+', '-'}: inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  result = nimNumberPostfix(g, pos)

const
  OpChars  = {'+', '-', '*', '/', '\\', '<', '>', '!', '?', '^', '.',
              '|', '=', '%', '&', '$', '@', '~', ':', '\x80'..'\xFF'}

proc nimMultilineComment(g: var GeneralTokenizer; pos: int;
                          isDoc: bool): int =
  var pos = pos
  var nesting = 0
  while pos < g.buf.len:
    case g.buf[pos]
    of '#':
      if isDoc:
        if g.buf[pos+1] == '#' and g.buf[pos+2] == '[':
          inc nesting
      elif g.buf[pos+1] == '[':
        inc nesting
      inc pos
    of ']':
      if isDoc:
        if g.buf[pos+1] == '#' and g.buf[pos+2] == '#':
          if nesting == 0:
            inc(pos, 3)
            break
          dec nesting
      elif g.buf[pos+1] == '#':
        if nesting == 0:
          inc(pos, 2)
          break
        dec nesting
      inc pos
    else:
      inc pos
  result = pos

proc nimNextToken(g: var GeneralTokenizer) =
  const
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f', '_'}
    octChars = {'0'..'7', '_'}
    binChars = {'0'..'1', '_'}
    SymChars = {'a'..'z', 'A'..'Z', '0'..'9', '\x80'..'\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state == TokenClass.StringLit:
    g.kind = TokenClass.StringLit
    while pos < g.buf.len:
      case g.buf[pos]
      of '\\':
        g.kind = TokenClass.EscapeSequence
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
        g.state = TokenClass.None
        break
      of '\"':
        inc(pos)
        g.state = TokenClass.None
        break
      else:
        inc(pos)
  elif g.state == TokenClass.LongStringLit:
    g.kind = TokenClass.LongStringLit
    while pos < g.buf.len:
      if g.buf[pos] == '\"':
        inc(pos)
        if g.buf[pos] == '\"' and g.buf[pos+1] == '\"' and
            g.buf[pos+2] != '\"':
          inc(pos, 2)
          break
      else:
        inc(pos)
    g.state = TokenClass.None
  elif g.state in {TokenClass.LongComment, TokenClass.Comment}:
    g.kind = g.state
    pos = nimMultilineComment(g, pos, g.kind == TokenClass.LongComment)
    g.state = TokenClass.None
  else:
    case g.buf[pos]
    of ' ', '\x09'..'\x0D':
      g.kind = TokenClass.Whitespace
      while pos < g.buf.len and g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
    of '#':
      if g.buf[pos+1] == '#':
        g.kind = TokenClass.LongComment
        inc pos
      else: g.kind = TokenClass.Comment
      if g.buf[pos+1] == '[':
        g.state = g.kind
        pos = nimMultilineComment(g, pos+2, g.kind == TokenClass.LongComment)
        g.state = TokenClass.None
      else:
        while g.buf[pos] != '\L': inc(pos)
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in SymChars + {'_'}:
        add(id, g.buf[pos])
        inc(pos)
      if (g.buf[pos] == '\"'):
        if (g.buf[pos + 1] == '\"') and (g.buf[pos + 2] == '\"'):
          inc(pos, 3)
          g.kind = TokenClass.LongStringLit
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
          g.kind = TokenClass.RawData
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
      g.kind = TokenClass.CharLit
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
        g.kind = TokenClass.LongStringLit
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
        g.kind = TokenClass.StringLit
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
    of '(', '[', '{':
      inc(pos)
      g.kind = TokenClass.Punctuation
      if g.buf[pos] == '.' and g.buf[pos+1] != '.': inc pos
    of ')', ']', '}', '`', ':', ',', ';':
      inc(pos)
      g.kind = TokenClass.Punctuation
    of '.':
      if g.buf[pos+1] in {')', ']', '}'}:
        inc(pos, 2)
        g.kind = TokenClass.Punctuation
      else:
        g.kind = TokenClass.Operator
        inc pos
    else:
      if g.buf[pos] in OpChars:
        g.kind = TokenClass.Operator
        while g.buf[pos] in OpChars: inc(pos)
      else:
        if pos < g.buf.len: inc(pos)
        g.kind = TokenClass.None
  g.length = pos - g.pos
  g.pos = pos

proc generalNumber(g: var GeneralTokenizer, position: int): int =
  const decChars = {'0'..'9'}
  var pos = position
  g.kind = TokenClass.DecNumber
  while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] == '.':
    g.kind = TokenClass.FloatNumber
    inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] in {'e', 'E'}:
    g.kind = TokenClass.FloatNumber
    inc(pos)
    if g.buf[pos] in {'+', '-'}: inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  result = pos

proc generalStrLit(g: var GeneralTokenizer, position: int): int =
  const
    decChars = {'0'..'9'}
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f'}
  var pos = position
  g.kind = TokenClass.StringLit
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
    hasPreprocessor, hasNestedComments, hasRe, hasBackticks
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
  if g.state == TokenClass.StringLit:
    g.kind = TokenClass.StringLit
    while true:
      case g.buf[pos]
      of '\\':
        g.kind = TokenClass.EscapeSequence
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
        g.state = TokenClass.None
        break
      of '\"':
        inc(pos)
        g.state = TokenClass.None
        break
      else: inc(pos)
  elif g.state == TokenClass.LongComment:
    var nested = 0
    g.kind = TokenClass.LongComment
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
    g.state = TokenClass.None
  else:
    case g.buf[pos]
    of ' ', '\x09'..'\x0D':
      g.kind = TokenClass.Whitespace
      while pos < g.buf.len and g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
    of '/':
      inc(pos)
      if g.buf[pos] == '/':
        g.kind = TokenClass.Comment
        while g.buf[pos] != '\L': inc(pos)
      elif g.buf[pos] == '*':
        g.kind = TokenClass.LongComment
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
      elif g.buf[pos] notin {'\L', ' ', '\t'} and hasRe in flags:
        g.kind = TokenClass.Operator
        var lookAhead = pos
        while g.buf[lookAhead] != '\L':
          if g.buf[lookAhead] == '/':
            inc(lookAhead)
            pos = lookAhead
            g.kind = TokenClass.RegularExpression
            break
          inc(lookAhead)
      else:
        g.kind = TokenClass.Operator
    of '#':
      inc(pos)
      if hasPreprocessor in flags:
        g.kind = TokenClass.Preprocessor
        while g.buf[pos] in {' ', '\t'}: inc(pos)
        while g.buf[pos] in symChars: inc(pos)
      else:
        g.kind = TokenClass.Operator
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(keywords, id) >= 0: g.kind = TokenClass.Keyword
      else: g.kind = TokenClass.Identifier
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
      g.kind = TokenClass.CharLit
    of '`':
      if hasBackticks in flags:
        pos = generalStrLit(g, pos)
        g.kind = TokenClass.Backticks
      else:
        inc(pos)
        g.kind = TokenClass.None
    of '\"':
      inc(pos)
      g.kind = TokenClass.StringLit
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
      g.kind = TokenClass.Punctuation
    else:
      if g.buf[pos] in OpChars:
        g.kind = TokenClass.Operator
        while g.buf[pos] in OpChars: inc(pos)
      else:
        inc(pos)
        g.kind = TokenClass.None
  g.length = pos - g.pos
  g.pos = pos

proc consoleNextToken(g: var GeneralTokenizer) =
  template fallback() =
    g.kind = TokenClass.None
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
    var id = $c.toLowerAscii
    inc pos
    while true:
      let c = g.buf[pos]
      if c in (symChars+{'/','\\',':','\x80'..'\xFF', '.'}):
        add(id, c.toLowerAscii)
        inc(pos)
      else:
        break
    case id
    of "error:", "fatal:": g.kind = TokenClass.Red
    of "warning:": g.kind = TokenClass.Yellow
    of "hint:": g.kind = TokenClass.Green
    else: g.kind = TokenClass.Identifier
  of '[':
    if pos > 0 and g.buf[pos-1] == ' ' and g.buf[pos+1] in Letters:
      inc pos
      let rollback = pos
      while g.buf[pos] in Letters: inc pos
      if g.buf[pos] == ']':
        inc pos
        g.kind = TokenClass.Rule
      else:
        g.kind = TokenClass.None
        pos = rollback
    else:
      fallback()
  of '+': diff(TokenClass.Green)
  of '-': diff(TokenClass.Red)
  of '@':
    if g.buf[pos+1] == '@':
      g.kind = TokenClass.Directive
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

proc jsNextToken(g: var GeneralTokenizer) =
  const
    keywords = ["abstract", "arguments", "boolean", "break", "byte",
        "case", "catch", "char", "class", "const", "continue", "debugger",
        "default", "delete", "do", "double", "else", "enum", "eval", "export",
        "extends", "false", "final", "finally", "float", "for", "function",
        "goto", "if", "implements", "import", "in", "instanceof", "int",
        "interface", "let", "long", "native", "new", "null",
        "package", "private", "protected", "public", "return",
        "short", "static", "super", "switch", "synchronized",
        "this", "throw", "throws", "transient", "true", "try", "typeof",
        "var", "void", "volatile", "while", "with", "yield"]
  clikeNextToken(g, keywords, {hasRe, hasBackticks})


proc getNextToken(g: var GeneralTokenizer, lang: SourceLanguage) =
  case lang
  of langNone: assert false
  of langNim: nimNextToken(g)
  of langCpp: cppNextToken(g)
  of langCsharp: csharpNextToken(g)
  of langC: cNextToken(g)
  of langJava: javaNextToken(g)
  of langJs: jsNextToken(g)
  of langXml, langHtml: xmlNextToken(g)
  of langConsole: consoleNextToken(g)

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

proc highlightLine*(b: Buffer; oldCursor: Natural) =
  # Updating everything turned out to be way too slow even for files of
  # moderate size.
  if b.lang != langNone:
    # move to the *start* of this line
    var i = oldCursor
    while i >= 1 and b[i-1] != '\L': dec i
    let first = i
    i = b.cursor
    while b[i] != '\L': inc i
    let last = i
    let initialState = if first == 0: TokenClass.None else: getCell(b, first-1).s
    highlight(b, first, last, initialState)

proc highlightEverything*(b: Buffer) =
  if b.lang != langNone:
    highlight(b, 0, b.len-1, TokenClass.None)

proc highlightIncrementally*(b: Buffer) =
  if b.lang == langNone or b.highlighter.version == b.version: return
  const charsToIndex = 40*40
  if b.highlighter.currentlyIndexing != b.version:
    b.highlighter.currentlyIndexing = b.version
    b.highlighter.position = 0
  var i = b.highlighter.position
  if i < b.len:
    let initialState = if i == 0: TokenClass.None else: getCell(b, i-1).s
    var last = i+charsToIndex
    if last > b.len-1:
      last = b.len-1
    else:
      while b[last] != '\L': inc last
    highlight(b, i, last, initialState)
    b.highlighter.position = last+1
  else:
    # we highlighted the whole buffer:
    b.highlighter.version = b.version
    b.highlighter.currentlyIndexing = 0

when false:
  proc bufferWithWorkToDo(start: Buffer): Buffer =
    var it = start
    while true:
      if it.highlighter.version != it.version: return it
      it = it.next
      if it == start: break

  proc indexBuffers*(start: Buffer) =
    # search for a single buffer that can be indexed and index it. Since we
    # store the version, eventually everything will be indexed. Works
    # incrementally.
    let it = bufferWithWorkToDo(start)
    if it != nil: indexBuffer(it)


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
