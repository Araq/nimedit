
import nimscript/common

const
  sourceLanguageToStr*: array[SourceLanguage, string] = ["none",
    "Nim", "C++", "C#", "C", "Java", "JavaScript", "XML", "HTML", "Console"]

  additionalIndentChars*: array[SourceLanguage, set[char]] = [
    langNone: {},
    langNim: {'(', '[', '{', ':', '='},
    langCpp: {'(', '[', '{'},
    langCsharp: {'(', '[', '{'},
    langC: {'(', '[', '{'},
    langJava: {'(', '[', '{'},
    langJs: {'(', '[', '{'},
    langXml: {'>'},
    langHtml: {'>'},
    langConsole: {}]

from strutils import toLowerAscii, cmpIgnoreStyle

proc getSourceLanguage*(name: string): SourceLanguage =
  for i in countup(succ(low(SourceLanguage)), high(SourceLanguage)):
    if cmpIgnoreStyle(name, sourceLanguageToStr[i]) == 0:
      return i
  result = langNone

proc fileExtToLanguage*(ext: string): SourceLanguage =
  case ext.toLowerAscii
  of ".nim", ".nims": langNim
  of ".cpp", ".hpp", ".cxx", ".h": langCpp
  of ".c": langC
  of ".js": langJs
  of ".java": langJava
  of ".cs": langCsharp
  of ".xml": langXml
  of ".html", ".htm": langHtml
  else: langNone

type
  InterestingControlflowEnum* = enum
    isUninteresting, isIf, isCase, isDecl

proc interestingControlflow*(lang: SourceLanguage;
                             word: string): InterestingControlflowEnum =
  case lang
  of langNone, langConsole: isUninteresting
  of langNim:
    case word
    of "case": isCase
    of "if", "while", "for", "when": isIf
    of "proc", "template", "method", "macro", "converter", "func", "iterator":
      isDecl
    else:
      isUninteresting
  of langCpp, langCsharp, langC, langJs, langJava:
    case word
    of "class", "struct": isDecl
    of "if", "for", "while": isIf
    of "switch": isCase
    else:
      isUninteresting
  of langXml, langHtml: isIf
