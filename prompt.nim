
proc singleQuoted(s: string): string =
  if find(s, {'\L', '\C'}) >= 0:
    result = escape(s)
  elif find(s, {' ', '\t'}) >= 0:
    result = '\'' & s.replace("'", "''") & '\''
  else:
    result = s

proc openCmd(ed: Editor) =
  when defined(windows):
    if ed.prompt.fullText == "o ":
      let previousLocation =
        if ed.main.filename.len > 0: ed.main.filename.splitFile.dir
        else: ""
      let toOpen = chooseFilesToOpen(nil, previousLocation)
      for p in toOpen:
        ed.openTab(p)
      focus = ed.main
      return
  let prompt = ed.prompt
  focus = prompt

  prompt.clear()
  prompt.insert "o "

const
  saveChanges = "Closing tab: Save changes? [yes|no|abort]"
  askForReplace = "Replace? [yes|no|abort|all]"

proc askForQuitTab(ed: Editor) =
  let prompt = ed.prompt
  prompt.clear()
  ed.sh.statusMsg = saveChanges
  focus = prompt

proc findAll(ed: Editor; searchPhrase: string; searchOptions: SearchOptions;
             toReplaceWith: string = nil) =
  for it in allBuffers(ed):
    it.findNext(searchPhrase, searchOptions, toReplaceWith)
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

proc unmark(ed: Editor) =
  ed.sh.focus = ed.main
  ed.sh.state = requestedNothing
  ed.sh.statusMsg = readyMsg
  for x in allBuffers(ed):
    x.markers.setLen 0

proc runCmd(ed: Editor; cmd: string; shiftPressed: bool): bool =
  let prompt = ed.prompt
  let sh = ed.sh

  ed.promptCon.hist.addCmd(cmd)

  template success() =
    prompt.clear()
    sh.focus = ed.main

  var action = ""
  var i = parseWord(cmd, action, 0, true)
  case action
  of "": focus = ed.main
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
        sh.statusMsg = "Unknown command: " & procname
    success()
    sh.state = requestedNothing
  of "yes", "y":
    case sh.state
    of requestedShutdown, requestedCloseTab:
      ed.main.save()
      ed.removeBuffer(ed.main)
      success()
      sh.statusMsg = readyMsg
      sh.state = if sh.state==requestedShutdown: requestedShutdownNext
                 else: requestedNothing
    of requestedReplace:
      if ed.main.doReplace():
        ed.gotoNextMarker(onlyCurrentFile in sh.searchOptions)
      else:
        sh.statusMsg = readyMsg
        sh.state = requestedNothing
        focus = ed.main
    of requestedReload:
      loadFromFile(ed.main, ed.main.filename)
      success()
      sh.statusMsg = readyMsg
    else: discard
  of "no", "n":
    case sh.state
    of requestedShutdown, requestedCloseTab:
      ed.main.changed = false
      ed.removeBuffer(ed.main)
      success()
      sh.statusMsg = readyMsg
      sh.state = if sh.state==requestedShutdown: requestedShutdownNext
                 else: requestedNothing
    of requestedReplace:
      ed.gotoNextMarker(onlyCurrentFile in sh.searchOptions)
    of requestedReload:
      sh.state = requestedNothing
      sh.statusMsg = readyMsg
      success()
    else: discard
  of "abort", "a":
    success()
    sh.statusMsg = readyMsg
    sh.state = requestedNothing
  of "all":
    if sh.state == requestedReplace:
      ed.main.activeMarker = 0
      while ed.main.doReplace():
        ed.gotoNextMarker(onlyCurrentFile in sh.searchOptions)
      sh.statusMsg = readyMsg
      ed.prompt.clear()
      focus = ed.main
      sh.state = requestedNothing
  of "quit", "q": result = true
  of "find", "findall", "f", "filter":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
      sh.searchOptions = parseSearchOptions searchOptions
      if action != "findall": sh.searchOptions.incl onlyCurrentFile
      ed.findAll(searchPhrase, sh.searchOptions)
      if ed.gotoFirstMarker(onlyCurrentFile in sh.searchOptions):
        ed.prompt.clear()
        if action == "filter":
          filterOccurances(ed.main)
          focus = ed.main
        else:
          ed.prompt.insert("next")
          ed.prompt.selected.a = 0
          ed.prompt.selected.b = len"next" - 1
      else:
        sh.statusMsg = "Match not found."
    else:
      unmark(ed)
      if action == "filter":
        ed.main.filterLines = false
  of "next":
    if not shiftPressed:
      ed.gotoNextMarker(onlyCurrentFile in sh.searchOptions)
    else:
      ed.gotoPrevMarker(onlyCurrentFile in sh.searchOptions)
  of "prev", "v":
    if not shiftPressed:
      ed.gotoPrevMarker(onlyCurrentFile in sh.searchOptions)
    else:
      ed.gotoNextMarker(onlyCurrentFile in sh.searchOptions)
  of "replace", "r", "replaceall":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var toReplaceWith = ""
      i = parseWord(cmd, toReplaceWith, i)
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
      sh.searchOptions = parseSearchOptions searchOptions
      if action != "replaceall": sh.searchOptions.incl onlyCurrentFile
      ed.findAll(searchPhrase, sh.searchOptions)
      ed.main.findNext(searchPhrase, sh.searchOptions,
                       toReplaceWith)
      if ed.gotoFirstMarker(onlyCurrentFile in sh.searchOptions):
        ed.prompt.clear()
        sh.state = requestedReplace
        sh.statusMsg = askForReplace
      else:
        sh.statusMsg = "Match not found."
    else:
      unmark(ed)
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
        focus = ed.main
    prompt.clear()
  of "save", "s":
    var p = ""
    i = parseWord(cmd, p, i)
    if not p.isAbsolute:
      if ed.main.filename.isNil:
        p = os.getCurrentDir() / p
      else:
        p = ed.main.filename.splitFile.dir / p
    if p.len > 0:
      sh.statusMsg = readyMsg
      var answer = ""
      i = parseWord(cmd, answer, i, true)
      if cmpPaths(ed.main.filename, p) == 0 or
          not os.fileExists(p) or answer[0] == 'y':
        ed.main.saveAs(p)
        try:
          ed.main.filename = expandFilename(p)
        except OSError:
          discard
        success()
      elif answer[0] == 'n':
        success()
      else:
        sh.statusMsg = "File already exists. Overwrite? [yes|no]"
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
    openTab(ed, sh.cfgColors, true)
    success()
  of "script", "scripts", "actions":
    openTab(ed, sh.cfgActions, true)
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
    sh.project = ""
    i = parseWord(cmd, sh.project, i)
    if sh.project.len == 0:
      sh.setTitle(windowTitle)
    else:
      let p = findFile(ed, sh.project.addFileExt("nim"))
      if p.len != 0: sh.project = p
      sh.setTitle(windowTitle & " - " & sh.project.extractFilename)
    success()
  of "nimsug", "nimsuggest", "sug":
    var a = ""
    i = parseWord(cmd, a, i, true)
    case a
    of "shutdown", "stop", "quit", "halt", "exit":
      nimsuggestclient.shutdown()
    of "restart", "start":
      if not startup(sh.theme.nimsuggestPath, sh.project, sh.nimsuggestDebug):
        sh.statusMsg = "Nimsuggest failed for: " & sh.project
    of "debug":
      var onoff = ""
      i = parseWord(cmd, onoff, i, true)
      sh.nimsuggestDebug = onoff != "off"
    else:
      sh.statusMsg = "wrong command, try: start|stop|debug"
    success()
  of "help":
    openDefaultBrowser getAppDir() / "docs.html"
    success()
  else:
    sh.statusMsg = "wrong command, try: help|open|save|find|..."
