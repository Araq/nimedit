

when defined(gcc) and defined(windows):
  when defined(x86):
    {.link: "icons/crown.o".}

import
  std/[strutils, critbits, os, times, browsers, tables, hashes, intsets,
    exitprocs]
from parseutils import parseInt
import sdl2, sdl2/ttf
import buffertype except Action
import buffer, styles, unicode, highlighters, console
import nimscript/common, nimscript/keydefs, languages, themes,
  nimscriptsupport, tabbar, finder,
  scrollbar, indexer, overviews, nimsuggestclient, minimap

import compiler / pathutils

when defined(windows):
  import dialogs

include version

const
  readyMsg = "Ready."
  windowTitle = "NimEdit v" & Version

type
  Command = object
    action: Action
    arg: string
  KeyMapping = Table[set[Key], Command]

  EditorState = enum
    requestedNothing,
    requestedShutdown, requestedShutdownNext,
    requestedReplace, requestedCloseTab, requestedReload

  Spot = object
    fullpath: string     # again, we are smarter that the other and re-open
                         # the buffer when it comes to it.
    line, col: int
  Spots = object
    wr, rd: int
    a: array[7, Spot]    # keeping track of N different edit
                         # positions should really be enough!

  SharedState = ref object ## state that is shared for all windows
    focus: Buffer
    firstWindow, activeWindow: Editor
    mgr: StyleManager
    statusMsg: string
    uiFont: FontPtr
    ticker, idle, blink: int
    indexer: Index
    hotspots: Spots
    searchPath: seq[string] # we use an explicit search path rather than
                            # the list of open buffers so that it's dead
                            # simple to reopen a recently closed file.
    theme: InternalTheme
    keymapping: KeyMapping
    fontM: FontManager
    cfgColors, cfgActions: AbsoluteFile
    project: string
    nimsuggestDebug, clickOnFilename, windowHasFocus: bool
    state: EditorState
    searchOptions: SearchOptions

  Editor = ref object
    sh: SharedState
    main, prompt, console, autocomplete, minimap, sug: Buffer
    mainRect, promptRect, consoleRect: Rect

    renderer: RendererPtr
    window: WindowPtr
    screenW, screenH: cint
    buffersCounter: int
    con, promptCon: Console
    bar: TabBar
    next: Editor

proc trackSpot(s: var Spots; b: Buffer) =
  if b.filename.len == 0: return
  # positions are only interesting if they are far away (roughly 1 screen):
  const interestingDiff = 30
  # it has to be a really new position:
  let line = b.getLine
  let col = b.getColumn
  var i = 0
  while i < s.a.len and not s.a[i].fullpath.len == 0:
    if b.filename == s.a[i].fullpath:
      # update the existing spot:
      if abs(s.a[i].line - line) < interestingDiff:
        s.a[i].line = line
        s.a[i].col = col
        s.rd = i
        return
    inc i
  s.rd = s.wr
  s.a[s.wr].fullpath = b.filename
  s.a[s.wr].line = line
  s.a[s.wr].col = col
  s.wr = (s.wr+1) mod s.a.len

template unkownName(): untyped = "unknown-" & $ed.buffersCounter & ".txt"

proc newSharedState(): SharedState =
  var ed = SharedState()
  ed.theme.active[true] = parseColor"#FFA500"
  ed.theme.active[false] = parseColor"#C0C0C0"
  ed.theme.bg = parseColor"#292929"
  ed.theme.fg = parseColor"#fafafa"
  ed.theme.cursor = parseColor"#fafafa"
  ed.cfgColors = AbsoluteFile(os.getAppDir() / "nimscript" / "colors.nims")
  ed.cfgActions = AbsoluteFile(os.getAppDir() / "nimscript" / "actions.nims")
  ed.searchPath = @[]
  ed.nimsuggestDebug = true
  ed.keymapping = initTable[set[Key], Command]()
  ed.fontM = @[]
  result = ed

proc setDefaults(ed: Editor; sh: SharedState) =
  ed.sh = sh
  ed.screenW = cint(650)
  ed.screenH = cint(780)
  sh.statusMsg = readyMsg

  ed.prompt = newBuffer("prompt", addr sh.mgr)
  ed.console = newBuffer("console", addr sh.mgr)
  ed.console.lang = langConsole

  ed.autocomplete = newBuffer("autocomplete", addr sh.mgr)
  ed.autocomplete.isSmall = true
  ed.minimap = newBuffer("minimap", addr sh.mgr)
  ed.minimap.isSmall = true
  ed.sug = newBuffer("sug", addr sh.mgr)
  ed.sug.isSmall = true
  ed.sug.lang = langNim

  sh.focus = ed.prompt
  ed.con = newConsole(ed.console)
  ed.promptCon = newConsole(ed.prompt)

proc createUnknownTab(ed: Editor; sh: SharedState) =
  ed.main = newBuffer(unkownName(), addr sh.mgr)
  ed.buffersCounter = 1
  ed.main.next = ed.main
  ed.main.prev = ed.main
  sh.focus = ed.main

proc destroy(ed: Editor) =
  destroyRenderer ed.renderer
  destroy ed.window

template insertBuffer(head, n) =
  n.next = head
  n.prev = head.prev
  head.prev.next = n
  head.prev = n
  head = n
  inc ed.buffersCounter

proc removeBuffer(ed: Editor; n: Buffer) =
  if ed.buffersCounter > 1:
    let nxt = n.next
    if n == ed.bar.first:
      ed.bar.first = nxt
    if n == ed.bar.last:
      ed.bar.last = nxt
    if n == ed.sh.focus:
      ed.sh.focus = nxt
    n.next.prev = n.prev
    n.prev.next = n.next
    ed.main = nxt
    dec ed.buffersCounter

iterator allBuffers(ed: Editor): Buffer =
  let start = ed.main
  var it = start
  while true:
    yield it
    it = it.next
    if it == start: break

proc addSearchPath(ed: SharedState; path: string) =
  for i in 0..ed.searchPath.high:
    if cmpPaths(ed.searchPath[i], path) == 0:
      # move to front so we remember it's a path that's preferred:
      swap(ed.searchPath[i], ed.searchPath[0])
      return
  ed.searchPath.add path

proc findFile(ed: Editor; filename: string): string =
  # be smart and use the list of open tabs as the search path. Ultimately
  # this should also be scriptable.
  if os.isAbsolute filename:
    if fileExists(filename): return filename
    return
  let basePath = if ed.main.filename.len > 0: ed.main.filename.splitFile.dir
                 else: os.getCurrentDir()
  let cwd = basePath / filename
  if fileExists(cwd): return cwd
  for i in 0..ed.sh.searchPath.high:
    let res = ed.sh.searchPath[i] / filename
    if fileExists(res): return res

proc findFileAbbrev(ed: Editor; filename: string): string =
  # open the file in searchpath. Be fuzzy.
  ed.sh.addSearchPath os.getCurrentDir()
  for p in ed.sh.searchPath:
    for k, f in os.walkDir(p, relative=true):
      if k in {pcLinkToFile, pcFile} and not f.ignoreFile:
        # we love substrings:
        if filename in f and '.' in f:
          return p / f

proc getWindow(sh: SharedState; b: Buffer; returnPrevious=false): Editor =
  result = sh.firstWindow
  while result != nil:
    var it = result.main
    var prev: Editor = nil
    while true:
      if it == b:
        if returnPrevious: return prev
        else: return result
      it = it.next
      if it == result.main or it == result.bar.last: break
    prev = result
    result = result.next
  doAssert false

proc openTab(ed: Editor; filename: string;
             doTrack=false): bool {.discardable.} =
  var fullpath = findFile(ed, filename)
  if fullpath.len == 0:
    ed.sh.statusMsg = "cannot open: " & filename
    return false

  fullpath = expandFilename(fullpath)
  ed.sh.statusMsg = readyMsg
  for it in ed.allBuffers:
    if cmpPaths(it.filename, fullpath) == 0:
      # just bring the existing tab into focus:
      let window = getWindow(ed.sh, it)
      if doTrack: trackSpot(ed.sh.hotspots, ed.main)
      if window != ed.sh.activeWindow:
        ed.sh.activeWindow = window
        #setGrab(window.w, true)
      window.main = it
      return true

  # be more intelligent; if now the display name is ambiguous, disambiguate it:
  var displayname = fullpath.extractFilename
  proc disamb(a, b: string; displayA, displayB: var string) =
    # find the "word" in the path that disambiguates properly:
    var aa = a.splitPath()[0]
    var bb = b.splitPath()[0]
    # the last thing we want is yet another fragile 'while true'
    # that can make us hang for edge cases:
    for i in 0..80:
      let canA = aa.splitPath()[1]
      let canB = bb.splitPath()[1]
      if canA != canB:
        displayA.add(":" & canA)
        displayB.add(":" & canB)
        break
      elif canA.len == 0: break
      aa = aa.splitPath()[0]
      bb = bb.splitPath()[0]

  ed.sh.addSearchPath(fullpath.splitFile.dir)
  let x = newBuffer(displayname, addr ed.sh.mgr)
  try:
    x.loadFromFile(fullpath)
    if doTrack: trackSpot(ed.sh.hotspots, ed.main)
    insertBuffer(ed.main, x)
    ed.sh.focus = ed.main
    for it in ed.allBuffers:
      if it.heading == displayname:
        disamb(it.filename, fullpath, it.heading, x.heading)
    result = true
  except IOError:
    ed.sh.statusMsg = "cannot open: " & filename

proc gotoNextSpot(ed: Editor; s: var Spots; b: Buffer) =
  # again, be smart. Do not go to where we already are.
  const interestingDiff = 30
  var i = s.rd
  var j = 0
  while j < s.a.len:
    if not s.a[i].fullpath.len == 0:
      if b.filename != s.a[i].fullpath or
          abs(s.a[i].line - b.currentLine) >= interestingDiff:
        for it in ed.allBuffers:
          if cmpPaths(it.filename, s.a[i].fullpath) == 0:
            ed.main = it
            ed.sh.focus = ed.main
            it.gotoLine(s.a[i].line+1, s.a[i].col+1)
            dec i
            if i < 0: i = s.a.len-1
            s.rd = i
            return
    dec i
    if i < 0: i = s.a.len-1
    inc j

template prompt: untyped = ed.prompt
template focus: untyped = ed.sh.focus
template main: untyped = ed.main
template renderer: untyped = ed.renderer

iterator allWindows(sh: SharedState): Editor =
  var it = sh.firstWindow
  while it != nil:
    yield it
    it = it.next

proc setTitle(sh: SharedState; title: string) =
  for w in allWindows(sh):
    w.window.setTitle title

include prompt

proc hasConsole(ed: Editor): bool = ed.consoleRect.x >= 0

proc layout(ed: Editor) =
  let sh = ed.sh
  let yGap = sh.theme.uiYGap
  let xGap = sh.theme.uiXGap
  let fontSize = sh.theme.editorFontSize.int
  ed.promptRect = rect(15, ed.screenH - 3*fontSize - yGap*3,
                          ed.screenW - 15*2,
                          fontSize+yGap*2)
  ed.mainRect = rect(15, yGap*3+sh.theme.uiFontSize.int+3,
                        ed.screenW - 15*2,
                        ed.promptRect.y -
                        (yGap*5+sh.theme.uiFontSize.int+3))
  if ed.screenW > sh.theme.consoleAfter and sh.theme.consoleAfter >= 0:
    # enable the console:
    let d = ed.screenW * (100 - sh.theme.consoleWidth.cint) div 100
    ed.mainRect.w = d - 15
    ed.consoleRect = ed.mainRect
    ed.consoleRect.w = ed.screenW - d - 15
    ed.consoleRect.x += ed.mainRect.w + xGap.cint*2
  else:
    # disable console:
    ed.consoleRect.x = -1
    # if the console is disabled, it cannot have the focus:
    if sh.focus == ed.console: sh.focus = ed.main

proc withUnsavedChanges(start: Buffer): Buffer =
  result = start
  while true:
    if result.changed: return result
    result = result.next
    if result == start: break
  return nil

proc displayNL(s: string): string =
  if s.len == 0: return "LF"
  case s
  of "\C\L": return "CR-LF"
  of "\C": return "CR"
  else: return "LF"

proc filelistFile(): string =
  const dot = when defined(windows): "" else: "."
  os.getConfigDir() / (dot & "nimedit_filelist.txt")

proc saveOpenTabs(ed: Editor) =
  var f: File
  if open(f, filelistFile(), fmWrite):
    f.writeline(SessionFileVersion)
    f.writeline(ed.sh.project)
    f.writeline(os.getCurrentDir())
    var it = ed.main.prev
    while it != nil:
      if it.filename.len > 0:
        f.writeline("file\t", it.filename, "\t", it.getLine, "\t", it.getColumn)
      if it == ed.main: break
      it = it.prev
    for key, vals in pairs(ed.con.hist):
      f.writeline("histkey\t", key, "\t", vals.suggested)
      for v in vals.cmds:
        f.writeline("histval\t", v)
    f.close()

proc loadOpenTabs(ed: Editor) {.error: "This proc disabled until the " &
    "fileListFile writing proc is fixed".} =
  var oldRoot = ed.main
  var f: File
  var key: string
  if open(f, filelistFile()):
    let fileVersion = f.readline
    if fileVersion == SessionFileVersion:
      ed.sh.project = f.readline
      try:
        os.setCurrentDir f.readline
      except OSError:
        discard
      for line in lines(f):
        let x = line.split('\t')
        case x[0]
        of "file":
          if ed.openTab(x[1]):
            gotoLine(ed.main, parseInt(x[2]), parseInt(x[3]))
            ed.sh.focus = ed.main
            if oldRoot != nil:
              ed.removeBuffer(oldRoot)
              oldRoot = nil
        of "histkey":
          key = x[1]
          let suggested = parseInt(x[2])
          ed.con.hist[key] = CmdHistory(cmds: @[], suggested: suggested)
        of "histval":
          doAssert(not key.len == 0)
          ed.con.hist[key].cmds.add x[1]
        else: discard
    else:
      ed.sh.statusMsg = "cannot restore session; versions differ"
    f.close()

proc sugSelected(ed: Editor; s: Buffer) =
  # this is a bit hacky: We parse the line and if it looks like a
  # filename(line, col) information, we pretend it is:
  var (file, line, col) = extractFilePosition(s)
  if line >= 0:
    # extract directory information:
    let currline = s.getCurrentLine
    let pos = find(currline, '#')
    if pos >= 0:
      file = currline.substr(pos+1) / file
    if ed.openTab(file, true):
      gotoLine(ed.main, line, col)
    else:
      ed.sh.statusMsg = "Cannot open: " & file
  else:
    var main = ed.main
    inc main.version
    let p = main.getWordPrefix
    for i in 0..<p.len:
      dec main.version
      backspace(main, false, overrideUtf8=true)
    # undo the upcoming version increase that 'insert' performs:
    dec main.version
    insert(main, s.getCurrentWord)

proc harddiskCheck(ed: Editor) =
  for it in ed.allBuffers:
    if it.filename.len > 0:
      try:
        let newTimestamp = os.getLastModificationTime(it.filename)
        if it.timestamp != newTimestamp:
          it.timestamp = newTimestamp
          ed.sh.state = requestedReload
          if it != ed.main:
            trackSpot(ed.sh.hotspots, ed.main)
            ed.main = it
          ed.main.changed = true
          ed.sh.focus = ed.prompt
          ed.sh.statusMsg = "File changed on disk. Reload?"
          break
      except OSError:
        discard

const
  DefaultTimeOut = 500.cint
  TimeoutsPerSecond = 1000 div DefaultTimeOut

proc hashPosition(b: Buffer): int = b.currentLine shl 20 + b.firstLine

proc tick(sh: SharedState) =
  let ed = sh.activeWindow
  inc sh.ticker
  if sh.idle > 1:
    # run the index every 500ms. It's incremental and fast.
    indexBuffers(sh.indexer, ed.main)
    highlightIncrementally(ed.main)

    if sh.theme.showMinimap:
      if ed.minimap.version != hashPosition(ed.main):
        fillMinimap(ed.minimap, ed.main)
        ed.minimap.version = hashPosition(ed.main)
      if ed.minimap.heading != ed.main.heading:
        ed.minimap.heading = ed.main.heading
        fillMinimap(ed.minimap, ed.main)
        ed.minimap.version = hashPosition(ed.main)

  # every 10 seconds check if the file's contents have changed on the hard disk
  # behind our back:
  if sh.ticker mod (TimeoutsPerSecond*10) == 0:
    harddiskCheck(ed)

  # periodic events. Every 5 minutes we save the list of open tabs.
  if sh.ticker > TimeoutsPerSecond*60*5:
    sh.ticker = 0
    saveOpenTabs(ed)

proc findProject(ed: Editor): string =
  for it in ed.allBuffers:
    if it.filename.len > 0 and it.lang == langNim:
      for ext in [".nims", ".nimcfg", ".nim.cfg"]:
        let probe = it.filename.changeFileExt(ext)
        if fileExists(probe):
          return "'" & it.filename & "'"
  return ""

proc suggest(ed: Editor; cmd: string) =
  if ed.main.lang != langNim: return
  let sh = ed.sh
  if sh.project.len == 0:
    sh.statusMsg = "Which project?"
    let prompt = ed.prompt
    sh.focus = ed.prompt
    prompt.clear()
    prompt.insert "project " & findProject(ed)
  elif not startup(sh.theme.nimsuggestPath, sh.project, sh.nimsuggestDebug):
    sh.statusMsg = "Nimsuggest failed for: " & sh.project
  else:
    requestSuggestion(ed.main, cmd)
    ed.sug.clear()
    sh.focus = ed.sug

include api

proc handleEvent(ed: Editor; procname: string) =
  try:
    nimscriptsupport.execProc procname
  except:
    ed.con.insertReadonly(getCurrentExceptionMsg())
    if not ed.hasConsole:
      ed.sh.statusMsg = "Errors! Open console to see them."

proc pollEvents*(someConsoleRunning, windowHasFocus: bool): seq[Event] =
  ## Returns all events held by sdl2, blocking to save cycles when possible.
  # Please note that the last (unsuccessful) call the `sdl2.pollEvent` will
  # turn the `e` var hidden pointer's value into garbage.
  # So we have to return some form of copied value, not a pointer.
  result = @[]

  # Initialize an event of any value.
  var e = Event()

  # While nimedit doesnt have focus, wait for an event of some kind (usually
  # a WindowEvent).
  if not (someConsoleRunning or windowHasFocus):
    let wasSucessful = waitEvent(e) # halts while theres no input
    assert wasSucessful
    result.add e

  # Take note of all the events that sdl2 has registered.
  while pollEvent(e): # returns true until no events are left to poll
    result.add e

proc ctrlKeyPressed*(): bool =
  let keys = getKeyboardState()
  result = keys[SDL_SCANCODE_LCTRL.int] == 1 or
           keys[SDL_SCANCODE_RCTRL.int] == 1

proc shiftKeyPressed*(): bool =
  let keys = getKeyboardState()
  result = keys[SDL_SCANCODE_LSHIFT.int] == 1 or
           keys[SDL_SCANCODE_RSHIFT.int] == 1

proc loadTheme(ed: SharedState) =
  loadTheme(ed.cfgColors, ed.theme, ed.mgr, ed.fontM)
  ed.uiFont = ed.fontM.fontByName(ed.theme.uiFont, ed.theme.uiFontSize)
  ed.theme.uiFontPtr = ed.uiFont
  ed.theme.editorFontPtr = ed.fontM.fontByName(ed.theme.editorFont,
                                               ed.theme.editorFontSize)

proc eventToKeySet(e: Event): set[Key] =
  result = {}
  if e.kind == KeyDown: discard
  elif e.kind == KeyUp: result.incl(Key.KeyReleased)
  else: return
  let w = e.key
  let ch = char(w.keysym.sym and 0xff)
  case ch
  of 'a'..'z':
    result.incl(Key(ord(ch) - 'a'.ord + Key.A.ord))
  of '0'..'9':
    result.incl(Key(ord(ch) - '0'.ord + Key.N0.ord))
  else: discard
  case w.keysym.scancode
  of SDL_SCANCODE_F1..SDL_SCANCODE_F12:
    result.incl(Key(ord(Key.F1) + ord(w.keysym.scancode) - SDL_SCANCODE_F1.ord))
  of SDL_SCANCODE_RETURN:
    result.incl(Key.Enter)
  of SDL_SCANCODE_SPACE:
    result.incl(Key.Space)
  of SDL_SCANCODE_ESCAPE:
    result.incl(Key.Esc)
  of SDL_SCANCODE_DELETE:
    result.incl(Key.Del)
  of SDL_SCANCODE_BACKSPACE:
    result.incl Key.Backspace
  of SDL_SCANCODE_INSERT:
    result.incl Key.Ins
  of SDL_SCANCODE_PAGEUP:
    result.incl Key.PageUp
  of SDL_SCANCODE_PAGEDOWN:
    result.incl Key.PageDown
  of SDL_SCANCODE_CAPSLOCK:
    result.incl Key.Capslock
  of SDL_SCANCODE_TAB:
    result.incl Key.Tab
  of SDL_SCANCODE_COMMA:
    result.incl Key.Comma
  of SDL_SCANCODE_PERIOD:
    result.incl Key.Period
  of SDL_SCANCODE_LEFT:
    result.incl Key.Left
  of SDL_SCANCODE_RIGHT:
    result.incl Key.Right
  of SDL_SCANCODE_UP:
    result.incl Key.Up
  of SDL_SCANCODE_DOWN:
    result.incl Key.Down
  else: discard
  when defined(macosx):
    if (w.keysym.modstate and KMOD_GUI()) != 0:
      result.incl Key.Apple
  if (w.keysym.modstate and KMOD_CTRL()) != 0:
    result.incl Key.Ctrl
  if (w.keysym.modstate and KMOD_SHIFT()) != 0:
    result.incl Key.Shift
  if (w.keysym.modstate and KMOD_ALT()) != 0:
    result.incl Key.Alt

proc produceHelp(ed: Editor): string =
  proc getArg(a: Command): string =
    (if a.arg.len == 0: ""
    else: " " & a.arg)
  const width = 24
  result = "\L"
  var probed = initTable[set[Key], Command]()
  for m in Key.Ctrl..Key.Apple:
    for k in Key.A..Key.Z:
      let cmd = ed.sh.keymapping.getOrDefault({m,k})
      if cmd.action != Action.None:
        let keys = $m & "+" & $k
        result.add(keys & repeat(' ', max(1, width-keys.len)) & " " & $cmd.action & cmd.getArg & "\L")
        probed[{m,k}] = Command()
  for k in Key.N0..Key.F12:
    let cmd = ed.sh.keymapping.getOrDefault({k})
    if cmd.action != Action.None:
      let keys = $k
      result.add(keys & repeat(' ', max(1, width-keys.len)) & " " & $cmd.action & cmd.getArg & "\L")
      probed[{k}] = Command()
  # now check for other keybindings, but in no order:
  for binding, cmd in pairs(ed.sh.keymapping):
    if not probed.contains(binding):
      let keys = $binding
      result.add(keys & repeat(' ', max(1, width-keys.len)) & " " & $cmd.action & cmd.getArg & "\L")

proc closeTab(ed: Editor) =
  if not main.changed:
    ed.removeBuffer(main)
  else:
    ed.sh.state = requestedCloseTab
    ed.askForQuitTab()

proc setActiveWindow(sh: SharedState; wid: uint32): Editor =
  if sh.activeWindow.window.getId() != wid:
    for it in sh.allWindows:
      if it.window.getId() == wid:
        sh.activeWindow = it
        break
  return sh.activeWindow

proc createSdlWindow(ed: Editor; maximize: range[0u32 .. 1u32]) =
  # Doesn't work on Linux. Yay.
  when defined(linux):
    const maximized = 0'u32
  else:
    let maximized = SDL_WINDOW_MAXIMIZED * maximize

  ed.window = createWindow(windowTitle, 10, 30, ed.screenW, ed.screenH,
                            SDL_WINDOW_RESIZABLE or maximized)
  ed.window.getSize(ed.screenW, ed.screenH)
  ed.renderer = createRenderer(ed.window, -1, Renderer_Software)


proc moveTabToRightWindow(ed: Editor) =
  let current = ed.main
  var result = ed.next

  ed.removeBuffer(current)
  if result.isNil:
    result = Editor()
    result.setDefaults(ed.sh)
    result.screenW = ed.screenW
    result.screenH = ed.screenH
    createSdlWindow(result, 0u32)
    result.next = ed.next
    ed.next = result
    result.bar.first = current
    result.bar.last = result.bar.first
    layout(result)
  if ed.bar.last.isNil:
    ed.bar.last = ed.bar.first.prev

  #insertBuffer(result.main, current)
  result.main = current
  current.prev = ed.bar.last
  ed.bar.last.next = current
  if result.buffersCounter == 0:
    current.next = ed.bar.first
  else:
    current.next = result.bar.first
  current.next.prev = current
  result.bar.first = current
  ed.sh.focus = current
  ed.sh.activeWindow = result

proc closeWindow(ed: Editor) =
  var left = ed.sh.firstWindow
  while left.next != ed:
    left = left.next
  # move all tabs back to the Window on the left:
  left.bar.last = ed.bar.last
  destroy ed
  left.next = left.next.next
  ed.sh.activeWindow = left

proc runAction(ed: Editor; action: Action; arg: string): bool =
  template console: untyped = ed.console

  case action
  of Action.None: discard
  of Action.ShowHelp:
    ed.con.insertReadonly(produceHelp(ed))
    ed.con.insertPrompt()
  of Action.Left, Action.LeftJump:
    focus.deselect()
    focus.left(action == Action.LeftJump)
  of Action.Right, Action.RightJump:
    focus.deselect()
    focus.right(action == Action.RightJump)
  of Action.Up, Action.UpJump:
    if focus==prompt:
      ed.promptCon.upPressed()
    elif focus == console:
      ed.con.upPressed()
    else:
      focus.deselect()
      focus.up(action == Action.UpJump)
  of Action.Down, Action.DownJump:
    if focus==prompt:
      ed.promptCon.downPressed()
    elif focus == console:
      ed.con.downPressed()
    else:
      focus.deselect()
      focus.down(action == Action.DownJump)
  of Action.LeftSelect, Action.LeftJumpSelect:
    focus.selectLeft(action == Action.LeftJumpSelect)
  of Action.RightSelect, Action.RightJumpSelect:
    focus.selectRight(action == Action.RightJumpSelect)
  of Action.UpSelect, Action.UpJumpSelect:
    focus.selectUp(action == Action.UpJumpSelect)
  of Action.DownSelect, Action.DownJumpSelect:
    focus.selectDown(action == Action.DownJumpSelect)

  of Action.PageUp:
    focus.scrollLines(-focus.span)
    focus.cursor = focus.firstLineOffset
  of Action.PageDown:
    focus.scrollLines(focus.span)
    focus.cursor = focus.firstLineOffset

  of Action.Insert:
    if arg.len > 0:
      focus.insertSingleKey(arg)
  of Action.Backspace:
    if focus==ed.autocomplete or focus==ed.sug:
      # delegate to main, but keep the focus on the autocomplete!
      main.backspace(false)
      if focus==ed.autocomplete:
        populateBuffer(ed.sh.indexer, ed.autocomplete, main.getWordPrefix())
      else:
        gotoPrefix(ed.sug, main.getWordPrefix())
      trackSpot(ed.sh.hotspots, main)
    elif focus == ed.prompt:
      focus.backspacePrompt()
    else:
      focus.backspace(true)
      if focus==main: trackSpot(ed.sh.hotspots, main)
  of Action.Del:
    focus.deleteKey()
    if focus==main: trackSpot(ed.sh.hotspots, main)
  of Action.DelVerb:
    focus.deleteVerb()
    if focus==main: trackSpot(ed.sh.hotspots, main)
  of Action.Enter:
    if focus==main:
      main.insertEnter()
      trackSpot(ed.sh.hotspots, main)
    elif focus==prompt:
      if ed.runCmd(prompt.fullText, shiftKeyPressed()):
        saveOpenTabs(ed)
        result = true
    elif focus==console:
      let x = enterPressed(ed.con)
      if x.len > 0:
        openTab(ed, x, true)
    elif focus==ed.autocomplete:
      indexer.selected(ed.autocomplete, main)
      focus = main
    elif focus==ed.sug:
      sugSelected(ed, ed.sug)
      focus = main

  of Action.Dedent:
    if focus == main:
      main.shiftTabPressed()
  of Action.Indent:
    if focus == main:
      main.tabPressed()
    elif focus == console:
      ed.con.tabPressed(os.getCurrentDir())
    elif focus == prompt:
      let basePath = if main.filename.len > 0: main.filename.splitFile.dir
                     else: os.getCurrentDir()
      ed.promptCon.tabPressed(basePath)

  of Action.SwitchEditorPrompt:
    if focus==main: focus = prompt
    else: focus = main
  of Action.SwitchEditorConsole:
    if focus == console or not ed.hasConsole: focus = main
    else: focus = console

  of Action.Copy:
    let text = focus.getSelectedText
    if text.len > 0:
      discard sdl2.setClipboardText(cstring text)
  of Action.Cut:
    let text = focus.getSelectedText
    if text.len > 0:
      focus.removeSelectedText()
      discard sdl2.setClipboardText(cstring text)
  of Action.Paste:
    let text = sdl2.getClipboardText()
    focus.insert($text, smartInsert=true)
    freeClipboardText(text)

  of Action.AutoComplete:
    let prefix = main.getWordPrefix()
    if prefix[^1] == '.':
      ed.suggest("sug")
    elif prefix[^1] == '(':
      ed.suggest("con")
    else:
      focus = ed.autocomplete
      populateBuffer(ed.sh.indexer, ed.autocomplete, prefix)

  of Action.Undo:
    if focus==prompt: prompt.undo
    else: main.undo
  of Action.Redo:
    if focus==prompt: prompt.redo
    else: main.redo

  of Action.SelectAll: focus.selectAll()
  of Action.SendBreak: ed.con.sendBreak()

  of Action.UpdateView:
    main.markers.setLen 0
    if ed.sh.state == requestedReplace: ed.sh.state = requestedNothing
    highlightEverything(focus)

  of Action.OpenTab: ed.openCmd()
  of Action.SaveTab:
    main.save()
    let sh = ed.sh
    if cmpPaths(main.filename, sh.cfgColors.string) == 0:
      loadTheme(sh)
      layout(ed)
    elif cmpPaths(main.filename, sh.cfgActions.string) == 0:
      reloadActions(sh.cfgActions)
    sh.statusMsg = readyMsg

  of Action.NewTab:
    let x = newBuffer(unkownName(), addr ed.sh.mgr)
    insertBuffer(main, x)
    focus = main
  of Action.CloseTab:
    ed.closeTab()

  of Action.MoveTabLeft:
    # if already leftmost, create new window to the left:
    if ed.buffersCounter >= 2:
      discard "too implement"
  of Action.MoveTabRight:
    if ed.buffersCounter >= 2:
      moveTabToRightWindow(ed)

  of Action.QuitApplication: sdl2.quit()
  of Action.Declarations:
    if main.lang == langNim:
      main.filterLines = not main.filterLines
      if main.filterLines:
        filterMinimap(main)
        caretToActiveLine main
      else:
        main.gotoPos(main.cursor)
    else:
      ed.sh.statusMsg = "List of declarations only supported for Nim."
  of Action.NextBuffer:
    main = main.next
    focus = main
  of Action.PrevBuffer:
    main = main.prev
    focus = main
  of Action.NextEditLocation:
    trackSpot(ed.sh.hotspots, main)
    ed.gotoNextSpot(ed.sh.hotspots, main)
    focus = main

  of Action.InsertPrompt:
    focus = prompt
    prompt.clear()
    prompt.insert arg
  of Action.InsertPromptSelectedText:
    let text = focus.getSelectedText()
    focus = prompt
    prompt.clear()
    prompt.insert arg & text.singleQuoted
  of Action.Nimsuggest:
    ed.suggest(arg)
  of Action.NimScript:
    ed.handleEvent(arg)

proc handleQuitEvent(ed: Editor): bool =
  saveOpenTabs(ed)
  ed.sh.state = requestedShutdown
  let b = withUnsavedChanges(main)
  if b == nil:
    result = true
  else:
    main = b
    ed.askForQuitTab()

proc processEvents(events: out seq[Event]; ed: Editor): bool =
  template console: untyped = ed.console

  let sh = ed.sh

  events = pollEvents(ed.con.processRunning, sh.windowHasFocus)

  for e in events:
    case e.kind
    of QuitEvent:
      if handleQuitEvent(ed):
        result = true
        break
    of WindowEvent:
      let w = e.window
      let ed = ed.sh.setActiveWindow(w.windowId)
      case w.event
      of WindowEvent_Resized:
        ed.screenW = w.data1
        ed.screenH = w.data2
        layout(ed)
      of WindowEvent_FocusLost:
        sh.windowHasFocus = false
      of WindowEvent_FocusGained:
        sh.windowHasFocus = true
      of WindowEvent_Close:
        if sh.firstWindow.next.isNil:
          if handleQuitEvent(ed):
            result = true
            break
        else:
          closeWindow(sh.activeWindow)
      else: discard
    of MouseButtonDown:
      let w = e.button
      # This mitigates problems with older SDL 2 versions. Prior to 2.0.3
      # there was no 'clicks' field. Yeah introduce major features in
      # a bugfix release, why not...
      if w.clicks == 0 or w.clicks > 5u8: w.clicks = 1
      if ctrlKeyPressed(): inc(w.clicks)
      let p = point(w.x, w.y)
      if ed.mainRect.contains(p) and ed.main.scrollingEnabled:
        # XXX extract to a proc
        var rawMainRect = ed.mainRect
        rawMainRect.w -= scrollBarWidth
        if focus == main and rawMainRect.contains(p):
          main.setCursorFromMouse(ed.mainRect, p, w.clicks.int)
        else:
          focus = main
      elif ed.promptRect.contains(p):
        if focus == prompt:
          prompt.setCursorFromMouse(ed.promptRect, p, w.clicks.int)
        else:
          focus = prompt
      elif hasConsole(ed) and ed.consoleRect.contains(p):
        if focus == console:
          console.setCursorFromMouse(ed.consoleRect, p, w.clicks.int)
          ed.sh.clickOnFilename = w.clicks.int >= 2
        else:
          focus = console
    of MouseWheel:
      let w = e.wheel
      var p: Point
      discard getMouseState(p.x, p.y)
      let a = if hasConsole(ed) and ed.consoleRect.contains(p): console
              else: focus
      a.scrollLines(-w.y*3)
    of TextInput:
      let w = e.text
      # surpress CTRL+Space:
      var surpress = false
      if w.text[0] == ' ' and w.text[1] == '\0':
        if ctrlKeyPressed():
          surpress = true
      if not surpress:
        if focus==ed.autocomplete or focus==ed.sug:
          # delegate to main, but keep the focus on the autocomplete!
          main.insertSingleKey($cast[cstring](addr w.text))
          if focus==ed.autocomplete:
            populateBuffer(ed.sh.indexer, ed.autocomplete, main.getWordPrefix())
          else:
            gotoPrefix(ed.sug, main.getWordPrefix())
          trackSpot(ed.sh.hotspots, main)
        else:
          focus.insertSingleKey($cast[cstring](addr w.text))
          if focus==main: trackSpot(ed.sh.hotspots, main)
    of KeyDown, KeyUp:
      let ks = eventToKeySet(e)
      let cmd = sh.keymapping.getOrDefault(ks)
      if ed.runAction(cmd.action, cmd.arg):
        result = true
        break
    else: discard
    # keydown means show the cursor:
    sh.blink = 0
    sh.idle = 0

proc draw(events: sink seq[Event]; ed: Editor) =
  let sh = ed.sh
  # position of the tab bar hard coded for now as we don't want to adapt it
  # to the main margin (tried it, is ugly):
  let activeTab = drawTabBar(ed.bar, sh.theme, 47, ed.screenW,
                             events, ed.main)
  if activeTab != nil:
    if (getMouseState(nil, nil) and SDL_BUTTON(BUTTON_RIGHT)) != 0:
      let oldMain = main
      if not activeTab.changed:
        ed.removeBuffer(activeTab)
        if oldMain != activeTab: main = oldMain
      else:
        ed.sh.state = requestedCloseTab
        main = activeTab
        ed.askForQuitTab()
    else:
      main = activeTab
    focus = main

  var rawMainRect = ed.mainRect
  if main.scrollingEnabled:
    rawMainRect.w -= scrollBarWidth
  sh.theme.draw(main, rawMainRect, (sh.blink==0 and focus==main) or
                                    focus==ed.autocomplete,
                if sh.theme.showLines: {showLines} else: {})
  let scrollTo = drawScrollBar(main, sh.theme, events, ed.mainRect)
  if scrollTo >= 0:
    scrollLines(main, scrollTo-main.firstLine)

  var mainBorder = ed.mainRect
  mainBorder.x = spaceForLines(main, sh.theme).cint + sh.theme.uiXGap.cint + 2
  mainBorder.w = ed.mainRect.x + ed.mainRect.w - 1 - mainBorder.x
  sh.theme.drawBorder(mainBorder, focus==main)
  if main.posHint.w > 0 and ed.minimap.len > 0 and sh.theme.showMinimap and
      main.cursorDim.h > 0 and ed.minimap.heading == ed.main.heading:
    # cursorDim.h > 0 means that the cursor is in the view. The minimap is
    # too confusing when the cursor is not visible.
    main.posHint.x += sh.theme.uiXGap.cint
    main.posHint.y += sh.theme.uiYGap.cint
    main.posHint.w -= sh.theme.uiXGap.cint
    main.posHint.h -= sh.theme.uiYGap.cint * 2

    main.posHint.h = min(sh.theme.draw(ed.minimap, main.posHint,
                                   false, {showGaps}) -
                     main.posHint.y + 1, main.posHint.h)
    sh.theme.drawBorder(main.posHint, sh.theme.lines)

  if focus == ed.autocomplete or focus == ed.sug:
    var autoRect = mainBorder
    autoRect.x += 10
    autoRect.w -= 20
    autoRect.y = cint(main.cursorDim.y + main.cursorDim.h + 10)
    autoRect.h = min(ed.mainRect.y + ed.mainRect.h - autoRect.y, 400)
    sh.theme.drawBorderBox(autoRect, true)
    sh.theme.drawAutoComplete(focus, autoRect)

  if ed.hasConsole:
    sh.theme.draw(ed.console, ed.consoleRect,
                  sh.blink==0 and focus==ed.console)
    sh.theme.drawBorder(ed.consoleRect, focus==ed.console)
    #console.span = ed.consoleRect.h div fontLineSkip(sh.theme.editorFontPtr)

  sh.theme.draw(prompt, ed.promptRect, sh.blink==0 and focus==prompt)
  sh.theme.drawBorder(ed.promptRect, focus==prompt)

  let statusBar = sh.theme.renderText(ed.sh.statusMsg & "     " & main.filename,
                      sh.uiFont,
    if ed.sh.statusMsg == readyMsg: sh.theme.fg else: color(0xff, 0x44, 0x44, 0))
  let bottom = ed.screenH - sh.theme.editorFontSize.cint - sh.theme.uiYGap*2

  let position = sh.theme.renderText("Ln: " & $(getLine(main)+1) &
                                     " Col: " & $(getColumn(main)+1) &
                                     " \\t: " & $main.tabSize &
                                     " " & main.lineending.displayNL,
                                     sh.uiFont, sh.theme.fg)
  renderer.draw(statusBar, 15, bottom)
  renderer.draw(position,
    ed.mainRect.x + ed.mainRect.w - 14*sh.theme.uiFontSize.int, bottom)

  present(renderer)

proc drawAllWindows(sh: SharedState; events: sink seq[Event]) =
  var ed = sh.firstWindow
  while ed != nil:
    clear(renderer)
    # little hack so that not everything needs to be rewritten
    ed.sh.theme.renderer = renderer
    if ed == sh.activeWindow:
      draw(events, ed)
    else:
      draw(@[], ed)
    ed = ed.next

proc mainProc(ed: Editor) =
  addExitProc nimsuggestclient.shutdown

  var sh = newSharedState()
  setDefaults(ed, sh)
  createUnknownTab(ed, sh)
  sh.activeWindow = ed
  sh.firstWindow = ed
  let scriptContext = setupNimscript(sh.cfgColors)
  scriptContext.setupApi(sh)
  compileActions(sh.cfgActions)

  loadTheme(sh)
  createSdlWindow(ed, 1u32)

  include nimscript/keybindings #XXX TODO: nimscript instead of include

  ed.bar.first = ed.main

  sh.blink = 1
  sh.clickOnFilename = false
  layout(ed)
  # XXX TODO: fix this proc: loadOpenTabs(ed)
  if sh.project.len > 0:
    sh.setTitle(windowTitle & " - " & sh.project.extractFilename)
  ed.con.insertPrompt()
  sh.windowHasFocus = true
  # we only redraw if an event has been processed or after a timeout
  # for the cursor blinking in order to save CPU cycles massively:
  var doRedraw = true
  var oldTicks = getTicks()
  while true:
    # we need to wait for the next frame until the cursor has moved to the
    # right position:
    if sh.clickOnFilename:
      sh.clickOnFilename = false
      let (file, line, col) = ed.console.extractFilePosition()
      if file.len > 0 and line > 0:
        if ed.openTab(file, true):
          gotoLine(main, line, col)
          focus = main

    var events: seq[Event] = @[]
    if processEvents(events, sh.activeWindow): break
    if sh.state == requestedShutdownNext:
      sh.state = requestedShutdown
      let b = withUnsavedChanges(main)
      if b == nil: break
      main = b
      ed.askForQuitTab()

    if events.len != 0 or doRedraw:
      doRedraw = false
      update(ed.con)
      nimsuggestclient.update(ed.sug)
      sh.drawAllWindows(events)
    # if we have an external process running in the background, we have a
    # much shorter timeout. Nevertheless this should not affect our blinking
    # speed:
    let timeout = if ed.con.processRunning or nimsuggestclient.processing:
                    100.cint
                  else:
                    DefaultTimeOut
    # reduce CPU usage:
    delay(20)
    let newTicks = getTicks()
    if newTicks - oldTicks > timeout.uint32:
      oldTicks = newTicks

      inc sh.idle
      if timeout == 500:
        sh.blink = 1-sh.blink
        tick(sh)
        doRedraw = true
      else:
        inc sh.blink
        if sh.blink >= 5:
          sh.blink = 0
          tick(sh)
          doRedraw = true

  freeFonts sh.fontM
  destroy ed



if sdl2.init(INIT_VIDEO) != SdlSuccess:
  echo "SDL_Init"
elif ttfInit() != SdlSuccess:
  echo "TTF_Init"
else:
  startTextInput()
  mainProc(Editor())
sdl2.quit()
