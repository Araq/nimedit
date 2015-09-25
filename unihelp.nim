

template ones(n: expr): expr = ((1 shl n)-1)

template fastRuneAt(s: Buffer, i: int, result: expr, doInc = true) =
  ## Returns the Unicode character ``s[i]`` in ``result``. If ``doInc == true``
  ## ``i`` is incremented by the number of bytes that have been processed.
  bind ones
  let ch = s[i]
  if ord(ch) <=% 127:
    result = Rune(ord(ch))
    when doInc: inc(i)
  elif ord(ch) shr 5 == 0b110:
    # assert(ord(s[i+1]) shr 6 == 0b10)
    result = Rune((ord(ch) and (ones(5))) shl 6 or
                  (ord(s[i+1]) and ones(6)))
    when doInc: inc(i, 2)
  elif ord(ch) shr 4 == 0b1110:
    # assert(ord(s[i+1]) shr 6 == 0b10)
    # assert(ord(s[i+2]) shr 6 == 0b10)
    result = Rune((ord(ch) and ones(4)) shl 12 or
             (ord(s[i+1]) and ones(6)) shl 6 or
             (ord(s[i+2]) and ones(6)))
    when doInc: inc(i, 3)
  elif ord(ch) shr 3 == 0b11110:
    # assert(ord(s[i+1]) shr 6 == 0b10)
    # assert(ord(s[i+2]) shr 6 == 0b10)
    # assert(ord(s[i+3]) shr 6 == 0b10)
    result = Rune((ord(ch) and ones(3)) shl 18 or
             (ord(s[i+1]) and ones(6)) shl 12 or
             (ord(s[i+2]) and ones(6)) shl 6 or
             (ord(s[i+3]) and ones(6)))
    when doInc: inc(i, 4)
  elif ord(ch) shr 2 == 0b111110:
    # assert(ord(s[i+1]) shr 6 == 0b10)
    # assert(ord(s[i+2]) shr 6 == 0b10)
    # assert(ord(s[i+3]) shr 6 == 0b10)
    # assert(ord(s[i+4]) shr 6 == 0b10)
    result = Rune((ord(ch) and ones(2)) shl 24 or
             (ord(s[i+1]) and ones(6)) shl 18 or
             (ord(s[i+2]) and ones(6)) shl 12 or
             (ord(s[i+3]) and ones(6)) shl 6 or
             (ord(s[i+4]) and ones(6)))
    when doInc: inc(i, 5)
  elif ord(ch) shr 1 == 0b1111110:
    # assert(ord(s[i+1]) shr 6 == 0b10)
    # assert(ord(s[i+2]) shr 6 == 0b10)
    # assert(ord(s[i+3]) shr 6 == 0b10)
    # assert(ord(s[i+4]) shr 6 == 0b10)
    # assert(ord(s[i+5]) shr 6 == 0b10)
    result = Rune((ord(ch) and ones(1)) shl 30 or
             (ord(s[i+1]) and ones(6)) shl 24 or
             (ord(s[i+2]) and ones(6)) shl 18 or
             (ord(s[i+3]) and ones(6)) shl 12 or
             (ord(s[i+4]) and ones(6)) shl 6 or
             (ord(s[i+5]) and ones(6)))
    when doInc: inc(i, 6)
  else:
    result = Rune(ord(ch))
    when doInc: inc(i)

proc graphemeLen(s: Buffer; i: Natural): Natural =
  ## The number of bytes belonging to 's[i]' including following combining
  ## characters.
  var j = i.int
  var r, r2: Rune
  if j < s.len:
    fastRuneAt(s, j, r, true)
    result = j-i
    while j < s.len:
      fastRuneAt(s, j, r2, true)
      if not isCombining(r2): break
      result = j-i

proc lastRune(s: Buffer; last: int): (Rune, int) =
  ## length of the last rune in 's[0..last]'. Returns the rune and its length
  ## in bytes.
  if s[last] <= chr(127):
    result = (Rune(s[last]), 1)
  else:
    var L = 0
    while last-L >= 0 and ord(s[last-L]) shr 6 == 0b10: inc(L)
    #inc(L)
    var r: Rune
    if last < L:
      # not a proper UTF-8 char:
      result = (Rune(s[last]), 1)
    else:
      fastRuneAt(s, last-L, r, false)
      result = (r, L+1)
