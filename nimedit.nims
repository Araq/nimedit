
#switch("path", "$projectPath/..")
switch("path", "$lib/packages/docutils")
switch("path", "$lib/../")
#switch("path", "../sdl2/src")

--threads:on

#when defined(windows):
#  --app:gui

#--noNimblePath

import ospaths
include version

task installer, "Build the installer":
  mkDir "build"
  let cmd = when defined(windows): "inno" else: "xz"
  exec "niminst".toExe & " --var:version=" & Version & " " &
      cmd & " installer.ini"
  when defined(macosx):
    mvFile("build/nimedit-" & Version & ".tar.xz",
           "build/nimedit-" & Version & "-mac.tar.xz")
  setCommand "nop"

task docs, "Build the documentation":
  exec "nim doc2 nimscript/editor.nim"
  exec "nim doc2 nimscript/common.nim"
  setCommand "rst2html", "docs.rst"
