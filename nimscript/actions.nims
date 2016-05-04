
import strutils, editor

import keybindings

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

proc toSql*(s: string): string =
  proc isSql(s: string): bool =
    s in ["select", "from", "where", "group", "by", "having",
          "as", "update", "like", "length", "coalesce", "length",
          "between", "and", "or", "not", "sum", "if", "case", "end",
          "create", "table", "insert", "into", "left", "right",
          "outer", "inner", "join", "on", "concat"]

  const letters = {'a'..'z', '0'..'9', '_', 'A'..'Z'}
  result = ""
  var i = 0
  while i < s.len:
    let k = i
    while i < s.len and s[i] in letters: inc i
    if k != i:
      let w = s.substr(k, i-1)
      if isSql w.toLower:
        result.add w.toUpper
      else:
        result.add w
    while i < s.len and s[i] notin letters:
      result.add s[i]
      inc i

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

defineAlias("tt", r"tests\testament\tester")
defineAlias("j-edit", r"cd C:\Users\Anwender\projects\nimedit")
defineAlias("j-nim", r"cd C:\Users\Anwender\projects\nim")
defineAlias("j-lib", r"cd C:\Users\Anwender\projects\nim\lib")
defineAlias("j-web", r"cd C:\Users\Anwender\projects\nim\web")
defineAlias("j-sys", r"cd C:\Users\Anwender\projects\nim\lib\system")


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

