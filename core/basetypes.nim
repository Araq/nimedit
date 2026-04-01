# Base types for the UI layer. No SDL or platform dependencies.

type
  Rect* = object
    x*, y*: int
    w*, h*: int

  Point* = object
    x*, y*: int

  GlobalPos* = object
    x*, y*, z*: int
    t*: int

proc rect*(x, y, w, h: int): Rect =
  Rect(x: x, y: y, w: w, h: h)

proc point*(x, y: int): Point =
  Point(x: x, y: y)

proc contains*(r: Rect; p: Point): bool =
  p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h
