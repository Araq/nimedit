# [Package]

when defined(nimsuggest):
  import system/nimscript

packageName          = "NimEdit"
version       = "0.91"
author        = "Andreas Rumpf"
description   = "A beautiful SDL-based Nim IDE."
license       = "Commercial"

bin = @["nimedit"]

# [Deps]
requires: "nim >= 0.19.0, sdl2#head, dialogs >= 1.0"
