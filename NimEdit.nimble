[Package]
name          = "NimEdit"
version       = "0.91"
author        = "Andreas Rumpf"
description   = "A beautiful SDL-based Nim IDE."
license       = "Commercial"

bin = "nimedit"

[Deps]
Requires: "nim >= 0.11.3, sdl2#head, dialogs >= 1.0"
