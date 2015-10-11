
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


const
  saveChanges = "Closing tab: Save changes? [yes|no|abort]"
  askForReplace = "Replace? [yes|no|abort|all]"

proc askForQuitTab(ed: Editor) =
  let prompt = ed.prompt
  prompt.clear()
  ed.statusMsg = saveChanges
  ed.focus = prompt

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
        ed.main.gotoNextMarker()
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
      ed.main.gotoNextMarker()
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
        ed.main.gotoNextMarker()
      ed.statusMsg = readyMsg
      ed.prompt.clear()
      ed.focus = ed.main
      ed.state = requestedNothing
  of "quit", "q": result = true
  of "find", "f":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
      ed.main.findNext(searchPhrase, parseSearchOptions searchOptions)
      if ed.main.gotoFirstMarker():
        ed.prompt.clear()
        ed.prompt.insert("next")
      else:
        ed.statusMsg = "Match not found."
    else:
      unmark()
  of "next":
    ed.main.gotoNextMarker()
  of "prev":
    ed.main.gotoPrevMarker()
  of "replace", "r":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var toReplaceWith = ""
      i = parseWord(cmd, toReplaceWith, i)
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
      ed.main.findNext(searchPhrase, parseSearchOptions searchOptions,
                       toReplaceWith)
      if ed.main.gotoFirstMarker():
        ed.prompt.clear()
        ed.state = requestedReplace
        ed.statusMsg = askForReplace
      else:
        ed.statusMsg = "Match not found."
    else:
      unmark()
  of "goto", "g":
    var line = ""
    i = parseWord(cmd, line, i, true)
    if line.len > 0:
      var lineAsInt = -1
      case line
      of "end", "last", "ending", "e":
        lineAsInt = high(int)
      of "begin", "start", "first", "b":
        lineAsInt = 1
      else:
        discard parseutils.parseInt(line, lineAsInt)
      if lineAsInt >= 0:
        var col = -1
        i = parseWord(cmd, line, i, true)
        discard parseutils.parseInt(line, col)
        ed.main.gotoLine(lineAsInt, col)
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
    if p.len > 0: openTab(ed, p)
    success()
  of "lang":
    var lang = ""
    i = parseWord(cmd, lang, i)
    ed.main.lang = getSourceLanguage(lang)
    highlightEverything(ed.main)
    success()
  of "config", "conf", "cfg", "colors":
    openTab(ed, ed.cfgColors)
    success()
  of "script", "scripts":
    openTab(ed, ed.cfgActions)
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
  else:
    ed.statusMsg = "wrong command, try: open|save|find|replace|..."
