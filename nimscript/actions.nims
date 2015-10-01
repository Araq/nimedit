


proc onTabPressed*() =
  echo "tab pressed"

import strutils

proc doQuote*(selected: string): string =
  result = ""
  for x in split(selected):
    if result.len > 0: result.add ", "
    result.add escape(x)
