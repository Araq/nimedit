
#switch("path", "$projectPath/..")
switch("path", "$lib/packages/docutils")
switch("path", "$lib/../")
#switch("path", "../sdl2/src")

--threads:on

--define: booting
--define:useStdoutAsStdmsg
--app:gui

#--noNimblePath

import ospaths
include version

task installer, "Build the installer":
  mkDir "build"
  exec "niminst".toExe & " --var:version=" & Version & " inno installer.ini"
  setCommand "nop"

task docs, "Build the documentation":
  exec "nim doc2 nimscript/editor.nim"
  mvFile "nimscript/editor.html", "api.html"
  setCommand "rst2html", "docs.rst"
