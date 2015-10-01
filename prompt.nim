
proc singleQuoted(s: string): string =
  if find(s, {'\L', '\C'}) >= 0:
    result = escape(s)
  elif find(s, {' ', '\t'}) >= 0:
    result = '\'' & s.replace("'", "''") & '\''
  else:
    result = s

proc findCmd(ed: Editor) =
  let prompt = ed.prompt
  let text = ed.active.getSelectedText()
  ed.active = prompt
  prompt.clear()
  prompt.insert "find " & text.singleQuoted

proc replaceCmd(ed: Editor) =
  let prompt = ed.prompt
  let text = ed.active.getSelectedText()
  ed.active = prompt
  prompt.clear()
  prompt.insert "replace " & text.singleQuoted & " "

proc gotoCmd(ed: Editor) =
  let prompt = ed.prompt
  ed.active = prompt
  prompt.clear()
  prompt.insert "goto "

proc runScriptCmd(ed: Editor) =
  let prompt = ed.prompt
  let text = ed.active.getSelectedText()
  ed.active = prompt
  prompt.clear()
  prompt.insert "e " & text.singleQuoted & " "


const
  saveChanges = "Closing tab: Save changes? [yes|no|abort]"
  askForReplace = "Replace? [yes|no|abort|all]"

proc askForQuitTab(ed: Editor) =
  let prompt = ed.prompt
  prompt.clear()
  ed.statusMsg = saveChanges
  ed.active = prompt

proc runCmd(ed: Editor; cmd: string): bool =
  let prompt = ed.prompt

  ed.promptCon.hist.addCmd(cmd)

  template unmark() =
    ed.active = ed.main
    ed.state = requestedNothing
    ed.statusMsg = readyMsg
    ed.main.markers.setLen 0

  var action = ""
  var i = parseWord(cmd, action, 0, true)
  case action
  of "yes", "y":
    if ed.state == requestedShutdown:
      ed.prompt.clear()
      ed.main.save()
      removeBuffer(ed.main)
      ed.active = ed.main
      ed.state = requestedShutdownNext
    elif ed.state == requestedReplace:
      if ed.main.doReplace():
        ed.main.gotoNextMarker()
      else:
        ed.statusMsg = readyMsg
        ed.state = requestedNothing
        ed.active = ed.main
  of "no", "n":
    if ed.state == requestedShutdown:
      ed.prompt.clear()
      ed.main.changed = false
      removeBuffer(ed.main)
      ed.active = ed.main
      ed.state = requestedShutdownNext
    elif ed.state == requestedReplace:
      ed.main.gotoNextMarker()
  of "abort", "a":
    ed.prompt.clear()
    ed.active = ed.main
    ed.state = requestedNothing
  of "all":
    if ed.state == requestedReplace:
      ed.main.activeMarker = 0
      while ed.main.doReplace():
        ed.main.gotoNextMarker()
      ed.statusMsg = readyMsg
      ed.prompt.clear()
      ed.active = ed.main
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
        ed.main.gotoLine(lineAsInt)
        ed.active = ed.main
    prompt.clear()
  of "save", "s":
    var p = ""
    i = parseWord(cmd, p, i)
    if p.len > 0:
      ed.main.saveAs(p)
    else:
      ed.main.save()
    prompt.clear()
  of "open", "o":
    var p = ""
    i = parseWord(cmd, p, i)
    if p.len > 0: openTab(ed, p)
    prompt.clear()
    ed.active = ed.main
  of "lang":
    var lang = ""
    i = parseWord(cmd, lang, i)
    ed.main.lang = getSourceLanguage(lang)
    highlightEverything(ed.main)
    prompt.clear()
  of "cr":
    ed.main.lineending = "\C"
    prompt.clear()
  of "lf":
    ed.main.lineending = "\L"
    prompt.clear()
  of "crlf":
    ed.main.lineending = "\C\L"
    prompt.clear()
  else:
    ed.statusMsg = "wrong command, try: open|save|find|replace|..."
