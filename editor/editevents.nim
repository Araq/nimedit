# Editor input/output events. No platform or SDL dependencies.
# The TextBuffer speaks these types exclusively.

type
  EditInputKind* = enum
    eiNone,
    eiTick,              ## time passed; cursor blink, undo grouping, autosave
    eiInsertChar,        ## insert a character
    eiNewline,
    eiBackspace,
    eiDelete,
    eiDeleteVerb,        ## delete word/token
    eiLeft, eiRight, eiUp, eiDown,
    eiWordLeft, eiWordRight,
    eiJumpUp, eiJumpDown,
    eiHome, eiEnd,
    eiPageUp, eiPageDown,
    eiSelectLeft, eiSelectRight, eiSelectUp, eiSelectDown,
    eiSelectWordLeft, eiSelectWordRight,
    eiSelectJumpUp, eiSelectJumpDown,
    eiSelectAll,
    eiCopy, eiCut, eiPaste,
    eiUndo, eiRedo,
    eiIndent, eiDedent,
    eiGotoDefinition,
    eiFindReferences,
    eiAutocomplete,
    eiRename,
    eiScrollUp, eiScrollDown,

  EditInput* = object
    kind*: EditInputKind
    ch*: char             ## for eiInsertChar
    text*: string         ## for eiPaste

  EditOutputKind* = enum
    akNone,              ## nothing the app needs to handle
    akGotoDefinition,
    akFindReferences,
    akAutocomplete,
    akRename,
    akAutoSave,          ## buffer idle long enough
    akCopy,              ## app should put this text on the clipboard
    akChanged,           ## buffer content changed (for status bar updates etc.)

  EditOutputEvent* = object
    kind*: EditOutputKind
    line*, col*: int     ## position in the buffer that triggered this
    text*: string        ## for akCopy: the selected text
