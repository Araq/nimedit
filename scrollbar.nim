## Draws a vertical scrollbar for a buffer.

import buffertype, themes
import sdl2, sdl2/ttf, prims, tabbar

const width = 15

proc scrollBarWidth*(b: Buffer): cint =
  if b.span >= b.numberOfLines: return 0
  return width

proc drawScrollBar*(b: Buffer; t: InternalTheme; e: var Event;
                    bufferRect: Rect): int =
  ## returns -1 if no scrolling was requested.
  # if the whole screen fits, do not show a scrollbar:
  result = -1
  let width = scrollBarWidth(b)
  if width == 0: return

  var rect = bufferRect
  rect.w = width
  rect.x = bufferRect.x + bufferRect.w - width
  let fontSize = fontLineSkip(t.editorFontPtr)
  #let span = bufferRect.h div fontSize
  # This is surprisingly difficult to get right. Look at
  # http://csdgn.org/inform/scrollbar-mechanics for a detailed description of
  # the algorithm.

  # Determine how large the content is, and how big our window is
  let contentSize = b.numberOfLines.float * fontSize.float
  let windowSize = bufferRect.h.float
  let trackSize = windowSize

  # Divide the window size by the content size to get a ratio
  let windowContentRatio = windowSize / contentSize

  # Multiply the trackSize by the ratio to determine how large our grip will be
  let gripSize = clamp(trackSize * windowContentRatio, 20, trackSize)

  let windowScrollAreaSize = contentSize - windowSize
  # The position of our window in accordance to its top on the content.
  # The top of the window over the content.
  let windowPosition = b.firstLine.float * fontSize.float

  # The ratio of the window to the scrollable area.
  let windowPositionRatio = windowPosition / windowScrollAreaSize

  # Just like we did for the window
  # we do this to keep the grip from flying off from the end of the track.
  let trackScrollAreaSize = trackSize - gripSize

  # Determine the location by multiplying the ratio
  let gripPositionOnTrack = trackScrollAreaSize * windowPositionRatio

  #let pixelsPerLine = b.numberOfLines.cint / bufferRect.h
  #let screens = b.numberOfLines.cint / span
  #let pixelsPerScreen = bufferRect.h.float / screens
  var active = false

  var grip = rect
  grip.x -= 1
  grip.w -= 2
  grip.h = gripSize.cint #max(8, pixelsPerScreen.cint)
  #let yy = b.firstLine.float * pixelsPerLine + bufferRect.y.float
  grip.y = clamp(gripPositionOnTrack.cint + bufferRect.y, bufferRect.y,
                 bufferRect.y + bufferRect.h - grip.h)

  if e.kind == MouseMotion:
    let w = e.motion
    let p = point(w.x, w.y)
    if rect.contains(p):
      active = true
    #if grip.contains(p):
    #  if (w.state and BUTTON_LMASK) != 0:
      let mousePositionDelta = w.yrel.float

      # Determine the new location of the grip
      let newGripPosition = clamp(gripPositionOnTrack + mousePositionDelta,
                                  0.0, trackScrollAreaSize)
      let newGripPositionRatio = newGripPosition / trackScrollAreaSize
      result = clamp((newGripPositionRatio * windowScrollAreaSize /
         fontSize.float).int, 0, b.numberOfLines)
      #result = clamp(cint((p.y-rect.y).float * pixelsPerLine),
      #               0, b.numberOfLines)
  elif e.kind == MouseButtonDown:
    let w = e.button
    let p = point(w.x, w.y)
    if rect.contains(p):
      active = true
      let linesInWindow = max(bufferRect.h div fontSize, 1)
      if w.y < grip.y:
        result = clamp(b.firstLine - linesInWindow, 0, b.numberOfLines)
      elif w.y > grip.y + grip.h:
        result = clamp(b.firstLine + linesInWindow, 0, b.numberOfLines)
  else:
    var p: Point
    discard getMouseState(p.x, p.y)
    if rect.contains(p):
      active = true

  # draw the bar:
  #drawBorder(t, rect, active)

  # draw the grip:
  drawBox(t, grip, active, 4)
