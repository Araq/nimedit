# Some nice console support.

import buffertype, buffer, os, osproc, streams, strutils, browsers

const
  ExtensionsToIgnore* = [
    ".ppu", ".o", ".obj", ".dcu",
    ".map", ".tds", ".err", ".bak", ".pyc", ".exe", ".rod", ".pdb", ".idb",
    ".idx", ".ilk", ".dll", ".so", ".a"
  ]

proc ignoreFile*(f: string): bool =
  let (_, _, ext) = f.splitFile
  result = f[0] == '.' or ext in ExtensionsToIgnore or f == "nimcache"

type
  CmdHistory* = object
    cmds*: seq[string]
    suggested*: int

proc addCmd*(h: var CmdHistory; cmd: string) =
  var replaceWith = -1
  for i in 0..high(h.cmds):
    if h.cmds[i] == cmd:
      # suggest it again:
      h.suggested = i
      return
    elif h.cmds[i] in cmd:
      # correct previously wrong or shorter command:
      if replaceWith < 0 or h.cmds[replaceWith] < h.cmds[i]: replaceWith = i
  if replaceWith < 0:
    h.cmds.add cmd
  else:
    h.cmds[replaceWith] = cmd

proc suggest*(h: var CmdHistory; up: bool): string =
  if h.suggested < 0 or h.suggested >= h.cmds.len:
    h.suggested = (if up: h.cmds.high else: 0)
  if h.suggested >= 0 and h.suggested < h.cmds.len:
    result = h.cmds[h.suggested]
    h.suggested += (if up: -1 else: 1)
  else:
    result = ""

type
  Console* = ref object
    b: Buffer
    hist*: CmdHistory
    files: seq[string]
    prefix: string
    processRunning*: bool
    beforeSuggestionPos: int
    aliases*: seq[(string, string)]

proc insertReadonly*(c: Console; s: string) =
  insertReadonly(c.b, s)

proc insertPrompt*(c: Console) =
  c.insertReadOnly(os.getCurrentDir() & ">")

proc newConsole*(b: Buffer): Console =
  result = Console(b: b, hist: CmdHistory(cmds: @[], suggested: -1), files: @[],
                   prefix: "", aliases: @[])

proc getCommand(c: Console): string =
  result = ""
  let b = c.b
  for i in b.readOnly+1 .. <c.b.len:
    result.add c.b[i]

proc emptyCmd(c: Console) =
  let b = c.b
  while true:
    if b.len-1 <= b.readOnly: break
    backspace(b, false)

proc upPressed*(c: Console) =
  let sug = c.hist.suggest(up=true)
  if sug.len > 0:
    emptyCmd(c)
    c.b.insert sug

proc downPressed*(c: Console) =
  let sug = c.hist.suggest(up=false)
  if sug.len > 0:
    emptyCmd(c)
    c.b.insert sug

proc handleHexChar(s: string; pos: int; xi: var int): int =
  case s[pos]
  of '0'..'9':
    xi = (xi shl 4) or (ord(s[pos]) - ord('0'))
    result = pos+1
  of 'a'..'f':
    xi = (xi shl 4) or (ord(s[pos]) - ord('a') + 10)
    result = pos+1
  of 'A'..'F':
    xi = (xi shl 4) or (ord(s[pos]) - ord('A') + 10)
    result = pos+1
  else: discard

proc parseEscape(s: string; w: var string; start=0): int =
  var pos = start+1 # skip '\'
  case s[pos]
  of 'n', 'N':
    w.add("\n")
    inc(pos)
  of 'r', 'R', 'c', 'C':
    add(w, '\c')
    inc(pos)
  of 'l', 'L':
    add(w, '\L')
    inc(pos)
  of 'f', 'F':
    add(w, '\f')
    inc(pos)
  of 'e', 'E':
    add(w, '\e')
    inc(pos)
  of 'a', 'A':
    add(w, '\a')
    inc(pos)
  of 'b', 'B':
    add(w, '\b')
    inc(pos)
  of 'v', 'V':
    add(w, '\v')
    inc(pos)
  of 't', 'T':
    add(w, '\t')
    inc(pos)
  of '\'', '\"':
    add(w, s[pos])
    inc(pos)
  of '\\':
    add(w, '\\')
    inc(pos)
  of 'x', 'X':
    inc(pos)
    var xi = 0
    pos = handleHexChar(s, pos, xi)
    pos = handleHexChar(s, pos, xi)
    add(w, chr(xi))
  of '0'..'9':
    var xi = 0
    while s[pos] in {'0'..'9'}:
      xi = (xi * 10) + (ord(s[pos]) - ord('0'))
      inc(pos)
    if xi <= 255: add(w, chr(xi))
  else:
    w.add('\\')
  result = pos

proc parseWord*(s: string; w: var string;
                start=0; convToLower=false): int =
  template conv(c): untyped = (if convToLower: c.toLower else: c)
  w.setLen(0)
  var i = start
  while s[i] in {' ', '\t'}: inc i
  case s[i]
  of '\'':
    inc i
    while i < s.len:
      if s[i] == '\'':
        if s[i+1] == '\'':
          w.add s[i]
          inc i
        else:
          inc i
          break
      else:
        w.add s[i].conv
      inc i
  of '"':
    inc i
    while i < s.len:
      if s[i] == '"':
        inc i
        break
      elif s[i] == '\\':
        i = parseEscape(s, w, i)
      else:
        w.add s[i].conv
        inc i
  else:
    while s[i] > ' ':
      w.add s[i].conv
      inc i
  result = i

proc startsWithIgnoreCase(s, prefix: string): bool =
  var i = 0
  while true:
    if prefix[i] == '\0': return true
    if s[i].toLower != prefix[i].toLower: return false
    inc(i)

proc suggestPath(c: Console; b: Buffer; prefix: string) =
  # suggest the path with the matching prefix (ignoring case),
  # but ultimately suggest every file:
  var sug = -1
  if prefix.len > 0:
    for i, x in c.files:
      if x.startsWithIgnoreCase(prefix) and not x.ignoreFile:
        sug = i
        break
  if sug < 0 and prefix.len > 0:
    # if we have no prefix, pick a file that contains the prefix somewhere
    let p = prefix.toLower
    for i, x in c.files:
      if p in x.toLower and not x.ignoreFile:
        sug = i
        break
  # no match, just suggest something, but ignore crap starting with a dot:
  if sug < 0:
    sug = 0
    while sug < c.files.high:
      if c.files[sug].ignoreFile: inc sug
      else: break
  if sug >=% c.files.len: return
  # these inserts&deletes do not count as changed event:
  let oldChanged = b.changed
  for i in 0..<c.beforeSuggestionPos: backspace(b, false, overrideUtf8=true)
  insert(b, c.files[sug])
  c.beforeSuggestionPos = c.files[sug].len
  delete(c.files, sug)
  b.changed = oldChanged

proc addFile(c: Console; path: string) =
  if find(path, {' ', '\t'}) >= 0:
    c.files.add path.escape
  else:
    c.files.add path

proc tabPressed*(c: Console; basePath: string) =
  let b = c.b

  if b.changed:
    let cmd = getCommand(c)
    c.prefix.setLen 0
    var prefixB = ""
    var i = 0
    while true:
      i = parseWord(cmd, prefixB, i)
      # if prefixB.len == 0 means at end:
      if prefixB.len == 0:
        # parseWord always skips initial whitespace, so we look at the passed
        # character:
        if i > 0 and cmd[i-1] == ' ':
          # no prefix:
          setLen c.prefix, 0
        break
      swap(c.prefix, prefixB)

    c.beforeSuggestionPos = c.prefix.len
    setLen c.files, 0
    b.changed = false

  if c.files.len == 0:
    # prefix == "..\..\foo"
    let (path, prefix) = c.prefix.splitPath
    if path[0] == '~':
      let expandedPath = getHomeDir() / path.substr(1)
      for k, f in os.walkDir(expandedPath, relative=false):
        c.addFile f
    elif c.prefix.isAbsolute:
      for k, f in os.walkDir(path, relative=false):
        c.addFile f
    else:
      for k, f in os.walkDir(basePath / path, relative=true):
        c.addFile path / f
    c.prefix = prefix
  suggestPath(c, b, c.prefix)

proc cmdToArgs(cmd: string): tuple[exe: string, args: seq[string]] =
  result.exe = ""
  result.args = @[]
  var i = parseWord(cmd, result.exe, 0)
  while true:
    var x = ""
    i = parseWord(cmd, x, i)
    if x.len == 0: break
    result.args.add x

proc dirContents(c: Console; ext: string) =
  for k, f in os.walkDir(getCurrentDir()):
    if ext.len == 0 or cmpPaths(f.splitFile.ext, ext) == 0:
      c.insertReadonly(f)
      c.insertReadonly("    ")

# Threading channels
var requests: Channel[string]
requests.open()
var responses: Channel[string]
responses.open()
# Threading channels END

const EndToken = "\e" # a single ESC

proc execThreadProc() {.thread.} =
  template waitForExit() =
    started = false
    let exitCode = p.waitForExit()
    p.close()
    if exitCode != 0:
      responses.send("Process terminated with exitcode: " & $exitCode & "\L")
    responses.send EndToken
  when defined(consoleapp):
    template echod(msg) = echo msg
  else:
    template echod(msg) = discard

  var p: Process
  var o: Stream
  var started = false
  while true:
    var tasks = requests.peek()
    if tasks == 0 and not started: tasks = 1
    if tasks > 0:
      for i in 0..<tasks:
        let task = requests.recv()
        if task == EndToken:
          echod("[Thread] Stopping process.")
          p.terminate()
          o.close()
          waitForExit()
        else:
          if not started:
            let (bin, args) = cmdToArgs(task)
            try:
              p = startProcess(bin, os.getCurrentDir(), args,
                        options = {poStdErrToStdOut, poUsePath, poInteractive,
                                   poDemon})
              o = p.outputStream
              started = true
            except:
              started = false
              responses.send getCurrentExceptionMsg()
              responses.send EndToken
            echod "STARTED " & bin
          else:
            p.inputStream.writeline task
    # Check if process exited.
    if started:
      if not p.running:
        echod("[Thread] Process exited.")
        while not o.atEnd:
          let line = o.readAll()
          responses.send(line)

        # Process exited.
        waitForExit()
      elif osproc.hasData(p):
        let line = o.readAll()
        responses.send(line)

var backgroundThread: Thread[void]
createThread[void](backgroundThread, execThreadProc)

proc update*(c: Console) =
  if c.processRunning:
    if responses.peek > 0:
      let resp = responses.recv()
      if resp == EndToken:
        c.processRunning = false
        c.insertReadOnly "\L"
        insertPrompt(c)
      else:
        insertReadOnly(c, resp)

proc sendBreak*(c: Console) =
  if c.processRunning:
    requests.send EndToken

proc extractFilePosition*(b: Buffer): (string, int, int) =
  ## Line is -1 if not an interpretable file position.
  template parseNumber(line) =
    while b[i] in Digits:
      line = line * 10 + (b[i].ord - '0'.ord)
      inc i

  # assume the cursor is under 'Hint:', 'Error:' etc. This is how the message
  # might look like:  foo.nim(3, 4) Error: bla bla bla.
  # As a nice benefit, the same parsing also detects Nim stack traces. :-)
  var i = b.cursor
  while i > 0 and b[i-1] != '\L': dec i
  result = ("", -1, -1)
  while b[i] == ' ': inc i
  while i < b.len and b[i] != ' ':
    if b[i] == '(': break
    elif b[i] == ':' and b[i+1] != '\\': break
    result[0].add b[i]
    inc i
  var line, col: int
  if b[i] == '(' and b[i+1] in Digits:
    inc i
    parseNumber(line)
    if b[i] == ',':
      inc i
      while b[i] == ' ': inc i
      parseNumber(col)
    else:
      col = -1
    if b[i] == ')':
      result[1] = line
      result[2] = col
  elif b[i] == ':' and b[i+1] in Digits:
    inc i
    parseNumber(line)
    if b[i] == ':':
      inc i
      parseNumber(col)
      if b[i] == ':':
        result[1] = line
        result[2] = col

proc enterPressed*(c: Console): string =
  c.b.gotoPos(c.b.len)
  c.files.setLen 0
  var cmd = getCommand(c)
  addCmd(c.hist, cmd)
  var a = ""
  var i = parseWord(cmd, a, 0, true)
  c.insertReadOnly "\L"
  for al in c.aliases:
    if a == al[0]:
      cmd = al[1] & cmd.substr(i)
      i = parseWord(cmd, a, 0, true)
      break
  case a
  of "":
    insertPrompt c
  of "o":
    result = ""
    i = parseWord(cmd, result, i)
    insertPrompt c
  of "cls":
    clear(c.b)
    insertPrompt c
  of "cd":
    var b = ""
    i = parseWord(cmd, b, i)
    try:
      os.setCurrentDir(b)
    except OSError:
      c.insertReadOnly(getCurrentExceptionMsg() & "\L")
    insertPrompt c
  of "save":
    var filename = ""
    i = parseWord(cmd, filename, i)
    if filename.len > 0: c.b.saveAs(filename)
    insertPrompt c
  of "d":
    var b = ""
    i = parseWord(cmd, b, i)
    c.dirContents(b)
    insertPrompt c
  else:
    if i >= cmd.len-1 and (a.endsWith".html" or a.startsWith"http://" or
        a.startsWith"https://"):
      openDefaultBrowser(a)
      #echo a
    else:
      requests.send cmd
      c.processRunning = true
