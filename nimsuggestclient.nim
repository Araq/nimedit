
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
      results.send(line)
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

var backgroundThread: Thread[void]
createThread[void](backgroundThread, suggestThread)
