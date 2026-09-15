# Resolve menu and frame readability

The main menu uses a 14px font floor and 32px minimum row height. Overall
Resolve scale remains governed by the existing Auto/explicit preference; it is
not increased for menu readability. Editing controls and preview scaling are unchanged; native dropdown colors and
controls are preserved. Fonts already larger than 14px remain
larger.

Resolve 21.1's main menu is a Qt5 QMenuBar. Its custom UI renderer does not
accept a local Qt stylesheet correctly, and it treats the standard Qt
`-stylesheet` launch argument as an application configuration filename. Neither
route is used by this fix.

The small public-Qt5 adapter is compiled separately on Rocky 9. The host stores
it at `/usr/lib64/aquarius/libaquarius-resolve-menu.so`; the container-side
wrapper loads it only into `/opt/resolve/bin/resolve`, after Resolve's normal
runner establishes its library path. It uses no private Qt API or vendor binary
modifications. Its constructor removes only its own preload entry before Resolve
can launch helpers or a browser, preserving unrelated preload entries.

For troubleshooting a future Resolve/Qt compatibility change, add
`readable_menus=off` to `~/.config/aquarius/resolve.conf`, then reopen Resolve.
Remove that line to restore the readable main menu. Missing wrapper/library or
missing Qt5 causes the normal launch path to remain available.

The pinned labwc source receives the documented `decorationColors` window-rule
extension. Resolve normal windows use a charcoal palette for the active/inactive
background, border and title text. Rounded corners follow that palette; all
other windows retain the desktop theme. Existing window-control placement,
geometry and shadows remain unchanged.

## The three round buttons on Resolve's bar

Plainly: the title bar matched Resolve, and then you could not see the close,
minimise and maximise buttons on it. Those buttons are little pictures, and the
desktop draws them in its own ink — which in the light theme is almost black.
Almost black on Resolve's almost-black bar is nothing at all.

So Resolve now gets its own set of the same three buttons, drawn in the same
white Resolve writes its own window title in (`#dedee2`). Nothing else about
them changes: same round discs in the same places, same sizes, the same faded
look on a window you are not working in, and the close button still turns red
only while your pointer is on it.

How it reaches the screen, in one line each:

1. `generate-theme` draws the buttons twice — the ordinary set, and a second set
   in white inside a folder called `buttons-resolve`. It does this for both the
   light (Ice) and dark (Midnight) themes, so flipping the theme cannot lose it.
2. `rc.xml`'s DaVinci Resolve rule says `decorationButtons="buttons-resolve"`.
3. The labwc patch reads that, and gives that one window that one folder of
   buttons. Every other window on the desktop is untouched. The menu stays inside
Resolve: no exported appmenu interface was found in the running application,
and no duplicate or simulated menu is added to the title bar.

## Validation

- Real Resolve 21.1.0.0014 on the bench: final Rocky-built adapter opens the
  existing project; the initial 16px main-menu test rendered in a 32px row. Native menu
  opens normally. Overall automatic 125% scale is retained.
- Qt5 offscreen behavior test: body/button fonts and stylesheets, dropdown font matching,
  larger fonts, late-created menus, action callbacks and child preload cleanup.
  Negative control without the adapter fails the expected sizing assertions.
- Container launch boundary: editor-only loading, disable switch, missing
  dependencies and exact argument preservation.
- Patched labwc compiled at pinned source; upstream tests pass. Real headless
  XWayland pixel tests cover active/inactive palettes, ordinary-window isolation,
  corners, borders, title text, malformed/default rules, maximize/restore,
  fullscreen recreation, reconfiguration, and that a rule's own button set
  reaches its window while every other window keeps the theme's buttons. ASan/UBSan/leak checks passed.
- These gates run in the build stages; the finished-image launch test runs in CI.

The live bench currently uses the temporary menu test launcher. Persistent
packaging and the charcoal frame take effect with the resulting OS update.

The user approved the 14px main menu. Dropdowns and submenus now receive the
same font floor, including dynamic actions. Resolve's native style resets its
painter font after menu layout, so the adapter also intercepts QPainter::setFont
only when the paint device is a QMenu widget. Other widget and image painters
are unchanged. Actual File and Clip dropdown captures verify larger text with
shortcuts, checkmarks and disabled entries retained. The offscreen test simulates
a style resetting text to 10px, checks the 14px result, and preserves larger fonts.

## Cursor consistency

The launcher scales cursor pixels with the actual desktop output scale, using
`aquarius-display-scale --cursor-scale`. Resolve's independent UI zoom is not
included. On the bench this means Adwaita at 24px on a 1x desktop, even though Resolve
uses 125% UI scaling. User cursor-size preferences remain respected.

Cursor lookup prefers personal theme directories, then host local/system icons,
then the runtime container as fallback. The container's older Adwaita cursor
artwork differs from the host's despite having the same theme name. Pixel data,
dimensions and hotspots for arrow, text, hand and crosshair cursors were verified
identical between host loading and container loading through the new host path.
Application-specific editing cursors remain available; no global arrow override
is installed. Launch-scale regression covers app zoom independently of display
scale and explicit cursor size.
