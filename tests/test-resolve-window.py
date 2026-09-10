#!/usr/bin/python3
"""Exercise saved geometry and manual maximize on a private XWayland desktop."""
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import time


def worker(root):
    import gi
    gi.require_version('Gtk', '3.0')
    gi.require_version('GdkX11', '3.0')
    from gi.repository import Gtk, GdkX11, GLib
    from Xlib import display
    helper = root/'usr/libexec/aquarius-resolve-window'
    module = runpy.run_path(str(helper))
    state = Path(os.environ['XDG_STATE_HOME'])/'aquarius/resolve-window.json'
    module['store'](state, [100, 110, 600, 400])
    assert module['fit']([4000, 0, 1600, 900], [[0,0,1280,720]]) == [16,40,1248,656]
    win = Gtk.Window()
    win.set_wmclass('resolve','resolve')
    win.set_title('DaVinci Resolve Studio - Geometry Test')
    win.set_default_size(700,450)
    win.show_all()
    proc = subprocess.Popen([str(helper)])
    d = display.Display()
    assert not d.has_extension('GLX'), 'geometry test unexpectedly enabled GLX'
    xwin = d.create_resource_object('window', win.get_window().get_xid())
    def pump(seconds):
        until=time.monotonic()+seconds
        while time.monotonic()<until:
            GLib.MainContext.default().iteration(False)
            time.sleep(.01)
    try:
        pump(5)
        g = xwin.get_geometry()
        assert (g.width,g.height)==(600,400), (g.width,g.height)
        pump(2)
        normal=module['saved'](state)
        assert normal[2:]==[600,400], normal
        win.maximize()
        pump(3)
        assert module['saved'](state)==normal, 'maximize overwrote normal geometry'
        props=xwin.get_full_property(d.intern_atom('_NET_WM_STATE'), 0).value
        assert d.intern_atom('_NET_WM_STATE_MAXIMIZED_HORZ') in props, 'watcher undid user maximize'
        subprocess.run([str(helper), '--reset'], check=True, timeout=3)
        pump(3)
        props=xwin.get_full_property(d.intern_atom('_NET_WM_STATE'),0).value
        assert d.intern_atom('_NET_WM_STATE_MAXIMIZED_HORZ') not in props
        pos=d.screen().root.translate_coords(xwin,0,0)
        assert pos.x>=0 and pos.y>=0, (pos.x,pos.y)
        # Change the live headless output while the app stays open. This is
        # the same RandR change the watcher sees on a disconnected monitor.
        win.iconify()
        pump(2)
        props=xwin.get_full_property(d.intern_atom('_NET_WM_STATE'),0).value
        assert d.intern_atom('_NET_WM_STATE_HIDDEN') in props, 'test did not minimize'
        subprocess.run(['wlr-randr', '--output', 'HEADLESS-1', '--custom-mode', '800x600'], check=True, timeout=3)
        pump(2)
        win.deiconify()
        pump(3)
        pos=d.screen().root.translate_coords(xwin,0,0)
        g=xwin.get_geometry()
        assert pos.x>=0 and pos.y>=0 and pos.x+g.width<=800 and pos.y+g.height<=600, (pos.x,pos.y,g.width,g.height)
        print('PASS: real XWayland restore, normal memory, manual maximize, reset, live output shrink')
    finally:
        proc.terminate()
        proc.wait(timeout=3)
        win.destroy()
        d.close()


def main():
    if len(sys.argv)>1 and sys.argv[1]=='--worker':
        worker(Path(sys.argv[2]))
        return
    root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parent.parent/'system_files'
    with tempfile.TemporaryDirectory(prefix='aq-resolve-geometry-') as temp:
        work=Path(temp)
        (work/'run').mkdir(mode=0o700)
        (work/'config').mkdir()
        (work/'config/rc.xml').write_text('<labwc_config/>')
        command=work/'worker.sh'
        # Arguments are fixed filesystem paths, shell quoted independently.
        import shlex
        command.write_text('#!/bin/sh\n'+shlex.join([sys.executable,str(Path(__file__).resolve()),'--worker',str(root)])+'\n')
        command.chmod(0o700)
        # Pixman controls labwc, but Xwayland still tries its own GPU renderer.
        # The NVIDIA image has GPU libraries and no GPU in CI. Use wlroots'
        # WLR_XWAYLAND override only inside this test selects shared-memory
        # rendering. Disable GLX too: even with glamor off its swrast loader
        # enumerates EGL vendors and crashes in NVIDIA's GBM code without a GPU.
        # These geometry checks use no OpenGL; real sessions keep acceleration.
        xwayland = shutil.which('Xwayland')
        if xwayland is None:
            raise RuntimeError('Window test requires Xwayland')
        wrapper = work/'Xwayland-software'
        wrapper.write_text('#!/bin/sh\necho "TEST: software Xwayland" >&2\nexec '
                           + shlex.quote(xwayland) + ' -glamor off -extension GLX "$@"\n')
        wrapper.chmod(0o700)
        env=dict(os.environ,XDG_RUNTIME_DIR=str(work/'run'),XDG_CONFIG_HOME=str(work/'config'),XDG_STATE_HOME=str(work/'state'),WLR_BACKENDS='headless',WLR_HEADLESS_OUTPUTS='1',WLR_RENDERER='pixman',WLR_XWAYLAND=str(wrapper),GDK_BACKEND='x11',GTK_A11Y='none')
        env.pop('DISPLAY',None)
        env.pop('WAYLAND_DISPLAY',None)
        with (work/'log').open('w+') as log:
            wm=subprocess.Popen(['labwc','-C',str(work/'config'),'-s',str(command)],env=env,stdout=log,stderr=log)
            try:
                until=time.monotonic()+30
                while time.monotonic()<until:
                    time.sleep(.5)
                    log.flush();log.seek(0);text=log.read()
                    if 'PASS: real XWayland' in text:
                        assert 'TEST: software Xwayland' in text, 'labwc did not use the test Xwayland wrapper'
                        print(text[text.index('PASS: real XWayland'):].splitlines()[0]);return
                    if 'Traceback' in text: raise RuntimeError(text)
                raise RuntimeError('Window test timed out:\n'+text)
            finally:
                wm.terminate();wm.wait(timeout=5)

if __name__=='__main__':
    main()
