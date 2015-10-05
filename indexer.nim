

import critbits, buffertype, buffer, strutils

const someWordChar = {'A'..'Z', 'a'..'z', '_', '\128'..'\255', '0'..'9'}

proc indexBuffer(database: var CritBitTree[int]; b: Buffer) =
  # do not do too much work so that everything remains responsive. We don't
  # want to use threading here as the locking would be too complex.
  var linesToIndex = 200
  var i = b.indexer.position
  var word = newStringOfCap(50)
  while i < b.len:
    let c = b[i]
    if c == '\L':
      dec linesToIndex
      if linesToIndex <= 0:
        # remember where we were to resume later properly:
        b.indexer.position = i+1
        return
    if c in {'A'..'Z', 'a'..'z', '_', '\128'..'\255'}:
      word.setLen 0
      while true:
        let c = b[i]
        if c notin someWordChar: break
        word.add c
        inc i
      # do not index words of length 1:
      if word.len > 1:
        database.inc word
    else:
      inc i
  # we indexed the whole buffer:
  b.indexer.version = b.version

proc getWordPrefix*(b: Buffer): string =
  result = ""
  var i = b.cursor-1
  while i > 0 and b[i-1] in someWordChar:
    dec i
  while i < b.cursor:
    result.add b[i]
    inc i

proc bufferWithWorkToDo(start: Buffer): Buffer =
  var it = start
  while true:
    if it.indexer.version != it.version: return it
    it = it.next
    if it == start: break

proc indexBuffers*(database: var CritBitTree[int]; start: Buffer) =
  # search for a single buffer that can be indexed and index it. Since we
  # store the version, eventually everything will be indexed. Works
  # incrementally.
  let it = bufferWithWorkToDo(start)
  if it != nil:
    indexBuffer(database, it)

proc makeSuggestion*(database: var CritBitTree[int]; prefix: string): string =
  if prefix.len == 0:
    # suggest nothing:
    return nil
  # suggest the word of the highest frequency:
  var best = -1
  for key, val in database.mpairsWithPrefix(prefix):
    if best < val:
      best = val
      result = key

proc populateBuffer*(database: CritBitTree[int]; b: Buffer;
                     prefix: string) =
  # only repopulate if the database knows new words:
  if database.len != b.numberOfLines:
    var interesting = -1
    b.clear()
    for key in database.keys():
      b.insert(key)
      b.insertEnter()
      if interesting < 0 and key.startsWith(prefix):
        # gotoLine is 1 based, arg:
        interesting = b.numberOfLines+1
    b.gotoLine(interesting, -1)
    b.readOnly = b.len-1
  else:
    b.gotoLine(0, -1)

proc selected*(autocomplete, main: Buffer) =
  inc main.version
  let p = main.getWordPrefix
  for i in 0..<p.len:
    dec main.version
    backspace(main, overrideUtf8=true)
  # undo the upcoming version increase that 'insert' performs:
  dec main.version
  insert(main, autocomplete.getCurrentLine)
