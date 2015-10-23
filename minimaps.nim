## Currently only supports Nim.

import buffertype, buffer

import
  parseutils, strutils, intsets,
  compiler/ast, compiler/parser,
  compiler/llstream,
  compiler/msgs,
  compiler/astalgo, compiler/renderer

proc errorHandler(info: TLineInfo; msg: TMsgKind; arg: string) =
  discard "ignore errors for the minimap generation"

proc allDeclarations(n: PNode; minimap: Buffer; useActiveLines: bool) =
  proc addDecl(n: PNode; minimap: Buffer; useActiveLines: bool) =
    if n.info.line >= 0:
      if useActiveLines:
        minimap.activeLines.incl n.info.line-1
      else:
        let line = $n.info.line
        minimap.insert(line & repeat(' ', 6 - line.len) &
          renderTree(n, {renderNoBody, renderNoComments, renderDocComments,
                         renderNoPragmas}).replace("\L"))
        minimap.insert("\L")
  case n.kind
  of nkProcDef, nkMethodDef, nkIteratorDef, nkConverterDef,
     nkTemplateDef, nkMacroDef:
    addDecl(n, minimap, useActiveLines)
  of nkConstDef, nkTypeDef:
    addDecl(n[0], minimap, useActiveLines)
  of nkIdentDefs:
    for i in 0..n.len-3:
      addDecl(n[i], minimap, useActiveLines)
  of nkStmtList, nkStmtListExpr, nkConstSection, nkLetSection,
     nkVarSection, nkTypeSection:
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
    let ast = parser.parseString(b.fullText, b.filename, 0,
                                 errorHandler)
    allDeclarations(ast, b, true)

proc populateMinimap*(minimap, buffer: Buffer) =
  # be smart and don't do unnecessary work:
  if minimap.version != buffer.version or minimap.filename != buffer.filename:
    minimap.version = buffer.version
    minimap.filename = buffer.filename
    minimap.lang = buffer.lang
    # XXX make the buffer implement the streams interface
    let ast = parser.parseString(buffer.fullText, buffer.filename, 0,
                                 errorHandler)
    minimap.clear()
    allDeclarations(ast, minimap, false)
    if minimap.numberOfLines >= 1:
      minimap.gotoLine(1, -1)
