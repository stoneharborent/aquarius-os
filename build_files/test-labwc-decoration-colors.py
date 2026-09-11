#!/usr/bin/python3
"""Check real window-frame pixels on a private, software-rendered desktop."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

PALETTE = '#313233 #414243 #515253 #616263 #f1f2f3 #d1d2d3'

def config(palette):
    return f'''<labwc_config><placement><policy>client</policy></placement>
<theme><cornerRadius>12</cornerRadius><font place="ActiveWindow" name="sans" size="12"/><font place="InactiveWindow" name="sans" size="12"/></theme>
<windowRules>
<windowRule identifier="colored" decorationColors="{palette}"/>
<windowRule identifier="reset" decorationColors="{palette}"/>
<windowRule identifier="reset" decorationColors="default"/>
<windowRule identifier="invalid" decorationColors="#bad"/>
</windowRules></labwc_config>'''

def worker(work):
    from Xlib import X, Xatom, display, protocol
    from PIL import Image
    d = display.Display()
    root = d.screen().root
    wins = {}
    for i, name in enumerate(('colored', 'normal', 'reset', 'invalid')):
        w = root.create_window(30 + (i % 2)*350, 90 + (i//2)*280, 280, 190,
                               0, d.screen().root_depth, X.InputOutput,
                               X.CopyFromParent, background_pixel=0x111111)
        w.set_wm_class(name, name)
        w.set_wm_name('Frame Palette Test')
        w.change_property(d.intern_atom('_NET_WM_WINDOW_TYPE'), Xatom.ATOM, 32,
                          [d.intern_atom('_NET_WM_WINDOW_TYPE_NORMAL')])
        w.map()
        wins[name] = w
    d.sync()
    time.sleep(1)
    for i, w in enumerate(wins.values()):
        w.configure(x=30+(i%2)*350, y=90+(i//2)*280)
    d.sync()
    time.sleep(.3)
    def focus(name):
        w = wins[name]
        root.send_event(protocol.event.ClientMessage(window=w,
            client_type=d.intern_atom('_NET_ACTIVE_WINDOW'),
            data=(32,[2,X.CurrentTime,0,0,0])),
            event_mask=X.SubstructureRedirectMask|X.SubstructureNotifyMask)
        d.sync()
        time.sleep(.3)
    def capture():
        subprocess.run(['grim', str(work/'frame.png')], check=True)
        return Image.open(work/'frame.png').convert('RGB')
    def positions(name):
        w=wins[name];g=w.get_geometry();p=root.translate_coords(w,0,0)
        return p.x,p.y,g.width,g.height
    def check(name,bg,border,text=None):
        im=capture();x,y,width,height=positions(name)
        assert im.getpixel((x+width//2,y-6))==bg,(name,'background',im.getpixel((x+width//2,y-6)),bg,(x,y))
        assert im.getpixel((x-2,y+height//2))==border,(name,'border')
        # Rounded corner's lower interior shares its title background, not the global fill.
        assert im.getpixel((x+3,y-6))==bg,(name,'corner')
        if text:
            pixels=list(im.crop((x,y-34,x+width,y)).getdata())
            assert text in pixels,(name,'title text')
    focus('colored')
    check('colored',(49,50,51),(81,82,83),(241,242,243))
    original=positions('colored')
    for action in (1,0):
        root.send_event(protocol.event.ClientMessage(window=wins['colored'],
            client_type=d.intern_atom('_NET_WM_STATE'), data=(32,[action,
                d.intern_atom('_NET_WM_STATE_MAXIMIZED_HORZ'),
                d.intern_atom('_NET_WM_STATE_MAXIMIZED_VERT'),2,0])),
            event_mask=X.SubstructureRedirectMask|X.SubstructureNotifyMask)
        d.sync();time.sleep(.3)
        x,y,width,height=positions('colored')
        assert capture().getpixel((x+width//2,y-6))==(49,50,51), 'maximize palette'
    assert positions('colored')==original, 'maximize changed restored geometry'
    # Fullscreen actually destroys/recreates SSDs. Repeat to exercise ownership.
    for _ in range(6):
        for action in (1,0):
            root.send_event(protocol.event.ClientMessage(window=wins['colored'],
                client_type=d.intern_atom('_NET_WM_STATE'), data=(32,[action,
                    d.intern_atom('_NET_WM_STATE_FULLSCREEN'),0,2,0])),
                event_mask=X.SubstructureRedirectMask|X.SubstructureNotifyMask)
            d.sync();time.sleep(.1)
    assert positions('colored')==original, 'fullscreen changed restored geometry'
    check('colored',(49,50,51),(81,82,83),(241,242,243))
    check('normal',(161,162,163),(177,178,179))
    focus('normal')
    check('colored',(65,66,67),(97,98,99),(209,210,211))
    check('normal',(129,130,131),(145,146,147))
    for name in ('reset','invalid'):
        focus(name)
        check(name,(129,130,131),(145,146,147))
    # Reconfigure destroys/rebuilds the cloned assets. Check both changed colors and fallback.
    (work/'config/rc.xml').write_text(config('#717273 #747576 #777879 #7a7b7c #f1f2f3 #d1d2d3'))
    subprocess.run([os.environ['AQ_LABWC_TEST_BINARY'],'--reconfigure'],check=True)
    time.sleep(.5)
    focus('colored')
    check('colored',(113,114,115),(119,120,121))
    (work/'config/rc.xml').write_text(config('default'))
    subprocess.run([os.environ['AQ_LABWC_TEST_BINARY'],'--reconfigure'],check=True)
    time.sleep(.5)
    check('colored',(129,130,131),(145,146,147))
    for w in wins.values(): w.destroy()
    d.sync();d.close()
    (work/'passed').write_text('PASS: isolated decoration colors, active/inactive, corners, borders, text, defaults, invalid palette, maximize/fullscreen restore, reconfigure')

def main():
    if len(sys.argv)>1 and sys.argv[1]=='--worker':
        worker(Path(sys.argv[2]));return
    binary=str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix='aq-decoration-test-') as tmp:
        work=Path(tmp)
        (work/'run').mkdir(mode=0o700)
        (work/'config').mkdir()
        (work/'config/rc.xml').write_text(config(PALETTE))
        (work/'config/themerc-override').write_text('''border.width: 4
window.active.title.bg.color: #818283
window.inactive.title.bg.color: #a1a2a3
window.active.border.color: #919293
window.inactive.border.color: #b1b2b3
window.titlebar.padding.height: 6
''')
        command=work/'worker.sh'
        command.write_text('#!/bin/sh\n'+shlex.join([sys.executable,str(Path(__file__).resolve()),'--worker',str(work)])+'\n')
        command.chmod(0o700)
        wrapper=work/'xwayland'
        wrapper.write_text('#!/bin/sh\nexec '+shlex.quote(shutil.which('Xwayland'))+' -glamor off -extension GLX "$@"\n')
        wrapper.chmod(0o700)
        env=dict(os.environ,XDG_RUNTIME_DIR=str(work/'run'),XDG_CONFIG_HOME=str(work/'config'),WLR_BACKENDS='headless',WLR_HEADLESS_OUTPUTS='1',WLR_RENDERER='pixman',WLR_XWAYLAND=str(wrapper),AQ_LABWC_TEST_BINARY=binary)
        env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
        with (work/'log').open('w+') as log:
            wm=subprocess.Popen([binary,'-C',str(work/'config'),'-s',str(command)],env=env,stdout=log,stderr=log)
            try:
                until=time.monotonic()+30
                while time.monotonic()<until:
                    time.sleep(.25)
                    if (work/'passed').exists():
                        print((work/'passed').read_text());return
                    log.flush();log.seek(0);text=log.read()
                    if 'Traceback' in text or wm.poll() is not None:
                        raise RuntimeError(text)
                raise RuntimeError('Frame test timed out:\n'+text)
            finally:
                if wm.poll() is None:
                    wm.terminate();wm.wait(timeout=5)
                if wm.returncode != 0:
                    log.flush();log.seek(0)
                    raise RuntimeError('Compositor exited with '+str(wm.returncode)+':\n'+log.read())

if __name__=='__main__':main()
