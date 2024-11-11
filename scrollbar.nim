## Draws a vertical scrollbar for a buffer.

import buffertype, themes
import sdl2, sdl2/ttf, tabbar

const scrollBarWidth* = 15

func scrollingEnabled*(b: Buffer): bool =
  ## Returns true if a scrollbar should be displayed in the input buffer.
  result = b.span <= b.numberOfLines

proc mouseInsideRect(r: Rect): bool =
  ## Returns true if the mouse is currently inside the input rectangle.
  var p: Point
  discard getMouseState(p.x, p.y)
  result = r.contains(p)

proc drawScrollBar*(b: Buffer; t: InternalTheme; events: seq[Event];
                    bufferRect: Rect): int =
  ## Draws a scrollbar inside the buffer, if it is needed.
  ## Returns the new position that the buffer should scroll to, or
  ## `-1` if no scrolling was requested.
  result = -1

  # if the whole screen fits, do not show a scrollbar:
  if not b.scrollingEnabled: return


  let fontSize = fontLineSkip(t.editorFontPtr)
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
  # making it noticably unsymmetrical.
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

  const width = scrollBarWidth

  var grip: Rect # the area of the scroll bar
  grip.x = bufferRect.x + bufferRect.w - width - 1
  grip.w = width - 2
  grip.h = gripSize.cint
  grip.y = clamp(gripPositionOnTrack.cint + bufferRect.y, bufferRect.y,
                 bufferRect.y + bufferRect.h - grip.h)

  template state: var ScrollBarState =
    b.scrollState

  # this variable represents whether something is happening with the bar.
  # if something is, we'll change the bars color.
  var active = false
  if mouseInsideRect(grip) or state.usingScrollbar: #cmove
    active = true

  # handle events:
  for e in events:
    #[we'll have to handle:
        - user clicking the bar, initiating a state of scrolling
        - user moving the mouse during a state of scrolling
        - user letting go of the bar, leaving the state of scrolling
      ]##
    case state.usingScrollbar
    of false:
      # check if we need to change state to being used
      if e.kind == MouseButtonDown:
        let w = e.button
        let p = point(w.x, w.y)
        if grip.contains(p):
          state = ScrollBarState(usingScrollbar: true,
            initiallyGrippedAt: w.y - grip.y)
    of true:
      # check if we need to change state to not being used
      if e.kind == MouseButtonUp:
        state = ScrollBarState(usingScrollbar: false)

      elif e.kind == MouseMotion:
        # move scrollbar and buffer position
        let w = e.motion
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

  # draw the bar:
  # drawBorder(t, rect, active)

  # draw the grip:
  drawBox(t, grip, active, 4)
