# Included from nimedit.nim. Implements the exposed API for Nimscript support.

# List only the imports that the main file doesn't already import here:
import
  compiler/[ast, vm, vmdef],
  nimscriptsupport

proc setupApi(result: PEvalContext; sh: SharedState) =
  gConfig.errorMax = high(int)
  gConfig.writelnHook = proc (msg: string) =
    sh.firstWindow.console.insertReadOnly(msg & '\L')

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
    let res = if i < 0: '\0' else: sh.activeWindow.main[i]
    setResult(a, res.ord)
  expose tokenAt:
    let i = getInt(a, 0)
    let res = if i < 0: TokenClass.None else: sh.activeWindow.main.getCell(i).s
    setResult(a, res.ord)
  expose insert:
    let x = getString(a, 0)
    dec sh.activeWindow.main.version
    sh.activeWindow.main.insert(x)
  expose setLang:
    sh.activeWindow.main.lang = SourceLanguage(getInt(a, 0))
  expose getLang:
    setResult(a, sh.activeWindow.main.lang.ord)
  expose remove:
    let x = getInt(a, 0)
    let y = getInt(a, 1)
    sh.activeWindow.main.removeText(x.int, y.int)
  expose getSelection:
    let res = newNode(nkPar)
    res.add newIntNode(nkIntLit, sh.activeWindow.main.selected.a)
    res.add newIntNode(nkIntLit, sh.activeWindow.main.selected.b)
    setResult(a, res)
  expose setSelection:
    let b = sh.activeWindow.main
    let x = getInt(a, 0).int.clamp(0, b.len-1)
    let y = getInt(a, 1).int.clamp(-1, b.len-1)
    sh.activeWindow.main.selected.a = x
    sh.activeWindow.main.selected.b = y
  expose setFocus:
    let x = getInt(a, 0)
    if x <= 0:
      sh.focus = sh.activeWindow.main
    elif x == 1:
      sh.focus = sh.activeWindow.prompt
    elif sh.activeWindow.hasConsole:
      sh.focus = sh.activeWindow.console
  expose setPrompt:
    let x = getString(a, 0)
    sh.activeWindow.prompt.clear()
    sh.activeWindow.prompt.insert(x)
  expose getPrompt:
    setResult(a, sh.activeWindow.prompt.fullText)
  expose clear:
    sh.activeWindow.main.clear()
  expose gotoPos:
    let b = sh.activeWindow.main
    let x = getInt(a, 0).int
    let y = getInt(a, 1).int
    b.gotoLine(x+1, y+1)

  expose setCaret:
    let b = sh.activeWindow.main
    let x = getInt(a, 0).int
    b.gotoPos(x)
  expose getCaret:
    let b = sh.activeWindow.main
    setResult(a, b.cursor)
  expose currentLineNumber:
    let b = sh.activeWindow.main
    setResult(a, b.currentLine)
  expose openTab:
    let x = getString(a, 0)
    setResult(a, sh.activeWindow.openTab(x, true))
  expose closeTab:
    sh.activeWindow.removeBuffer(sh.activeWindow.main)
  expose getHistory:
    let i = getInt(a, 0).int
    let cmds = sh.activeWindow.con.hist[""].cmds
    if i < 0 or i >= cmds.len:
      setResult(a, "")
    else:
      setResult(a, cmds[i])
  expose historyLen:
    setResult(a, sh.activeWindow.con.hist[""].cmds.len)
  expose runConsoleCmd:
    sh.activeWindow.console.gotoPos(sh.activeWindow.console.len)
    var aa = getString(a, 0)
    sh.activeWindow.console.insertReadonly(aa)
    let x = sh.activeWindow.con.runCommand(aa)
    if x.len > 0:
      sh.activeWindow.openTab(x, true)
  expose currentFilename:
    setResult(a, sh.activeWindow.main.filename)
  expose addSearchPath:
    sh.addSearchPath(getString(a, 0))
  expose getSearchPath:
    let i = getInt(a, 0).int
    if i < 0 or i >= sh.searchPath.len:
      setResult(a, "")
    else:
      setResult(a, sh.searchPath[i])
  expose setStatus:
    sh.statusMsg = getString(a, 0)
  expose save:
    sh.activeWindow.main.save()
  expose saveAs:
    sh.activeWindow.main.saveAs(getString(a, 0))
  expose defineAlias:
    sh.activeWindow.con.aliases.add((getString(a, 0), getString(a, 1)))

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
      sh.keymapping[bitset] = Command(action: Action(action),
                                      arg: getString(a, 2))
