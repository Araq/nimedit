## Draws a vertical scrollbar for a buffer.

import buffertype, themes, intsets
import sdl2, sdl2/ttf, prims, tabbar

const scrollBarWidth* = 15

func scrollingEnabled*(b: Buffer): bool =
  result = b.span <= b.numberOfLines

proc drawScrollBar*(b: Buffer; t: InternalTheme; events: seq[Event];
                    bufferRect: Rect): int =
  ## returns -1 if no scrolling was requested.
  result = -1

  # if the whole screen fits, do not show a scrollbar:
  if not b.scrollingEnabled: return

  const width = scrollBarWidth

  var rect = bufferRect
  rect.w = width
  rect.x = bufferRect.x + bufferRect.w - width
  let fontSize = fontLineSkip(t.editorFontPtr)
  #let span = bufferRect.h div fontSize
  # This is surprisingly difficult to get right. Look at
  # http://csdgn.org/inform/scrollbar-mechanics for a detailed description of
  # the algorithm.

  # Determine how large the content is, and how big our window is
  let
    # we allow for scrolling past the end of the document whenever scrolling is
    # enabled, so we have to account for this extra length:
    numberOfViewableLines = b.numberOfLines + b.span

  let contentSize = float(numberOfViewableLines) * fontSize.float
  let windowSize = bufferRect.h.float

  # the `- 2` is for aesthetic purposes.
  # without it, the track area extends slightly further down than at the top,
  # making it noticable unsymmetrical.
  let trackSize = windowSize - 2

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

  template state: var ScrollBarState =
      b.scrollState

  for e in events:
    case state.usingScrollbar
    of false:
      # check if we need to change state to being used
      if e.kind == MouseButtonDown:
        let w = e.button
        let p = point(w.x, w.y)
        if grip.contains(p):
          active = true
          state = ScrollBarState(usingScrollbar: true,
            initiallyGrippedAt: w.y - grip.y)
    of true:
      # check if we need to change state to not being used
      if e.kind == MouseButtonUp:
        state = ScrollBarState(usingScrollbar: false)

      elif e.kind == MouseMotion:
        # move scrollbar and buffer position
        let w = e.motion
        let p = point(w.x, w.y)
        if grip.contains(p):
          active = true
        #if grip.contains(p):
        if (w.state and BUTTON_LMASK) != 0:
          let
            mousePosRelativeToScrollbar = w.y - grip.y
            yMovement = mousePosRelativeToScrollbar - state.initiallyGrippedAt

          # Determine the new location of the grip
          let newGripPosition = clamp(gripPositionOnTrack + float(yMovement),
                                      0.0, trackScrollAreaSize)
          let newGripPositionRatio = newGripPosition / trackScrollAreaSize
          result = clamp((newGripPositionRatio * windowScrollAreaSize /
            fontSize.float).int, 0, b.numberOfLines)
          #result = clamp(cint((p.y-rect.y).float * pixelsPerLine),
          #               0, b.numberOfLines)


  if not active:
    var p: Point
    discard getMouseState(p.x, p.y)
    if grip.contains(p) or state.usingScrollbar:
      active = true

  # draw the bar:
  #drawBorder(t, rect, active)

  # draw the grip:
  drawBox(t, grip, active, 4)
