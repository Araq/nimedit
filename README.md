NimEdit is the new upcoming slim IDE/editor for the Nim programming language.

![shot1.png](https://bitbucket.org/repo/ee5daK/images/675518804-shot1.png)

# Installation

NimEdit now uses the new [uirelays]() library for drawing and font rendering. This library talks directly to your
OS and has no dependencies. But it can also use an SDL 3 backend via `-d:sdl3`.

To install the required dependencies use:

```nim
nimble install
```

## Windows

NimEdit uses the Windows API for drawing and font rendering. To the best of my knowledge nothing special
needs to be installed. (Corrections welcome!)


## Linux

On Linux we use X11:

```
sudo apt install libx11-dev libxft-dev
```

You may need to install good fonts via:

```
sudo apt install fonts-freefont-ttf fonts-dejavu-core
```


## OSX

NimEdit uses a Cocoa-based wrapper which does not require anything beyond the typical frameworks. To the best of my knowledge nothing special needs to be installed. (Corrections welcome!)

