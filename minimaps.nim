## Currently only supports Nim.

import buffertype, buffer

import
  parseutils, strutils,
  compiler/ast, compiler/parser,
  compiler/llstream,
  compiler/msgs,
  compiler/astalgo, compiler/renderer

proc errorHandler(info: TLineInfo; msg: TMsgKind; arg: string) =
  discard "ignore errors for the minimap generation"

proc allDeclarations(n: PNode; minimap: Buffer) =
  proc addDecl(n: PNode; minimap: Buffer) =
    if n.info.line >= 0:
      let line = $n.info.line
      minimap.insert(line & repeat(' ', 6 - line.len) &
        renderTree(n, {renderNoBody, renderNoComments, renderDocComments,
                       renderNoPragmas}).replace("\L"))
      minimap.insert("\L")
  case n.kind
  of nkProcDef, nkMethodDef, nkIteratorDef, nkConverterDef,
     nkTemplateDef, nkMacroDef:
    addDecl(n, minimap)
  of nkConstDef, nkTypeDef:
    addDecl(n[0], minimap)
  of nkIdentDefs:
    for i in 0..n.len-3:
      addDecl(n[i], minimap)
  of nkStmtList, nkStmtListExpr, nkConstSection, nkLetSection,
     nkVarSection, nkTypeSection:
    for i in 0..<n.len:
      allDeclarations(n[i], minimap)
  else: discard

proc onEnter*(minimap: Buffer): int =
  ## returns the line it should be jumped to. -1 if nothing was selected.
  result = -1
  discard parseInt(minimap.getCurrentLine, result, 0)

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
    allDeclarations(ast, minimap)
    if minimap.numberOfLines >= 1:
      minimap.gotoLine(1, -1)
