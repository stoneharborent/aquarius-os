# Saved Resolve defaults

These are OS defaults for the Aquarius **Install DaVinci Resolve** app and
`aq resolve install`. Every new account and guided reinstall uses the shipped
launcher; application updates continue to route through it.

| Area | Default behavior |
| --- | --- |
| Main menu | 14px minimum text, 32px minimum row; larger explicit fonts respected |
| Dropdowns and submenus | Matching 14px minimum text, including shortcuts and dynamic items; native colors and controls |
| Cursor | Desktop theme, desktop cursor size and display scale; host artwork takes precedence over container artwork |
| Overall UI | Automatic display-aware scaling, including 125% on the tested unscaled 4K setup; independent of cursor and menu fixes |
| Window | Resizable main window with Aquarius controls and reachable geometry; each account remembers its own normal window position |
| Frame | Charcoal active/inactive Resolve palette; window-control placement follows the OS preference |
| Browser handoff | Repair Resolve's browser opener on launch and forward web links to the host browser |
| Installer completion | Installed Resolve logo and launch action |
| App shortcuts | Repaired desktop metadata and host launcher routing, including after updates; file arguments preserved |
| Settings | Display Settings app provides scale choices and window reset; explicit user overrides remain respected |

Implementation lives in the OS's `/usr/libexec/aquarius-resolve-*` helpers,
`/usr/lib64/aquarius/libaquarius-resolve-menu.so`, the display-scale helper and
labwc configuration. The menu adapter is built against Rocky9 Qt5; the frame
palette extension is included in the pinned labwc build. Neither depends on
`/tmp`, this device's project directory or a particular user home.

A new account starts with these defaults and creates its own window state.
Project libraries, cloud credentials and editing preferences remain with their
owner. A Resolve reinstall through the guided installer reconnects its entries
to the OS integrations automatically.

Build gates verify fresh accounts without resolve.conf, cursor sizing independent
of app zoom, theme search priority, required packaged components, desktop-entry
repair, native-menu rendering and behavior, browser bridge handling, and frame
colors/lifecycle. Actual Cloud account sign-in still needs user acceptance; the
browser handoff regression does not substitute for account authentication.

These defaults require an OS image built from the current Resolve fixes. An
older OS image does not acquire newer launcher code merely by reinstalling the
vendor application. The current bench uses a verified temporary launcher until
that OS update is published and installed.
