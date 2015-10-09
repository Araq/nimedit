
import osproc, streams, os, net, strutils, buffertype, buffer

const
  endToken = "\e"
  port = 6000.Port

type
  SuggestItem* = object
    symKind*, name*, nimType*, file*, nmName*, docs*: string
    line*, col*: int32

var
  commands: Channel[string]
  results: Channel[string]

commands.open()
results.open()

proc processTask(task: string) =
  var socket = newSocket()
  try:
    socket.connect("localhost", port)
    socket.send(task & "\c\l")
    var line = ""
    while true:
      line.setLen 0
      socket.readLine(line)
      if line.len == 0: break
      var tabs = 0
      for i in 0..line.high:
        if line[i] == '\t':
          inc tabs
          if tabs == 2:
            results.send(line.substr(i+1))
            break
    socket.close()
  except OSError, IOError:
    results.send getCurrentExceptionMsg()
  results.send(endToken)

proc parseNimSuggestLine(cmd, line: string, item: var SuggestItem): bool =
  if line.startsWith(cmd):
    var s = line.split('\t')
    if s.len >= 8:
      item.symKind = s[1]
      item.name = s[2]
      item.nimType = s[3]
      item.file = s[4]
      item.line = int32(s[5].parseInt())
      item.col = int32(s[6].parseInt())
      item.docs = unescape(s[7])
    # Get the name without the module name in front of it.
    var dots = item.name.split('.')
    if dots.len() == 2:
      item.nmName = item.name[dots[0].len()+1.. ^1]
    else:
      item.nmName = item.name
    result = true

proc suggestThread() {.thread.} =
  while true:
    let cmd = commands.recv()
    if cmd == endToken: break
    processTask(cmd)

var nimsuggest: Process

proc startup*(project: string): bool =
  if nimsuggest.isNil:
    try:
      let nimPath = findExe("nim").splitFile.dir.parentDir
      nimsuggest = startProcess(findExe("nimsuggest"), nimPath,
                       ["--port:" & $port, project],
                       options = {poStdErrToStdOut, poUsePath})
      # give it some time to startup:
      os.sleep(1000)
    except OSError:
      discard
  result = nimsuggest != nil

proc shutdown*() {.noconv.} =
  if not nimsuggest.isNil:
    nimsuggest.terminate()
    nimsuggest.close()
    nimsuggest = nil

var processing*: bool

# sug|con|def|use
proc requestSuggestion*(b: Buffer; cmd: string) =
  var sugCmd: string
  if b.changed:
    let file = getTempDir() / b.filename.extractFilename
    b.saveAsTemp(file)
    sugCmd = "$# \"$#\";\"$#\":$#:$4\c\l" % [
      cmd, b.filename, file, $(b.currentLine+1), $(b.getColumn+1)]
  else:
    sugCmd = "$# \"$#\":$#:$#\c\l" % [
      cmd, b.filename, $(b.currentLine+1), $(b.getColumn+1)]
  commands.send sugCmd
  processing = true

proc update*(b: Buffer) =
  if processing:
    let L = results.peek
    for i in 0..<L:
      let resp = results.recv()
      if resp == endToken:
        processing = false
      else:
        b.insertReadOnly resp
        b.insertReadOnly "\L"
    if L > 0:
      b.gotoLine(1, -1)

proc gotoPrefix*(b: Buffer; prefix: string) =
  if prefix.len == 0: return
  var matches = newSeq[int](prefix.len+1)
  var i = 0
  while i < b.len:
    let ii = i
    # first char is case sensitive in Nim:
    if b[i] == prefix[0]:
      var j = 1
      inc i
      while i < b.len and j < prefix.len and b[i].toLower == prefix[j].toLower:
        inc i
        inc j
      if matches[j] == 0: matches[j] = ii+1
    if b[i] in {'\t', ' '}:
      # jump to next line:
      inc i
      while i < b.len and b[i-1] != '\L': inc i
    else:
      inc i
  for hit in countdown(prefix.len, 0):
    if matches[hit] != 0:
      b.gotoPos(matches[hit]-1)
      break

proc selected*(autocomplete, main: Buffer) =
  inc main.version
  let p = main.getWordPrefix
  for i in 0..<p.len:
    dec main.version
    backspace(main, overrideUtf8=true)
  # undo the upcoming version increase that 'insert' performs:
  dec main.version
  insert(main, autocomplete.getCurrentWord)

var backgroundThread: Thread[void]
createThread[void](backgroundThread, suggestThread)
