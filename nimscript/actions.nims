


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
  echo "echo redirected!"

proc pressedF6*() =
  let w = getCurrentIdent(true)
  insert("<$1></$1>" % w)
  setCaret(getCaret() - w.len - "</>".len)

