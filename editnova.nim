
import sdl2, sdl2/ttf
import buffer, unicode

proc renderText*(message: string; font: FontPtr; color: Color;
                renderer: RendererPtr): TexturePtr =
  var surf: SurfacePtr = renderUtf8Solid(font, message, color)
  if surf == nil:
    echo("TTF_RenderText")
    return nil
  var texture: TexturePtr = createTextureFromSurface(renderer, surf)
  if texture == nil:
    echo("CreateTexture")
  freeSurface(surf)
  return texture

proc main =
  var
    screenW = cint(650)
    screenH = cint(780)
    buffer = newBuffer()
  let window = createWindow("Editnova", 10, 30, screenW, screenH,
                            SDL_WINDOW_RESIZABLE)
  let renderer = createRenderer(window, -1, Renderer_Software)
     #r"C:\Windows\Fonts\cour.ttf",
  var font: FontPtr = openFont("fonts/DejaVuSansMono.ttf", 15)
  if font == nil:
    echo("TTF_OpenFont")
    return

  while true:
    var e = Event(kind: UserEvent5)
    if waitEvent(e) == SdlSuccess:
      case e.kind
      of QuitEvent: break
      of WindowEvent:
        let w = e.window
        if w.event == WindowEvent_Resized:
          screenW = w.data1
          screenH = w.data2
      of MouseButtonDown: discard
      of MouseWheel:
        # scroll(w.x, w.y)
        let w = e.wheel
        echo "xy ", w.x, " ", w.y
      of TextInput:
        let w = e.text
        buffer.insert($w.text)
      of KeyDown:
        let w = e.key
        case w.keysym.scancode
        of SDL_SCANCODE_BACKSPACE:
          buffer.backspace()
        of SDL_SCANCODE_RETURN:
          buffer.insert("\L")
        of SDL_SCANCODE_ESCAPE: break
        of SDL_SCANCODE_RIGHT: buffer.right((w.keysym.modstate and KMOD_SHIFT) != 0)
        of SDL_SCANCODE_LEFT: buffer.left((w.keysym.modstate and KMOD_SHIFT) != 0)
        of SDL_SCANCODE_DOWN: buffer.down((w.keysym.modstate and KMOD_SHIFT) != 0)
        of SDL_SCANCODE_UP: buffer.up((w.keysym.modstate and KMOD_SHIFT) != 0)
        else: discard
        if (w.keysym.modstate and KMOD_CTRL) != 0:
          # CTRL+Z: undo
          # CTRL+shift+Z: redo
          if w.keysym.sym == ord('z'):
            if (w.keysym.modstate and KMOD_SHIFT) != 0:
              buffer.redo
            else:
              buffer.undo
          elif w.keysym.sym == ord('f'):
            discard "find"
          elif w.keysym.sym == ord('h'):
            discard "replace"
          elif w.keysym.sym == ord('x'):
            discard "cut"
          elif w.keysym.sym == ord('c'):
            discard "copy"
          elif w.keysym.sym == ord('v'):
            discard "insert"
          elif w.keysym.sym == ord('o'):
            discard "open"
          elif w.keysym.sym == ord('s'):
            discard "safe"
          elif w.keysym.sym == ord('n'):
            discard "new buffer"

        #let u = w.keysym.unicode
        #echo "GOT ", u, " ", Rune(u)
      else: discard

    clear(renderer)

    var image: TexturePtr = renderText(buffer.contents, font,
                                   color(255, 255, 255, 255), renderer)
    if image == nil:
      echo "arg, nil!"
    var
      iW: cint
      iH: cint
    queryTexture(image, nil, nil, addr(iW), addr(iH))
    let r = rect(5, 5, iW, iH)

    copy(renderer, image, nil, unsafeAddr r)
    destroy image
    present(renderer)

  close(font)
  destroyRenderer renderer
  destroy window

if sdl2.init(INIT_VIDEO) != SdlSuccess:
  echo "SDL_Init"
elif ttfInit() != SdlSuccess:
  echo "TTF_Init"
else:
  startTextInput()
  main()
sdl2.quit()
