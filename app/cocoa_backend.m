/*  cocoa_backend.m – Cocoa/AppKit backend for NimEdit.
 *
 *  Exposes a flat C API that cocoa_driver.nim imports.
 *  Uses Core Graphics for drawing, Core Text for fonts,
 *  NSView subclass for events.
 *
 *  Compile:  included automatically via {.compile.} in cocoa_driver.nim
 *  Link:     -framework Cocoa -framework CoreText -framework CoreGraphics -framework QuartzCore
 */

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mach/mach_time.h>

/* ---- Event queue (ring buffer) ---------------------------------------- */

enum {
  NE_NONE = 0,
  NE_KEY_DOWN, NE_KEY_UP, NE_TEXT_INPUT,
  NE_MOUSE_DOWN, NE_MOUSE_UP, NE_MOUSE_MOVE, NE_MOUSE_WHEEL,
  NE_WINDOW_RESIZE, NE_WINDOW_CLOSE,
  NE_WINDOW_FOCUS_GAINED, NE_WINDOW_FOCUS_LOST,
  NE_QUIT
};

enum {
  NE_MOD_SHIFT = 1,
  NE_MOD_CTRL  = 2,
  NE_MOD_ALT   = 4,
  NE_MOD_GUI   = 8
};

enum {
  NE_MB_LEFT   = 0,
  NE_MB_RIGHT  = 1,
  NE_MB_MIDDLE = 2
};

typedef struct {
  int kind;
  int key;            /* NimEdit KeyCode ordinal */
  int mods;           /* bitmask of NE_MOD_* */
  char text[4];       /* UTF-8 codepoint for NE_TEXT_INPUT */
  int x, y;
  int xrel, yrel;
  int button;         /* NE_MB_* */
  int buttons;        /* bitmask: 1=left, 2=right, 4=middle */
  int clicks;
} NEEvent;

#define EVENT_QUEUE_SIZE 256
static NEEvent eventQueue[EVENT_QUEUE_SIZE];
static int eqHead = 0, eqTail = 0;

static void pushEvent(NEEvent ev) {
  int next = (eqHead + 1) % EVENT_QUEUE_SIZE;
  if (next == eqTail) return;  /* queue full, drop */
  eventQueue[eqHead] = ev;
  eqHead = next;
}

int cocoa_pollEvent(NEEvent *out) {
  /* Pump the run loop briefly so Cocoa delivers events */
  @autoreleasepool {
    NSEvent *ev;
    while ((ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                    untilDate:nil
                                       inMode:NSDefaultRunLoopMode
                                      dequeue:YES]) != nil) {
      [NSApp sendEvent:ev];
      [NSApp updateWindows];
    }
  }
  if (eqTail == eqHead) {
    out->kind = NE_NONE;
    return 0;
  }
  *out = eventQueue[eqTail];
  eqTail = (eqTail + 1) % EVENT_QUEUE_SIZE;
  return 1;
}

int cocoa_waitEvent(NEEvent *out, int timeoutMs) {
  @autoreleasepool {
    NSDate *deadline = (timeoutMs < 0)
      ? [NSDate distantFuture]
      : [NSDate dateWithTimeIntervalSinceNow:timeoutMs / 1000.0];
    NSEvent *ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                     untilDate:deadline
                                        inMode:NSDefaultRunLoopMode
                                       dequeue:YES];
    if (ev) {
      [NSApp sendEvent:ev];
      [NSApp updateWindows];
      /* pump remaining */
      while ((ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                      untilDate:nil
                                         inMode:NSDefaultRunLoopMode
                                        dequeue:YES]) != nil) {
        [NSApp sendEvent:ev];
        [NSApp updateWindows];
      }
    }
  }
  if (eqTail == eqHead) {
    out->kind = NE_NONE;
    return 0;
  }
  *out = eventQueue[eqTail];
  eqTail = (eqTail + 1) % EVENT_QUEUE_SIZE;
  return 1;
}

/* ---- Modifier helpers ------------------------------------------------- */

static int translateModifiers(NSEventModifierFlags flags) {
  int m = 0;
  if (flags & NSEventModifierFlagShift)   m |= NE_MOD_SHIFT;
  if (flags & NSEventModifierFlagControl) m |= NE_MOD_CTRL;
  if (flags & NSEventModifierFlagOption)  m |= NE_MOD_ALT;
  if (flags & NSEventModifierFlagCommand) m |= NE_MOD_GUI;
  return m;
}

int cocoa_getModState(void) {
  NSEventModifierFlags flags = [NSEvent modifierFlags];
  return translateModifiers(flags);
}

/* ---- Key translation -------------------------------------------------- */

/* Returns NimEdit KeyCode ordinal.  Must match input.nim KeyCode enum. */
static int translateKeyCode(unsigned short kc) {
  switch (kc) {
    case 0x00: return 1;   /* keyA */
    case 0x0B: return 2;   /* keyB */
    case 0x08: return 3;   /* keyC */
    case 0x02: return 4;   /* keyD */
    case 0x0E: return 5;   /* keyE */
    case 0x03: return 6;   /* keyF */
    case 0x05: return 7;   /* keyG */
    case 0x04: return 8;   /* keyH */
    case 0x22: return 9;   /* keyI */
    case 0x26: return 10;  /* keyJ */
    case 0x28: return 11;  /* keyK */
    case 0x25: return 12;  /* keyL */
    case 0x2E: return 13;  /* keyM */
    case 0x2D: return 14;  /* keyN */
    case 0x1F: return 15;  /* keyO */
    case 0x23: return 16;  /* keyP */
    case 0x0C: return 17;  /* keyQ */
    case 0x0F: return 18;  /* keyR */
    case 0x01: return 19;  /* keyS */
    case 0x11: return 20;  /* keyT */
    case 0x20: return 21;  /* keyU */
    case 0x09: return 22;  /* keyV */
    case 0x0D: return 23;  /* keyW */
    case 0x07: return 24;  /* keyX */
    case 0x10: return 25;  /* keyY */
    case 0x06: return 26;  /* keyZ */
    case 0x12: return 28;  /* key1 -- note: key0 = 27, key1 = 28 .. key9 = 36 */
    case 0x13: return 29;  /* key2 */
    case 0x14: return 30;  /* key3 */
    case 0x15: return 31;  /* key4 */
    case 0x17: return 32;  /* key5 */
    case 0x16: return 33;  /* key6 */
    case 0x1A: return 34;  /* key7 */
    case 0x1C: return 35;  /* key8 */
    case 0x19: return 36;  /* key9 */
    case 0x1D: return 27;  /* key0 */
    case 0x7A: return 37;  /* keyF1 */
    case 0x78: return 38;  /* keyF2 */
    case 0x63: return 39;  /* keyF3 */
    case 0x76: return 40;  /* keyF4 */
    case 0x60: return 41;  /* keyF5 */
    case 0x61: return 42;  /* keyF6 */
    case 0x62: return 43;  /* keyF7 */
    case 0x64: return 44;  /* keyF8 */
    case 0x65: return 45;  /* keyF9 */
    case 0x6D: return 46;  /* keyF10 */
    case 0x67: return 47;  /* keyF11 */
    case 0x6F: return 48;  /* keyF12 */
    case 0x24: return 49;  /* keyEnter */
    case 0x31: return 50;  /* keySpace */
    case 0x35: return 51;  /* keyEsc */
    case 0x30: return 52;  /* keyTab */
    case 0x33: return 53;  /* keyBackspace */
    case 0x75: return 54;  /* keyDelete */
    case 0x72: return 55;  /* keyInsert (Help key on Mac) */
    case 0x7B: return 56;  /* keyLeft */
    case 0x7C: return 57;  /* keyRight */
    case 0x7E: return 58;  /* keyUp */
    case 0x7D: return 59;  /* keyDown */
    case 0x74: return 60;  /* keyPageUp */
    case 0x79: return 61;  /* keyPageDown */
    case 0x73: return 62;  /* keyHome */
    case 0x77: return 63;  /* keyEnd */
    case 0x39: return 64;  /* keyCapslock */
    case 0x2B: return 65;  /* keyComma */
    case 0x2F: return 66;  /* keyPeriod */
    default:   return 0;   /* keyNone */
  }
}

/* ---- Font management -------------------------------------------------- */

#define MAX_FONTS 64

typedef struct {
  CTFontRef font;
  int ascent, descent, lineHeight;
} FontSlot;

static FontSlot fonts[MAX_FONTS];
static int fontCount = 0;

int cocoa_openFont(const char *path, int size,
                   int *outAscent, int *outDescent, int *outLineHeight) {
  if (fontCount >= MAX_FONTS) return 0;

  /* Create font from file path */
  CFStringRef cfPath = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
  CFURLRef url = CFURLCreateWithFileSystemPath(NULL, cfPath, kCFURLPOSIXPathStyle, false);
  CGDataProviderRef provider = CGDataProviderCreateWithURL(url);
  CTFontRef ctFont = NULL;

  if (provider) {
    CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
    if (cgFont) {
      ctFont = CTFontCreateWithGraphicsFont(cgFont, (CGFloat)size, NULL, NULL);
      CGFontRelease(cgFont);
    }
    CGDataProviderRelease(provider);
  }
  CFRelease(url);
  CFRelease(cfPath);

  if (!ctFont) return 0;

  int idx = fontCount++;
  fonts[idx].font = ctFont;
  fonts[idx].ascent = (int)ceil(CTFontGetAscent(ctFont));
  fonts[idx].descent = (int)ceil(CTFontGetDescent(ctFont));
  fonts[idx].lineHeight = fonts[idx].ascent + fonts[idx].descent +
                          (int)ceil(CTFontGetLeading(ctFont));
  /* Ensure lineHeight is at least ascent + descent */
  if (fonts[idx].lineHeight < fonts[idx].ascent + fonts[idx].descent)
    fonts[idx].lineHeight = fonts[idx].ascent + fonts[idx].descent;

  *outAscent = fonts[idx].ascent;
  *outDescent = fonts[idx].descent;
  *outLineHeight = fonts[idx].lineHeight;
  return idx + 1;  /* 1-based handle */
}

void cocoa_closeFont(int handle) {
  int idx = handle - 1;
  if (idx >= 0 && idx < fontCount && fonts[idx].font) {
    CFRelease(fonts[idx].font);
    fonts[idx].font = NULL;
  }
}

void cocoa_getFontMetrics(int handle, int *asc, int *desc, int *lh) {
  int idx = handle - 1;
  if (idx >= 0 && idx < fontCount && fonts[idx].font) {
    *asc = fonts[idx].ascent;
    *desc = fonts[idx].descent;
    *lh = fonts[idx].lineHeight;
  } else {
    *asc = *desc = *lh = 0;
  }
}

/* Measure text width/height using Core Text */
void cocoa_measureText(int handle, const char *text, int *outW, int *outH) {
  int idx = handle - 1;
  *outW = 0; *outH = 0;
  if (idx < 0 || idx >= fontCount || !fonts[idx].font || !text || !text[0]) return;

  CFStringRef str = CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
  if (!str) return;

  CFStringRef keys[] = { kCTFontAttributeName };
  CFTypeRef vals[] = { fonts[idx].font };
  CFDictionaryRef attrs = CFDictionaryCreate(NULL,
    (const void **)keys, (const void **)vals, 1,
    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

  CFAttributedStringRef attrStr = CFAttributedStringCreate(NULL, str, attrs);
  CTLineRef line = CTLineCreateWithAttributedString(attrStr);

  CGRect bounds = CTLineGetImageBounds(line, NULL);
  double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
  *outW = (int)ceil(width);
  *outH = fonts[idx].lineHeight;

  CFRelease(line);
  CFRelease(attrStr);
  CFRelease(attrs);
  CFRelease(str);
}

/* ---- Backing bitmap context ------------------------------------------- */

static CGContextRef backingCtx = NULL;
static int backingW = 0, backingH = 0;
static CGFloat backingScale = 1.0;

/* Clip rect stack (simple, max 32 deep) */
#define MAX_CLIP_STACK 32
static CGRect clipStack[MAX_CLIP_STACK];
static int clipTop = 0;

static void ensureBacking(int w, int h, CGFloat scale) {
  if (backingCtx && backingW == w && backingH == h) return;
  if (backingCtx) CGContextRelease(backingCtx);

  backingW = w;
  backingH = h;
  backingScale = scale;

  int pw = (int)(w * scale);
  int ph = (int)(h * scale);

  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  backingCtx = CGBitmapContextCreate(NULL, pw, ph, 8, pw * 4,
    cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(cs);

  if (backingCtx) {
    /* Scale so we can draw in point coordinates */
    CGContextScaleCTM(backingCtx, scale, scale);
    /* Flip coordinate system: Core Graphics is bottom-up, we want top-down */
    CGContextTranslateCTM(backingCtx, 0, h);
    CGContextScaleCTM(backingCtx, 1.0, -1.0);
    CGContextSetShouldAntialias(backingCtx, true);
    CGContextSetShouldSmoothFonts(backingCtx, true);
  }
}

/* ---- Drawing primitives ----------------------------------------------- */

void cocoa_fillRect(int x, int y, int w, int h, int r, int g, int b, int a) {
  if (!backingCtx) return;
  CGContextSetRGBFillColor(backingCtx, r/255.0, g/255.0, b/255.0, a/255.0);
  CGContextFillRect(backingCtx, CGRectMake(x, y, w, h));
}

void cocoa_drawLine(int x1, int y1, int x2, int y2, int r, int g, int b, int a) {
  if (!backingCtx) return;
  CGContextSetRGBStrokeColor(backingCtx, r/255.0, g/255.0, b/255.0, a/255.0);
  CGContextSetLineWidth(backingCtx, 1.0);
  CGContextBeginPath(backingCtx);
  CGContextMoveToPoint(backingCtx, x1 + 0.5, y1 + 0.5);
  CGContextAddLineToPoint(backingCtx, x2 + 0.5, y2 + 0.5);
  CGContextStrokePath(backingCtx);
}

void cocoa_drawPoint(int x, int y, int r, int g, int b, int a) {
  if (!backingCtx) return;
  CGContextSetRGBFillColor(backingCtx, r/255.0, g/255.0, b/255.0, a/255.0);
  CGContextFillRect(backingCtx, CGRectMake(x, y, 1, 1));
}

void cocoa_drawText(int fontHandle, int x, int y, const char *text,
                    int fgR, int fgG, int fgB, int fgA,
                    int bgR, int bgG, int bgB, int bgA,
                    int *outW, int *outH) {
  *outW = 0; *outH = 0;
  int idx = fontHandle - 1;
  if (idx < 0 || idx >= fontCount || !fonts[idx].font || !backingCtx) return;
  if (!text || !text[0]) return;

  CTFontRef ctFont = fonts[idx].font;
  int lh = fonts[idx].lineHeight;
  int asc = fonts[idx].ascent;

  /* Measure first for background fill */
  CFStringRef str = CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
  if (!str) return;

  CGColorRef fgColor = CGColorCreateSRGB(fgR/255.0, fgG/255.0, fgB/255.0, fgA/255.0);

  CFStringRef keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
  CFTypeRef vals[] = { ctFont, fgColor };
  CFDictionaryRef attrs = CFDictionaryCreate(NULL,
    (const void **)keys, (const void **)vals, 2,
    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

  CFAttributedStringRef attrStr = CFAttributedStringCreate(NULL, str, attrs);
  CTLineRef line = CTLineCreateWithAttributedString(attrStr);

  double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
  int tw = (int)ceil(width);

  /* Fill background */
  CGContextSetRGBFillColor(backingCtx, bgR/255.0, bgG/255.0, bgB/255.0, bgA/255.0);
  CGContextFillRect(backingCtx, CGRectMake(x, y, tw, lh));

  /* Draw text.
   * Core Text draws bottom-up. Our context is flipped to top-down.
   * We need to locally un-flip for Core Text rendering. */
  CGContextSaveGState(backingCtx);
  /* Move to the text baseline position:
   * In our flipped coords, y is top of the line, baseline is at y + ascent.
   * We un-flip around the line center. */
  CGContextTranslateCTM(backingCtx, 0, y + lh);
  CGContextScaleCTM(backingCtx, 1.0, -1.0);
  /* Now in un-flipped local coords, baseline is at (x, descent) from bottom */
  CGFloat baseline = fonts[idx].descent + (lh - asc - fonts[idx].descent) * 0.5;
  if (baseline < fonts[idx].descent) baseline = fonts[idx].descent;
  CGContextSetTextPosition(backingCtx, x, baseline);
  CTLineDraw(line, backingCtx);
  CGContextRestoreGState(backingCtx);

  *outW = tw;
  *outH = lh;

  CFRelease(line);
  CFRelease(attrStr);
  CFRelease(attrs);
  CGColorRelease(fgColor);
  CFRelease(str);
}

void cocoa_setClipRect(int x, int y, int w, int h) {
  if (!backingCtx) return;
  CGContextRestoreGState(backingCtx);
  CGContextSaveGState(backingCtx);
  CGContextClipToRect(backingCtx, CGRectMake(x, y, w, h));
}

void cocoa_saveState(void) {
  if (!backingCtx) return;
  CGContextSaveGState(backingCtx);
}

void cocoa_restoreState(void) {
  if (!backingCtx) return;
  CGContextRestoreGState(backingCtx);
}

/* ---- Clipboard -------------------------------------------------------- */

const char *cocoa_getClipboardText(void) {
  @autoreleasepool {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *s = [pb stringForType:NSPasteboardTypeString];
    if (!s) return "";
    /* Return a C string that persists until next call */
    static char *buf = NULL;
    free(buf);
    const char *utf8 = [s UTF8String];
    buf = strdup(utf8);
    return buf;
  }
}

void cocoa_putClipboardText(const char *text) {
  @autoreleasepool {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[NSString stringWithUTF8String:text]
          forType:NSPasteboardTypeString];
  }
}

/* ---- Timing ----------------------------------------------------------- */

static uint64_t startTime = 0;
static mach_timebase_info_data_t timebaseInfo;

uint32_t cocoa_getTicks(void) {
  uint64_t elapsed = mach_absolute_time() - startTime;
  uint64_t nanos = elapsed * timebaseInfo.numer / timebaseInfo.denom;
  return (uint32_t)(nanos / 1000000);
}

void cocoa_delay(uint32_t ms) {
  [NSThread sleepForTimeInterval:ms / 1000.0];
}

/* ---- NSView subclass -------------------------------------------------- */

@interface NimEditView : NSView <NSTextInputClient>
@property (nonatomic) BOOL hasMarkedText;
@end

@implementation NimEditView {
  NSTrackingArea *_trackingArea;
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)isFlipped { return YES; }

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_trackingArea) [self removeTrackingArea:_trackingArea];
  _trackingArea = [[NSTrackingArea alloc]
    initWithRect:self.bounds
         options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow |
                 NSTrackingInVisibleRect
           owner:self
        userInfo:nil];
  [self addTrackingArea:_trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
  if (!backingCtx) return;
  CGContextRef viewCtx = [[NSGraphicsContext currentContext] CGContext];
  CGImageRef img = CGBitmapContextCreateImage(backingCtx);
  if (img) {
    NSRect bounds = self.bounds;
    /* Flip for drawing since view is flipped but CGImage is bottom-up */
    CGContextSaveGState(viewCtx);
    CGContextTranslateCTM(viewCtx, 0, bounds.size.height);
    CGContextScaleCTM(viewCtx, 1.0, -1.0);
    CGContextDrawImage(viewCtx, CGRectMake(0, 0, bounds.size.width, bounds.size.height), img);
    CGContextRestoreGState(viewCtx);
    CGImageRelease(img);
  }
}

/* ---- Keyboard events ---- */

- (void)keyDown:(NSEvent *)event {
  NEEvent e = {0};
  e.kind = NE_KEY_DOWN;
  e.key = translateKeyCode(event.keyCode);
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);

  /* Only feed to interpretKeyEvents when the key can produce text input.
     Skip for Ctrl/Cmd combos and special keys (arrows, backspace, etc.)
     — the app handles those via evKeyDown already. */
  int m = e.mods;
  if ((m & (NE_MOD_CTRL | NE_MOD_GUI)) == 0 && e.key == 0) {
    [self interpretKeyEvents:@[event]];
  } else if ((m & (NE_MOD_CTRL | NE_MOD_GUI)) == 0) {
    /* Known key but no modifier — still try for text (e.g. space, comma).
       But skip keys that are purely control keys. */
    unsigned short kc = event.keyCode;
    switch (kc) {
      case 0x33: /* backspace */
      case 0x75: /* delete */
      case 0x35: /* escape */
      case 0x30: /* tab */
      case 0x24: /* return */
      case 0x7B: case 0x7C: case 0x7E: case 0x7D: /* arrows */
      case 0x74: case 0x79: case 0x73: case 0x77: /* pgup/pgdn/home/end */
      case 0x72: /* insert/help */
      case 0x7A: case 0x78: case 0x63: case 0x76: /* F1-F4 */
      case 0x60: case 0x61: case 0x62: case 0x64: /* F5-F8 */
      case 0x65: case 0x6D: case 0x67: case 0x6F: /* F9-F12 */
        break;
      default:
        [self interpretKeyEvents:@[event]];
        break;
    }
  }
}

/* Suppress the system beep for unhandled key combos */
- (void)doCommandBySelector:(SEL)selector {
  /* intentionally empty — swallows the NSBeep that interpretKeyEvents
     would otherwise trigger for keys without a binding */
}

- (void)keyUp:(NSEvent *)event {
  NEEvent e = {0};
  e.kind = NE_KEY_UP;
  e.key = translateKeyCode(event.keyCode);
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

- (void)flagsChanged:(NSEvent *)event {
  /* Ignore standalone modifier key events */
}

/* ---- Mouse events ---- */

- (void)mouseDown:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  NEEvent e = {0};
  e.kind = NE_MOUSE_DOWN;
  e.button = NE_MB_LEFT;
  e.x = (int)p.x;
  e.y = (int)p.y;
  e.clicks = (int)event.clickCount;
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

- (void)mouseUp:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  NEEvent e = {0};
  e.kind = NE_MOUSE_UP;
  e.button = NE_MB_LEFT;
  e.x = (int)p.x;
  e.y = (int)p.y;
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

- (void)rightMouseDown:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  NEEvent e = {0};
  e.kind = NE_MOUSE_DOWN;
  e.button = NE_MB_RIGHT;
  e.x = (int)p.x;
  e.y = (int)p.y;
  e.clicks = (int)event.clickCount;
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

- (void)rightMouseUp:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  NEEvent e = {0};
  e.kind = NE_MOUSE_UP;
  e.button = NE_MB_RIGHT;
  e.x = (int)p.x;
  e.y = (int)p.y;
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

- (void)otherMouseDown:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  NEEvent e = {0};
  e.kind = NE_MOUSE_DOWN;
  e.button = NE_MB_MIDDLE;
  e.x = (int)p.x;
  e.y = (int)p.y;
  e.clicks = (int)event.clickCount;
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

- (void)otherMouseUp:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  NEEvent e = {0};
  e.kind = NE_MOUSE_UP;
  e.button = NE_MB_MIDDLE;
  e.x = (int)p.x;
  e.y = (int)p.y;
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

static int currentButtons(NSEvent *event) {
  NSUInteger pressed = [NSEvent pressedMouseButtons];
  int b = 0;
  if (pressed & (1 << 0)) b |= 1;  /* left */
  if (pressed & (1 << 1)) b |= 2;  /* right */
  if (pressed & (1 << 2)) b |= 4;  /* middle */
  return b;
}

- (void)mouseMoved:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  NEEvent e = {0};
  e.kind = NE_MOUSE_MOVE;
  e.x = (int)p.x;
  e.y = (int)p.y;
  e.xrel = (int)event.deltaX;
  e.yrel = (int)event.deltaY;
  e.buttons = currentButtons(event);
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

- (void)mouseDragged:(NSEvent *)event {
  [self mouseMoved:event];
}

- (void)rightMouseDragged:(NSEvent *)event {
  [self mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent *)event {
  [self mouseMoved:event];
}

- (void)scrollWheel:(NSEvent *)event {
  NEEvent e = {0};
  e.kind = NE_MOUSE_WHEEL;
  if (event.hasPreciseScrollingDeltas) {
    /* Trackpad: pixel-level deltas, divide down to line-level.
       Accumulate fractional remainder so slow swipes still register. */
    static double accumX = 0, accumY = 0;
    accumX += event.scrollingDeltaX;
    accumY += event.scrollingDeltaY;
    e.x = (int)(accumX / 16.0);
    e.y = (int)(accumY / 16.0);
    accumX -= e.x * 16.0;
    accumY -= e.y * 16.0;
    if (e.x == 0 && e.y == 0) return;  /* sub-line movement, wait */
  } else {
    /* Discrete mouse wheel: already line-based */
    e.x = (int)event.scrollingDeltaX;
    e.y = (int)event.scrollingDeltaY;
  }
  e.mods = translateModifiers(event.modifierFlags);
  pushEvent(e);
}

/* ---- NSTextInputClient (for text input / IME) ---- */

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
  NSString *s = ([string isKindOfClass:[NSAttributedString class]])
    ? [string string] : string;
  const char *utf8 = [s UTF8String];
  if (!utf8) return;

  /* Send each character as a separate text input event */
  NSUInteger len = strlen(utf8);
  NSUInteger i = 0;
  while (i < len) {
    NEEvent e = {0};
    e.kind = NE_TEXT_INPUT;
    /* Copy one UTF-8 codepoint (1-4 bytes) */
    unsigned char c = (unsigned char)utf8[i];
    int cpLen = 1;
    if (c >= 0xC0) cpLen = 2;
    if (c >= 0xE0) cpLen = 3;
    if (c >= 0xF0) cpLen = 4;
    for (int j = 0; j < cpLen && j < 4 && (i + j) < len; j++)
      e.text[j] = utf8[i + j];
    pushEvent(e);
    i += cpLen;
  }
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange
      replacementRange:(NSRange)replacementRange {
  self.hasMarkedText = ([(NSString *)string length] > 0);
}

- (void)unmarkText { self.hasMarkedText = NO; }
- (BOOL)hasMarkedText { return _hasMarkedText; }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (NSRange)selectedRange { return NSMakeRange(0, 0); }
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actual {
  return NSMakeRect(0, 0, 0, 0);
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point { return NSNotFound; }
- (NSArray *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
                                                actualRange:(NSRangePointer)actual {
  return nil;
}

@end

/* ---- Window delegate -------------------------------------------------- */

@interface NimEditWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation NimEditWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
  NEEvent e = {0};
  e.kind = NE_WINDOW_CLOSE;
  pushEvent(e);
  return NO;  /* let the app decide */
}

- (void)windowDidResize:(NSNotification *)n {
  NSWindow *w = n.object;
  NSRect frame = [[w contentView] frame];
  CGFloat scale = [w backingScaleFactor];
  ensureBacking((int)frame.size.width, (int)frame.size.height, scale);

  NEEvent e = {0};
  e.kind = NE_WINDOW_RESIZE;
  e.x = (int)frame.size.width;
  e.y = (int)frame.size.height;
  pushEvent(e);
}

- (void)windowDidBecomeKey:(NSNotification *)n {
  NEEvent e = {0};
  e.kind = NE_WINDOW_FOCUS_GAINED;
  pushEvent(e);
}

- (void)windowDidResignKey:(NSNotification *)n {
  NEEvent e = {0};
  e.kind = NE_WINDOW_FOCUS_LOST;
  pushEvent(e);
}

@end

/* ---- Window management ------------------------------------------------ */

static NSWindow *mainWindow = nil;
static NimEditView *mainView = nil;
static NimEditWindowDelegate *winDelegate = nil;

void cocoa_createWindow(int w, int h, int *outW, int *outH,
                        int *outScaleX, int *outScaleY) {
  @autoreleasepool {
    /* Initialize timing */
    mach_timebase_info(&timebaseInfo);
    startTime = mach_absolute_time();

    /* Set up NSApplication */
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    /* Create menu bar (minimal: just app menu with Quit) */
    NSMenu *menubar = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];

    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *quitItem = [[NSMenuItem alloc]
      initWithTitle:@"Quit NimEdit"
             action:@selector(terminate:)
      keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    /* Create window */
    NSRect rect = NSMakeRect(100, 100, w, h);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    mainWindow = [[NSWindow alloc] initWithContentRect:rect
                                             styleMask:style
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [mainWindow setTitle:@"NimEdit"];
    [mainWindow setAcceptsMouseMovedEvents:YES];

    /* Create view */
    mainView = [[NimEditView alloc] initWithFrame:rect];
    [mainWindow setContentView:mainView];
    [mainWindow makeFirstResponder:mainView];

    /* Window delegate */
    winDelegate = [[NimEditWindowDelegate alloc] init];
    [mainWindow setDelegate:winDelegate];

    /* Show */
    [mainWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    /* Finish launch so events flow */
    [NSApp finishLaunching];

    /* Set up backing bitmap */
    CGFloat scale = [mainWindow backingScaleFactor];
    NSRect contentFrame = [mainView frame];
    ensureBacking((int)contentFrame.size.width, (int)contentFrame.size.height, scale);

    *outW = (int)contentFrame.size.width;
    *outH = (int)contentFrame.size.height;
    *outScaleX = (int)scale;
    *outScaleY = (int)scale;
  }
}

void cocoa_refresh(void) {
  @autoreleasepool {
    [mainView setNeedsDisplay:YES];
    [mainView displayIfNeeded];
  }
}

void cocoa_setWindowTitle(const char *title) {
  @autoreleasepool {
    [mainWindow setTitle:[NSString stringWithUTF8String:title]];
  }
}

void cocoa_setCursor(int kind) {
  @autoreleasepool {
    NSCursor *cur;
    switch (kind) {
      case 2:  cur = [NSCursor IBeamCursor]; break;       /* curIbeam */
      case 3:  cur = [NSCursor arrowCursor]; break;        /* curWait (no wait cursor, use arrow) */
      case 4:  cur = [NSCursor crosshairCursor]; break;    /* curCrosshair */
      case 5:  cur = [NSCursor pointingHandCursor]; break; /* curHand */
      case 6:  cur = [NSCursor resizeUpDownCursor]; break; /* curSizeNS */
      case 7:  cur = [NSCursor resizeLeftRightCursor]; break; /* curSizeWE */
      default: cur = [NSCursor arrowCursor]; break;
    }
    [cur set];
  }
}

void cocoa_startTextInput(void) {
  /* NSTextInputClient is always active on our view */
}

void cocoa_quitRequest(void) {
  NEEvent e = {0};
  e.kind = NE_QUIT;
  pushEvent(e);
}
