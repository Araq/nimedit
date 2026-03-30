# Base types for the UI layer. No SDL or platform dependencies.

type
  Rect* = object
    x*, y*: cint
    w*, h*: cint

  Point* = object
    x*, y*: cint

  Pixel* = distinct uint32

  GlobalPos* = object
    x*, y*, z*: int
    t*: int
