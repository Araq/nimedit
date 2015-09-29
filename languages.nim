
type
  TokenClass* = enum
    gtNone, gtWhitespace, gtDecNumber, gtBinNumber, gtHexNumber,
    gtOctNumber, gtFloatNumber, gtIdentifier, gtKeyword, gtStringLit,
    gtLongStringLit, gtCharLit, gtEscapeSequence, # escape sequence like \xff
    gtOperator, gtPunctuation, gtComment, gtLongComment, gtRegularExpression,
    gtTagStart, gtTagEnd, gtKey, gtValue, gtRawData, gtAssembler,
    gtPreprocessor, gtDirective, gtCommand, gtRule, gtLink, gtLabel,
    gtReference, gtOther, gtGreen, gtYellow, gtRed

  SourceLanguage* = enum
    langNone, langNim, langNimrod, langCpp, langCsharp, langC, langJava,
    langConsole

  MarkerClass* = enum
    mcSelected, mcHighlighted, mcBreakPoint

const
  sourceLanguageToStr*: array[SourceLanguage, string] = ["none",
    "Nim", "Nimrod", "C++", "C#", "C", "Java", "Console"]
  tokenClassToStr*: array[TokenClass, string] = ["None", "Whitespace",
    "DecNumber", "BinNumber", "HexNumber", "OctNumber", "FloatNumber",
    "Identifier", "Keyword", "StringLit", "LongStringLit", "CharLit",
    "EscapeSequence", "Operator", "Punctuation", "Comment", "LongComment",
    "RegularExpression", "TagStart", "TagEnd", "Key", "Value", "RawData",
    "Assembler", "Preprocessor", "Directive", "Command", "Rule", "Link",
    "Label", "Reference", "Other", "Green", "Yellow", "Red"]

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
