
import common

const
  sourceLanguageToStr*: array[SourceLanguage, string] = ["none",
    "Nim", "C++", "C#", "C", "Java", "JavaScript", "XML", "HTML", "Console"]

  additionalIndentChars*: array [SourceLanguage, set[char]] = [
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
  of ".js": langJs
  of ".java": langJava
  of ".cs": langCsharp
  of ".xml": langXml
  of ".html", ".htm": langHtml
  else: langNone

type
  InterestingControlflowEnum = enum
    isUninteresting, isInteresting, isCase

proc interestingControlflow*(lang: SourceLanguage; word: string): bool =
  case lang
  of langNone, langConsole: false
  of langNim: word in ["if", "while", "for", "case", "when", "elif", "proc",
                       "template", "method", "macro", "converter", "func",
                       "iterator"]
  of langCpp, langCsharp:
    word in ["class", "if", "switch", "for", "while", "struct"]
  of langC:
    word in ["if", "switch", "for", "while", "struct"]
  of langJs, langJava:
    word in ["class", "if", "switch", "for", "while"]
  of langXml, langHtml: true
