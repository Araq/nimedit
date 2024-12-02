
import
  compiler/[ast, modules, passes,
  condsyms, options,
  llstream, vm, vmdef,
  magicsys, idents,
  modulegraphs, pathutils]

when NimMajor >= 2:
  import
    compiler/[pipelines, commands]
else:
  import
    compiler/sem


from compiler/scriptconfig import setupVM

import os, strutils
import themes, styles, nimscript/common


proc raiseVariableError(ident, typ: string) {.noinline.} =
  raise newException(ValueError,
    "NimScript's variable '" & ident & "' needs a value of type '" & typ & "'.")

proc isStrLit(n: PNode): bool = n.kind in {nkStrLit..nkTripleStrLit}
proc isIntLit(n: PNode): bool = n.kind in {nkCharLit..nkUInt64Lit}

proc getIdent(n: PNode): int =
  if n.kind == nkIdent: n.ident.id
  elif n.kind == nkSym: n.sym.name.id
  else: -1

var identCache* = newIdentCache()
var gConfig* = newConfigRef()
var moduleGraph = newModuleGraph(identCache, gConfig)

var
  actionsModule, colorsModule: PSym

proc getAction(x: string): PSym =
  moduleGraph.someSym actionsModule, getIdent(identCache, x)

proc getIdgen*(): IdGenerator = moduleGraph.idgen

proc getGlobal(varname, field: string): PNode =
  let s = getNimScriptSymbol(moduleGraph, varname)
  assert s != nil, "could not load " & varname
  let n = PCtx(moduleGraph.vm).getGlobalValue(s)
  if n.kind != nkObjConstr:
    raiseVariableError(varname, "object")
  for i in 1 ..< n.len:
    let it = n[i]
    if getIdent(it[0]) == getIdent(identCache, field).id: return it[1]

proc getGlobal(varname, field: string; result: var int) =
  let n = getGlobal(varname, field)
  if n != nil and n.isIntLit:
    result = int(n.intVal)
  else:
    raiseVariableError(varname & "." & field, "int")

proc getGlobal(varname, field: string; result: var byte) =
  let n = getGlobal(varname, field)
  if n != nil and n.isIntLit and n.intVal <% 256:
    result = byte(n.intVal)
  else:
    raiseVariableError(varname & "." & field, "byte")

proc getGlobal(varname, field: string; result: var bool) =
  let n = getGlobal(varname, field)
  if n != nil and n.isIntLit:
    result = n.intVal != 0
  else:
    raiseVariableError(varname & "." & field, "bool")

proc getGlobal(varname, field: string; result: var string) =
  let n = getGlobal(varname, field)
  if n != nil and n.isStrLit:
    result = n.strVal
  else:
    raiseVariableError(varname & "." & field, "string")

proc getGlobal(varname, field: string; result: var type(parseColor"")) =
  let n = getGlobal(varname, field)
  if n != nil and n.isIntLit:
    result = colorFromInt(n.intVal)
  else:
    raiseVariableError(varname & "." & field, "Color")

proc extractStyles(result: var StyleManager; fm: var FontManager;
                   fontSize: byte; fontName: string) =
  let n = PCtx(moduleGraph.vm).getGlobalValue(getNimScriptSymbol(moduleGraph, "tokens"))
  if n.kind == nkBracket and n.len == int(high(TokenClass))+1:
    for i, x in n.sons:
      if x.kind in {nkTupleConstr, nkPar} and x.len == 2 and x[0].isIntLit and x[1].isIntLit:
        let style = FontStyle(x[1].intVal)
        result.a[TokenClass(i)] = Style(
            font: fontByName(fm, fontName, fontSize, style),
            attr: FontAttr(color: colorFromInt(x[0].intVal),
                           style: style,
                           size: fontSize))
      else:
        raiseVariableError("tokens", "array[TokenClass, (Color, FontStyle)]")
  else:
    raiseVariableError("tokens", "array[TokenClass, (Color, FontStyle)]")

proc detectNimLib(): string =
  let nimlibCfg = os.getAppDir() / "nimlib.cfg"
  result = ""
  if fileExists(nimlibCfg):
    result = readFile(nimlibCfg).strip
    if not fileExists(result / "system.nim"): result.setlen 0
  if result.len == 0:
    let nimexe = os.findExe("nim")
    if nimexe.len == 0: quit "cannot find Nim's stdlib location"
    result = nimexe.splitPath()[0] /../ "lib"
    if not fileExists(result / "system.nim"):
      when defined(unix):
        try:
          result = nimexe.expandSymlink.splitPath()[0] /../ "lib"
        except OSError:
          result = getHomeDir() / ".choosenim/toolchains/nim-" & NimVersion / "lib"
      elif defined(windows):
        result = getHomeDir() / ".choosenim/toolchains/nim-" & NimVersion / "lib"
      else:
        # TODO
        {.error: "not implemented".}
      if not fileExists(result / "system.nim"):
        echo result
        quit "cannot find Nim's stdlib location"
  when not defined(release): echo result

proc setupNimscript*(colorsScript: AbsoluteFile): PEvalContext =
  # This is ripped from compiler/scriptconfig's runNimScript.
  when NimMajor >= 2:
    let libraryPath = AbsoluteDir detectNimLib()
    gConfig.libpath = libraryPath
    connectPipelineCallbacks moduleGraph
    initDefines gConfig.symbols

    defineSymbol(gConfig.symbols, "nimscript")
    defineSymbol(gConfig.symbols, "nimconfig")

    gConfig.searchPaths.add(gConfig.libpath)
    unregisterArcOrc(gConfig)
    gConfig.globalOptions.excl optOwnedRefs
    gConfig.selectedGC = gcUnselected

    colorsModule = makeModule(moduleGraph, colorsScript)
    colorsModule.flags.incl sfMainModule

    var vm = setupVM(colorsModule, identCache, colorsScript.string,
                            moduleGraph, moduleGraph.idgen)
    moduleGraph.vm = vm
    moduleGraph.setPipeLinePass(EvalPass)
    moduleGraph.compilePipelineSystemModule()
    discard moduleGraph.processPipelineModule(colorsModule, vm.idgen,
      llStreamOpen(colorsScript, fmRead))


    result = PCtx(moduleGraph.vm)
    result.mode = emRepl
  else:

    let config = moduleGraph.config
    config.libpath = detectNimLib().AbsoluteDir
    add(config.searchPaths, config.libpath)
    add(config.searchPaths, AbsoluteDir(config.libpath.string / "pure"))

    initDefines(config.symbols)
    defineSymbol(config.symbols, "nimscript")
    defineSymbol(config.symbols, "nimconfig")

    registerPass(moduleGraph, semPass)
    registerPass(moduleGraph, evalPass)

    colorsModule = makeModule(moduleGraph, colorsScript)
    incl(colorsModule.flags, sfMainModule)
    moduleGraph.vm = setupVM(colorsModule, identCache, colorsScript.string, moduleGraph, moduleGraph.idgen)
    compileSystemModule(moduleGraph)
    result = PCtx(moduleGraph.vm)
    result.mode = emRepl


proc compileActions*(actionsScript: AbsoluteFile) =
  ## Compiles the actions module for the first time.
  actionsModule = makeModule(moduleGraph, actionsScript)
  processModule(moduleGraph, actionsModule, moduleGraph.idgen, llStreamOpen(actionsScript, fmRead))

proc reloadActions*(actionsScript: AbsoluteFile) =
  #resetModule(actionsModule)
  processModule(moduleGraph, actionsModule, moduleGraph.idgen, llStreamOpen(actionsScript, fmRead))

proc execProc*(procname: string) =
  let a = getAction(procname)
  if a != nil:
    discard vm.execProc(PCtx(moduleGraph.vm), a, [])

proc supportsAction*(procname: string): bool = getAction(procname) != nil

proc runTransformator*(procname, selectedText: string): string =
  let a = getAction(procname)
  if a != nil:
    let res = vm.execProc(PCtx(moduleGraph.vm), a, [newStrNode(nkStrLit, selectedText)])
    if res.isStrLit:
      result = res.strVal

proc loadTheme*(colorsScript: AbsoluteFile; result: var InternalTheme;
                sm: var StyleManager; fm: var FontManager) =
  let m = colorsModule
  #resetModule(m)

  processModule(moduleGraph, m, moduleGraph.idgen, llStreamOpen(colorsScript, fmRead))

  template trivialField(field) =
    getGlobal("theme", astToStr field, result.field)

  template trivialField(externalName, field) =
    getGlobal("theme", externalName, result.field)


  getGlobal("theme", "uiActiveElement", result.active[true])
  getGlobal("theme", "uiInactiveElement", result.active[false])

  getGlobal("theme", "selected", sm.b[mcSelected])
  getGlobal("theme", "highlighted", sm.b[mcHighlighted])

  trivialField "background", bg
  trivialField "foreground", fg
  trivialField cursor
  trivialField cursorWidth
  trivialField uiXGap
  trivialField uiYGap
  trivialField editorFont
  trivialField editorFontSize
  trivialField uiFont
  trivialField uiFontSize
  trivialField tabWidth
  trivialField consoleAfter
  trivialField consoleWidth
  trivialField lines
  trivialField showLines
  trivialField bracket
  trivialField showBracket
  trivialField showIndentation
  trivialField indentation
  trivialField showMinimap
  trivialField showLigatures
  trivialField nimsuggestPath

  let fontName = if result.editorFont.len > 0: result.editorFont
                 else: "DejaVuSansMono"
  extractStyles sm, fm, result.editorFontSize, fontName
