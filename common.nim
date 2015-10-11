# Common definitions for both the core of Editnova
# as well as its NimScript support

type
  TokenClass* {.pure.} = enum
    None, Whitespace, DecNumber, BinNumber, HexNumber,
    OctNumber, FloatNumber, Identifier, Keyword, StringLit,
    LongStringLit, CharLit, Backticks,
    EscapeSequence, # escape sequence like \xff
    Operator, Punctuation, Comment, LongComment, RegularExpression,
    TagStart, TagStandalone, TagEnd, Key, Value, RawData, Assembler,
    Preprocessor, Directive, Command, Rule, Link, Label,
    Reference, Text, Other, Green, Yellow, Red

  FontStyle* {.pure.} = enum
    Normal, Bold, Italic, BoldItalic

type
  SourceLanguage* = enum
    langNone, langNim, langCpp, langCsharp, langC, langJava, langJs,
    langXml, langHtml, langConsole
