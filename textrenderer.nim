

import sdl2
export Color

from os import fileExists, expandFilename

when defined(useNimx):
  import nimx.types except Color
  import nimx.font, nimx.context

  type
    FontPtr* = Font
    RendererPtr* = object
      nx*: GraphicsContext
      sd*: sdl2.RendererPtr
      w, h: cint
else:
  from sdl2/ttf import FontPtr
  export FontPtr, RendererPtr

proc createRenderer*(window: WindowPtr): RendererPtr =
  when defined(useNimx):
    result.sd = createRenderer(window, -1, Renderer_Software)
    window.getSize(result.w, result.h)
    result.nx = newGraphicsContext()
  else:
    result = createRenderer(window, -1, Renderer_Software)

proc openFont*(name: string; size: Natural): FontPtr =
  when defined(useNimx):
    if fileExists(name):
      result = newFontWithFile(expandFilename name, float size)
  else:
    result = ttf.openFont(name, byte(size))

proc close*(f: FontPtr) =
  when not defined(useNimx): ttf.close(f)

when not defined(useNimx):
  proc drawTexture(r: RendererPtr; font: FontPtr; msg: cstring;
                   fg, bg: Color): TexturePtr =
    assert font != nil
    assert msg[0] != '\0'
    var surf: SurfacePtr = renderUtf8Shaded(font, msg, fg, bg)
    if surf == nil:
      echo("TTF_RenderText failed")
      return
    result = createTextureFromSurface(r, surf)
    if result == nil:
      echo("CreateTexture failed")
    freeSurface(surf)

proc drawText*(r: RendererPtr; font: FontPtr; msg: cstring;
               fg, bg: Color; x, y: var int) =
  when defined(useNimx):
    r.nx.fillColor = newColor(fg.r.float / 256.0,
                              fg.g.float / 256.0,
                              fg.b.float / 256.0)
    var p = newPoint(float32 x, float32 y)
    r.nx.withTransform ortho(0, float32 r.w, float32 r.h, 0, -1, 1):
      r.nx.drawText(font, p, $msg)
    x = int p.x
    y = int p.y
  else:
    let tex = drawTexture(r, font, buf, col, t.bg)
    var d: Rect
    d.x = x.cint
    d.y = y.cint
    queryTexture(tex, nil, nil, addr(d.w), addr(d.h))
    r.copy(tex, nil, addr d)
    destroy tex
    x += d.w
    y += d.h

proc textSize*(font: FontPtr; buffer: cstring): cint =
  when defined(useNimx):
    result = font.sizeOfString($buffer).width.cint
  else:
    discard sizeUtf8(font, buffer, addr result, nil)

proc drawLine*(r: RendererPtr; col: Color; x, y, w, h: cint) =
  when defined(useNimx):
    r.sd.setDrawColor(col)
    r.sd.drawLine(x, y, w, h)
  else:
    r.setDrawColor(col)
    r.drawLine(x, y, w, h)

proc fontLineSkip*(f: FontPtr): cint =
  when defined(useNimx):
    result = f.sizeOfString("").height.cint
  else:
    fontLineSkip(f)

proc destroyRenderer*(r: RendererPtr) =
  when defined(useNimx):
    r.sd.destroyRenderer()
  else:
    r.destroyRenderer()

proc present*(r: RendererPtr) =
  when defined(useNimx):
    r.sd.present()
  else:
    r.present()

proc clear*(r: RendererPtr) =
  when defined(useNimx):
    r.sd.clear()
  else:
    r.clear()

