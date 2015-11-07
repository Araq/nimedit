# Included from nimedit.nim. Implements the exposed API for Nimscript support.

# List only the imports that the main file doesn't already import here:
import
  compiler/ast, compiler/vm, compiler/vmdef, compiler/msgs

proc setupApi(result: PEvalContext; ed: Editor) =
  msgs.gErrorMax = high(int)
  msgs.writelnHook = proc (msg: string) =
    ed.console.insertReadOnly(msg & '\L')

  # XXX: Expose markers.
  template expose(name, body) {.dirty.} =
    result.registerCallback "nimedit.editor." & astToStr(name),
      proc (a: VmArgs) =
        body

  when false:
    var errorMsg: string
    template edex(name, body) {.dirty.} =
      result.registerCallback "nimedit.editor." & astToStr(name),
        proc (a: VmArgs) =
          try:
            body
          except OSError:
            errorMsg = getCurrentExceptionMsg()

  expose charAt:
    let i = getInt(a, 0)
    let res = if i < 0: '\0' else: ed.main[i]
    setResult(a, res.ord)
  expose tokenAt:
    let i = getInt(a, 0)
    let res = if i < 0: TokenClass.None else: ed.main.getCell(i).s
    setResult(a, res.ord)
  expose insert:
    let x = getString(a, 0)
    dec ed.main.version
    ed.main.insert(x)
  expose setLang:
    ed.main.lang = SourceLanguage(getInt(a, 0))
  expose getLang:
    setResult(a, ed.main.lang.ord)
  expose remove:
    let x = getInt(a, 0)
    let y = getInt(a, 1)
    ed.main.removeText(x.int, y.int)
  expose getSelection:
    let res = newNode(nkPar)
    res.add newIntNode(nkIntLit, ed.main.selected.a)
    res.add newIntNode(nkIntLit, ed.main.selected.b)
    setResult(a, res)
  expose setSelection:
    let b = ed.main
    let x = getInt(a, 0).int.clamp(0, b.len-1)
    let y = getInt(a, 1).int.clamp(-1, b.len-1)
    ed.main.selected.a = x
    ed.main.selected.b = y
  expose setFocus:
    let x = getInt(a, 0)
    if x <= 0:
      ed.focus = ed.main
    elif x == 1:
      ed.focus = ed.prompt
    elif ed.hasConsole:
      ed.focus = ed.console
  expose setPrompt:
    let x = getString(a, 0)
    ed.prompt.clear()
    ed.prompt.insert(x)
  expose getPrompt:
    setResult(a, ed.prompt.fullText)
  expose clear:
    ed.main.clear()
  expose gotoPos:
    let b = ed.main
    let x = getInt(a, 0).int
    let y = getInt(a, 1).int
    b.gotoLine(x+1, y+1)

  expose setCaret:
    let b = ed.main
    let x = getInt(a, 0).int
    b.gotoPos(x)
  expose getCaret:
    let b = ed.main
    setResult(a, b.cursor)
  expose currentLineNumber:
    let b = ed.main
    setResult(a, b.currentLine)
  expose openTab:
    let x = getString(a, 0)
    setResult(a, ed.openTab(x, true))
  expose closeTab:
    ed.removeBuffer(ed.main)
  expose getHistory:
    let i = getInt(a, 0).int
    if i < 0 or i >= ed.con.hist.cmds.len:
      setResult(a, "")
    else:
      setResult(a, ed.con.hist.cmds[i])
  expose historyLen:
    setResult(a, ed.con.hist.cmds.len)
  expose runConsoleCmd:
    ed.console.gotoPos(ed.console.len)
    ed.console.insert(getString(a, 0))
    ed.con.enterPressed()
  expose currentFilename:
    setResult(a, ed.main.filename)
  expose addSearchPath:
    ed.addSearchPath(getString(a, 0))
  expose getSearchPath:
    let i = getInt(a, 0).int
    if i < 0 or i >= ed.searchPath.len:
      setResult(a, "")
    else:
      setResult(a, ed.searchPath[i])
  expose setStatus:
    ed.statusMsg = getString(a, 0)
  expose save:
    ed.main.save()
  expose saveAs:
    ed.main.saveAs(getString(a, 0))
  expose defineAlias:
    ed.con.aliases.add((getString(a, 0), getString(a, 1)))


  result.registerCallback "nimedit.keydefs.bindKey",
    proc (a: VmArgs) =
      let keyset = getNode(a, 0)
      doAssert keyset.kind == nkCurly
      var bitset: set[Key] = {}
      for n in keyset:
        if n.kind in {nkCharLit..nkUInt64Lit} and n.intVal >= 0 and
           n.intVal <= int(high(Key)):
          bitset.incl n.intVal.Key
        else:
          doAssert false
      let action = getInt(a, 1)
      doAssert action >= 0 and action <= int(high(Action))
      ed.keymapping[bitset] = Command(action: Action(action),
                                      arg: getString(a, 2))
