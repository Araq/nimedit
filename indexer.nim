

import critbits, buffertype, buffer
import strutils except Letters

type
  Index* = object
    tree*: CritBitTree[int]
    version*: int

proc indexBuffer(index: var Index; b: Buffer) =
  # do not do too much work so that everything remains responsive. We don't
  # want to use threading here as the locking would be too complex.
  var linesToIndex = 200
  if b.indexer.currentlyIndexing != b.version:
    b.indexer.currentlyIndexing = b.version
    b.indexer.position = 0
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
      # do not add the word that the cursor is currently over:
      var metCursor = false
      word.setLen 0
      while true:
        let c = b[i]
        if i == b.cursor: metCursor = true
        if c notin Letters: break
        word.add c
        inc i
      if i == b.cursor: metCursor = true
      # do not index words of length 1:
      if word.len > 1 and not metCursor:
        if word notin index.tree:
          index.tree[word] = 0
          inc index.version
    elif c in {'0'..'9'}:
      # prevent indexing numbers like 0xffff:
      inc i
      while true:
        let c = b[i]
        if c notin Letters: break
        inc i
    else:
      inc i
  # we indexed the whole buffer:
  b.indexer.version = b.version
  b.indexer.currentlyIndexing = 0

proc bufferWithWorkToDo(start: Buffer): Buffer =
  var it = start
  while true:
    if it.indexer.version != it.version: return it
    it = it.next
    if it == start: break

proc indexBuffers*(database: var Index; start: Buffer) =
  # search for a single buffer that can be indexed and index it. Since we
  # store the version, eventually everything will be indexed. Works
  # incrementally.
  let it = bufferWithWorkToDo(start)
  if it != nil:
    indexBuffer(database, it)

proc populateBuffer*(index: var Index; b: Buffer;
                     prefix: string) =
  # only repopulate if the database knows new words:
  if b.version != index.version:
    b.clear()
    for key, value in index.tree.mpairs():
      value = b.numberOfLines
      b.insert(key)
      b.insertEnter()
    b.readOnly = b.len-1
    b.version = index.version

  # we of course want to use the database for *fast* term searching:
  var interesting = -1
  if prefix.len > 0:
    for hit in index.tree.valuesWithPrefix(prefix):
      interesting = hit
      break
  b.gotoLine(interesting+1, -1)

proc selected*(autocomplete, main: Buffer) =
  inc main.version
  let p = main.getWordPrefix
  for i in 0..<p.len:
    dec main.version
    backspace(main, false, overrideUtf8=true)
  # undo the upcoming version increase that 'insert' performs:
  dec main.version
  insert(main, autocomplete.getCurrentLine)
