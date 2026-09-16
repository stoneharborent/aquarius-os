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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aquarius_headless as headless  # noqa: E402


def shrink_screen(d, width, height):
    """Tell X the screen is now smaller, the way unplugging a monitor does.

    ⚠️ 2026-09-15 — this used to be `wlr-randr --output HEADLESS-1
    --custom-mode 800x600`. wlr-randr speaks a wlroots-only protocol: it worked
    on labwc, and on KWin it answers "compositor doesn't support
    wlr-output-management-unstable-v1" and changes nothing. KWin has no
    stand-in either — kscreen-doctor hangs against a bare headless kwin, and
    Xwayland's own RandR mode-setting only fakes a resolution for the one
    program that asked for it.

    So we do it in X itself, where the watcher is looking. X lets any program
    define the monitor list with RandR's SetMonitor; every other program then
    reads our definition back from GetMonitors. GetMonitors is EXACTLY the call
    /usr/libexec/aquarius-resolve-window makes to find out how big the screen
    is, so from the watcher's side this is indistinguishable from a monitor
    being unplugged and a smaller one taking its place — and it works the same
    on every compositor, which wlr-randr never did.

    (python-xlib 0.33's own randr.set_monitor() is broken — it packs the
    request through rq.Object, which returns two values where the packer wants
    three. So the request is spelled out field by field here instead; this is
    the same wire format, just written flat.)
    """
    from Xlib.ext import randr
    from Xlib.protocol import rq

    class SetMonitor(rq.Request):
        _request = rq.Struct(
            rq.Card8('opcode'), rq.Opcode(43), rq.RequestLength(),
            rq.Window('window'),
            rq.Card32('name'), rq.Bool('primary'), rq.Bool('automatic'),
            rq.LengthOf('outputs', 2),
            rq.Int16('x'), rq.Int16('y'),
            rq.Card16('width_in_pixels'), rq.Card16('height_in_pixels'),
            rq.Card32('width_in_millimeters'), rq.Card32('height_in_millimeters'),
            rq.List('outputs', rq.Card32Obj),
        )

    root = d.screen().root
    # Claiming the real outputs is what makes the automatic monitor go away, so
    # the screen genuinely shrinks instead of a second monitor appearing.
    outputs = list(randr.get_screen_resources(root).outputs)
    SetMonitor(display=d.display, opcode=d.display.get_extension_major('RANDR'),
               window=root, name=d.intern_atom('AQUARIUS-TEST'),
               primary=1, automatic=0, x=0, y=0,
               width_in_pixels=width, height_in_pixels=height,
               width_in_millimeters=int(width*0.265), height_in_millimeters=int(height*0.265),
               outputs=outputs)
    d.sync()
    seen = [[m.x, m.y, m.width_in_pixels, m.height_in_pixels]
            for m in randr.get_monitors(root, True).monitors]
    assert seen == [[0, 0, width, height]], seen


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
        # Shrink the live screen while the app stays open. This is the same
        # change the watcher sees when a monitor is unplugged: the monitor list
        # it reads gets smaller under it.
        win.iconify()
        pump(2)
        props=xwin.get_full_property(d.intern_atom('_NET_WM_STATE'),0).value
        assert d.intern_atom('_NET_WM_STATE_HIDDEN') in props, 'test did not minimize'
        shrink_screen(d, 800, 600)
        pump(2)
        win.deiconify()
        pump(3)
        pos=d.screen().root.translate_coords(xwin,0,0)
        g=xwin.get_geometry()
        assert pos.x>=0 and pos.y>=0 and pos.x+g.width<=800 and pos.y+g.height<=600, (pos.x,pos.y,g.width,g.height)
        print('PASS: real XWayland restore, normal memory, manual maximize, reset, live screen shrink')
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
        # labwc, if it is the compositor that ends up being used on somebody's
        # own machine, wants this file to exist. The others ignore it.
        (work/'config/rc.xml').write_text('<labwc_config/>')
        command=work/'worker.sh'
        # Arguments are fixed filesystem paths, shell quoted independently.
        import shlex
        command.write_text('#!/bin/sh\n'+shlex.join([sys.executable,str(Path(__file__).resolve()),'--worker',str(root)])+'\n')
        command.chmod(0o700)
        # The compositor renders in software, but Xwayland still tries its own
        # GPU renderer. The NVIDIA image has GPU libraries and no GPU in CI, so
        # this test hands the compositor a WRAPPER around Xwayland that selects
        # shared-memory rendering. Disable GLX too: even with glamor off its
        # swrast loader enumerates EGL vendors and crashes in NVIDIA's GBM code
        # without a GPU. These geometry checks use no OpenGL; real sessions keep
        # acceleration. (tests/aquarius_headless.py knows how to make each
        # compositor use it: KWin runs whatever `Xwayland` is first on PATH, so
        # the helper puts ours there. It also makes /tmp/.X11-unix, without
        # which KWin skips X and the worker below gets no DISPLAY.)
        xwayland = shutil.which('Xwayland')
        if xwayland is None:
            raise RuntimeError('Window test requires Xwayland')
        wrapper = work/'Xwayland-software'
        wrapper.write_text('#!/bin/sh\necho "TEST: software Xwayland" >&2\nexec '
                           + shlex.quote(xwayland) + ' -glamor off -extension GLX "$@"\n')
        wrapper.chmod(0o700)
        env=dict(os.environ,XDG_RUNTIME_DIR=str(work/'run'),XDG_CONFIG_HOME=str(work/'config'),XDG_STATE_HOME=str(work/'state'),GDK_BACKEND='x11',GTK_A11Y='none')
        env.pop('DISPLAY',None)
        env.pop('WAYLAND_DISPLAY',None)
        with (work/'log').open('w+') as log:
            compositor=headless.start(work/'run',work/'config',log,env,
                                      xwayland_wrapper=wrapper,run_after=command)
            print('Invisible desktop: %s'%compositor.name)
            try:
                until=time.monotonic()+30
                while time.monotonic()<until:
                    time.sleep(.5)
                    log.flush();log.seek(0);text=log.read()
                    if 'PASS: real XWayland' in text:
                        assert 'TEST: software Xwayland' in text, compositor.name+' did not use the test Xwayland wrapper'
                        print(text[text.index('PASS: real XWayland'):].splitlines()[0]);return
                    if 'Traceback' in text: raise RuntimeError(text)
                raise RuntimeError('Window test timed out:\n'+text)
            finally:
                compositor.stop()

if __name__=='__main__':
    main()
