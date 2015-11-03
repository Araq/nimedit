
import osproc, streams, os, net, strutils, buffertype, buffer

const
  endToken = "\e"
  pauseToken = "\e\e"
  clearToken = "\e\e\e"
  port = 6000.Port

type
  SuggestItem* = object
    cmd*, symKind*, name*, nimType*, file*, moduleName*, docs*: string
    line*, col*: string

proc parseNimSuggestLine(line: string, item: var SuggestItem): bool =
  var s = line.split('\t')
  if s.len >= 8:
    item.cmd = s[0]
    item.symKind = s[1]
    item.name = s[2]
    item.nimType = s[3]
    item.file = s[4]
    item.line = s[5]
    item.col = s[6]
    item.docs = unescape(s[7])
    # Get the name without the module name in front of it.
    var dots = item.name.split('.')
    if dots.len() >= 2:
      item.moduleName = dots[0]
      item.name = dots[^1]
    else:
      item.moduleName = ""
    result = true

proc `$`(item: SuggestItem): string =
  case item.cmd
  of "sug":
    result = join([item.name, item.nimType, item.moduleName], "\t")
  of "con":
    result = join([item.nimType, item.moduleName], "\t")
  of "def", "use", "mod":
    let (dir, file) = splitPath(item.file)
    result = file & "(" & item.line & ", " & item.col & ") " &
             item.cmd & " #" & dir
  else: doAssert(false, "unknown nimsuggest result: " & item.cmd)


var
  commands: Channel[string]
  results: Channel[string]

commands.open()
results.open()

proc processTask(task: string) =
  var socket = newSocket()
  var item: SuggestItem
  var errors = 0
  for i in 0..9:
    try:
      socket.connect("localhost", port)
      socket.send(task & "\c\l")
      var line = ""
      while true:
        line.setLen 0
        socket.readLine(line)
        if line.len == 0: break
        if errors > 0:
          results.send clearToken
          errors = 0
        if parseNimSuggestLine(line, item):
          results.send($item)
      socket.close()
      results.send(endToken)
    except OSError, IOError:
      results.send getCurrentExceptionMsg()
      inc errors
      os.sleep(1000)
    if errors == 0: break

proc suggestThread() {.thread.} =
  while true:
    let cmd = commands.recv()
    case cmd
    of endToken: break
    of pauseToken: os.sleep(300)
    else: processTask(cmd)

var nimsuggest: Process
var prevProject: string

proc shutdown*() {.noconv.} =
  if not nimsuggest.isNil:
    nimsuggest.terminate()
    nimsuggest.close()
    nimsuggest = nil

proc startup*(nimsuggestPath, project: string; debug: bool): bool =
  if nimsuggest.isNil or project != prevProject or not nimsuggest.running:
    let sug = if nimsuggestPath == "$path": findExe("nimsuggest")
              elif nimsuggestPath.len > 0: nimsuggestPath
              else: getAppDir() / addFileExt("nimsuggest", ExeExt)
    prevProject = project
    try:
      shutdown()
      let nimPath = findExe("nim").splitFile.dir.parentDir
      var args = if debug: @["--debug"] else: @[]
      args.add("--port:" & $port)
      args.add("--v2")
      args.add(project)

      nimsuggest = startProcess(sug, nimPath, args,
                       options = {poStdErrToStdOut, poUsePath, poDemon})
      # give it some time to startup:
      #commands.send(pauseToken)
    except OSError:
      discard
  result = nimsuggest != nil

var processing*: bool

# sug|con|def|use|dus
proc requestSuggestion*(b: Buffer; cmd: string) =
  let col = b.getByteColumn
  var sugCmd: string
  if b.changed:
    let file = getTempDir() / b.filename.extractFilename
    b.saveAsTemp(file)
    sugCmd = "$# \"$#\";\"$#\":$#:$#\c\l" % [
      cmd, b.filename, file, $(b.currentLine+1), $(col+1)]
  else:
    sugCmd = "$# \"$#\":$#:$#\c\l" % [
      cmd, b.filename, $(b.currentLine+1), $(col+1)]
  commands.send sugCmd
  processing = true

proc update*(b: Buffer) =
  if processing:
    let L = results.peek
    for i in 0..<L:
      let resp = results.recv()
      if resp == endToken:
        processing = false
        break
      elif resp == clearToken:
        b.clear()
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

var backgroundThread: Thread[void]
createThread[void](backgroundThread, suggestThread)
