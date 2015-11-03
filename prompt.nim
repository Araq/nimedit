
proc singleQuoted(s: string): string =
  if find(s, {'\L', '\C'}) >= 0:
    result = escape(s)
  elif find(s, {' ', '\t'}) >= 0:
    result = '\'' & s.replace("'", "''") & '\''
  else:
    result = s

proc findCmd(ed: Editor) =
  let prompt = ed.prompt
  let text = ed.focus.getSelectedText()
  ed.focus = prompt
  prompt.clear()
  prompt.insert "find " & text.singleQuoted

proc replaceCmd(ed: Editor) =
  let prompt = ed.prompt
  let text = ed.focus.getSelectedText()
  ed.focus = prompt
  prompt.clear()
  prompt.insert "replace " & text.singleQuoted & " "

proc gotoCmd(ed: Editor) =
  let prompt = ed.prompt
  ed.focus = prompt
  prompt.clear()
  prompt.insert "goto "

proc runScriptCmd(ed: Editor) =
  let prompt = ed.prompt
  ed.focus = prompt
  prompt.clear()
  prompt.insert "e "

proc openCmd(ed: Editor) =
  when defined(windows):
    if ed.prompt.fullText == "o ":
      let previousLocation =
        if ed.main.filename.len > 0: ed.main.filename.splitFile.dir
        else: ""
      let toOpen = chooseFilesToOpen(nil, previousLocation)
      for p in toOpen:
        ed.openTab(p)
      ed.focus = ed.main
      return
  let prompt = ed.prompt
  ed.focus = prompt

  prompt.clear()
  prompt.insert "o "

const
  saveChanges = "Closing tab: Save changes? [yes|no|abort]"
  askForReplace = "Replace? [yes|no|abort|all]"

proc askForQuitTab(ed: Editor) =
  let prompt = ed.prompt
  prompt.clear()
  ed.statusMsg = saveChanges
  ed.focus = prompt

proc findAll(ed: Editor; searchPhrase: string; searchOptions: SearchOptions) =
  for it in allBuffers(ed):
    it.findNext(searchPhrase, searchOptions)
    it.activeMarker = 0
    if onlyCurrentFile in searchOptions: break

proc gotoFirstMarker(ed: Editor; stayInFile: bool): bool =
  for b in allBuffers(ed):
    if b.activeMarker < b.markers.len:
      gotoPos(b, b.markers[b.activeMarker].b+1)
      result = true
      break
    elif stayInFile:
      break

proc gotoNextMarker(ed: Editor; stayInFile: bool) =
  var b = ed.main
  inc b.activeMarker
  if b.activeMarker >= b.markers.len:
    b.activeMarker = 0
    if not stayInFile:
      let start = b
      while true:
        b = b.next
        if b == start: break
        if b.activeMarker < b.markers.len:
          ed.main = b
          break
  if b.activeMarker < b.markers.len:
    gotoPos(b, b.markers[b.activeMarker].b+1)

proc gotoPrevMarker(ed: Editor; stayInFile: bool) =
  var b = ed.main
  dec b.activeMarker
  if b.activeMarker < 0:
    b.activeMarker = b.markers.high
    if not stayInFile:
      let start = b
      while true:
        b = b.prev
        if b == start: break
        if b.activeMarker < b.markers.len:
          ed.main = b
          break
  if b.activeMarker < b.markers.len:
    gotoPos(b, b.markers[b.activeMarker].b+1)

proc smartOpen(ed: Editor; p: var string): bool {.discardable.} =
  if p.len > 0:
    if not ed.openTab(p, true):
      # don't give up, do "what I mean":
      p = findFileAbbrev(ed, p)
      if p.len > 0:
        result = ed.openTab(p, true)
  else:
    result = true

proc runCmd(ed: Editor; cmd: string): bool =
  let prompt = ed.prompt

  ed.promptCon.hist.addCmd(cmd)

  template unmark() =
    ed.focus = ed.main
    ed.state = requestedNothing
    ed.statusMsg = readyMsg
    ed.main.markers.setLen 0

  template success() =
    prompt.clear()
    ed.focus = ed.main

  var action = ""
  var i = parseWord(cmd, action, 0, true)
  case action
  of "exec", "e":
    var procName = ""
    i = parseWord(cmd, procName, i)
    if procname.len > 0:
      if supportsAction(procName):
        let x = runTransformator(procName, ed.main.getSelectedText())
        if not x.isNil:
          inc ed.main.version
          ed.main.removeSelectedText()
          dec ed.main.version
          ed.main.insert(x)
      else:
        ed.statusMsg = "Unknown command: " & procname
    success()
    ed.state = requestedNothing
  of "yes", "y":
    case ed.state
    of requestedShutdown, requestedCloseTab:
      ed.main.save()
      ed.removeBuffer(ed.main)
      success()
      ed.statusMsg = readyMsg
      ed.state = if ed.state==requestedShutdown: requestedShutdownNext
                 else: requestedNothing
    of requestedReplace:
      if ed.main.doReplace():
        ed.gotoNextMarker(onlyCurrentFile in ed.searchOptions)
      else:
        ed.statusMsg = readyMsg
        ed.state = requestedNothing
        ed.focus = ed.main
    of requestedReload:
      loadFromFile(ed.main, ed.main.filename)
      success()
      ed.statusMsg = readyMsg
    else: discard
  of "no", "n":
    case ed.state
    of requestedShutdown, requestedCloseTab:
      ed.main.changed = false
      ed.removeBuffer(ed.main)
      success()
      ed.statusMsg = readyMsg
      ed.state = if ed.state==requestedShutdown: requestedShutdownNext
                 else: requestedNothing
    of requestedReplace:
      ed.gotoNextMarker(onlyCurrentFile in ed.searchOptions)
    of requestedReload:
      ed.state = requestedNothing
      ed.statusMsg = readyMsg
      success()
    else: discard
  of "abort", "a":
    success()
    ed.statusMsg = readyMsg
    ed.state = requestedNothing
  of "all":
    if ed.state == requestedReplace:
      ed.main.activeMarker = 0
      while ed.main.doReplace():
        ed.gotoNextMarker(onlyCurrentFile in ed.searchOptions)
      ed.statusMsg = readyMsg
      ed.prompt.clear()
      ed.focus = ed.main
      ed.state = requestedNothing
  of "quit", "q": result = true
  of "find", "f", "filter":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
      ed.searchOptions = parseSearchOptions searchOptions
      ed.findAll(searchPhrase, ed.searchOptions)
      if ed.gotoFirstMarker(onlyCurrentFile in ed.searchOptions):
        ed.prompt.clear()
        if action == "filter":
          filterOccurances(ed.main)
          ed.focus = ed.main
        else:
          ed.prompt.insert("next")
      else:
        ed.statusMsg = "Match not found."
    else:
      unmark()
      if action == "filter":
        ed.main.filterLines = false
  of "next":
    ed.gotoNextMarker(onlyCurrentFile in ed.searchOptions)
  of "prev":
    ed.gotoPrevMarker(onlyCurrentFile in ed.searchOptions)
  of "replace", "r":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var toReplaceWith = ""
      i = parseWord(cmd, toReplaceWith, i)
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
      ed.searchOptions = parseSearchOptions searchOptions
      ed.findAll(searchPhrase, ed.searchOptions)
      ed.main.findNext(searchPhrase, ed.searchOptions,
                       toReplaceWith)
      if ed.gotoFirstMarker(onlyCurrentFile in ed.searchOptions):
        ed.prompt.clear()
        ed.state = requestedReplace
        ed.statusMsg = askForReplace
      else:
        ed.statusMsg = "Match not found."
    else:
      unmark()
  of "goto", "g":
    var dest = ""
    i = parseWord(cmd, dest, i, true)
    if dest.len > 0:
      var p = ""
      i = parseWord(cmd, p, i)
      if smartOpen(ed, p):
        var lineAsInt = -1
        discard parseutils.parseInt(dest, lineAsInt)
        if lineAsInt >= 0:
          var col = -1
          i = parseWord(cmd, dest, i, true)
          discard parseutils.parseInt(dest, col)
          ed.main.gotoLine(lineAsInt, col)
        else:
          # search for declaration of this identifier:
          ed.main.filterMinimap()
          lineAsInt = gotoNextDeclaration(ed.main, dest)
          if lineAsInt > 0:
            ed.main.gotoLine(lineAsInt, -1)
        ed.focus = ed.main
    prompt.clear()
  of "save", "s":
    var p = ""
    i = parseWord(cmd, p, i)
    if p.len > 0:
      ed.statusMsg = readyMsg
      try:
        p = expandFilename(p)
      except OSError:
        ed.statusMsg = getCurrentExceptionMsg()
      if ed.statusMsg == readyMsg:
        var answer = ""
        i = parseWord(cmd, answer, i, true)
        if cmpPaths(ed.main.filename, p) == 0 or
            not os.fileExists(p) or answer[0] == 'y':
          ed.main.saveAs(p)
          success()
        elif answer[0] == 'n':
          success()
        else:
          ed.statusMsg = "File already exists. Overwrite? [yes|no]"
          ed.prompt.insert(" no")
    else:
      ed.main.save()
      success()
  of "open", "o":
    var p = ""
    i = parseWord(cmd, p, i)
    smartOpen(ed, p)
    success()
  of "lang":
    var lang = ""
    i = parseWord(cmd, lang, i)
    ed.main.lang = getSourceLanguage(lang)
    highlightEverything(ed.main)
    success()
  of "config", "conf", "cfg", "colors":
    openTab(ed, ed.cfgColors, true)
    success()
  of "script", "scripts", "actions":
    openTab(ed, ed.cfgActions, true)
    success()
  of "cr":
    ed.main.lineending = "\C"
    success()
  of "lf":
    ed.main.lineending = "\L"
    success()
  of "crlf":
    ed.main.lineending = "\C\L"
    success()
  of "tab", "tabsize", "tabs":
    var x = ""
    i = parseWord(cmd, x, i)
    var xx: int
    discard parseutils.parseInt(x, xx)
    if xx > 0 and xx <= 127:
      ed.main.tabSize = xx.int8
      success()
  of "setproject", "proj", "project":
    ed.project = ""
    i = parseWord(cmd, ed.project, i)
    if ed.project.len == 0:
      ed.window.setTitle(windowTitle)
    else:
      let p = findFile(ed, ed.project.addFileExt("nim"))
      if p.len != 0: ed.project = p
      ed.window.setTitle(windowTitle & " - " & ed.project.extractFilename)
    success()
  of "nimsug", "nimsuggest", "sug":
    var a = ""
    i = parseWord(cmd, a, i, true)
    case a
    of "shutdown", "stop", "quit", "halt", "exit":
      nimsuggestclient.shutdown()
    of "restart", "start":
      if not startup(ed.theme.nimsuggestPath, ed.project, ed.nimsuggestDebug):
        ed.statusMsg = "Nimsuggest failed for: " & ed.project
    of "debug":
      var onoff = ""
      i = parseWord(cmd, onoff, i, true)
      ed.nimsuggestDebug = onoff != "off"
    else:
      ed.statusMsg = "wrong command, try: start|stop|debug"
    success()
  of "help":
    openDefaultBrowser getAppDir() / "docs.html"
    success()
  else:
    ed.statusMsg = "wrong command, try: help|open|save|find|..."
