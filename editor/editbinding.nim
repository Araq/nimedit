# Translates the existing Action enum into EditInput events.
# This bridges the old keybinding system with the new event abstraction.

import editevents
import nimscript/keydefs

proc toEditInput*(action: Action; arg: string = ""): EditInput =
  ## Translates an Action (from the keybinding system) into an EditInput.
  ## Returns eiNone for app-level actions that the editor doesn't handle.
  case action
  of Action.None: result = EditInput(kind: eiNone)
  of Action.Left: result = EditInput(kind: eiLeft)
  of Action.Right: result = EditInput(kind: eiRight)
  of Action.Up: result = EditInput(kind: eiUp)
  of Action.Down: result = EditInput(kind: eiDown)
  of Action.LeftJump: result = EditInput(kind: eiWordLeft)
  of Action.RightJump: result = EditInput(kind: eiWordRight)
  of Action.UpJump: result = EditInput(kind: eiJumpUp)
  of Action.DownJump: result = EditInput(kind: eiJumpDown)
  of Action.LeftSelect: result = EditInput(kind: eiSelectLeft)
  of Action.RightSelect: result = EditInput(kind: eiSelectRight)
  of Action.UpSelect: result = EditInput(kind: eiSelectUp)
  of Action.DownSelect: result = EditInput(kind: eiSelectDown)
  of Action.LeftJumpSelect: result = EditInput(kind: eiSelectWordLeft)
  of Action.RightJumpSelect: result = EditInput(kind: eiSelectWordRight)
  of Action.UpJumpSelect: result = EditInput(kind: eiSelectJumpUp)
  of Action.DownJumpSelect: result = EditInput(kind: eiSelectJumpDown)
  of Action.PageUp: result = EditInput(kind: eiPageUp)
  of Action.PageDown: result = EditInput(kind: eiPageDown)
  of Action.Insert:
    if arg.len > 0:
      result = EditInput(kind: eiInsertChar, ch: arg[0])
    else:
      result = EditInput(kind: eiNone)
  of Action.Enter: result = EditInput(kind: eiNewline)
  of Action.Backspace: result = EditInput(kind: eiBackspace)
  of Action.Del: result = EditInput(kind: eiDelete)
  of Action.DelVerb: result = EditInput(kind: eiDeleteVerb)
  of Action.Indent: result = EditInput(kind: eiIndent)
  of Action.Dedent: result = EditInput(kind: eiDedent)
  of Action.Copy: result = EditInput(kind: eiCopy)
  of Action.Cut: result = EditInput(kind: eiCut)
  of Action.Paste: result = EditInput(kind: eiPaste)
  of Action.Undo: result = EditInput(kind: eiUndo)
  of Action.Redo: result = EditInput(kind: eiRedo)
  of Action.SelectAll: result = EditInput(kind: eiSelectAll)
  of Action.AutoComplete: result = EditInput(kind: eiAutocomplete)
  else:
    # App-level actions (OpenTab, SaveTab, QuitApplication, etc.)
    # are not editor events — return eiNone.
    result = EditInput(kind: eiNone)
