
import strutils
from parseutils import parseInt
import sdl2, sdl2/ttf

import prims

proc mainProc() =
  var screenW = cint(800)
  var screenH = cint(600)
  let window = createWindow("Editnova", 10, 30, screenW, screenH,
                            SDL_WINDOW_RESIZABLE)
  let renderer = createRenderer(window, -1, Renderer_Software)

  while true:
    var e = Event(kind: UserEvent5)
    let timeout = 100.cint
    if waitEventTimeout(e, timeout) == SdlSuccess:
      case e.kind
      of QuitEvent: break
      of WindowEvent:
        let w = e.window
        if w.event == WindowEvent_Resized:
          screenW = w.data1
          screenH = w.data2
      of MouseButtonDown:
        let w = e.button
        let p = point(w.x, w.y)
      else: discard
    else:
      # timeout:
      discard

    clear(renderer)
    let p = Pixel(col: color(0xFF, 0xA5, 0x00, 255), thickness: 8,
                  gradient: color(0xff, 0xff, 0xff, 0xff))
    #renderer.roundedRect(40, 40, 320, 300, 8, p)
    renderer.roundedBox(30, 30, 120, 100, 8, color(0x44, 0xff, 0x44, 255))

    renderer.roundedBox(120, 100, 330, 330, 8, color(0xff, 0x22, 0x22, 255))
    renderer.roundedBox(420, 700, 330, 330, 8, color(0x22, 0x22, 0xff, 255))

    renderer.setDrawColor(color(0, 0, 0, 0))
    present(renderer)
  destroyRenderer renderer
  destroy window


if sdl2.init(INIT_VIDEO) != SdlSuccess:
  echo "SDL_Init"
elif ttfInit() != SdlSuccess:
  echo "TTF_Init"
else:
  startTextInput()
  mainProc()
sdl2.quit()
