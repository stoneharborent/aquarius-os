# Known issue: blur-behind does not render (investigated 2026-08-30, accepted)

## The short version

On AquariusOS (Bazzite 44 base, Plasma 6.7.4, KF 6.29), the compositor never draws the
"frosted glass" blur behind panels, popups and KRunner — surfaces are translucent but the
content behind them stays sharp. After a full evening of systematic elimination on real
hardware (Royce's RTX 4090 / Ryzen 9 9950X3D bench), **every layer we can inspect checks
out healthy and the frost still does not render.** Royce's call, 2026-08-30: **ship without
it.** The theme keeps requesting blur on every boot, so if a future Plasma update fixes the
underlying issue, frost turns on by itself with no change on our side.

Nothing else is affected: translucency, the glass artwork, rounded corners, shadows,
saturation settings and the whole V2 shell all work.

## What was eliminated, in order (the full chart)

Every test on the bench, most with photos or command output on file:

| Suspect | Verdict | Evidence |
|---|---|---|
| Our Plasma Style (theme) | ✅ innocent | Breeze Dark doesn't frost either |
| Our KWin effects (Better Blur DX, ShapeCorners) | ✅ innocent | No frost with both disabled; stock-only tested |
| Our config layer entirely | ✅ innocent | `zz-aquarius.sh` parked (whole cascade unplugged) — still no frost |
| NVIDIA driver | ✅ innocent | Same failure on the Ryzen iGPU output |
| HDR | ✅ innocent | Toggled off, no change |
| Fractional scaling (1.5×) | ✅ innocent | Same failure at scale 1.0 (also refuted at source level — output scale never enters blur's skip conditions) |
| KWin GL context (reports GL 3.1) | ✅ normal | KWin 6.7 deliberately requests a 3.1 core context (`eglcontext.cpp`); blur shaders are `#version 140`. Healthy reading |
| Frameworks too old for the new blur protocol | ✅ innocent | KF 6.29's Wayland plugin carries `ext_background_effect_manager_v1` |
| The blur request path | ✅ **proven healthy** | `WAYLAND_DEBUG` trace: global advertised (v1), client binds, **`capabilities(1)`** received, `get_background_effect` + repeated `set_blur_region` committed by KRunner |
| Effect not loaded / shaders failing | ✅ innocent | `loadedEffects` and `activeEffects` both list `blur`; journal has zero shader/GL/blur errors |
| DX stripping KWin's blur capability on unload (its dtor calls `removeBlurCapability()` unconditionally against a non-refcounted flag — a real footgun, see below) | ✅ not the cause here | `capabilities(1)` observed live |
| Stuck fullscreen-effect flag suppressing blur | ✅ innocent | `activeEffects` = `blur` only; Overview opens normally |
| Screen-lock state stuck (blur disables behind the lock) | ✅ innocent | `blur` present in `activeEffects` (it self-deactivates when locked) |
| Accumulated session state from a night of config churn | ✅ innocent | Final test: `ujust update` + full clean reboot — still no frost |

**What remains:** the one link not observable from a terminal — whether the blur effect's
internal window-tracking actually picks up the surfaces that committed blur regions
(kwin `blur.cpp` window map, fed by `blurChanged`/`windowAdded`). Everything on both sides
of that link is verified working. This is where an upstream developer with a debugger
picks up.

## If anyone wants to revisit

1. Quick health probes (all safe): `qdbus org.kde.KWin /Effects loadedEffects`,
   `... activeEffects`, and the WAYLAND_DEBUG one-liner in the investigation notes below.
2. `qdbus org.kde.KWin /KWin showDebugConsole` → Windows tab is the next diagnostic
   step nobody has taken yet (inspect the KRunner window's properties as KWin sees them).
3. Retest after every Bazzite rebase that bumps Plasma (6.7.5+, 6.8): click the clock —
   if the calendar popup frosts, delete this file's "accepted" status and celebrate.
4. An upstream bug report draft can be assembled from this file + the session transcript
   (2026-08-30): the version matrix, the elimination chart, and the protocol trace are
   exactly what kde.org triage asks for. Product: kwin, component: effects-various /
   wayland-generic.

## Side-findings worth keeping (came out of the investigation)

- **KWin 6.7 removed the old blur protocol** (`org_kde_kwin_blur_manager`) — third-party
  apps (Ghostty, WezTerm, Alacritty, Kitty) lost blur until they port to
  `ext-background-effect-v1`. KDE bug 521702, RESOLVED UPSTREAM. Unrelated to our issue
  but explains "blur worked for app X before."
- **KWin 6.7's blur capability flag is not reference-counted**, and Better Blur DX v2.5.1's
  destructor removes it unconditionally — unloading DX while stock blur runs would strip
  blur for the whole session. Not our bug tonight, but a real reason to keep the shipped
  rule "exactly one blur effect enabled" and worth an upstream report to both projects
  someday.
- **Stock blur in 6.7 natively supports rounded blur regions** (`onscreen_rounded.frag`)
  and has a Saturation setting — when frost works, the popup glass needs no third-party
  effect at all. Relevant to the Wave 2 decision about keeping DX in the image.
- KWin reporting **OpenGL 3.1** in supportInformation is normal and healthy — do not
  chase it.
- Recovery commands that are safe to hand a user: `qdbus org.kde.KWin /Effects
  unloadEffect <name>` / `loadEffect <name>` apply live; a full reboot resets all
  compositor state.

## Status of the shipped config (unchanged by this issue)

`/usr/share/aquarius/xdg/kwinrc` still disables stock blur and enables Better Blur DX +
ShapeCorners as designed — the effects load and are harmless. Frost is invisible either
way until the underlying issue is resolved; the Wave 2 shell work will revisit which blur
effect the image should standardize on (see the "natively supports rounded corners"
finding above — stock-only is now a live option).
