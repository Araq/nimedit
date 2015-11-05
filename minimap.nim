
import buffertype, buffer, languages, nimscript/common, highlighters
import strutils except Letters

proc fillMinimap*(m, b: Buffer) =
  m.lang = b.lang
  m.clear()
  if b.lang in {langNone, langConsole}: return
  var i = b.cursor
  while i > 0 and b[i-1] != '\L': dec i
  var indent = 0
  while b[i+indent] == ' ':
    inc indent
  if indent == 0 or b.firstLineOffset == 0: return
  var content: array[10, int]
  var cr = 0
  let origIndent = indent
  while i > 0:
    dec i
    assert b[i] == '\L'
    while i > 0 and b[i-1] != '\L': dec i

    var currindent = 0
    while b[i+currindent] == ' ':
      inc currindent
    var j = i+currindent
    if currindent <= indent and b[j] in Letters and i < b.firstLineOffset and
       currindent < origIndent:
      var keyw = ""
      keyw.add b[j]
      inc j
      while true:
        let c = b[j]
        if c notin Letters: break
        if b.lang == langNim:
          if c != '_':
            keyw.add c.toLower
        else:
          keyw.add c
        inc j
      let flow = interestingControlflow(b.lang, keyw)
      if flow == isIf and currindent < indent or
         flow == isCase or
         flow == isDecl and currindent == 0:
        content[cr] = i
        inc cr
        if cr == content.len:
          break
    # if not an empty line:
    if b[i+currindent] in Letters:
      if currindent == 0: break
      if currindent < indent: indent = currindent
  for ii in countdown(cr-1, 0):
    var i = content[ii]
    while true:
      let c = b[i]
      if c == '\L': break
      m.rawInsert c
      inc i
    m.rawInsert '\L'
  m.setCaret(0)
  #m.span = 3
  m.currentLine = 0
  m.firstLine = 0
  m.firstLineOffset = 0
  m.highlightEverything()
  #echo m.fullText
