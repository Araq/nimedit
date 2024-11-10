## Currently only supports Nim.

import buffertype, buffer

import
  parseutils, strutils, intsets, nimscriptsupport,
  compiler / [ast, idents, parser, llstream, msgs, astalgo, renderer, lookups,
    lineinfos, options]

proc errorHandler(conf: ConfigRef; info: TLineInfo; msg: TMsgKind; arg: string) =
  discard "ignore errors for the minimap generation"

proc considerQuotedIdent(n: PNode): PIdent =
  case n.kind
  of nkIdent: result = n.ident
  of nkSym: result = n.sym.name
  of nkAccQuoted:
    case n.len
    of 0: discard
    of 1: result = considerQuotedIdent(n.sons[0])
    else:
      var id = ""
      for i in 0..<n.len:
        let x = n.sons[i]
        case x.kind
        of nkIdent: id.add(x.ident.s)
        of nkSym: id.add(x.sym.name.s)
        of nkLiterals - nkFloatLiterals: id.add(x.renderTree)
        else: discard
      result = getIdent(identCache, id)
  of nkOpenSymChoice, nkClosedSymChoice:
    if n[0].kind == nkSym:
      result = n.sons[0].sym.name
  else:
    discard

proc allDeclarations(n: PNode; minimap: Buffer; useActiveLines: bool) =
  proc addDecl(n: PNode; minimap: Buffer; useActiveLines: bool) =
    if n.info.line >= 0u16:
      if useActiveLines:
        minimap.activeLines.incl n.info.line.int-1
        var nn = n
        if nn.kind == nkPragmaExpr: nn = nn[0]
        if nn.kind == nkPostfix: nn = nn[1]
        let ident = considerQuotedIdent(nn)
        when NimMajor >= 2:
          let s = newSym(skUnknown, ident, getIdgen(), nil, n.info)
        else:
          let s = newSym(skUnknown, ident, nextSymId(getIdgen()), nil, n.info)
        minimap.symtab.strTableAdd(s)
      else:
        let line = $n.info.line
        minimap.insert(line & repeat(' ', 6 - line.len) &
          renderTree(n, {renderNoBody, renderNoComments, renderDocComments,
                         renderNoPragmas}).replace("\L"))
        minimap.insert("\L")
  case n.kind
  of nkProcDef, nkMethodDef, nkIteratorDef, nkConverterDef,
     nkTemplateDef, nkMacroDef:
    addDecl(n[namePos], minimap, useActiveLines)
  of nkConstDef, nkTypeDef:
    addDecl(n[0], minimap, useActiveLines)
  of nkIdentDefs:
    for i in 0..n.len-3:
      addDecl(n[i], minimap, useActiveLines)
  of nkStmtList, nkStmtListExpr, nkConstSection, nkLetSection,
     nkVarSection, nkTypeSection, nkWhenStmt:
    for i in 0..<n.len:
      allDeclarations(n[i], minimap, useActiveLines)
  else: discard

proc onEnter*(minimap: Buffer): int =
  ## returns the line it should be jumped to. -1 if nothing was selected.
  result = -1
  discard parseInt(minimap.getCurrentLine, result, 0)

proc filterMinimap*(b: Buffer) =
  if b.minimapVersion != b.version:
    b.minimapVersion = b.version
    b.activeLines = initIntSet()
    let ast = parser.parseString(b.fullText, identCache, gConfig, b.filename, 0,
                                 errorHandler)
    allDeclarations(ast, b, true)

proc containsIgnoreStyle(a, b: string): bool =
  # YYY optimize and make part of stdlib
  a.normalize.contains(b.normalize)

proc gotoNextDeclaration*(b: Buffer; ident: string): int =
  var it: TIdentIter
  var s = initIdentIter(it, b.symtab, getIdent(identCache, ident))
  if s == nil:
    # there is no such declared identifier, so search for something similar:
    var it: TTabIter
    s = initTabIter(it, b.symtab)
    while s != nil:
      if s.name.s.containsIgnoreStyle(ident) and b.currentLine+1 != s.info.line.int:
        return s.info.line.int
      s = nextIter(it, b.symtab)
  else:
    while s != nil:
      if b.currentLine+1 != s.info.line.int:
        return s.info.line.int
      s = nextIdentIter(it, b.symtab)

proc populateMinimap*(minimap, buffer: Buffer) =
  # be smart and don't do unnecessary work:
  if minimap.version != buffer.version or minimap.filename != buffer.filename:
    minimap.version = buffer.version
    minimap.filename = buffer.filename
    minimap.lang = buffer.lang
    # XXX make the buffer implement the streams interface
    let ast = parser.parseString(buffer.fullText, identCache, gConfig, buffer.filename, 0,
                                 errorHandler)
    minimap.clear()
    allDeclarations(ast, minimap, false)
    if minimap.numberOfLines >= 1:
      minimap.gotoLine(1, -1)
