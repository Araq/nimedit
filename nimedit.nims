
#switch("path", "$projectPath/..")
switch("path", "$lib/packages/docutils")
switch("path", "$lib/../")
#switch("path", "../sdl2/src")

--threads:on

--define: booting
--define:useStdoutAsStdmsg
when defined(windows):
  --app:gui

#--noNimblePath

import ospaths
include version

task installer, "Build the installer":
  mkDir "build"
  let cmd = when defined(windows): "inno" else: "xz"
  exec "niminst".toExe & " --var:version=" & Version & " " &
      cmd & " installer.ini"
  setCommand "nop"

task docs, "Build the documentation":
  exec "nim doc2 nimscript/editor.nim"
  exec "nim doc2 nimscript/common.nim"
  setCommand "rst2html", "docs.rst"
