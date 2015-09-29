
proc runCmd(ed: Editor; cmd: string): bool =
  ed.promptCon.hist.addCmd(cmd)
  if cmd.startsWith("#"):
    ed.theme.bg = parseColor(cmd)
  cmd == "quit" or cmd == "q"
