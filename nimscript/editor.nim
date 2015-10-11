## The API that is available for Nimscript.

import "../common"

template builtin = discard

proc setCaret*(x: Natural) = builtin
proc getCaret*: Natural = builtin
proc openTab*(name: string): bool = builtin
proc closeTab*() = builtin

proc gotoPos*(line: Natural; col = -1) = builtin
proc clear*() = builtin

type
  UiElement* = enum
    Main, Prompt, Console

proc setFocus*(element: UiElement) = builtin
proc setPrompt*(text: string) = builtin
proc getPrompt*(): string = builtin

proc setSelection*(a: Natural; b: int) = builtin
proc getSelection*(): (int, int) = builtin
proc currentLineNumber*(): Natural = builtin

proc remove*(a, b: Natural) = builtin

proc insert*(text: string) = builtin
proc setLang*(lang: SourceLanguage) = builtin
proc getLang*(): SourceLanguage = builtin

proc charAt*(i: int): char = builtin
proc tokenAt*(i: int): TokenClass = builtin

proc getHistory*(i: int): string = builtin
proc runConsoleCmd*(cmd: string) = builtin

proc getCurrentIdent*(del=false): string =
  ## Retrives the current identifier, the one left to the caret. If `del` is
  ## true, the identifier is removed.
  result = ""
  let caret = getCaret()
  var i = caret
  while i > 0 and charAt(i-1) in {'a'..'z', 'A'..'Z', '_', '0'..'9'}: dec i
  for j in i..caret-1:
    result.add charAt(j)
  if del:
    remove(i, caret-1)

