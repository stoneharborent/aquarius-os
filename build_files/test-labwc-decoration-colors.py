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

# The two button sets the test paints. Each button picture is a plain, solid,
# fully opaque square of one of these colours, so "did this window get the other
# button set?" becomes "is this exact colour anywhere in its title bar?" — which
# needs no arithmetic about where a button lands and cannot be fooled by
# anti-aliasing at a disc's edge.
#
# This is the AquariusOS case in miniature: on a real machine the theme's own
# buttons are the desktop's near-black ink, the alternative set is Resolve's own
# near-white #dedee2, and the whole point of the feature is that the second set
# reaches Resolve's window and nothing else. Both colours below are chosen not
# to occur anywhere else on the test desktop.
THEME_NAME = 'AqDecorationTest'
BUTTON_DIR = 'buttons-alt'
ORDINARY_BUTTON = (10, 11, 12)      # dark, like the desktop ink
ALT_BUTTON = (244, 245, 246)        # light, like Resolve's title text
BUTTON_NAMES = ('menu', 'iconify', 'max', 'max_toggled', 'close',
                'iconify_hover', 'max_hover', 'max_toggled_hover', 'close_hover')

def config(palette):
    return f'''<labwc_config><placement><policy>client</policy></placement>
<theme><name>{THEME_NAME}</name><cornerRadius>12</cornerRadius><font place="ActiveWindow" name="sans" size="12"/><font place="InactiveWindow" name="sans" size="12"/></theme>
<windowRules>
<windowRule identifier="colored" decorationColors="{palette}"/>
<windowRule identifier="reset" decorationColors="{palette}"/>
<windowRule identifier="reset" decorationColors="default"/>
<windowRule identifier="invalid" decorationColors="#bad"/>
<windowRule identifier="buttons" decorationColors="{palette}" decorationButtons="{BUTTON_DIR}"/>
<windowRule identifier="badbuttons" decorationColors="{palette}" decorationButtons="../escape"/>
</windowRules></labwc_config>'''


def paint_buttons(theme_root):
    """Write both button sets into a throwaway labwc theme folder.

    The theme's own buttons go in <theme>/labwc/; the alternative set goes in
    <theme>/labwc/<BUTTON_DIR>/, which is exactly the layout generate-theme
    produces on a real machine (buttons-resolve/ beside the ordinary pictures).
    """
    from PIL import Image
    base = theme_root / 'themes' / THEME_NAME / 'labwc'
    for folder, colour in ((base, ORDINARY_BUTTON), (base / BUTTON_DIR, ALT_BUTTON)):
        folder.mkdir(parents=True, exist_ok=True)
        for name in BUTTON_NAMES:
            for state in ('-active.png', '-inactive.png'):
                Image.new('RGBA', (20, 20), colour + (255,)).save(folder / (name + state))

def worker(work):
    from Xlib import X, Xatom, display, protocol
    from PIL import Image
    d = display.Display()
    root = d.screen().root
    wins = {}
    placed = {}
    for i, name in enumerate(('colored', 'normal', 'reset', 'invalid',
                              'buttons', 'badbuttons')):
        placed[name] = (30 + (i % 3)*350, 90 + (i//3)*280, 280, 190)
        w = root.create_window(30 + (i % 3)*350, 90 + (i//3)*280, 280, 190,
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
        w.configure(x=30+(i%3)*350, y=90+(i//3)*280)
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
    def strip(name):
        """The band of pixels immediately above a window's own top-left corner.

        34 is comfortably taller than the title bar; the extra rows are the
        desktop behind it and hold neither button colour.
        """
        im=capture();x,y,width,height=positions(name)
        return list(im.crop((x,y-34,x+width,y)).getdata())
    def strip_colours(name):
        """The few colours actually present in that band, commonest first.

        Named in a failure message so "this window lost its buttons" can be
        told apart from "the test is not looking at a title bar at all".
        """
        seen={}
        for px in strip(name):
            seen[px]=seen.get(px,0)+1
        return sorted(seen.items(),key=lambda kv:-kv[1])[:4]
    def check(name,bg,border,text=None):
        im=capture();x,y,width,height=positions(name)
        assert im.getpixel((x+width//2,y-6))==bg,(name,'background',im.getpixel((x+width//2,y-6)),bg,(x,y))
        assert im.getpixel((x-2,y+height//2))==border,(name,'border')
        # Rounded corner's lower interior shares its title background, not the global fill.
        assert im.getpixel((x+3,y-6))==bg,(name,'corner')
        if text:
            pixels=list(im.crop((x,y-34,x+width,y)).getdata())
            assert text in pixels,(name,'title text')
    # Raise every fixture once, and prove each one landed where it was asked
    # to. A window that has never been focused sits at the bottom of the
    # stack, and until a window has been raised and its geometry confirmed the
    # test cannot tell "this frame is drawn wrong" from "this frame is not
    # where the test is looking".
    for name in wins:
        focus(name)
        assert positions(name)==placed[name],(name,'is not where it was placed',
            positions(name),placed[name])
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
    # --- decorationButtons: the per-rule button set ---------------------------
    # A window the rule names gets the LIGHT buttons; every other window keeps
    # the theme's own DARK ones. Both are checked in both directions, because
    # "the right window changed" and "no other window changed" are two different
    # failures and only the pair of them is the feature.
    def button_pixels(name, colour):
        return strip(name).count(colour)
    # 'badbuttons' is about to be read as a plain, ordinary window, so prove
    # first that it IS one: a full frame, in the desktop's own palette for
    # this rule, exactly where the button counting below will look for it.
    focus('badbuttons')
    # But before reading its FRAME, read its BODY. Every window here is painted
    # a flat 0x111111 by the X server, so the middle of the client area says
    # whether this window is being drawn on screen at all. X reporting a
    # position is not the same as the compositor drawing something there: an
    # X window that the compositor never mapped keeps the position its client
    # asked for, and every geometry check in this file would still pass.
    # Separating the two matters, because "this window has no title bar" and
    # "this window is not on screen" have completely different causes and the
    # frame checks below cannot tell them apart -- both read as bare desktop.
    # The message carries the screen size and the colours actually found above
    # the window, so a failure here needs no second run to interpret.
    def body(name):
        im=capture();x,y,width,height=positions(name)
        return im.getpixel((x+width//2,y+height//2)),im.size
    pixel,size=body('badbuttons')
    assert pixel==(17,17,17),('badbuttons is not on screen at all',
        'body='+str(pixel),'placed='+str(positions('badbuttons')),
        'screen='+str(size),'above='+str(strip_colours('badbuttons')))
    check('badbuttons',(49,50,51),(81,82,83),(241,242,243))
    for name in ('buttons','normal','colored'):
        focus(name)
        light=button_pixels('buttons',ALT_BUTTON)
        dark=button_pixels('buttons',ORDINARY_BUTTON)
        assert light>500,('buttons window is not wearing the light set',name,light)
        assert dark==0,('buttons window still shows theme buttons',name,dark)
        for other in ('normal','colored','badbuttons'):
            # Both counts are read before either is judged, and both are named
            # in either failure message. "no theme buttons" and "wearing the
            # other set" fail the same assert, and only the pair of numbers
            # says which happened.
            other_dark=button_pixels(other,ORDINARY_BUTTON)
            other_light=button_pixels(other,ALT_BUTTON)
            counts=(other,'focused='+name,'dark='+str(other_dark),
                    'light='+str(other_light),'titlebar='+str(positions(other)))
            # Neither colour anywhere is not a button failure at all: it means
            # the band held no buttons of any kind, so say what it did hold.
            assert other_dark or other_light,(
                'nothing drawn here - window hidden or not decorated',
                )+counts+('strip='+str(strip_colours(other)),)
            assert other_dark>500,('lost the theme buttons',)+counts
            assert other_light==0,('leaked the alternative buttons',)+counts
    # A folder name that tries to climb out of the theme is refused outright, so
    # 'badbuttons' above is wearing the theme's own set — already asserted.
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
    (work/'passed').write_text('PASS: isolated decoration colors, active/inactive, corners, borders, text, defaults, invalid palette, maximize/fullscreen restore, reconfigure, per-rule button sets and their isolation')

def main():
    if len(sys.argv)>1 and sys.argv[1]=='--worker':
        worker(Path(sys.argv[2]));return
    binary=str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix='aq-decoration-test-') as tmp:
        work=Path(tmp)
        (work/'run').mkdir(mode=0o700)
        (work/'config').mkdir()
        (work/'data').mkdir()
        paint_buttons(work/'data')
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
        env=dict(os.environ,XDG_RUNTIME_DIR=str(work/'run'),XDG_CONFIG_HOME=str(work/'config'),XDG_DATA_HOME=str(work/'data'),WLR_BACKENDS='headless',WLR_HEADLESS_OUTPUTS='1',WLR_RENDERER='pixman',WLR_XWAYLAND=str(wrapper),AQ_LABWC_TEST_BINARY=binary)
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
