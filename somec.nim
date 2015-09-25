proc renderText*(message: string; fontFile: string; color: Color; fontSize: cint;
                renderer: ptr Renderer): ptr Texture =
  #Open the font
  var font: ptr Font = openFont(fontFile.cStr(), fontSize)
  if font == nullptr:
    echo("TTF_OpenFont")
    return nullptr
  var surf: ptr Surface = renderTextBlended(font, message.cStr(), color)
  if surf == nullptr:
    closeFont(font)
    echo("TTF_RenderText")
    return nullptr
  var texture: ptr Texture = createTextureFromSurface(renderer, surf)
  if texture == nullptr:
    echo("CreateTexture")
  freeSurface(surf)
  closeFont(font)
  return texture

proc main*() =
  var resPath: string = getResourcePath("Lesson6")
  #We'll render the string "TTF fonts are cool!" in white
  #Color is in RGBA format
  var color: Color = [255, 255, 255, 255]
  var image: ptr Texture = renderText("TTF fonts are cool!", resPath + "sample.ttf",
                                 color, 64, renderer)
  if image == nil:
    cleanup(renderer, window)
    quit()
    quit()
    return 1
  var
    iW: cint
    iH: cint
  queryTexture(image, nil, nil, addr(iW), addr(iH))
  var x: cint = screen_Width div 2 - iW div 2
  var y: cint = screen_Height div 2 - iH div 2
  #Note: This is within the program's main loop
  renderClear(renderer)
  #We can draw our message as we do any other texture, since it's been
  #rendered to a texture
  renderTexture(image, renderer, x, y)
  renderPresent(renderer)
