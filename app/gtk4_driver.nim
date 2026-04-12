# GTK 4 backend: thin C bindings. Sets hooks from core/input and core/screen.
#
# Build (from repo root, with nim.cfg):
#   nim c -d:gtk4 app/nimedit.nim
# Requires dev packages: gtk4, pangocairo, pangoft2, fontconfig (pkg-config names).
# Uses gtk_event_controller_key_set_im_context (GTK 4.2+). GtkDrawingArea "resize" needs GTK 4.6+.
# If pkg-config is missing, set compile-time flags manually, e.g.:
#   nim c -d:gtk4 --passC:"$(pkg-config --cflags gtk4)" --passL:"$(pkg-config --libs gtk4 pangocairo pangoft2 fontconfig)" app/nimedit.nim
# evMouseMove does not set `buttons` (held buttons) yet; SDL drivers do.

{.emit: """
#include <gtk/gtk.h>
#include <gdk/gdk.h>
#include <cairo.h>
#include <pango/pangocairo.h>
#include <pango/pangofc-fontmap.h>
#include <fontconfig/fontconfig.h>
#include <glib.h>

static inline FcPattern *nimedit_fc_font_match(FcPattern *p, void *result_out) {
  return FcFontMatch(NULL, p, (FcResult *)result_out);
}
""".}

import std/unicode
import basetypes, input, screen

const
  gtkCflags {.strdefine.} = staticExec("pkg-config --cflags gtk4 pangocairo pangoft2 fontconfig glib-2.0 2>/dev/null").strip
  gtkLibs {.strdefine.} = staticExec("pkg-config --libs gtk4 pangocairo pangoft2 fontconfig glib-2.0 2>/dev/null").strip

const gtkFallbackCflags =
  "-I/usr/include/gtk-4.0 -I/usr/include/glib-2.0 " &
  "-I/usr/lib/x86_64-linux-gnu/glib-2.0/include -I/usr/lib/aarch64-linux-gnu/glib-2.0/include " &
  "-I/usr/include/pango-1.0 -I/usr/include/harfbuzz -I/usr/include/freetype2 " &
  "-I/usr/include/libpng16 -I/usr/include/libmount -I/usr/include/blkid " &
  "-I/usr/include/fribidi -I/usr/include/cairo -I/usr/include/pixman-1 " &
  "-I/usr/include/gdk-pixbuf-2.0 -I/usr/include/webp -I/usr/include/graphene-1.0 " &
  "-I/usr/include/fontconfig -pthread"

const gtkFallbackLibs =
  "-lgtk-4 -lgdk-4 -lpangocairo-1.0 -lpangoft2-1.0 -lpango-1.0 -lgobject-2.0 " &
  "-lglib-2.0 -lgio-2.0 -lgmodule-2.0 -lfontconfig -lfreetype -lcairo -lharfbuzz " &
  "-lgraphene-1.0 -lfribidi -lgdk_pixbuf-2.0 -lXi -lX11 -ldl -lm"

when gtkCflags.len > 0:
  {.passC: gtkCflags.}
else:
  {.warning: "gtk4_driver: pkg-config --cflags failed; using fallback -I paths".}
  {.passC: gtkFallbackCflags.}

when gtkLibs.len > 0:
  {.passL: gtkLibs.}
else:
  {.warning: "gtk4_driver: pkg-config --libs failed; using fallback -l flags".}
  {.passL: gtkFallbackLibs.}

type
  gboolean = cint
  guint = cuint
  gint = cint
  gulong = culong
  gdouble = cdouble
  GCallback = pointer
  GConnectFlags = cint

type
  GtkDrawingArea {.importc, header: "<gtk/gtk.h>", incompleteStruct.} = object
  cairo_t {.importc, header: "<cairo.h>", incompleteStruct.} = object
  GError {.importc, header: "<glib.h>", incompleteStruct.} = object
  GObject {.importc, header: "<glib-object.h>", incompleteStruct.} = object
  GAsyncResult {.importc, header: "<gio/gio.h>", incompleteStruct.} = object

const
  G_FALSE = gboolean(0)
  G_TRUE = gboolean(1)
  GDK_BUTTON_MIDDLE = 2'u32
  GDK_BUTTON_SECONDARY = 3'u32
  PANGO_SCALE = 1024
  GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES = 3
  FcMatchPattern = 0
  CAIRO_FORMAT_ARGB32 = 0 ## cairo_format_t; pixel buffer must be flushed before another cairo_t reads it

const
  FC_FILE = "file"

# --- Minimal GObject / GLib / GTK / Gdk / Cairo / Pango / Fontconfig ---

proc g_signal_connect_data(
  inst: pointer; signal: cstring; handler: GCallback;
  data, destroyData: pointer; flags: GConnectFlags
): gulong {.importc, nodecl, cdecl.}

proc g_object_unref(o: pointer) {.importc, nodecl, cdecl.}
proc g_error_free(err: ptr GError) {.importc, nodecl, cdecl.}
proc g_free(p: pointer) {.importc, nodecl, cdecl.}
proc g_get_monotonic_time(): int64 {.importc, nodecl, cdecl.}
proc g_usleep(micros: culong) {.importc, nodecl, cdecl.}

proc g_main_context_iteration(ctx: pointer; mayBlock: gboolean): gboolean {.importc, nodecl, cdecl.}

proc gtk_init_check(): gboolean {.importc, nodecl, cdecl.}
proc gtk_window_new(): pointer {.importc, nodecl, cdecl.}
proc gtk_window_set_title(win: pointer; title: cstring) {.importc, nodecl, cdecl.}
proc gtk_window_set_default_size(win: pointer; w, h: gint) {.importc, nodecl, cdecl.}
proc gtk_window_set_child(win: pointer; child: pointer) {.importc, nodecl, cdecl.}
proc gtk_window_destroy(win: pointer) {.importc, nodecl, cdecl.}
proc gtk_window_present(win: pointer) {.importc, nodecl, cdecl.}
proc gtk_widget_queue_draw(w: pointer) {.importc, nodecl, cdecl.}
proc gtk_widget_grab_focus(w: pointer) {.importc, nodecl, cdecl.}
proc gtk_widget_set_cursor(w, cursor: pointer) {.importc, nodecl, cdecl.}
proc gtk_widget_get_width(w: pointer): gint {.importc, nodecl, cdecl.}
proc gtk_widget_get_height(w: pointer): gint {.importc, nodecl, cdecl.}
proc gtk_widget_set_focusable(w: pointer; focusable: gboolean) {.importc, nodecl, cdecl.}
proc gtk_widget_set_hexpand(w: pointer; expand: gboolean) {.importc, nodecl, cdecl.}
proc gtk_widget_set_vexpand(w: pointer; expand: gboolean) {.importc, nodecl, cdecl.}
proc gtk_widget_add_controller(w, ctrl: pointer) {.importc, nodecl, cdecl.}

proc gtk_drawing_area_new(): pointer {.importc, nodecl, cdecl.}
proc gtk_drawing_area_set_content_width(area: ptr GtkDrawingArea; width: gint) {.importc, nodecl, cdecl.}
proc gtk_drawing_area_set_content_height(area: ptr GtkDrawingArea; height: gint) {.importc, nodecl, cdecl.}
proc gtk_drawing_area_get_content_width(area: ptr GtkDrawingArea): gint {.importc, nodecl, cdecl.}
proc gtk_drawing_area_get_content_height(area: ptr GtkDrawingArea): gint {.importc, nodecl, cdecl.}
proc gtk_drawing_area_set_draw_func(
  area: pointer;
  drawFunc: proc (area: ptr GtkDrawingArea; cr: ptr cairo_t; w, h: gint;
      data: pointer) {.cdecl.};
  data: pointer; destroyNotify: pointer
) {.importc, nodecl, cdecl.}

proc gtk_event_controller_key_new(): pointer {.importc, nodecl, cdecl.}
proc gtk_event_controller_key_set_im_context(keyCtrl, im: pointer) {.importc, nodecl, cdecl.}
proc gtk_event_controller_get_current_event(ctrl: pointer): pointer {.importc, nodecl, cdecl.}
proc gtk_event_controller_motion_new(): pointer {.importc, nodecl, cdecl.}
proc gtk_event_controller_scroll_new(flags: guint): pointer {.importc, nodecl, cdecl.}
proc gtk_event_controller_focus_new(): pointer {.importc, nodecl, cdecl.}
proc gtk_gesture_click_new(): pointer {.importc, nodecl, cdecl.}
proc gtk_gesture_single_set_button(gesture: pointer; button: gint) {.importc, nodecl, cdecl.}
proc gtk_gesture_single_get_current_button(gesture: pointer): guint {.importc, nodecl, cdecl.}

proc gtk_im_multicontext_new(): pointer {.importc, nodecl, cdecl.}
proc gtk_im_context_set_client_widget(im, widget: pointer) {.importc, nodecl, cdecl.}
proc gtk_im_context_focus_in(im: pointer) {.importc, nodecl, cdecl.}

proc gdk_event_get_modifier_state(ev: pointer): guint {.importc, nodecl, cdecl.}
proc gdk_keyval_to_lower(k: guint): guint {.importc, nodecl, cdecl.}
proc gdk_cursor_new_from_name(name: cstring; fallback: pointer): pointer {.importc, nodecl, cdecl.}
proc gdk_display_get_default(): pointer {.importc, nodecl, cdecl.}
proc gdk_display_get_clipboard(disp: pointer): pointer {.importc, nodecl, cdecl.}
proc gdk_clipboard_set_text(clip: pointer; text: cstring) {.importc, nodecl, cdecl.}

proc gdk_clipboard_read_text_async(
  clip: pointer; cancellable: pointer;
  callback: proc (sourceObj: ptr GObject; res: ptr GAsyncResult; data: pointer) {.cdecl.};
  data: pointer
) {.importc, nodecl, cdecl.}

proc gdk_clipboard_read_text_finish(clip: pointer; res: pointer; err: ptr ptr GError): cstring {.importc, nodecl, cdecl.}

proc cairo_create(surface: pointer): pointer {.importc, nodecl, cdecl.}
proc cairo_destroy(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_surface_destroy(surf: pointer) {.importc, nodecl, cdecl.}
proc cairo_surface_flush(surf: pointer) {.importc, nodecl, cdecl.}
proc cairo_image_surface_create(fmt, w, h: gint): pointer {.importc, nodecl, cdecl.}
proc cairo_save(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_restore(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_reset_clip(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_rectangle(cr: pointer; x, y, w, h: gdouble) {.importc, nodecl, cdecl.}
proc cairo_clip(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_set_source_rgba(cr: pointer; r, g, b, a: gdouble) {.importc, nodecl, cdecl.}
proc cairo_set_source_surface(cr, surf: pointer; x, y: gdouble) {.importc, nodecl, cdecl.}
proc cairo_paint(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_fill(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_stroke(cr: pointer) {.importc, nodecl, cdecl.}
proc cairo_move_to(cr: pointer; x, y: gdouble) {.importc, nodecl, cdecl.}
proc cairo_line_to(cr: pointer; x, y: gdouble) {.importc, nodecl, cdecl.}
proc cairo_set_line_width(cr: pointer; w: gdouble) {.importc, nodecl, cdecl.}
proc cairo_scale(cr: pointer; sx, sy: gdouble) {.importc, nodecl, cdecl.}

proc pango_cairo_create_layout(cr: pointer): pointer {.importc, nodecl, cdecl.}
proc pango_cairo_update_layout(cr, layout: pointer) {.importc, nodecl, cdecl.}
proc pango_cairo_show_layout(cr, layout: pointer) {.importc, nodecl, cdecl.}
proc g_object_unref_layout(o: pointer) {.importc: "g_object_unref", nodecl, cdecl.}

proc pango_layout_set_text(layout: pointer; text: cstring; len: gint) {.importc, nodecl, cdecl.}
proc pango_layout_set_font_description(layout, desc: pointer) {.importc, nodecl, cdecl.}
proc pango_layout_get_pixel_size(layout: pointer; w, h: ptr gint) {.importc, nodecl, cdecl.}

proc pango_font_description_free(desc: pointer) {.importc, nodecl, cdecl.}
proc pango_font_description_set_absolute_size(desc: pointer; size: gint) {.importc, nodecl, cdecl.}

proc pango_fc_font_description_from_pattern(pat: pointer; includeSize: gboolean): pointer {.importc, nodecl, cdecl.}

proc pango_font_metrics_unref(m: pointer) {.importc, nodecl, cdecl.}
proc pango_layout_get_context(layout: pointer): pointer {.importc, nodecl, cdecl.}
proc pango_context_get_font_map(ctx: pointer): pointer {.importc, nodecl, cdecl.}
proc pango_font_map_load_font(map, ctx, desc: pointer): pointer {.importc, nodecl, cdecl.}
proc pango_font_get_metrics(font, lang: pointer): pointer {.importc, nodecl, cdecl.}
proc pango_font_metrics_get_ascent(m: pointer): gint {.importc, nodecl, cdecl.}
proc pango_font_metrics_get_descent(m: pointer): gint {.importc, nodecl, cdecl.}
proc pango_font_metrics_get_height(m: pointer): gint {.importc, nodecl, cdecl.}

proc FcInit(): gboolean {.importc, nodecl, cdecl.}
proc FcPatternCreate(): pointer {.importc, nodecl, cdecl.}
proc FcPatternDestroy(p: pointer) {.importc, nodecl, cdecl.}
proc FcPatternAddString(p: pointer; obj: cstring; s: cstring): gboolean {.importc, nodecl, cdecl.}
proc FcConfigSubstitute(cfg, p: pointer; kind: gint): gboolean {.importc, nodecl, cdecl.}
proc FcDefaultSubstitute(p: pointer) {.importc, nodecl, cdecl.}
proc nimedit_fc_font_match(p, resultOut: pointer): pointer {.importc: "nimedit_fc_font_match", nodecl, cdecl.}

# --- Font slots ---

type
  FontSlot = object
    desc: pointer ## PangoFontDescription*
    metrics: FontMetrics

var fonts: seq[FontSlot]

proc getDesc(f: Font): pointer =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].desc
  else: nil

# --- GTK state ---

var
  win: pointer
  drawingArea: pointer
  backingSurf: pointer
  backingCr: pointer
  backingW, backingH: int
  imContext: pointer
  eventQueue: seq[Event]
  modState: set[Modifier]
  clipboardBuf: string
  clipboardLoop: pointer ## GMainLoop* — set during sync read

proc pushEvent(e: Event) =
  eventQueue.add e

proc gdkModsToSet(st: guint): set[Modifier] =
  if (st and (1'u32 shl 0)) != 0: result.incl modShift
  if (st and (1'u32 shl 2)) != 0: result.incl modCtrl
  if (st and (1'u32 shl 3)) != 0: result.incl modAlt
  if (st and (1'u32 shl 26)) != 0: result.incl modGui
  if (st and (1'u32 shl 28)) != 0: result.incl modGui

proc syncModsFromController(ctrl: pointer) =
  let ev = gtk_event_controller_get_current_event(ctrl)
  if ev != nil:
    modState = gdkModsToSet(gdk_event_get_modifier_state(ev))

proc translateKeyval(kv: guint): KeyCode =
  let k = gdk_keyval_to_lower(kv)
  template ck(c: char, key: KeyCode): untyped =
    if k == cast[guint](ord(c)): return key
  ck('a', keyA); ck('b', keyB); ck('c', keyC); ck('d', keyD); ck('e', keyE)
  ck('f', keyF); ck('g', keyG); ck('h', keyH); ck('i', keyI); ck('j', keyJ)
  ck('k', keyK); ck('l', keyL); ck('m', keyM); ck('n', keyN); ck('o', keyO)
  ck('p', keyP); ck('q', keyQ); ck('r', keyR); ck('s', keyS); ck('t', keyT)
  ck('u', keyU); ck('v', keyV); ck('w', keyW); ck('x', keyX); ck('y', keyY)
  ck('z', keyZ)
  ck('0', key0); ck('1', key1); ck('2', key2); ck('3', key3); ck('4', key4)
  ck('5', key5); ck('6', key6); ck('7', key7); ck('8', key8); ck('9', key9)
  case k
  of 0xff1b: keyEsc
  of 0xff09: keyTab
  of 0xff0d: keyEnter
  of 0x020: keySpace
  of 0xff08: keyBackspace
  of 0xffff: keyDelete
  of 0xff63: keyInsert
  of 0xff51: keyLeft
  of 0xff53: keyRight
  of 0xff52: keyUp
  of 0xff54: keyDown
  of 0xff55: keyPageUp
  of 0xff56: keyPageDown
  of 0xff50: keyHome
  of 0xff57: keyEnd
  of 0xffe5: keyCapslock
  of 0x02c: keyComma
  of 0x02e: keyPeriod
  of 0xffbe: keyF1
  of 0xffbf: keyF2
  of 0xffc0: keyF3
  of 0xffc1: keyF4
  of 0xffc2: keyF5
  of 0xffc3: keyF6
  of 0xffc4: keyF7
  of 0xffc5: keyF8
  of 0xffc6: keyF9
  of 0xffc7: keyF10
  of 0xffc8: keyF11
  of 0xffc9: keyF12
  else: keyNone

proc enqueueTextFromUtf8(s: string) =
  for ch in s.toRunes:
    var ev = Event(kind: evTextInput)
    let u = toUtf8(ch)
    for i in 0 ..< min(4, u.len):
      ev.text[i] = u[i]
    for i in u.len .. 3:
      ev.text[i] = '\0'
    pushEvent ev

proc recreateBacking(w, h: int) =
  ## GTK can emit resize with a transient 0 width or height; do not destroy a good buffer then bail.
  if w <= 0 or h <= 0:
    return
  if backingCr != nil:
    cairo_destroy(backingCr)
    backingCr = nil
  if backingSurf != nil:
    cairo_surface_destroy(backingSurf)
    backingSurf = nil
  backingW = w
  backingH = h
  backingSurf = cairo_image_surface_create(gint(CAIRO_FORMAT_ARGB32), gint(w), gint(h))
  backingCr = cairo_create(backingSurf)
  cairo_set_source_rgba(backingCr, 1, 1, 1, 1)
  cairo_rectangle(backingCr, 0, 0, gdouble(w), gdouble(h))
  cairo_fill(backingCr)
  cairo_surface_flush(backingSurf)

proc ensureBackingCr() =
  if backingCr == nil and win != nil and drawingArea != nil:
    let w = gtk_widget_get_width(drawingArea).int
    let h = gtk_widget_get_height(drawingArea).int
    if w > 0 and h > 0:
      recreateBacking(w, h)

# --- Signal callbacks (cdecl) ---

proc onCloseRequest(self: pointer; data: pointer): gboolean {.cdecl.} =
  pushEvent(Event(kind: evWindowClose))
  G_TRUE

proc onResize(area: pointer; width, height: gint; data: pointer) {.cdecl.} =
  recreateBacking(width.int, height.int)
  pushEvent(Event(kind: evWindowResize, x: width.int, y: height.int))

proc onDraw(area: ptr GtkDrawingArea; cr: ptr cairo_t; width, height: gint;
    data: pointer) {.cdecl.} =
  ## Blit only. Never call recreateBacking here: it clears the image surface and
  ## drops NimEdit's pixels when the main loop skips redraws (events.len==0 &&
  ## doRedraw==false). Resize/`createWindow`/GtkDrawingArea::resize already size
  ## the backing; if GTK reports a transient mismatch, scale the blit.
  let w = width.int
  let h = height.int
  if w <= 0 or h <= 0 or backingSurf == nil:
    return
  cairo_surface_flush(backingSurf)
  let crp = cast[pointer](cr)
  cairo_save(crp)
  if backingW != w or backingH != h:
    cairo_scale(crp, gdouble(w) / gdouble(max(1, backingW)),
      gdouble(h) / gdouble(max(1, backingH)))
  cairo_set_source_surface(crp, backingSurf, 0, 0)
  cairo_paint(crp)
  cairo_restore(crp)

proc onKeyPressed(ctrl: pointer; keyval, keycode: guint; state: guint;
    data: pointer): gboolean {.cdecl.} =
  modState = gdkModsToSet(state)
  var ev = Event(kind: evKeyDown, key: translateKeyval(keyval), mods: modState)
  pushEvent ev
  G_FALSE

proc onKeyReleased(ctrl: pointer; keyval, keycode: guint; state: guint;
    data: pointer): gboolean {.cdecl.} =
  modState = gdkModsToSet(state)
  var ev = Event(kind: evKeyUp, key: translateKeyval(keyval), mods: modState)
  pushEvent ev
  G_FALSE

proc onImCommit(ctx: pointer; str: cstring; data: pointer) {.cdecl.} =
  if str != nil:
    enqueueTextFromUtf8($str)

proc onMotion(ctrl: pointer; x, y: gdouble; data: pointer) {.cdecl.} =
  syncModsFromController(ctrl)
  var ev = Event(kind: evMouseMove, x: int(x), y: int(y), mods: modState)
  pushEvent ev

proc onScroll(ctrl: pointer; dx, dy: gdouble; data: pointer): gboolean {.cdecl.} =
  syncModsFromController(ctrl)
  pushEvent(Event(kind: evMouseWheel, x: int(-dx), y: int(-dy), mods: modState))
  G_TRUE

proc onFocusEnter(ctrl: pointer; data: pointer) {.cdecl.} =
  pushEvent(Event(kind: evWindowFocusGained))

proc onFocusLeave(ctrl: pointer; data: pointer) {.cdecl.} =
  pushEvent(Event(kind: evWindowFocusLost))

proc onClickPressed(gesture: pointer; nPress: gint; x, y: gdouble; data: pointer) {.cdecl.} =
  let btn = gtk_gesture_single_get_current_button(gesture)
  var b = mbLeft
  if btn == GDK_BUTTON_SECONDARY: b = mbRight
  elif btn == GDK_BUTTON_MIDDLE: b = mbMiddle
  var ev = Event(kind: evMouseDown, x: int(x), y: int(y), button: b,
                 clicks: nPress.int)
  pushEvent ev

proc onClickReleased(gesture: pointer; nPress: gint; x, y: gdouble; data: pointer) {.cdecl.} =
  let btn = gtk_gesture_single_get_current_button(gesture)
  var b = mbLeft
  if btn == GDK_BUTTON_SECONDARY: b = mbRight
  elif btn == GDK_BUTTON_MIDDLE: b = mbMiddle
  pushEvent(Event(kind: evMouseUp, x: int(x), y: int(y), button: b))

proc g_main_loop_new(ctx: pointer, isRunning: gboolean): pointer {.importc, nodecl, cdecl.}
proc g_main_loop_run(loop: pointer) {.importc, nodecl, cdecl.}
proc g_main_loop_quit(loop: pointer) {.importc, nodecl, cdecl.}
proc g_main_loop_unref(loop: pointer) {.importc, nodecl, cdecl.}

proc clipboardReadCb(sourceObj: ptr GObject; res: ptr GAsyncResult; user: pointer) {.cdecl.} =
  var err: ptr GError
  let clip = cast[pointer](sourceObj)
  let tres = cast[pointer](res)
  let t = gdk_clipboard_read_text_finish(clip, tres, addr err)
  clipboardBuf = if t != nil: $t else: ""
  if t != nil:
    g_free(cast[pointer](t))
  if err != nil:
    g_error_free(err)
  if clipboardLoop != nil:
    g_main_loop_quit(clipboardLoop)

proc readClipboardSync(): string =
  let disp = gdk_display_get_default()
  if disp == nil: return ""
  let clip = gdk_display_get_clipboard(disp)
  if clip == nil: return ""
  clipboardBuf = ""
  let loop = g_main_loop_new(nil, G_FALSE)
  clipboardLoop = loop
  gdk_clipboard_read_text_async(clip, nil, clipboardReadCb, nil)
  g_main_loop_run(loop)
  g_main_loop_unref(loop)
  clipboardLoop = nil
  result = clipboardBuf

# --- Screen hooks ---

proc gtkCreateWindow(layout: var ScreenLayout) =
  if win != nil:
    let da = cast[ptr GtkDrawingArea](drawingArea)
    layout.width = max(1, gtk_drawing_area_get_content_width(da).int)
    layout.height = max(1, gtk_drawing_area_get_content_height(da).int)
    return
  if gtk_init_check() == G_FALSE:
    quit("GTK4 init failed")
  win = gtk_window_new()
  gtk_window_set_title(win, "NimEdit")
  gtk_window_set_default_size(win, gint(layout.width), gint(layout.height))
  drawingArea = gtk_drawing_area_new()
  gtk_window_set_child(win, drawingArea)
  let da = cast[ptr GtkDrawingArea](drawingArea)
  ## GtkDrawingArea content size defaults to 0; draw/blit is a no-op until set.
  gtk_drawing_area_set_content_width(da, gint(layout.width))
  gtk_drawing_area_set_content_height(da, gint(layout.height))
  gtk_widget_set_hexpand(drawingArea, G_TRUE)
  gtk_widget_set_vexpand(drawingArea, G_TRUE)
  gtk_drawing_area_set_draw_func(drawingArea, onDraw, nil, nil)
  discard g_signal_connect_data(drawingArea, "resize",
    cast[GCallback](onResize), nil, nil, 0)
  discard g_signal_connect_data(win, "close-request",
    cast[GCallback](onCloseRequest), nil, nil, 0)
  let keyc = gtk_event_controller_key_new()
  gtk_widget_add_controller(drawingArea, keyc)
  discard g_signal_connect_data(keyc, "key-pressed",
    cast[GCallback](onKeyPressed), nil, nil, 0)
  discard g_signal_connect_data(keyc, "key-released",
    cast[GCallback](onKeyReleased), nil, nil, 0)
  imContext = gtk_im_multicontext_new()
  gtk_im_context_set_client_widget(imContext, drawingArea)
  gtk_event_controller_key_set_im_context(keyc, imContext)
  discard g_signal_connect_data(imContext, "commit",
    cast[GCallback](onImCommit), nil, nil, 0)
  let motion = gtk_event_controller_motion_new()
  gtk_widget_add_controller(drawingArea, motion)
  discard g_signal_connect_data(motion, "motion",
    cast[GCallback](onMotion), nil, nil, 0)
  let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
  gtk_widget_add_controller(drawingArea, scroll)
  discard g_signal_connect_data(scroll, "scroll",
    cast[GCallback](onScroll), nil, nil, 0)
  let focusc = gtk_event_controller_focus_new()
  gtk_widget_add_controller(drawingArea, focusc)
  discard g_signal_connect_data(focusc, "enter",
    cast[GCallback](onFocusEnter), nil, nil, 0)
  discard g_signal_connect_data(focusc, "leave",
    cast[GCallback](onFocusLeave), nil, nil, 0)
  let click = gtk_gesture_click_new()
  gtk_gesture_single_set_button(click, 0)
  gtk_widget_add_controller(drawingArea, click)
  discard g_signal_connect_data(click, "pressed",
    cast[GCallback](onClickPressed), nil, nil, 0)
  discard g_signal_connect_data(click, "released",
    cast[GCallback](onClickReleased), nil, nil, 0)
  gtk_window_present(win)
  var guard = 0
  while gtk_drawing_area_get_content_width(da) <= 0 and guard < 5000:
    discard g_main_context_iteration(nil, G_FALSE)
    inc guard
  layout.width = max(1, gtk_drawing_area_get_content_width(da).int)
  layout.height = max(1, gtk_drawing_area_get_content_height(da).int)
  layout.scaleX = 1
  layout.scaleY = 1
  recreateBacking(layout.width, layout.height)
  gtk_widget_set_focusable(drawingArea, G_TRUE)
  gtk_widget_grab_focus(drawingArea)
  gtk_im_context_focus_in(imContext)

proc gtkRefresh() =
  if backingSurf != nil:
    cairo_surface_flush(backingSurf)
  if drawingArea != nil:
    gtk_widget_queue_draw(drawingArea)

proc gtkSaveState() = discard
proc gtkRestoreState() = discard

proc gtkSetClipRect(r: basetypes.Rect) =
  ensureBackingCr()
  if backingCr == nil: return
  cairo_reset_clip(backingCr)
  cairo_rectangle(backingCr, gdouble(r.x), gdouble(r.y), gdouble(r.w), gdouble(r.h))
  cairo_clip(backingCr)

proc gtkOpenFont(path: string; size: int; metrics: var FontMetrics): Font =
  discard FcInit()
  var pat = FcPatternCreate()
  if pat == nil:
    return Font(0)
  if FcPatternAddString(pat, FC_FILE, cstring(path)) == G_FALSE:
    FcPatternDestroy(pat)
    return Font(0)
  discard FcConfigSubstitute(nil, pat, FcMatchPattern)
  FcDefaultSubstitute(pat)
  var fcRes: cint
  let matched = nimedit_fc_font_match(pat, addr fcRes)
  FcPatternDestroy(pat)
  if matched == nil:
    return Font(0)
  let desc = pango_fc_font_description_from_pattern(matched, G_TRUE)
  FcPatternDestroy(matched)
  if desc == nil:
    return Font(0)
  pango_font_description_set_absolute_size(desc, gint(size * PANGO_SCALE))
  let surf = cairo_image_surface_create(0, 8, 8)
  let cr = cairo_create(surf)
  let layout = pango_cairo_create_layout(cr)
  pango_layout_set_font_description(layout, desc)
  pango_layout_set_text(layout, "Mg", -1)
  let pctx = pango_layout_get_context(layout)
  let fmap = pango_context_get_font_map(pctx)
  let font = pango_font_map_load_font(fmap, pctx, desc)
  if font != nil:
    let m = pango_font_get_metrics(font, nil)
    if m != nil:
      metrics.ascent = pango_font_metrics_get_ascent(m) div PANGO_SCALE
      metrics.descent = pango_font_metrics_get_descent(m) div PANGO_SCALE
      metrics.lineHeight = pango_font_metrics_get_height(m) div PANGO_SCALE
      pango_font_metrics_unref(m)
    g_object_unref(font)
  if metrics.lineHeight <= 0:
    var tw, th: gint
    pango_layout_get_pixel_size(layout, addr tw, addr th)
    metrics.lineHeight = th.int
    metrics.ascent = int(th.float64 * 0.75)
    metrics.descent = th.int - metrics.ascent
  g_object_unref_layout(layout)
  cairo_destroy(cr)
  cairo_surface_destroy(surf)
  fonts.add FontSlot(desc: desc, metrics: metrics)
  result = Font(fonts.len)

proc gtkCloseFont(f: Font) =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len and fonts[idx].desc != nil:
    pango_font_description_free(fonts[idx].desc)
    fonts[idx].desc = nil

proc gtkMeasureText(f: Font; text: string): TextExtent =
  ensureBackingCr()
  let desc = getDesc(f)
  if desc == nil or text.len == 0:
    return TextExtent()
  let cr = backingCr
  if cr == nil:
    return TextExtent()
  let layout = pango_cairo_create_layout(cr)
  pango_layout_set_font_description(layout, desc)
  pango_layout_set_text(layout, cstring(text), -1)
  var w, h: gint
  pango_layout_get_pixel_size(layout, addr w, addr h)
  g_object_unref_layout(layout)
  result = TextExtent(w: w.int, h: h.int)

proc gtkDrawText(f: Font; x, y: int; text: string; fg, bg: screen.Color): TextExtent =
  ensureBackingCr()
  let desc = getDesc(f)
  if desc == nil or text.len == 0 or backingCr == nil:
    return
  let ext = gtkMeasureText(f, text)
  cairo_save(backingCr)
  cairo_set_source_rgba(backingCr,
    gdouble(bg.r) / 255.0, gdouble(bg.g) / 255.0, gdouble(bg.b) / 255.0,
    gdouble(bg.a) / 255.0)
  cairo_rectangle(backingCr, gdouble(x), gdouble(y), gdouble(ext.w), gdouble(ext.h))
  cairo_fill(backingCr)
  let layout = pango_cairo_create_layout(backingCr)
  pango_layout_set_font_description(layout, desc)
  pango_layout_set_text(layout, cstring(text), -1)
  cairo_set_source_rgba(backingCr,
    gdouble(fg.r) / 255.0, gdouble(fg.g) / 255.0, gdouble(fg.b) / 255.0,
    gdouble(fg.a) / 255.0)
  pango_cairo_update_layout(backingCr, layout)
  cairo_move_to(backingCr, gdouble(x), gdouble(y))
  pango_cairo_show_layout(backingCr, layout)
  g_object_unref_layout(layout)
  cairo_restore(backingCr)
  result = ext

proc gtkGetFontMetrics(f: Font): FontMetrics =
  let idx = f.int - 1
  if idx >= 0 and idx < fonts.len: fonts[idx].metrics
  else: FontMetrics()

proc gtkFillRect(r: basetypes.Rect; color: screen.Color) =
  ensureBackingCr()
  if backingCr == nil: return
  cairo_save(backingCr)
  cairo_set_source_rgba(backingCr,
    gdouble(color.r) / 255.0, gdouble(color.g) / 255.0, gdouble(color.b) / 255.0,
    gdouble(color.a) / 255.0)
  cairo_rectangle(backingCr, gdouble(r.x), gdouble(r.y), gdouble(r.w), gdouble(r.h))
  cairo_fill(backingCr)
  cairo_restore(backingCr)

proc gtkDrawLine(x1, y1, x2, y2: int; color: screen.Color) =
  ensureBackingCr()
  if backingCr == nil: return
  cairo_save(backingCr)
  cairo_set_source_rgba(backingCr,
    gdouble(color.r) / 255.0, gdouble(color.g) / 255.0, gdouble(color.b) / 255.0,
    gdouble(color.a) / 255.0)
  cairo_set_line_width(backingCr, 1)
  cairo_move_to(backingCr, gdouble(x1), gdouble(y1))
  cairo_line_to(backingCr, gdouble(x2), gdouble(y2))
  cairo_stroke(backingCr)
  cairo_restore(backingCr)

proc gtkDrawPoint(x, y: int; color: screen.Color) =
  gtkFillRect(rect(x, y, 1, 1), color)

proc gtkSetCursor(c: CursorKind) =
  if drawingArea == nil: return
  let name = case c
    of curDefault, curArrow: "default"
    of curIbeam: "text"
    of curWait: "wait"
    of curCrosshair: "crosshair"
    of curHand: "pointer"
    of curSizeNS: "ns-resize"
    of curSizeWE: "ew-resize"
  let cur = gdk_cursor_new_from_name(cstring(name), nil)
  if cur != nil:
    gtk_widget_set_cursor(drawingArea, cur)
    g_object_unref(cur)

proc gtkSetWindowTitle(title: string) =
  if win != nil:
    gtk_window_set_title(win, cstring(title))

# --- Input hooks ---

proc pumpGtk() =
  while g_main_context_iteration(nil, G_FALSE) != G_FALSE:
    discard

proc gtkPollEvent(e: var Event): bool =
  pumpGtk()
  if eventQueue.len > 0:
    e = eventQueue[0]
    eventQueue.delete(0)
    return true
  false

proc gtkWaitEvent(e: var Event; timeoutMs: int): bool =
  if gtkPollEvent(e):
    return true
  if timeoutMs < 0:
    while true:
      discard g_main_context_iteration(nil, G_TRUE)
      if gtkPollEvent(e):
        return true
  elif timeoutMs == 0:
    return false
  else:
    let t0 = g_get_monotonic_time() div 1000
    while g_get_monotonic_time() div 1000 - t0 < timeoutMs:
      discard g_main_context_iteration(nil, G_FALSE)
      if gtkPollEvent(e):
        return true
      g_usleep(5000)
    return gtkPollEvent(e)

proc gtkGetClipboardText(): string =
  readClipboardSync()

proc gtkPutClipboardText(text: string) =
  let disp = gdk_display_get_default()
  if disp == nil: return
  let clip = gdk_display_get_clipboard(disp)
  if clip != nil:
    gdk_clipboard_set_text(clip, cstring(text))

proc gtkGetTicks(): int =
  int(g_get_monotonic_time() div 1000)

proc gtkDelay(ms: int) =
  g_usleep(culong(ms) * 1000)

proc gtkStartTextInput() =
  if drawingArea != nil:
    gtk_widget_grab_focus(drawingArea)
    if imContext != nil:
      gtk_im_context_focus_in(imContext)

proc gtkQuitRequest() =
  if win != nil:
    gtk_window_destroy(win)
    win = nil
    drawingArea = nil
  if backingCr != nil:
    cairo_destroy(backingCr)
    backingCr = nil
  if backingSurf != nil:
    cairo_surface_destroy(backingSurf)
    backingSurf = nil
  if imContext != nil:
    g_object_unref(imContext)
    imContext = nil

proc initGtk4Driver*() =
  windowRelays = WindowRelays(
    createWindow: gtkCreateWindow, refresh: gtkRefresh,
    saveState: gtkSaveState, restoreState: gtkRestoreState,
    setClipRect: gtkSetClipRect, setCursor: gtkSetCursor,
    setWindowTitle: gtkSetWindowTitle)
  fontRelays = FontRelays(
    openFont: gtkOpenFont, closeFont: gtkCloseFont,
    getFontMetrics: gtkGetFontMetrics, measureText: gtkMeasureText,
    drawText: gtkDrawText)
  drawRelays = DrawRelays(
    fillRect: gtkFillRect, drawLine: gtkDrawLine, drawPoint: gtkDrawPoint)
  inputRelays = InputRelays(
    pollEvent: gtkPollEvent, waitEvent: gtkWaitEvent,
    getTicks: gtkGetTicks, delay: gtkDelay,
    startTextInput: gtkStartTextInput, quitRequest: gtkQuitRequest)
  clipboardRelays = ClipboardRelays(
    getText: gtkGetClipboardText, putText: gtkPutClipboardText)
