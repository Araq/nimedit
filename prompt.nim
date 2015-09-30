
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


const saveChanges = "Closing tab: Save changes ([y]es/[n]o/[a]bort)? "

proc askForQuitTab(ed: Editor) =
  let prompt = ed.prompt
  prompt.clear()
  prompt.insert saveChanges
  ed.active = prompt

proc runCmd(ed: Editor; cmd: string): bool =
  let prompt = ed.prompt
  if cmd.startsWith(saveChanges):
    let action = cmd[^1]
    case action
    of 'a', 'A':
      ed.prompt.clear()
      ed.active = ed.main
      ed.requestedShutdown = false
      ed.requestedShutdownNext = false
    of 'n', 'N':
      ed.prompt.clear()
      ed.main.changed = false
      removeBuffer(ed.main)
      ed.active = ed.main
      ed.requestedShutdownNext = true
    of 'y', 'Y':
      ed.prompt.clear()
      ed.main.save()
      removeBuffer(ed.main)
      ed.active = ed.main
      ed.requestedShutdownNext = true
    else: discard
    return

  ed.promptCon.hist.addCmd(cmd)

  var action = ""
  var i = parseWord(cmd, action, 0, true)
  case action
  of "quit", "q": result = true
  of "find", "f":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
      ed.main.findNext(searchPhrase, parseSearchOptions searchOptions)
  of "replace", "r":
    var searchPhrase = ""
    i = parseWord(cmd, searchPhrase, i)
    if searchPhrase.len > 0:
      var toReplaceWith = ""
      i = parseWord(cmd, toReplaceWith, i)
      var searchOptions = ""
      i = parseWord(cmd, searchOptions, i)
    discard "too implement"
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
