
when defined(nimscript):
  {.pragma: mypure.}
else:
  {.pragma: mypure, pure.}

type
  Key* {.mypure.} = enum
    A, B, C, D, E, F, G, H, I, J,
    K, L, M, N, O, P, Q, R, S, T,
    U, V, W, X, Y, Z,
    N1, N2, N3, N4, N5, N6, N7, N8, N9, N0,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
    Enter, Space, Esc,
    Shift, Ctrl, Alt, Apple, Del, Backspace,
    Ins, PageUp, PageDown, Left, Right, Up, Down,
    Capslock, Tab, Comma, Period

  Action* {.pure.} = enum
    None,
    Left, Right, Up, Down,
    LeftJump, RightJump, UpJump, DownJump,
    LeftSelect, RightSelect, UpSelect, DownSelect,
    LeftJumpSelect, RightJumpSelect, UpJumpSelect, DownJumpSelect,
    PageUp, PageDown,
    Insert, Enter, Indent, Dedent, Backspace, Del,
    Copy, Cut, Paste,
    AutoComplete,
    Undo,
    Redo,
    SelectAll,
    SendBreak,
    UpdateView,
    OpenTab,
    SaveTab,
    NewTab,
    CloseTab,
    SwitchEditorConsole,
    SwitchEditorPrompt,
    QuitApplication,
    Declarations,
    NextBuffer,
    PrevBuffer,
    NextEditLocation,
    PrevEditLocation,
    InsertPrompt,
    InsertPromptSelectedText,
    NimSuggest,
    NimScript

proc bindKey*(key: set[Key]; action: Action; arg: string=nil) =
  discard
