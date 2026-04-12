## Draws a vertical scrollbar for a buffer.

import buffertype, themes
import uirelays/[coords, screen, input], tabbar

const scrollBarWidth* = 15

func scrollingEnabled*(b: Buffer): bool =
  result = b.span <= b.numberOfLines

proc drawScrollBar*(b: Buffer; t: InternalTheme; events: seq[Event];
                    bufferRect: Rect): int =
  result = -1
  if not b.scrollingEnabled: return

  let fontSize = screen.fontLineSkip(t.editorFontHandle)

  let
    numberOfViewableLines = b.numberOfLines + b.span

  let contentSize = float(numberOfViewableLines) * fontSize.float
  let windowSize = bufferRect.h.float
  let trackSize = windowSize - 2
  let windowContentRatio = windowSize / contentSize
  let gripSize = clamp(trackSize * windowContentRatio, 20, trackSize)
  let windowScrollAreaSize = contentSize - windowSize
  let windowPosition = b.firstLine.float * fontSize.float
  let windowPositionRatio = windowPosition / windowScrollAreaSize
  let trackScrollAreaSize = trackSize - gripSize
  let gripPositionOnTrack = trackScrollAreaSize * windowPositionRatio

  const width = scrollBarWidth

  var grip: Rect
  grip.x = bufferRect.x + bufferRect.w - width - 1
  grip.w = width - 2
  grip.h = gripSize.int
  grip.y = clamp(gripPositionOnTrack.int + bufferRect.y, bufferRect.y,
                 bufferRect.y + bufferRect.h - grip.h)

  template state: var ScrollBarState =
    b.scrollState

  var active = false
  if state.usingScrollbar:
    active = true

  for e in events:
    case state.usingScrollbar
    of false:
      if e.kind == MouseDownEvent:
        let p = point(e.x, e.y)
        if grip.contains(p):
          state = ScrollBarState(usingScrollbar: true,
            initiallyGrippedAt: e.y.int - grip.y)
    of true:
      if e.kind == MouseUpEvent:
        state = ScrollBarState(usingScrollbar: false)
      elif e.kind == MouseMoveEvent:
        let
          mousePosRelativeToScrollbar = e.y - grip.y
          yMovement = mousePosRelativeToScrollbar - state.initiallyGrippedAt

        let newGripPosition = clamp(gripPositionOnTrack + float(yMovement),
                                    0.0, trackScrollAreaSize)
        let newGripPositionRatio = newGripPosition / trackScrollAreaSize
        result = clamp((newGripPositionRatio * windowScrollAreaSize /
          fontSize.float).int, 0, b.numberOfLines)

  drawBox(t, grip, active, 4)
