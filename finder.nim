
import buffertype, buffer, re, strutils
from unicode import runeLen

type
  SearchOption* = enum
    searchRe,
    ignoreCase,
    ignoreStyle,
    wordBoundary,
    onlyCurrentFile
  SearchOptions* = set[SearchOption]

proc parseSearchOptions*(s: string): SearchOptions =
  result = {ignoreStyle}
  for i in 0..high(s):
    case s[i]
    of 'i', 'I': result.incl ignoreCase
    of 'y', 'Y': result.incl ignoreStyle
    of 'w', 'W', 'b', 'B': result.incl wordBoundary
    of 's', 'S': result.excl wordBoundary
    of 'p', 'P', 'c', 'C':
      result.excl ignoreCase
      result.excl ignoreStyle
    of 'f', 'F': result.incl onlyCurrentFile
    of 'r', 'R': result.incl searchRe
    else: discard

type
  SkipTable = array[char, int]

template conv(x): untyped =
  (if {ignoreCase, ignoreStyle} * options != {}: x.toLower else: x)

proc preprocessSub(sub: string, a: var SkipTable; options: SearchOptions) =
  var m = len(sub)
  for i in 0..0xff: a[chr(i)] = m+1
  for i in 0..m-1: a[(sub[i])] = m-i

proc findAux(s: Buffer; sub: string, start: int, a: SkipTable;
             options: SearchOptions): int =
  var
    m = len(sub)
    n = len(s)
  var j = start
  while j <= n - m:
    block match:
      for k in 0..m-1:
        if conv(sub[k]) != conv(s[k+j]): break match
      return j
    inc(j, a[s[j+m]])
  return -1

proc find(s: Buffer; sub: string, start: Natural; options: SearchOptions): int =
  var a {.noinit.}: SkipTable
  preprocessSub(sub, a, options)
  result = findAux(s, sub, start, a, options)

proc findNext*(b: Buffer; searchTerm: string; options: set[SearchOption];
               toReplaceWith: string = nil) =
  const Letters = {'a'..'z', '_', 'A'..'Z', '\128'..'\255', '0'..'9'}
  let options = options + (if searchTerm.runeLen == 1 and
                              searchTerm[0] in Letters: {wordBoundary} else: {})
  assert searchTerm.len > 0
  template inWordBoundary(): untyped =
    (i == 0 or b[i-1] notin Letters) and
      (last+1 >= b.len or b[last+1] notin Letters)
  b.markers.setLen 0
  if searchRe in options:
    let buf = b.fullText
    var flags = {reMultiline}
    if ignoreCase in options: flags.incl reIgnoreCase
    var rex: Regex
    try:
      rex = re(searchTerm)
    except RegexError:
      return
    var i = 0
    var matches: array[MaxSubpatterns, string]
    while true:
      let (first, last) = findBounds(buf, rex, matches, i)
      if first < 0: break
      if wordBoundary notin options or inWordBoundary():
        b.markers.add(Marker(a: first, b: last,
                             replacement: toReplaceWith % matches))
      i = last+1
  else:
    var i = 0
    while true:
      i = find(b, searchTerm, i, options)
      if i < 0: break
      var last = i+searchTerm.len-1
      if wordBoundary notin options or inWordBoundary():
        b.markers.add(Marker(a: i, b: last, replacement: toReplaceWith))
      i = last+1
  # first match is the one *after* the cursor:
  var i = 1
  while i < b.markers.len:
    if b.markers[i].a >= b.cursor:
      b.activeMarker = i-1
      break
    inc i

proc doReplace*(b: Buffer): bool =
  if b.activeMarker < b.markers.len:
    # we have to copy it here and delete it immediately so that the updates
    # to b.markers that 'removeSelectedText' and 'insert' perform do not
    # affect us:
    let m = b.markers[b.activeMarker]
    var x = m.a
    var y = m.b
    b.markers.delete b.activeMarker
    inc b.version
    removeSelectedText(b, x, y)
    if m.replacement.len > 0:
      dec b.version
      insert(b, m.replacement)
    result = true
