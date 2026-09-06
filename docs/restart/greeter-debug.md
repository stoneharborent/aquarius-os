# Why the Aquarius greeter does not draw — a debugging map

*Written 2026-09-05, after the bench journal confirmed the multi-day "black
screen with a cursor" saga was the greetd greeter, not GDM. This page does NOT
fix the greeter. It scopes the fault so the next person with a Linux machine in
front of them can find it in one session instead of five, and it lists the exact
commands to capture next time somebody opts in with `aq login use greetd`.*

*Assumes you have read `login.md` first — especially Part B (our own login
screen) and the new confirmed-root-cause section at the top.*

---

## What we know for certain (from the bench journal, 2026-09-05)

1. **greetd was the active login manager, not GDM.** The journal shows
   `Started greetd.service`, `greetd[1787]: session opened for user greetd`, and
   `systemd-logind: New session 'c1' of user 'greetd' class 'greeter'`. There is
   no GDM greeter in that boot.
2. **greetd was enabled by `aq login use greetd`** (the R5 greeter test) and its
   marker (`/etc/systemd/system/display-manager.service -> greetd.service`)
   persisted across every reboot. That is why the black screen came back every
   boot — it was not a race, it was the configured state.
3. **labwc started, the Quickshell greeter did not draw.** The machine sat on a
   **bare labwc desktop** — the tell is labwc's own root menu on right-click
   (**Terminal / Reconfigure / Exit**), whose items do nothing useful.
4. **`systemctl restart gdm` "fixed" it every time** — by starting GDM *over the
   top*, which is a different login screen, not by repairing the greeter.

So the question this page scopes is narrow: **greetd + labwc come up; `qs` (the
Quickshell greeter) does not put a login box on the screen. Why?**

---

## The single most important clue: the labwc root menu

`/usr/share/aquarius/greeter-labwc/rc.xml` **deliberately removes** labwc's root
menu — it ships no `<default />` and no `Root` mouse-context menu binding,
precisely so a person who has not logged in cannot open Terminal / Reconfigure /
Exit. Read the comments in that file; suppressing that menu is one of its two
jobs.

**And yet that exact menu is what showed on the bench.** That means one of two
things, and telling them apart is the first fork in the road:

- **A. labwc is NOT applying our rc.xml.** If labwc cannot find or parse the
  config we point it at, it falls back to its built-in defaults — which *include*
  the root menu. If this is it, the greeter's failure to draw may be secondary:
  fix the config path and much else may follow.
- **B. labwc IS applying our rc.xml, but `qs` never put a surface on top.** If qs
  crashed or never launched, labwc is left showing an empty desktop. But with our
  rc.xml the right-click menu should be *gone* — so if the menu is present, this
  case is less likely than A, unless labwc merged defaults for the menu while
  honouring the rest. Confirm by checking whether the *other* rc.xml settings
  (no title bars, `gap 0`) took effect.

**Capture which one it is first** (commands below): read labwc's own startup log
for "using config file …" / parse errors, and check whether qs is running.

---

## The hypotheses, most-likely first

### 1. labwc is not reading `-C /usr/share/aquarius/greeter-labwc`
`/usr/libexec/aquarius-greeter` runs:

```
/usr/bin/labwc -C /usr/share/aquarius/greeter-labwc -s /usr/libexec/aquarius-greeter-shell
```

Things to verify on the bench:
- Does labwc 0.20 read **`rc.xml`** from the `-C` directory, or does it expect a
  different filename/layout in that release? (`labwc --help`, and its startup log
  line naming the config file it loaded.)
- Is `-C <dir>` even the flag this labwc build takes, or is it `--config-dir` /
  `-c <file>`? A silently-ignored flag gives exactly "labwc came up with
  defaults".
- The root-menu tell (above) is the fast read: menu present ⇒ our config not
  applied.

### 2. `qs` launched, then its QML failed to load, so it exited
`/usr/libexec/aquarius-greeter-shell` ends with `exec /usr/bin/qs -p
/usr/share/aquarius/shell/greeter/greeter.qml`. If the QML fails to load, `qs`
exits non-zero, the greeter-shell exits, labwc's `-s` startup command is done —
**and labwc keeps running with an empty desktop** (see hypothesis 5). Sub-causes,
each checkable from qs's own stderr:
- A QML **import** that resolves to a Quickshell module not built into this `qs`.
  The greeter imports (confirmed from the shell repo, `main`):
  `QtQuick`, `Quickshell`, `Quickshell.Io`, `Quickshell.Services.Greetd`,
  `Quickshell.Wayland`, and the relative `"."` / `"../theme"`.
  - `Quickshell.Services.Greetd` (`SERVICE_GREETD`) **is** compiled in — the
    build stage enforces it and CI fails without it, so on a shell-present image
    this is not the missing module. Do not chase it first.
  - `Quickshell.Wayland` (`WlrLayershell`) needs `WAYLAND_WLR_LAYERSHELL` —
    also enforced ON. Also not the likely gap.
  - `Quickshell.Io` is core Quickshell; if it is somehow absent the very first
    imports fail. Worth confirming it resolves.
- The relative import `"../theme"` not resolving from `-p greeter/greeter.qml`
  when the file is given as an absolute path — a `qs -p <file>` vs `qs -p <dir>`
  /  `qs -c <name>` invocation-shape mismatch in this Quickshell version.
- A runtime error in `GreeterState.qml` (e.g. the account/desktop lister
  `/usr/libexec/aquarius-greeter-info` returning nothing usable) that throws
  before anything is shown.

### 3. `qs` launched, QML loaded, but the layer-shell surface never appeared
`GreeterWindow.qml` uses `WlrLayershell.namespace` and sets
`WlrLayershell.keyboardFocus = Exclusive`, guarded by
`this.WlrLayershell !== null`. If the window is **not** backed by layer-shell
(labwc did not grant a layer surface, or the protocol handshake failed), the
guard is false and the greeter may never become the full-screen top surface —
leaving labwc's desktop visible underneath. Check for a layer surface in the
`aquarius-greeter` namespace.

### 4. The `qs -p` invocation / config-path semantics in Quickshell 0.3.x
Confirm on the bench that `qs -p /usr/share/aquarius/shell/greeter/greeter.qml`
is the correct way to run a single-file config in the installed Quickshell
version (vs `qs -c`, or `-p` expecting a directory). A wrong flag shape can make
qs print usage and exit 0 — which looks like "it ran and did nothing".

### 5. labwc `-s` does not exit when its startup command exits
`/usr/libexec/aquarius-greeter`'s comments claim labwc, started with `-s`, "shuts
down when [the command] finishes". **Verify this is actually true for labwc
0.20.** If labwc does *not* exit when the `-s` command exits, then any qs crash
(hypothesis 2) leaves labwc running with an empty desktop and the root menu — the
exact bench symptom — instead of falling through to `aquarius-greeter`'s
tuigreet safety net. If this is the case, the launcher needs to treat "qs exited
but labwc is still up" as a failure and tear labwc down itself.

---

## What to capture on the next opt-in (before restarting gdm)

Somebody has to run `sudo aq login use greetd --yes`, restart, and — while
looking at the black screen — switch to a text console with **Ctrl+Alt+F3**, log
in, and run these. **Do this before `sudo systemctl restart gdm`**, which erases
the evidence.

```bash
# 1. greetd's own journal — this is where aquarius-greeter and everything it
#    starts print. labwc's config line, greeter-shell's messages, and qs's
#    stderr all land here.
journalctl -b -u greetd --no-pager | tee ~/greeter-boot.log

# 2. Is Quickshell even running? (If NOT, the greeter crashed or never launched —
#    hypothesis 2. If it IS, look at hypotheses 3/4.)
pgrep -a qs; pgrep -a quickshell; pgrep -a labwc

# 3. What did the safety net make of it?
journalctl -b -u aquarius-greeter-watchdog --no-pager

# 4. Run the greeter by hand, as the greetd user, to see qs's error directly.
#    (Adjust the runtime dir if logind named it differently.)
sudo -u greetd env XDG_RUNTIME_DIR=/run/user/$(id -u greetd) \
    /usr/bin/qs -p /usr/share/aquarius/shell/greeter/greeter.qml
#    ^ read the FIRST error line. "module X is not installed" points at
#      hypothesis 2; a QML runtime error points at GreeterState; a usage dump
#      points at hypothesis 4.

# 5. Does labwc load our config? Start it by hand and read its first lines.
labwc -C /usr/share/aquarius/greeter-labwc -s true 2>&1 | head -30
#    ^ look for the "using config file" line and any parse warnings. If it names
#      a config file that is NOT ours, that is hypothesis 1.
```

Write down which hypothesis the evidence points at, in `login.md`'s bench list.
A result nobody records has to be paid for twice.

---

## The one change worth making regardless — a "ready" stamp

The safety net (`aquarius-greeter-watchdog`) would be far more precise if the
greeter told it, "I drew." The watchdog already prefers a file at
**`/run/aquarius-greeter-ready`** over guessing from `pgrep qs`. If the greeter
QML touches that file in `GreeterWindow.qml`'s `Component.onCompleted` (only on
the primary screen), the watchdog gets an unambiguous "the login box is on the
screen" signal, and the frozen-`qs`-but-black case stops being invisible.

This is a **one-line change in the shell repo**, not here, and it must be made
there so the QML and its contract stay one thing:

```qml
// GreeterWindow.qml, in Component.onCompleted, primary screen only:
//   Quickshell.Io: FileView / Process to `touch /run/aquarius-greeter-ready`
```

Until that lands, the watchdog falls back to `pgrep qs` plus the
consecutive-boot counter, which already catches the confirmed bench symptom
(labwc root menu = qs not up). Do **not** rewrite the greeter blind to add this;
make it deliberately, on a machine where you can watch it draw.

---

## What is already safe, whatever the cause turns out to be

- `aq login use greetd` now **warns and requires confirmation**, so nobody
  switches to the experimental greeter by accident.
- `aquarius-greeter-watchdog` **switches the machine back to GDM after two failed
  greetd boots in a row**, so the greeter can no longer trap the machine.
- The recovery is one line from a text console: `sudo aq login use gdm` then
  reboot. See `login.md`.
