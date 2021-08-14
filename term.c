#include "ruby.h"
#include "extconf.h"
#include <locale.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>

#define FONT_STRING "-*-*-*-*-*-*-12-*-*-*-*-*-iso10646-*"
#define CHAR_W   6
#define CHAR_H   12
#define TOPMOST  10
#define LEFTMOST 2

Display *dpy;
Window win;
XFontSet fnt;

void xsetfg(uint32_t fg) { XSetForeground(dpy, DefaultGC(dpy, DefaultScreen(dpy)), fg ); }

VALUE xfillrect(VALUE self, VALUE x, VALUE y, VALUE fg) {
  xsetfg(FIX2LONG(fg));
  XFillRectangle(dpy, win, DefaultGC(dpy, DefaultScreen(dpy)),
    (FIX2INT(x)*CHAR_W)+LEFTMOST, FIX2INT(y)*CHAR_H, CHAR_W, CHAR_H
  );
  return Qnil;
}

VALUE xclear(VALUE self, VALUE x, VALUE y, VALUE w, VALUE h) {
  XClearArea(dpy, win, (FIX2INT(x)*CHAR_W)+LEFTMOST, FIX2INT(y)*CHAR_H, FIX2INT(w), FIX2INT(h), False);
  return Qnil;
}

VALUE xdrawch(VALUE self, VALUE x, VALUE y, VALUE c, VALUE fg, VALUE bg) {
  wchar_t ch = FIX2LONG(c);
  xsetfg(FIX2LONG(fg));
  //XSetBackground(dpy, DefaultGC(dpy, DefaultScreen(dpy)), FIX2LONG(bg) );
  XmbDrawString(
    dpy,win, fnt, DefaultGC(dpy, DefaultScreen(dpy)),
    (FIX2INT(x)*CHAR_W)+LEFTMOST, (FIX2INT(y)*CHAR_H)+TOPMOST,
    (char*)&ch, (ch <= 0xff ? 1 : (ch <= 0xffff ? 2 : (ch <= 0xffffff ? 3 : 4)))
  );
  return Qnil;
}

VALUE term_init(){
  XSetWindowAttributes attrs;
  char **missing_list, *def_string;
  int missing_count;

  setlocale(LC_ALL, "");
  dpy = XOpenDisplay(NULL);
  if(dpy == NULL) exit(1);

  attrs.background_pixel = 0;
  attrs.event_mask = SubstructureNotifyMask | StructureNotifyMask |
      ExposureMask | KeyPressMask | ButtonPressMask;

  win = XCreateWindow(dpy, DefaultRootWindow(dpy),
    0, 0, 400, 400, 0, DefaultDepth(dpy, DefaultScreen(dpy)),
    InputOutput, DefaultVisual(dpy, DefaultScreen(dpy)),
    CWBackPixel|CWEventMask, &attrs
  );

  // Make window transparent
  double alpha = 0.8;
  unsigned long opacity = (unsigned long)(0xFFFFFFFFul * alpha);
  Atom XA_NET_WM_WINDOW_OPACITY = XInternAtom(dpy, "_NET_WM_WINDOW_OPACITY", False);
  XChangeProperty(dpy, win, XA_NET_WM_WINDOW_OPACITY, XA_CARDINAL, 32,
  PropModeReplace, (unsigned char *)&opacity, 1L);

  XMapWindow(dpy, win);
  XFlush(dpy);

  fnt = XCreateFontSet(dpy, FONT_STRING, &missing_list, &missing_count, &def_string);
  if(fnt == NULL) exit(2);
  XFreeStringList(missing_list);
}

void term_key(VALUE self, XKeyEvent key){
  char buf[32];
  int num;
  KeySym ksym;
  num = XLookupString(&key, buf, sizeof(buf), &ksym, 0);
  rb_funcall(self, rb_intern("keyevent"), 2, INT2FIX(ksym), rb_str_new(buf, num));
}

VALUE term_flush() {
  XFlush(dpy);
  return Qnil;
}


VALUE term_event(VALUE self) {
  int w,h;
  XEvent evt;
  XNextEvent(dpy, &evt);
  switch(evt.type){
  case ButtonPress:
    break;
  case KeyPress:
    term_key(self,evt.xkey);
    break;
  case Expose: // FIXME: Doesn't seem to do anything.
    rb_funcall(self, rb_intern("redraw"), 0);
  case ConfigureNotify:
    w  = (evt.xconfigure.width / CHAR_W);
    h = (evt.xconfigure.height / CHAR_H);
    rb_funcall(self, rb_intern("resize"), 2, INT2FIX(w), INT2FIX(h));
    break;
  }
}

VALUE term_process(VALUE self) {
  while(XPending(dpy)){ term_event(self); }
  return Qnil;
}

VALUE term_shutdown(){
  XFreeFontSet(dpy, fnt);
  XUnmapWindow(dpy, win);
  XCloseDisplay(dpy);
  return Qnil;
}

VALUE rb_fd() { return INT2FIX(ConnectionNumber(dpy)); }

void Init_term() {
  //atexit(term_shutdown);
  VALUE mod = rb_define_class("RubyTerm", rb_cObject);
  rb_define_method(mod, "init", term_init, 0);
  rb_define_method(mod, "fd", rb_fd, 0);
  rb_define_method(mod, "xclear", xclear, 4);
  rb_define_method(mod, "xdrawch", xdrawch, 5);
  rb_define_method(mod, "xfillrect", xfillrect, 3);
  rb_define_method(mod, "flush", term_flush, 0);
  rb_define_method(mod, "process", term_process,0);
}
