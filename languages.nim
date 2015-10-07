
import common

type
  SourceLanguage* = enum
    langNone, langNim, langCpp, langCsharp, langC, langJava,
    langConsole

const
  sourceLanguageToStr*: array[SourceLanguage, string] = ["none",
    "Nim", "C++", "C#", "C", "Java", "Console"]
  tokenClassToStr*: array[TokenClass, string] = ["None", "Whitespace",
    "DecNumber", "BinNumber", "HexNumber", "OctNumber", "FloatNumber",
    "Identifier", "Keyword", "StringLit", "LongStringLit", "CharLit",
    "EscapeSequence", "Operator", "Punctuation", "Comment", "LongComment",
    "RegularExpression", "TagStart", "TagEnd", "Key", "Value", "RawData",
    "Assembler", "Preprocessor", "Directive", "Command", "Rule", "Link",
    "Label", "Reference", "Other", "Green", "Yellow", "Red"]

  additionalIndentChars*: array [SourceLanguage, set[char]] = [
    langNone: {},
    langNim: {'(', '[', '{', ':', '='},
    langCpp: {'(', '[', '{'},
    langCsharp: {'(', '[', '{'},
    langC: {'(', '[', '{'},
    langJava: {'(', '[', '{'},
    langConsole: {}]

from strutils import toLower, cmpIgnoreStyle

proc getSourceLanguage*(name: string): SourceLanguage =
  for i in countup(succ(low(SourceLanguage)), high(SourceLanguage)):
    if cmpIgnoreStyle(name, sourceLanguageToStr[i]) == 0:
      return i
  result = langNone

proc fileExtToLanguage*(ext: string): SourceLanguage =
  case ext.toLower
  of ".nim", ".nims": langNim
  of ".cpp", ".hpp", ".cxx", ".h": langCpp
  of ".c": langC
  of ".java": langJava
  of ".cs": langCsharp
  else: langNone
