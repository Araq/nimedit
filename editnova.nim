
import strutils
from parseutils import parseInt
from os import extractFilename, splitFile, expandFilename, cmpPaths, `/`
import sdl2, sdl2/ttf
import buffertype, buffer, styles, unicode, highlighters, console
import languages, themes, nimscriptsupport

when defined(windows):
  import dialogs


# TODO:
#  - markers need to be updated on insert and deletes
#  - regex search&replace
#  - click in console jumps to file
#  - port to Mac: Make Apple-Key the same as CTRL
#  - more intelligent showing of active tabs; select tab with mouse
#  - better line wrapping

# Optional:
#  - large file handling
#  - show line numbers
#  - show scroll bars
#  - highlighting of ()s
#  - highlighting of substring occurences
#  - minimap
# Optimizations:
#  - cache font renderings

const
  readyMsg = "Ready."

type
  EditorState = enum
    requestedNothing,
    requestedShutdown, requestedShutdownNext,
    requestedReplace

  Editor = ref object
    active, main, prompt, console: Buffer # active points to either
                                          # main, prompt or console
    mainRect, promptRect, consoleRect: Rect
    statusMsg: string
    uiFont: FontPtr

    renderer: RendererPtr
    window: WindowPtr
    theme: InternalTheme
    screenW, screenH: cint
    buffersCounter: int
    con, promptCon: Console
    mgr: StyleManager
    cfgPath: string
    state: EditorState

template unkownName(): untyped = "unknown-" & $ed.buffersCounter & ".txt"

proc setDefaults(ed: Editor; fontM: var FontManager) =
  ed.screenW = cint(650)
  ed.screenH = cint(780)
  ed.statusMsg = readyMsg

  ed.main = newBuffer(unkownName(), addr ed.mgr)
  ed.prompt = newBuffer("", addr ed.mgr)
  ed.console = newBuffer("", addr ed.mgr)
  ed.console.lang = langConsole

  ed.buffersCounter = 1
  ed.main.next = ed.main
  ed.main.prev = ed.main
  ed.active = ed.main

  ed.con = newConsole(ed.console)
  ed.con.insertPrompt()
  ed.promptCon = newConsole(ed.prompt)

  ed.uiFont = fontM.fontByName("Arial", 12)
  ed.theme.active[true] = parseColor"#FFA500"
  ed.theme.active[false] = parseColor"#C0C0C0"
  #ed.theme.bg = parseColor"#0c090a"
  ed.theme.bg = parseColor"#292929"
  ed.theme.fg = parseColor"#fafafa"
  ed.theme.cursor = ed.theme.fg
  ed.cfgPath = os.getAppDir() / "nimscript" / "colors.nims"

proc destroy(ed: Editor) =
  destroyRenderer ed.renderer
  destroy ed.window

proc rect(x,y,w,h: int): Rect = sdl2.rect(x.cint, y.cint, w.cint, h.cint)

proc drawBorder(ed: Editor; x, y, w, h: int; b: bool) =
  ed.renderer.setDrawColor(ed.theme.active[b])
  var r = rect(x, y, w, h)
  ed.renderer.drawRect(r)
  var r2 = rect(x+1, y+1, w-2, h-2)
  ed.renderer.drawRect(r2)
  ed.renderer.setDrawColor(ed.theme.bg)

proc renderText(ed: Editor;
                message: string; font: FontPtr; color: Color): TexturePtr =
  var surf: SurfacePtr = renderUtf8Shaded(font, message, color, ed.theme.bg)
  if surf == nil:
    echo("TTF_RenderText")
    return nil
  var texture: TexturePtr = createTextureFromSurface(ed.renderer, surf)
  if texture == nil:
    echo("CreateTexture")
  freeSurface(surf)
  return texture

proc draw(renderer: RendererPtr; image: TexturePtr; y: int) =
  var
    iW: cint
    iH: cint
  queryTexture(image, nil, nil, addr(iW), addr(iH))
  let r = rect(15, y.cint, iW, iH)
  copy(renderer, image, nil, unsafeAddr r)
  destroy image

template insertBuffer(head, n) =
  n.next = head
  n.prev = head.prev
  head.prev.next = n
  head.prev = n
  head = n
  inc ed.buffersCounter

template removeBuffer(n) =
  if ed.buffersCounter > 1:
    let nxt = n.next
    n.next.prev = n.prev
    n.prev.next = n.next
    n = nxt
    dec ed.buffersCounter

proc openTab(ed: Editor; filename: string) =
  var fullpath: string
  try:
    fullpath = expandFilename(filename)
  except OSError:
    ed.statusMsg = getCurrentExceptionMsg()
    return

  # be intelligent:
  var it = ed.main
  while true:
    if cmpPaths(it.filename, fullpath) == 0:
      # just bring the existing tab into focus:
      ed.main = it
      return
    it = it.next
    if it == ed.main: break

  let x = newBuffer(fullpath.extractFilename, addr ed.mgr)
  try:
    x.loadFromFile(fullpath)
    insertBuffer(ed.main, x)
    ed.active = ed.main
  except IOError:
    ed.statusMsg = "cannot open: " & filename


include prompt

proc hasConsole(ed: Editor): bool = ed.consoleRect.x >= 0

proc layout(ed: Editor) =
  let yGap = ed.theme.uiYGap
  let xGap = ed.theme.uiXGap
  let fontSize = ed.theme.editorFontSize.int
  ed.mainRect = rect(15, yGap*3+fontSize,
                        ed.screenW - 15*2,
                        ed.screenH - 7*fontSize - yGap*2)
  ed.promptRect = rect(15, fontSize+yGap*3 + ed.screenH - 7*fontSize,
                          ed.screenW - 15*2,
                          fontSize+yGap*2)
  if ed.screenW > ed.theme.consoleAfter:
    # enable the console:
    let d = ed.screenW div 2
    ed.mainRect.w = d - 15
    ed.consoleRect = ed.mainRect
    ed.consoleRect.x += ed.mainRect.w + xGap.cint*2
  else:
    # disable console:
    ed.consoleRect.x = -1
    # if the console is disabled, it cannot have the focus:
    if ed.active == ed.console: ed.active = ed.main

proc drawBorder(ed: Editor; rect: Rect; active: bool) =
  let yGap = ed.theme.uiYGap
  let xGap = ed.theme.uiXGap
  ed.drawBorder(rect.x - xGap, rect.y - yGap, rect.w + xGap, rect.h + yGap,
                active)

proc withUnsavedChanges(start: Buffer): Buffer =
  result = start
  while true:
    if result.changed: return result
    result = result.next
    if result == start: break
  return nil

proc mainProc(ed: Editor) =
  setupNimscript()
  var fontM: FontManager = @[]
  setDefaults(ed, fontM)
  when false:
    highlighters.setStyles(ed.mgr, fontM)
    ed.mgr.b[mcSelected] = parseColor("#1d1d1d")
    ed.mgr.b[mcHighlighted] = parseColor("#000000")

  template loadTheme() =
    loadTheme(ed.cfgPath, ed.theme, ed.mgr, fontM)
    ed.uiFont = fontM.fontByName(ed.theme.uiFont, ed.theme.uiFontSize)

  loadTheme()
  loadActions(os.getAppDir() / "nimscript" / "actions.nims")

  ed.window = createWindow("Editnova", 10, 30, ed.screenW, ed.screenH,
                            SDL_WINDOW_RESIZABLE)
  ed.renderer = createRenderer(ed.window, -1, Renderer_Software)
  template prompt: expr = ed.prompt
  template active: expr = ed.active
  template main: expr = ed.main
  template renderer: expr = ed.renderer
  template console: expr = ed.console

  var blink = 1
  layout(ed)
  while true:
    var e = Event(kind: UserEvent5)
    # if we have an external process running in the background, we have a
    # much shorter timeout. Nevertheless this should not affect our blinking
    # speed:
    let timeout = if ed.con.processRunning: 100.cint else: 500.cint
    if waitEventTimeout(e, timeout) == SdlSuccess:
      case e.kind
      of QuitEvent:
        ed.state = requestedShutdown
        let b = withUnsavedChanges(main)
        if b == nil: break
        main = b
        ed.askForQuitTab()
      of WindowEvent:
        let w = e.window
        if w.event == WindowEvent_Resized:
          ed.screenW = w.data1
          ed.screenH = w.data2
          layout(ed)
      of MouseButtonDown:
        let w = e.button
        let p = point(w.x, w.y)
        if ed.mainRect.contains(p):
          if active == main:
            main.setCursorFromMouse(ed.mainRect, p, w.clicks.int)
          else:
            active = main
        elif ed.promptRect.contains(p):
          if active == prompt:
            prompt.setCursorFromMouse(ed.promptRect, p, w.clicks.int)
          else:
            active = prompt
        elif hasConsole(ed) and ed.consoleRect.contains(p):
          if active == console:
            console.setCursorFromMouse(ed.consoleRect, p, w.clicks.int)
          else:
            active = console
      of MouseWheel:
        let w = e.wheel
        var p: Point
        discard getMouseState(p.x, p.y)
        let a = if hasConsole(ed) and ed.consoleRect.contains(p): console
                else: main
        a.scrollLines(-w.y*3)
      of TextInput:
        let w = e.text
        active.insertSingleKey($w.text)
      of KeyDown:
        let w = e.key
        case w.keysym.scancode
        of SDL_SCANCODE_BACKSPACE:
          active.backspace()
        of SDL_SCANCODE_DELETE:
          active.deleteKey()
        of SDL_SCANCODE_RETURN:
          if active==main:
            main.insertEnter()
          elif active==prompt:
            if ed.runCmd(prompt.fullText): break
          elif active==console:
            enterPressed(ed.con)
        of SDL_SCANCODE_ESCAPE:
          if (w.keysym.modstate and KMOD_SHIFT) != 0:
            if active == console or not ed.hasConsole: active = main
            else: active = console
          else:
            if active==main: active = prompt
            else: active = main
        of SDL_SCANCODE_RIGHT:
          if (w.keysym.modstate and KMOD_SHIFT) != 0:
            active.selectRight((w.keysym.modstate and KMOD_CTRL) != 0)
          else:
            active.deselect()
            active.right((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_LEFT:
          if (w.keysym.modstate and KMOD_SHIFT) != 0:
            active.selectLeft((w.keysym.modstate and KMOD_CTRL) != 0)
          else:
            active.deselect()
            active.left((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_DOWN:
          if (w.keysym.modstate and KMOD_SHIFT) != 0:
            active.selectDown((w.keysym.modstate and KMOD_CTRL) != 0)
          elif active==prompt:
            ed.promptCon.downPressed()
          elif active == console:
            ed.con.downPressed()
          else:
            active.deselect()
            active.down((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_UP:
          if (w.keysym.modstate and KMOD_SHIFT) != 0:
            active.selectUp((w.keysym.modstate and KMOD_CTRL) != 0)
          elif active==prompt:
            ed.promptCon.upPressed()
          elif active == console:
            ed.con.upPressed()
          else:
            active.deselect()
            active.up((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_TAB:
          if (w.keysym.modstate and KMOD_CTRL) != 0:
            main = main.next
            active = main
          elif active == main:
            if (w.keysym.modstate and KMOD_SHIFT) != 0:
              main.shiftTabPressed()
            else:
              main.tabPressed()
            handleEvent("onTabPressed")
          elif active == console:
            ed.con.tabPressed()
          elif active == prompt:
            ed.promptCon.tabPressed()
        of SDL_SCANCODE_F5:
          highlightEverything(active)
        else: discard
        if (w.keysym.modstate and KMOD_CTRL) != 0:
          # CTRL+Z: undo
          # CTRL+shift+Z: redo
          if w.keysym.sym == ord('z'):
            if (w.keysym.modstate and KMOD_SHIFT) != 0:
              active.redo
            else:
              active.undo
          elif w.keysym.sym == ord('a'):
            active.selectAll()
          elif w.keysym.sym == ord('b'):
            ed.con.sendBreak()
          elif w.keysym.sym == ord('e'):
            ed.runScriptCmd()
          elif w.keysym.sym == ord('f'):
            ed.findCmd()
          elif w.keysym.sym == ord('g'):
            ed.gotoCmd()
          elif w.keysym.sym == ord('h'):
            ed.replaceCmd()
          elif w.keysym.sym == ord('x'):
            let text = active.getSelectedText
            if text.len > 0:
              active.removeSelectedText()
              discard sdl2.setClipboardText(text)
          elif w.keysym.sym == ord('c'):
            let text = active.getSelectedText
            if text.len > 0:
              discard sdl2.setClipboardText(text)
          elif w.keysym.sym == ord('v'):
            let text = sdl2.getClipboardText()
            active.insert($text)
            freeClipboardText(text)
          elif w.keysym.sym == ord('u'):
            main.markers.setLen 0
            if ed.state == requestedReplace: ed.state = requestedNothing
          elif w.keysym.sym == ord('o'):
            when defined(windows):
              let previousLocation =
                if main.filename.len > 0: main.filename.splitFile.dir
                else: ""
              let toOpen = chooseFilesToOpen(nil, previousLocation)
              for p in toOpen:
                ed.openTab(p)
              active = main
          elif w.keysym.sym == ord('s'):
            main.save()
            if cmpPaths(main.filename, ed.cfgPath) == 0:
              loadTheme()
          elif w.keysym.sym == ord('n'):
            let x = newBuffer(unkownName(), addr ed.mgr)
            insertBuffer(main, x)
            active = main
          elif w.keysym.sym == ord('q'):
            if not main.changed:
              removeBuffer(main)
            else:
              ed.askForQuitTab()
      else: discard
      # keydown means show the cursor:
      blink = 0
    else:
      # timeout, so update the blinking:
      if timeout == 500:
        blink = 1-blink
      else:
        inc blink
        if blink >= 5: blink = 0
    if ed.state == requestedShutdownNext:
      ed.state = requestedShutdown
      let b = withUnsavedChanges(main)
      if b == nil: break
      main = b
      ed.askForQuitTab()

    update(ed.con)
    clear(renderer)
    let fileList = ed.renderText(
      main.heading & (if main.changed: "*" else: ""),
      ed.uiFont, ed.theme.fg)
    renderer.draw(fileList, ed.theme.uiYGap)

    renderer.draw(main, ed.mainRect, ed.theme.bg, ed.theme.cursor,
                  blink==0 and active==main)
    ed.drawBorder(ed.mainRect, active==main)

    if ed.hasConsole:
      renderer.draw(console, ed.consoleRect, ed.theme.bg, ed.theme.cursor,
                    blink==0 and active==console)
      ed.drawBorder(ed.consoleRect, active==console)

    renderer.draw(prompt, ed.promptRect, ed.theme.bg, ed.theme.cursor,
                  blink==0 and active==prompt)
    ed.drawBorder(ed.promptRect, active==prompt)

    let statusBar = ed.renderText(ed.statusMsg & main.filename &
                        repeatChar(10) & "Ln: " & $(getLine(main)+1) &
                                        " Col: " & $(getColumn(main)+1) &
                                        " \\t: " & $main.tabSize,
                        ed.uiFont,
                        if ed.statusMsg == readyMsg: ed.theme.fg else: color(0xff, 0x44, 0x44, 0))
    renderer.draw(statusBar,
      ed.screenH - ed.theme.editorFontSize.cint - ed.theme.uiYGap*2)
    present(renderer)
  freeFonts fontM
  destroy ed

if sdl2.init(INIT_VIDEO) != SdlSuccess:
  echo "SDL_Init"
elif ttfInit() != SdlSuccess:
  echo "TTF_Init"
else:
  startTextInput()
  mainProc(Editor())
sdl2.quit()
