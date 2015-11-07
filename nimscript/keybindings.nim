
import keydefs

bindKey({Left}, Action.Left)
bindKey({Right}, Action.Right)
bindKey({Up}, Action.Up)
bindKey({Down}, Action.Down)
bindKey({PageUp}, Action.PageUp)
bindKey({PageDown}, Action.PageDown)

bindKey({Ctrl,Left}, Action.LeftJump)
bindKey({Ctrl,Right}, Action.RightJump)
bindKey({Ctrl,Up}, Action.UpJump)
bindkey({Ctrl,Down}, Action.DownJump)

bindKey({Shift,Left}, Action.LeftSelect)
bindKey({Shift,Right}, Action.RightSelect)
bindkey({Shift,Up}, Action.UpSelect)
bindKey({Shift,Down}, Action.DownSelect)

bindKey({Shift,Ctrl,Left}, Action.LeftJumpSelect)
bindKey({Shift,Ctrl,Right}, Action.RightJumpSelect)
bindKey({Shift,Ctrl,Up}, Action.UpJumpSelect)
bindkey({Shift,Ctrl,Down}, Action.DownJumpSelect)

bindKey({Enter}, Action.Enter)
bindKey({Backspace}, Action.Backspace)
bindKey({Del}, Action.Del)

bindKey({Ctrl,C}, Action.Copy)
bindKey({Ctrl,X}, Action.Cut)
bindKey({Ctrl,V}, Action.Paste)

bindKey({Ctrl,Space}, Action.AutoComplete)
bindKey({Ctrl,Z}, Action.Undo)
bindKey({Ctrl,Shift,Z}, Action.Redo)

bindKey({Ctrl,A}, Action.SelectAll)
bindKey({Ctrl,B}, Action.SendBreak)

bindKey({Ctrl,E}, Action.InsertPromptSelectedText, "e ")
bindKey({Ctrl,G}, Action.InsertPrompt, "goto ")
bindKey({Ctrl,F}, Action.InsertPromptSelectedText, "find ")
bindKey({Ctrl,H}, Action.InsertPromptSelectedText, "replace ")
bindKey({Ctrl,U}, Action.UpdateView)
bindKey({Ctrl,O}, Action.OpenTab)
bindKey({Ctrl,S}, Action.SaveTab)
bindKey({Ctrl,N}, Action.NewTab)
bindKey({Ctrl,Q}, Action.CloseTab)

bindKey({Ctrl,M}, Action.Declarations)
bindKey({F3}, Action.NextEditLocation)
bindKey({Shift,F3}, Action.PrevEditLocation)

bindKey({F1}, Action.SwitchEditorConsole)
bindKey({F2}, Action.Nimsuggest, "dus")
bindKey({Esc}, Action.SwitchEditorPrompt)
bindKey({Shift,Esc}, Action.SwitchEditorConsole)

bindKey({Ctrl,Tab}, Action.NextBuffer)
bindKey({Ctrl,Shift,Tab}, Action.PrevBuffer)

bindKey({Tab}, Action.Indent)
bindKey({Shift,Tab}, Action.Dedent)

bindKey({F5}, Action.NimScript, "pressedF5")
bindKey({F6}, Action.NimScript, "pressedF6")
bindKey({F7}, Action.NimScript, "pressedF7")
bindKey({F8}, Action.NimScript, "pressedF8")
bindKey({F9}, Action.NimScript, "pressedF9")
bindKey({F10}, Action.NimScript, "pressedF10")
bindKey({F11}, Action.NimScript, "pressedF11")
bindKey({F12}, Action.NimScript, "pressedF12")
