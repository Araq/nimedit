
from strutils import contains, startsWith, repeatChar
from os import extractFilename, splitFile
import sdl2, sdl2/ttf
import buffertype, buffer, styles, unicode, dialogs, highlighters, console
import languages


# TODO:
#  - handle TABs properly
#  - support for range markers (required for selections)
#  - select, copy, cut from clipboard
#  - large file handling
#  - show line numbers
#  - show scroll bars; no horizontal scrolling though
#  - minimap
#  - highlighting of ()s
#  - highlighting of substring occurences
#  - search&replace

# Optimizations:
#  - cache font renderings
#  - cache content for quick search&replace

# BUGS:
#  - 'redo' does not work anymore


const
  XGap = 5
  YGap = 5

type
  Theme = object
    bg, fg, cursor: Color
    uiA, uiB: Color
    active: array[bool, Color]
    font: FontPtr # default font

  Editor = ref object
    active, main, prompt, console: Buffer # active points to either
                                          # main, prompt or console
    mainRect, promptRect, consoleRect: Rect
    statusMsg: string

    renderer: RendererPtr
    window: WindowPtr
    theme: Theme
    screenW, screenH: cint
    hist: CmdHistory
    buffersCounter: int
    con: Console

template unkownName(): untyped = "unknown-" & $ed.buffersCounter & ".txt"

proc setDefaults(ed: Editor; mgr: ptr StyleManager; fontM: var FontManager) =
  ed.screenW = cint(650)
  ed.screenH = cint(780)
  ed.statusMsg = "Ready "

  ed.main = newBuffer(unkownName(), mgr)
  ed.prompt = newBuffer("", mgr)
  ed.console = newBuffer("", mgr)
  ed.console.lang = langConsole

  ed.buffersCounter = 1
  ed.main.next = ed.main
  ed.main.prev = ed.main
  ed.active = ed.main
  ed.hist = CmdHistory(cmds: @[], suggested: -1)
  ed.con = newConsole(ed.console)

  ed.theme.font = fontM.fontByName("Arial", 12)
  ed.theme.active[true] = parseColor"#FFA500"
  ed.theme.active[false] = parseColor"#C0C0C0"
  #ed.theme.bg = parseColor"#0c090a"
  ed.theme.bg = parseColor"#2d2d2d"
  ed.theme.fg = parseColor"#fafafa"
  ed.theme.cursor = ed.theme.fg

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


proc runCmd(ed: Editor; cmd: string): bool =
  echo cmd
  ed.hist.addCmd(cmd)
  if cmd.startsWith("#"):
    ed.theme.fg = parseColor(cmd)
  cmd == "quit" or cmd == "q"

proc hasConsole(ed: Editor): bool = ed.consoleRect.x >= 0

proc layout(ed: Editor) =
  ed.mainRect = rect(15, YGap*3+FontSize,
                        ed.screenW - 15*2,
                        ed.screenH - 7*FontSize - YGap*2)
  ed.promptRect = rect(15, FontSize+YGap*3 + ed.screenH - 7*FontSize,
                          ed.screenW - 15*2,
                          FontSize+YGap*2)
  if ed.screenW > 900:
    # enable the console:
    let d = ed.screenW div 2
    ed.mainRect.w = d - 15
    ed.consoleRect = ed.mainRect
    ed.consoleRect.x += ed.mainRect.w + XGap*2
  else:
    # disable console:
    ed.consoleRect.x = -1
    # if the console is disabled, it cannot have the focus:
    if ed.active == ed.console: ed.active = ed.main

proc drawBorder(ed: Editor; rect: Rect; active: bool) =
  ed.drawBorder(rect.x - XGap, rect.y - YGap, rect.w + XGap, rect.h + YGap,
                active)

proc mainProc(ed: Editor) =
  var mgr: StyleManager
  var fontM: FontManager = @[]
  setDefaults(ed, addr mgr, fontM)
  highlighters.setStyles(mgr, fontM)

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
      of QuitEvent: break
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
            main.setCursorFromMouse(ed.mainRect, p)
          else:
            active = main
        elif ed.promptRect.contains(p):
          if active == prompt:
            prompt.setCursorFromMouse(ed.promptRect, p)
          else:
            active = prompt
        elif hasConsole(ed) and ed.consoleRect.contains(p):
          if active == console:
            console.setCursorFromMouse(ed.consoleRect, p)
          else:
            active = console
      of MouseWheel:
        let w = e.wheel
        var p: Point
        discard getMouseState(p.x, p.y)
        let a = if hasConsole(ed) and ed.consoleRect.contains(p): console
                else: main
        a.firstLine -= w.y*3
      of TextInput:
        let w = e.text
        active.insert($w.text)
      of KeyDown:
        let w = e.key
        case w.keysym.scancode
        of SDL_SCANCODE_BACKSPACE:
          active.backspace()
        of SDL_SCANCODE_RETURN:
          if active==main:
            main.insertEnter()
          elif active==prompt:
            if ed.runCmd(prompt.fullText): break
            prompt.clear
          elif active==console:
            enterPressed(ed.con)
        of SDL_SCANCODE_ESCAPE:
          if (w.keysym.modstate and KMOD_SHIFT) != 0:
            if active == console or not ed.hasConsole: active = main
            else: active = console
          else:
            if active==main: active = prompt
            else: active = main
        of SDL_SCANCODE_RIGHT: active.right((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_LEFT: active.left((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_DOWN:
          if active==prompt:
            prompt.clear
            prompt.insert(ed.hist.suggest(up=false))
          elif active == console:
            ed.con.downPressed()
          else:
            active.down((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_UP:
          if active==prompt:
            prompt.clear
            prompt.insert(ed.hist.suggest(up=true))
          elif active == console:
            ed.con.upPressed()
          else:
            active.up((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_TAB:
          if (w.keysym.modstate and KMOD_CTRL) != 0:
            main = main.next
            active = main
          elif active == console:
            ed.con.tabPressed()
        else: discard
        if (w.keysym.modstate and KMOD_CTRL) != 0:
          # CTRL+Z: undo
          # CTRL+shift+Z: redo
          if w.keysym.sym == ord('z'):
            if (w.keysym.modstate and KMOD_SHIFT) != 0:
              active.redo
            else:
              active.undo
          elif w.keysym.sym == ord('b'):
            ed.con.sendBreak()
          elif w.keysym.sym == ord('f'):
            discard "find"
          elif w.keysym.sym == ord('g'):
            discard "goto line"
          elif w.keysym.sym == ord('a'):
            discard "select all"
          elif w.keysym.sym == ord('h'):
            discard "replace"
          elif w.keysym.sym == ord('x'):
            discard "cut"
          elif w.keysym.sym == ord('c'):
            discard "copy"
          elif w.keysym.sym == ord('v'):
            let text = getClipboardText()
            active.insert($text)
            freeClipboardText(text)
          elif w.keysym.sym == ord('o'):
            let previousLocation =
              if main.filename.len > 0: main.filename.splitFile.dir
              else: ""
            let toOpen = chooseFilesToOpen(nil, previousLocation)
            for p in toOpen:
              let x = newBuffer(p.extractFilename, addr mgr)
              x.loadFromFile(p)
              insertBuffer(main, x)
            active = main
          elif w.keysym.sym == ord('s'):
            main.save()
          elif w.keysym.sym == ord('n'):
            let x = newBuffer(unkownName(), addr mgr)
            insertBuffer(main, x)
            active = main
          elif w.keysym.sym == ord('q'):
            removeBuffer(main)
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
    update(ed.con)
    clear(renderer)
    let fileList = ed.renderText(
      main.heading & (if main.changed: "*" else: ""),
      ed.theme.font, ed.theme.fg)
    renderer.draw(fileList, YGap)

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
                                        " Col: " & $(getColumn(main)+1),
                        ed.theme.font, ed.theme.fg)
    renderer.draw(statusBar, ed.screenH-FontSize-YGap*2)
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
