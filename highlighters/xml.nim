
proc parseCDATA(my: var GeneralTokenizer) =
  var pos = my.pos
  var buf = my.buf
  while pos < buf.len:
    case buf[pos]
    of ']':
      if buf[pos+1] == ']' and buf[pos+2] == '>':
        inc(pos, 3)
        break
      inc(pos)
    else:
      inc(pos)
  my.pos = pos # store back
  my.kind = TokenClass.RawData

proc parseComment(my: var GeneralTokenizer) =
  var pos = my.pos
  var buf = my.buf
  while pos < buf.len:
    case buf[pos]
    of '-':
      if buf[pos+1] == '-' and buf[pos+2] == '>':
        inc(pos, 3)
        break
      inc(pos)
    else:
      inc(pos)
  my.pos = pos
  my.kind = TokenClass.Comment

const
  NameStartChar = {'A'..'Z', 'a'..'z', '_', ':', '\128'..'\255'}
  NameChar = {'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_', ':', '\128'..'\255'}

proc parseName(my: var GeneralTokenizer) =
  var pos = my.pos
  var buf = my.buf
  if buf[pos] in NameStartChar:
    while true:
      inc(pos)
      if buf[pos] notin NameChar: break
    my.pos = pos

proc parseEntity(my: var GeneralTokenizer) =
  var pos = my.pos+1
  var buf = my.buf
  my.kind = TokenClass.CharLit
  if buf[pos] == '#':
    inc(pos)
    if buf[pos] == 'x':
      inc(pos)
      while true:
        case buf[pos]
        of '0'..'9', 'a'..'f', 'A'..'F': discard
        else: break
        inc(pos)
    else:
      while buf[pos] in {'0'..'9'}:
        inc(pos)
  elif buf[pos] == 'l' and buf[pos+1] == 't' and buf[pos+2] == ';':
    inc(pos, 2)
  elif buf[pos] == 'g' and buf[pos+1] == 't' and buf[pos+2] == ';':
    inc(pos, 2)
  elif buf[pos] == 'a' and buf[pos+1] == 'm' and buf[pos+2] == 'p' and
      buf[pos+3] == ';':
    inc(pos, 3)
  elif buf[pos] == 'a' and buf[pos+1] == 'p' and buf[pos+2] == 'o' and
      buf[pos+3] == 's' and buf[pos+4] == ';':
    inc(pos, 4)
  elif buf[pos] == 'q' and buf[pos+1] == 'u' and buf[pos+2] == 'o' and
      buf[pos+3] == 't' and buf[pos+4] == ';':
    inc(pos, 4)
  else:
    my.pos = pos
    parseName(my)
    if my.pos == pos:
      my.kind = TokenClass.Other
      inc pos
    pos = my.pos
  if buf[pos] == ';':
    inc(pos)
  else:
    my.kind = TokenClass.Other
  my.pos = pos

proc parsePI(my: var GeneralTokenizer) =
  parseName(my)
  var pos = my.pos
  var buf = my.buf
  while pos < buf.len:
    case buf[pos]
    of '?':
      if buf[pos+1] == '>':
        inc(pos, 2)
        break
      inc(pos)
    else:
      inc(pos)
  my.pos = pos
  my.kind = TokenClass.Directive

proc parseSpecial(my: var GeneralTokenizer) =
  # things that start with <!
  var pos = my.pos
  var buf = my.buf
  var opentags = 0
  while pos < buf.len:
    case buf[pos]
    of '<':
      inc(opentags)
      inc(pos)
    of '>':
      if opentags <= 0:
        inc(pos)
        break
      dec(opentags)
      inc(pos)
    else:
      inc(pos)
  my.pos = pos
  my.kind = TokenClass.Rule

proc parseWhitespace(my: var GeneralTokenizer) =
  var pos = my.pos
  var buf = my.buf
  while pos < buf.len and buf[pos] in {' ', '\t', '\c', '\L'}: inc pos
  my.pos = pos

proc parseTag(my: var GeneralTokenizer) =
  let oldPos = my.pos
  parseName(my)
  # if we have no name, do not interpret the '<':
  if oldPos == my.pos:
    my.kind = TokenClass.Other
    return
  parseWhitespace(my)
  if my.buf[my.pos] in NameStartChar:
    my.kind = TokenClass.TagStart
    my.state = my.kind
  else:
    if my.buf[my.pos] == '/' and my.buf[my.pos+1] == '>':
      inc(my.pos, 2)
      my.kind = TokenClass.TagStandalone
    elif my.buf[my.pos] == '>':
      inc(my.pos)
      my.kind = TokenClass.TagStart
    else:
      my.kind = TokenClass.Other

proc parseEndTag(my: var GeneralTokenizer) =
  parseName(my)
  parseWhitespace(my)
  if my.buf[my.pos] == '>':
    inc(my.pos)
    my.kind = TokenClass.TagEnd

proc parseCharData(my: var GeneralTokenizer) =
  var pos = my.pos
  var buf = my.buf
  while pos < buf.len:
    case buf[pos]
    of '<', '&': break
    else: inc(pos)
  my.pos = pos
  my.kind = TokenClass.Text

proc xmlTokenStart(my: var GeneralTokenizer) =
  var pos = my.pos
  var buf = my.buf
  case buf[pos]
  of '<':
    case buf[pos+1]
    of '/':
      inc(my.pos, 2)
      parseEndTag(my)
    of '!':
      if buf[pos+2] == '[' and buf[pos+3] == 'C' and buf[pos+4] == 'D' and
          buf[pos+5] == 'A' and buf[pos+6] == 'T' and buf[pos+7] == 'A' and
          buf[pos+8] == '[':
        inc my.pos, len("<![CDATA[")
        parseCDATA(my)
      elif buf[pos+2] == '-' and buf[pos+3] == '-':
        inc my.pos, len("<!--")
        parseComment(my)
      else:
        inc my.pos, 2
        parseSpecial(my)
    of '?':
      inc(my.pos, "<?".len)
      parsePI(my)
    else:
      inc(my.pos)
      parseTag(my)
  of ' ', '\t', '\c', '\l':
    inc my.pos
    my.kind = TokenClass.Whitespace
  of '&':
    parseEntity(my)
  else:
    parseCharData(my)

proc xmlNextToken(my: var GeneralTokenizer) =
  let oldPos = my.pos
  var pos = my.pos
  var buf = my.buf
  my.start = my.pos
  #let state = my.state
  # ensure the state machine is not fragile when it comes to errors:
  #my.state = TokenClass.None
  let state = if pos == 0: TokenClass.None else: getCell(buf, pos-1).s
  case state
  of TokenClass.RawData:
    if pos > 4 and buf[pos-3] == ']' and
        buf[pos-2] == ']' and buf[pos-1] == '>':
      xmlTokenStart(my)
    else:
      parseCDATA(my)
  of TokenClass.Comment:
    if pos > 4 and buf[pos-3] == '-' and
        buf[pos-2] == '-' and buf[pos-1] == '>':
      xmlTokenStart(my)
    else:
      parseComment(my)
  of TokenClass.Directive:
    if pos > 2 and buf[pos-2] == '?' and buf[pos-1] == '>':
      xmlTokenStart(my)
    else:
      parsePI(my)
  of TokenClass.Rule:
    if pos > 0 and buf[pos-1] == '>':
      xmlTokenStart(my)
    else:
      parseSpecial(my)
  of TokenClass.TagStart:
    if pos > 0 and buf[pos-1] != '>':
      parseName(my)
      parseWhitespace(my)
      if pos == my.pos:
        inc my.pos
        my.kind = TokenClass.None
      else:
        my.kind = TokenClass.Key
        my.state = TokenClass.Operator
    else:
      xmlTokenStart(my)
  of TokenClass.Key:
    if buf[pos] == '=':
      #echo "came here!!!!!!!"
      inc my.pos
      parseWhitespace(my)
      my.kind = TokenClass.Operator
      my.state = my.kind
    elif buf[pos] == '>':
      inc my.pos
      my.kind = TokenClass.TagStart
    elif buf[pos] == '/' and buf[pos+1] == '>':
      inc(my.pos, 2)
      my.kind = TokenClass.TagStart
    else:
      # error:
      inc my.pos
      my.kind = TokenClass.None
  of TokenClass.Operator:
    var pos = my.pos
    my.kind = TokenClass.Value
    if buf[pos] in {'\'', '"'}:
      var quote = buf[pos]
      inc(pos)
      while pos < buf.len:
        case buf[pos]
        of '&':
          my.pos = pos
          parseEntity(my)
          pos = my.pos
        else:
          if buf[pos] == quote:
            inc(pos)
            break
          else:
            inc(pos)
      my.pos = pos
    else:
      parseName(my)
      if pos == my.pos:
        # no name was parsed, error:
        inc my.pos
        my.kind = TokenClass.None
    my.state = TokenClass.TagStart
    parseWhitespace(my)
  of TokenClass.Value:
    if buf[pos] == '>':
      inc my.pos
      my.kind = TokenClass.TagStart
    elif buf[pos] == '/' and buf[pos+1] == '>':
      inc(my.pos, 2)
      my.kind = TokenClass.TagStart
    else:
      parseName(my)
      parseWhitespace(my)
      if pos == my.pos:
        # no name was parsed, error:
        inc my.pos
        my.kind = TokenClass.None
      else:
        my.kind = TokenClass.Key
      my.state = TokenClass.TagStart
  else:
    xmlTokenStart(my)
  my.length = my.pos - oldpos
