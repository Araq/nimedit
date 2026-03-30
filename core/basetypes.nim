# Base types for the UI layer. No SDL or platform dependencies.

type
  Rect* = object
    x*, y*: cint
    w*, h*: cint

  Point* = object
    x*, y*: cint

  GlobalPos* = object
    x*, y*, z*: int
    t*: int

proc rect*(x, y, w, h: cint): Rect =
  Rect(x: x, y: y, w: w, h: h)

proc rect*(x, y, w, h: int): Rect =
  Rect(x: x.cint, y: y.cint, w: w.cint, h: h.cint)

proc point*(x, y: cint): Point =
  Point(x: x, y: y)

proc point*(x, y: int): Point =
  Point(x: x.cint, y: y.cint)

proc contains*(r: Rect; p: Point): bool =
  p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h
