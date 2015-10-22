


import strutils, editor

proc doQuote*(selected: string): string =
  result = ""
  for x in split(selected):
    if result.len > 0: result.add ", "
    result.add escape(x)

proc commas*(selected: string): string =
  result = ""
  for x in split(selected):
    if result.len > 0: result.add ", "
    result.add x

proc pressedF5*() =
  save()
  for i in countdown(historyLen()-1, 0):
    let candidate = getHistory(i)
    if candidate.startsWith("nim") or candidate.startsWith("koch"):
      runConsoleCmd(candidate)
      break

proc pressedF6*() =
  let w = getCurrentIdent(true)
  insert("<$1></$1>" % w)
  setCaret(getCaret() - w.len - "</>".len)

when false:
  import ospaths

  proc pressedF7*() =
    # switch between header and implementation file for C/C++
    let f = currentFilename()
    case f.splitFile.ext
    of ".cpp":
      discard openTab(f.changeFileExt(".hpp")) or
              openTab(f.changeFileExt(".h"))
    of ".cxx":
      discard openTab(f.changeFileExt(".hxx")) or
              openTab(f.changeFileExt(".h"))
    of ".c":
      discard openTab(f.changeFileExt(".h"))
    of ".hpp":
      discard openTab(f.changeFileExt(".cpp")) or
              openTab(f.changeFileExt(".cxx"))
    of ".hxx":
      discard openTab(f.changeFileExt(".cxx")) or
              openTab(f.changeFileExt(".cpp"))
    of ".h":
      discard openTab(f.changeFileExt(".cpp")) or
              openTab(f.changeFileExt(".cxx")) or
              openTab(f.changeFileExt(".c"))
    else: discard

