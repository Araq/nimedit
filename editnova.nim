
from strutils import contains, startsWith, repeatChar
from os import extractFilename, splitFile
import sdl2, sdl2/ttf
import buffer, styles, unicode, dialogs


# TODO:
#  - scrolling!
#  - select, copy, cut from clipboard
#  - syntax highlighting
#  - large file handling
#  - mouse handling
#  - show line numbers
#  - show scroll bars; no horizontal scrolling though
#  - miniview
#  - highlighting of ()s
#  - highlighting of substring occurences

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

  CmdHistory = object
    cmds: seq[string]
    suggested: int

  Editor = ref object
    active, buffer, prompt: Buffer
    statusMsg: string

    renderer: RendererPtr
    window: WindowPtr
    theme: Theme
    screenW, screenH: cint
    hist: CmdHistory
    buffersCounter: int

template unkownName(): untyped = "unknown-" & $ed.buffersCounter & ".txt"

proc setDefaults(ed: Editor; mgr: ptr StyleManager) =
  ed.screenW = cint(650)
  ed.screenH = cint(780)
  ed.statusMsg = "Ready "

  ed.buffer = newBuffer(unkownName(), mgr)
  ed.prompt = newBuffer("", mgr)

  ed.buffersCounter = 1
  ed.buffer.next = ed.buffer
  ed.buffer.prev = ed.buffer
  ed.active = ed.buffer
  ed.hist = CmdHistory(cmds: @[], suggested: -1)

  #ed.theme.fg = color(255, 255, 255, 0)
  #r"C:\Windows\Fonts\cour.ttf"
  ed.theme.font = loadFont("fonts/DejaVuSansMono.ttf", FontSize)
  ed.theme.active[true] = parseColor"#FFA500"
  ed.theme.active[false] = parseColor"#C0C0C0"
  #ed.theme.bg = parseColor"#0c090a"
  ed.theme.bg = parseColor"#2d2d2d"
  ed.theme.fg = parseColor"#fafafa"
  ed.theme.cursor = ed.theme.fg

proc destroy(ed: Editor) =
  close(ed.theme.font)
  destroyRenderer ed.renderer
  destroy ed.window

proc rect(x,y,w,h: int): Rect = sdl2.rect(x.cint, y.cint, w.cint, h.cint)

proc drawBorder(ed: Editor; x, y, h: int; b: bool) =
  ed.renderer.setDrawColor(ed.theme.active[b])
  var r = rect(x, y, ed.screenW-10, h)
  ed.renderer.drawRect(r)
  var r2 = rect(x+1, y+1, ed.screenW-12, h-2)
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


proc addCmd(h: var CmdHistory; cmd: string) =
  var replaceWith = -1
  for i in 0..high(h.cmds):
    if h.cmds[i] == cmd:
      # suggest it again:
      h.suggested = i
      return
    elif h.cmds[i] in cmd:
      # correct previously wrong or shorter command:
      if replaceWith < 0 or h.cmds[replaceWith] < h.cmds[i]: replaceWith = i
  if replaceWith < 0:
    h.cmds.add cmd
  else:
    h.cmds[replaceWith] = cmd

proc suggest(h: var CmdHistory; up: bool): string =
  if h.suggested < 0 or h.suggested >= h.cmds.len:
    h.suggested = (if up: h.cmds.high else: 0)
  if h.suggested >= 0 and h.suggested < h.cmds.len:
    result = h.cmds[h.suggested]
    h.suggested += (if up: -1 else: 1)
  else:
    result = ""

proc runCmd(ed: Editor; cmd: string): bool =
  echo cmd
  ed.hist.addCmd(cmd)
  if cmd.startsWith("#"):
    ed.theme.fg = parseColor(cmd)
  cmd == "quit" or cmd == "q"

proc main(ed: Editor) =
  var mgr: StyleManager
  setDefaults(ed, addr mgr)
  # ensure index 0 exists and has reasonable defaults:
  discard mgr.getStyle(FontAttr(color: ed.theme.fg, size: FontSize))

  ed.window = createWindow("Editnova", 10, 30, ed.screenW, ed.screenH,
                            SDL_WINDOW_RESIZABLE)
  ed.renderer = createRenderer(ed.window, -1, Renderer_Software)
  template prompt: expr = ed.prompt
  template active: expr = ed.active
  template buffer: expr = ed.buffer
  template renderer: expr = ed.renderer

  var blink = 1
  while true:
    var e = Event(kind: UserEvent5)
    if waitEventTimeout(e, 500) == SdlSuccess:
      case e.kind
      of QuitEvent: break
      of WindowEvent:
        let w = e.window
        if w.event == WindowEvent_Resized:
          ed.screenW = w.data1
          ed.screenH = w.data2
      of MouseButtonDown: discard
      of MouseWheel:
        # scroll(w.x, w.y)
        let w = e.wheel
        ed.active.firstLine -= w.y*3
        #echo "xy ", w.x, " ", w.y
      of TextInput:
        let w = e.text
        active.insert($w.text)
      of KeyDown:
        let w = e.key
        case w.keysym.scancode
        of SDL_SCANCODE_BACKSPACE:
          active.backspace()
        of SDL_SCANCODE_RETURN:
          if active==buffer:
            buffer.insert("\L")
          else:
            if ed.runCmd(prompt.fullText): break
            prompt.clear
        of SDL_SCANCODE_ESCAPE:
          if active==buffer: active = prompt
          else: active = buffer
        of SDL_SCANCODE_RIGHT: active.right((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_LEFT: active.left((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_DOWN:
          if active==prompt:
            prompt.clear
            prompt.insert(ed.hist.suggest(up=false))
          else:
            active.down((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_UP:
          if active==prompt:
            prompt.clear
            prompt.insert(ed.hist.suggest(up=true))
          else:
            active.up((w.keysym.modstate and KMOD_CTRL) != 0)
        of SDL_SCANCODE_TAB:
          if (w.keysym.modstate and KMOD_CTRL) != 0:
            buffer = buffer.next
            active = buffer
        else: discard
        if (w.keysym.modstate and KMOD_CTRL) != 0:
          # CTRL+Z: undo
          # CTRL+shift+Z: redo
          if w.keysym.sym == ord('z'):
            if (w.keysym.modstate and KMOD_SHIFT) != 0:
              active.redo
            else:
              active.undo
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
              if buffer.filename.len > 0: buffer.filename.splitFile.dir
              else: ""
            let toOpen = chooseFilesToOpen(nil, previousLocation)
            for p in toOpen:
              let x = newBuffer(p.extractFilename, addr mgr)
              x.loadFromFile(p)
              insertBuffer(buffer, x)
            active = buffer
          elif w.keysym.sym == ord('s'):
            buffer.save()
          elif w.keysym.sym == ord('n'):
            let x = newBuffer(unkownName(), addr mgr)
            insertBuffer(buffer, x)
            active = buffer
          elif w.keysym.sym == ord('q'):
            removeBuffer(buffer)
      else: discard
      # keydown means show the cursor:
      blink = 0
    else:
      # timeout, so update the blinking:
      blink = 1-blink

    clear(renderer)
    let fileList = ed.renderText(
      buffer.heading & (if buffer.changed: "*" else: ""),
      ed.theme.font, ed.theme.fg)

    let mainRect = rect(15, YGap*3+FontSize,
                        ed.screenW - 16,
                        ed.screenH - 7*FontSize - YGap*2)
    let promptRect = rect(15, FontSize+YGap*2 + ed.screenH - 7*FontSize,
                          ed.screenW - 16,
                          FontSize+YGap*2)

    renderer.draw(buffer, mainRect, ed.theme.bg, ed.theme.cursor,
                  blink==0 and active==buffer)

    renderer.draw(fileList, YGap)
    ed.drawBorder(XGap, FontSize+YGap*2, ed.screenH - 7*FontSize - YGap*2, active==buffer)
    ed.drawBorder(XGap, FontSize+YGap*2 + ed.screenH - 7*FontSize - YGap,
      FontSize+YGap*3, active==prompt)

    #let prompt = ed.renderText(prompt.contents, ed.theme.font, ed.theme.fg)
    #renderer.draw(prompt, FontSize+YGap*2 + ed.screenH - 7*FontSize)
    renderer.draw(prompt, promptRect, ed.theme.bg, ed.theme.cursor,
                  blink==0 and active==prompt)

    let statusBar = ed.renderText(ed.statusMsg & buffer.filename &
                        repeatChar(10) & "Pos: " & $(getLine(buffer)+1) & ", " &
                                                   $(getColumn(buffer)+1),
                        ed.theme.font, ed.theme.fg)
    renderer.draw(statusBar, ed.screenH-FontSize-YGap*2)
    present(renderer)
  freeFonts mgr
  destroy ed

if sdl2.init(INIT_VIDEO) != SdlSuccess:
  echo "SDL_Init"
elif ttfInit() != SdlSuccess:
  echo "TTF_Init"
else:
  startTextInput()
  main(Editor())
sdl2.quit()
