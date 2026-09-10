#!/usr/bin/python3
"""Manual headless GTK regression probe; see docs/restart/files-crash.md."""
import gi
import gc
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib
Gtk.init()
loop=GLib.MainLoop()
wins=[]
count=0
def cycle():
 global count
 if wins:
  wins.pop().destroy()
  gc.collect()
 count+=1
 if count>20:
  print('PASS: 20 window icon create/destroy cycles',flush=True)
  loop.quit()
  return False
 w=Gtk.Window(title='Disposable GTK icon lifetime probe')
 w.set_icon_name('org.gnome.Nautilus')
 w.set_default_size(200,100)
 w.present()
 wins.append(w)
 return True
GLib.timeout_add(100,cycle)
loop.run()
