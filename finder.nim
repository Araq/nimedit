

type
  SearchOption* = enum
    #searchRe,
    ignoreCase,
    ignoreStyle,
    wordBoundary
  SearchOptions* = set[SearchOption]

proc parseSearchOptions*(s: string): SearchOptions =
  for i in 0..high(s):
    case s[i]
    #of 'r', 'R': result.incl searchRe
    of 'i', 'I': result.incl ignoreCase
    of 'y', 'Y': result.incl ignoreStyle
    of 'w', 'W', 'b', 'B': result.incl wordBoundary
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

proc findNext*(b: Buffer; searchTerm: string; options: set[SearchOption]) =
  var i = 0
  while true:
    i = find(b, searchTerm, i, options)
    if i < 0: break
    b.markers.add(Marker(a: i, b: i+searchTerm.len-1, s: mcHighlighted))
    inc i

