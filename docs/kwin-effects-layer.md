# The KWin effects layer — glassy, rounded windows

*Built 2026-08-30. Tier 2, Track B of the V2 shell work; the plan it implements is
`docs/v2-shell-tier2-research.md`, "Layer 2". Everything here assumes zero Linux
experience.*

## What this change is, in one paragraph

Application windows on AquariusOS are frosted glass: whatever is behind a window
shows through it, blurred and slightly more colourful, and all four corners are
rounded to 16 pixels with a big soft shadow underneath. KDE cannot do that on its
own, so AquariusOS adds two small community add-ons — and, unusually, **builds
them from source code every time the OS image is built**. That last part is the
whole interesting decision in this document, and there is a good reason for it.

Nothing here is forced. Every setting is a starting point a person can change in
System Settings, and once changed it stays changed — no OS update will put it
back.

---

## The two add-ons

| | What it does | Where it comes from |
|---|---|---|
| **Better Blur DX** | Blurs the desktop behind every window, adjusts how colourful that blur is, and rounds the blurred area to match the window | [xarblu/kwin-effects-better-blur-dx](https://github.com/xarblu/kwin-effects-better-blur-dx) |
| **KDE-Rounded-Corners** | Rounds all four corners of every window to 16px and re-shapes the window's shadow to follow that curve | [matinlotfali/KDE-Rounded-Corners](https://github.com/matinlotfali/KDE-Rounded-Corners) |

### Why Better Blur DX and not the blur KDE already has

KDE *does* ship a blur effect, and it is a good one — Plasma 6.5 even merged the
old separate "background contrast" effect into it, which is where the colour
adjustment comes from. But it has one hard rule: **KWin will only blur behind a
window if the application asks it to.** Plasma's own panels and popups ask.
Firefox does not. Neither does Blender, or DaVinci Resolve, or a terminal, or
anything else you actually work in. There is no setting to override this and no
window rule that can force it; the ability was never built, on purpose.

The result of transparency without blur is not glass. It is a window you can see
the mess of your desktop through, which reads as cheap rather than premium.

Better Blur DX is a fork of KDE's own blur effect with that rule removed. It can
blur behind everything whether the application asked or not. That is the entire
reason it is here.

**The two cannot both run.** They are the same effect twice, and upstream says
so: windows "might get double blurred and look off". So AquariusOS switches KDE's
off and ours on, in the same file, at the same time.

### Why KDE-Rounded-Corners

KDE rounds the *top two* corners of a window frame, at a radius it picks itself,
and there is no setting for it. The AquariusOS design wants all four corners at
exactly 16px, matching the panel and popup corners. That is what this second
add-on is for. It also takes the shadow the window already has and re-shapes it
to follow the new curve, so the shadow does not sit in a square around a round
window.

---

## Why they are compiled here — the part worth understanding

This is the doctrine for the whole layer. It is written out at length because it
looks like extra work and is in fact the thing that stops a silent, hard-to-
diagnose breakage from ever reaching a user.

### The problem: KWin plug-ins are welded to one exact KWin

A KWin effect is not a normal program. It is a plug-in loaded straight into the
running compositor, and it works with **exactly** the version of KWin it was
compiled against. Not "6.7" — the specific 6.7.2. KDE makes no promise of
compatibility here and is under no obligation to; the interface is internal.

And the failure mode is the worst kind. Nothing crashes. No error appears
anywhere. KWin looks at the plug-in, decides it does not fit, and does not load
it. The desktop just… stops being glassy, and there is nothing to report except
"it looks wrong now".

This is not hypothetical. Upstream issue
[#105](https://github.com/xarblu/kwin-effects-better-blur-dx/issues/105) is
exactly it: a user on an already-working machine took a routine update that moved
KWin from **6.7.1 to 6.7.2** — a bug-fix release, two weeks apart — and the blur
silently vanished. Rebuilding the identical version of the add-on against the new
KWin fixed it immediately.

### The tempting answer, and why we do not use it

There is a ready-made Fedora package for Better Blur DX (a "COPR", a
community-run package repository), and installing it would be one line.

Do not. Here is what that line actually buys:

- The package is rebuilt by a volunteer, when they get to it.
- Fedora ships a new KWin whenever Fedora ships a new KWin.
- Those are two different people on two different schedules.

Every time those two get out of step — and they will, because a rebuild takes a
day and an update takes a second — anybody who installs AquariusOS in that window
gets an image whose glass does not work, with no error and no way to know why.

**The standing rule: never layer the COPR packages. Always build from source, in
the Containerfile, against this image's own KWin headers.** If you find yourself
about to add `dnf5 copr enable` for either of these effects, stop and re-read
this section.

### What building here buys instead

Three things, and the third is the good one.

1. **The add-on and the KWin it was built for ship as one unit.** They are in the
   same image. An update ships both or neither. A rollback rolls back both.
   There is no window in which they can disagree.

2. **The pieces are checked before anything is published.**
   `build_files/kwin-effects.sh` checks that both plug-in files exist, that every
   library they need is in the image, and that their descriptions were compiled
   in. `.github/workflows/build.yml` asks the same questions again of the
   finished image that is about to be pushed.

3. **A future breakage becomes a red build instead of a broken desktop.** When
   Bazzite moves to a new Plasma release before the add-ons have caught up, the
   compile fails and *the OS build stops*. Nothing is published. And because this
   kind of OS only changes when a new image is published, everybody's installed
   AquariusOS carries on working exactly as it did yesterday.

That third point is the trade in one sentence: **an unavoidable compatibility
treadmill turned into a build-time signal.** The problem lands as a red X in a
tab that only we look at, instead of on somebody's screen.

### ⚠️ Therefore: never make this failure quiet

There is no `|| true` anywhere in `build_files/kwin-effects.sh` and there must
never be one. If a build fails there, the correct responses are, in order:

1. **Wait and re-run.** Historically the catch-up is days, not weeks — Better
   Blur DX has supported new Plasma releases from their first beta.
2. **Bump the pinned version** (below) if upstream has already shipped a fix.
3. **Ask whether we still want the effect**, if upstream has gone quiet.

The wrong response is to make the build skip it and carry on. That publishes an
image whose desktop is missing half its design, with nothing anywhere saying so —
which is precisely the situation all of this exists to prevent.

---

## What is pinned, and how to change it

Both add-ons are pinned three ways at the top of `build_files/kwin-effects.sh`:

| | Better Blur DX | KDE-Rounded-Corners |
|---|---|---|
| Tag | `v2.5.1` (released 2026-06-23) | `v0.10.0` (released 2026-08-23) |
| Commit | `e8475d0a7045e1ef035d54cff9cf2c0b02f0aff0` | `08dee25ac0410d977a45dd1e74a7de1823c1f098` |
| SHA-256 of the download | `42152f040434f0adfef55eab510000a5fc00b0afe1935e0dc6f01c766b4c9dbb` | `f3f03d96e17ae4b7dcee6347a01c75de6f90ed19e070e98ae8bf2dd71ae276db` |

The tag and the commit are for people reading release notes. The **checksum is
the one the machine enforces**: nothing is unpacked or compiled until the
downloaded file matches that string exactly. It is the same discipline the
DaVinci Resolve AAC plug-in recipe uses (`ujust install-resolve-aac-plugin`).

Both versions were chosen for Plasma 6.7, which is what Bazzite ships:

- Better Blur DX v2.5.1 — its README lists 6.5, 6.6 and 6.7 as supported, and its
  build files refuse outright to build against anything older than KWin 6.4.
- KDE-Rounded-Corners v0.10.0 — the release that added the 6.7 fixes by name:
  "Load the core-profile shader on KWin 6.7+" and "Fix shader loading on KWin X11
  6.7". The previous release, v0.9.0, predates both.

### To bump a version

1. Look at the project's releases page and pick the new tag.
2. Read its release notes. Confirm it still supports the Plasma we are on.
3. Download the file and compute the checksum **yourself** — do not copy a number
   off a web page, because the point of the number is that it was computed from a
   file somebody actually held:

   ```
   curl -fsSL -o /tmp/x.tar.gz https://github.com/<owner>/<repo>/archive/refs/tags/<new-tag>.tar.gz
   sha256sum /tmp/x.tar.gz
   ```

4. Get the commit that tag points at:

   ```
   curl -s https://api.github.com/repos/<owner>/<repo>/git/ref/tags/<new-tag>
   ```

5. Change all four lines for that project together — tag, commit, URL, checksum —
   and the folder name too if the version number is part of it (it is: the
   tarball unpacks into `<repo>-<version>`).
6. Push. GitHub Actions compiles it. If it goes red, the new version does not fit
   this Plasma and the old one should go back.

---

## What happens when Bazzite moves to a new Plasma

This will happen, probably twice a year, and it is worth knowing what it looks
like in advance so nobody panics.

1. Bazzite publishes a new image with, say, Plasma 6.8 in it.
2. Our next build starts from that image and tries to compile both add-ons
   against 6.8.
3. If upstream has already released a 6.8-compatible version and we are still
   pinned to the old one, **the build fails** — usually with pages of C++ errors,
   which look alarming and mean only "these two pieces do not fit together".
4. Nothing is published. Every installed AquariusOS keeps working, unchanged.
5. We bump the pins as above, the build goes green, and the update ships.

**Step 3 is the design working, not the design failing.** The alternative — a
build that shrugged and shipped — is an image that boots to a desktop with no
glass on it and no explanation anywhere.

A smaller version of the same thing can happen inside a single Plasma release, as
issue #105 showed with 6.7.1 → 6.7.2. Our build script pins the header files it
compiles against to the exact KWin already in the image, so this case cannot
produce a mismatch — it can only produce a build that stops.

---

## How to check it actually worked, on a real machine

Two commands, in a terminal on a booted AquariusOS. Neither changes anything.

### 1. Are both effects loaded?

```
qdbus org.kde.KWin /Effects loadedEffects
```

This prints every effect KWin has actually loaded, one per line. In that list
there should be:

- `better_blur_dx` — the glass
- `kwin4_effect_shapecorners` — the rounded corners

and there should **not** be:

- `blur` — KDE's own blur, which we switch off

If `qdbus` is not found, try `qdbus6` or `qdbus-qt6`; Fedora has renamed it more
than once.

> **This is the outstanding verification for this whole track.** The two names
> above were worked out by reading each project's build files (the working is
> written into `/usr/share/aquarius/xdg/kwinrc`, next to the settings that use
> them) and confirmed a second way from an upstream issue where a packager's
> build log names the files. That is strong, but it is still a derivation. One
> run of the command above turns it into a fact. If a name turns out to be
> different, fix it in `system_files/usr/share/aquarius/xdg/kwinrc` — do **not**
> work around it by ticking the box in System Settings, because that writes into
> your own account only and hides the problem from every other user.

### 2. Do the settings look right?

Open **System Settings → Colours & Themes → Desktop Effects**, and find "Better
Blur DX" and "Rounded Corners" in the list. Both should be ticked. Click the
spanner next to either to see the values this OS shipped.

If an effect appears under the "Unsupported" filter instead of the normal list,
that is the version-mismatch failure described above, appearing on a machine
rather than in a build.

---

## What was shipped, and where

Everything is a plain text default in the folder KDE reads *below* the user's own
settings. Nothing is forced; nothing is written into anybody's home folder.

| File | What it sets |
|---|---|
| `system_files/usr/share/aquarius/xdg/kwinrc` | which effects run; the blur's strength, colour, corner radius and "blur everything" rule; the 16px corners |
| `system_files/usr/share/aquarius/xdg/breezerc` | the window shadow — size, darkness, colour |
| `system_files/usr/share/aquarius/xdg-handheld/kwinrc` | a gentler blur, handhelds only |
| `build_files/kwin-effects.sh` | downloads, checks, compiles and installs the two add-ons |
| `build_files/build.sh` | one line, calling the above |
| `.github/workflows/build.yml` | the "Verify KWin effects" step |

Each of those files explains its own settings line by line, with the upstream
source each value and each name was read out of. That detail is deliberately in
the files rather than repeated here, so it cannot drift out of step with them.

The headline numbers, for orientation:

- **Blur strength 11** out of 15. Not a pixel radius — it is the number of passes
  in a repeated shrink-and-grow blur, so the scale is nothing like CSS's
  `blur(20px)`. 11 was chosen by eye as the closest match to the design.
- **Saturation 130** — the design's `saturate(1.3)`; colours behind glass stay
  vivid instead of going grey.
- **Corner radius 16** in two places, which must always match: the corners of the
  windows, and the corners of the blurred area behind them.
- **Shadow: the largest KDE has**, at 60% darkness.

### The shadow is one shadow, not two

Two add-ons that can each draw a shadow is an obvious way to end up with a halo
twice as heavy as intended. It is avoided by one line —
`UseNativeDecorationShadows=true` — which tells KDE-Rounded-Corners to re-shape
the shadow the window already has rather than draw a second one. The size and
darkness of that single shadow are then set in one place only, `breezerc`.

---

## Handhelds get a lighter version

The blur is a shader that runs on the graphics chip for every window, every
frame. On a desktop with a real graphics card that is free. On a handheld the
graphics chip is part of the same processor as everything else, shares the same
memory, and runs off a battery — so the handheld image turns the blur strength
down from 11 to 6. Same look, roughly half the work.

That override lives in `/usr/share/aquarius/xdg-handheld/kwinrc`, a folder that
only exists on the handheld image (`build_files/build.sh` deletes it from the
other two) and which sits *above* the normal one in KDE's search order. Because
KDE merges these files key by key, that one line replaces the blur strength and
leaves every other blur setting coming through from underneath.

**⚠️ The number 6 is a starting point, not a measurement.** It has never been run
on the ROG Xbox Ally — nothing in this repo can be, because neither the build
machines nor Royce's Mac is a handheld. Check it on the device: drag a window
around over the wallpaper with a few others open. If it feels heavy, lower it. If
it is perfectly smooth, it can go back up.

---

## Game Mode is completely unaffected

Worth stating plainly because it sounds like it should be a concern and is not.

When a handheld boots into Game Mode — or when anybody picks "Game Mode" at the
login screen — **KWin is not running at all**. Game Mode uses a different
compositor, `gamescope`, built for one job: put one game on the screen as fast as
possible. KWin effects do not exist in that world. They cannot slow a game down,
they cannot add latency, and they cannot break Steam.

The glass is a desktop-session feature, full stop. This is the same reasoning
that let the handheld image be added with no branching in the build recipe, which
is written up in `docs/deck-variant-research.md`.

---

## Honest gaps and things still to judge with eyes on a screen

Recorded rather than quietly pretended away.

1. **The shadow is 64px, the design asked for 80px.** KDE's window frames take
   one of five preset shadow sizes and the biggest is 64 pixels — there is no
   sixth and no way to type a number. Forking the window decoration for the last
   16 pixels is a lot of permanent maintenance for a difference nobody can see
   without a ruler. Not done, deliberately.

2. **Blur radius is one number for the whole system.** The design asks for
   `blur(20)` behind the panel and `blur(24)` behind popups. There is one blur
   setting, so those collapse into one value. Nothing can be done about this
   short of writing our own compositor.

3. ~~**The window outlines are at upstream's defaults.**~~ **Judged and changed
   on 2026-08-30 — see "First bench findings" at the bottom of this document.**

4. **The titlebar is not translucent.** KDE's Breeze window frame has no
   transparency setting. The blur is told to blur *behind* the frame as well,
   which gets most of the way there from the other direction. A different window
   decoration that does support translucency would be a second thing on the same
   recompile-every-release treadmill — a trade worth making once, not twice.

5. **Do the two effects coexist perfectly?** They are both shader passes over the
   same windows, and pairing them is common in the wild, but we have not
   confirmed it ourselves. Watch for corner artefacts on the first test image —
   particularly at the corners of maximised and tiled windows, which both
   projects treat as special cases.

6. **Static blur is gone and is not coming back soon.** The older, unmaintained
   Better Blur had a "static blur" mode that blurred once and reused the result,
   which was much kinder to a battery. The maintained fork has not reimplemented
   it. Do not promise it in any AquariusOS documentation or marketing.

---

## For the record: what CI proves, and what it cannot

The "Verify KWin effects" step in `.github/workflows/build.yml` runs against the
finished image and proves:

- both plug-in files exist where KWin looks for them, and are readable;
- so do both of their System Settings pages, and both of the shader files the
  rounded-corners effect reads at run time;
- every shared library the plug-ins need is present in the image (a missing one
  makes KWin ignore the plug-in silently);
- each plug-in carries its own description, which is what KDE lists it by;
- the settings that switch them on shipped, with the right values;
- the handheld override is present on the handheld image and absent on the other
  two;
- no development packages were left behind.

It **cannot** prove the plug-in loads. There is no compositor and no graphics
card in a container. That is what the `loadedEffects` command above is for, and
it is the one genuinely outstanding item on this track.

---

## First bench findings — 2026-08-30

The image booted on real x86 hardware. The photograph that matters here is a
close-up of a window's top-left corner. Everything this layer is *for* was
working: the effects compiled, loaded and rounded the corners, and the settings
cascade reached KWin.

### What the photo showed

Two lines, not one, and both wrong for the design.

1. A **cream-white hairline** tracing the whole window, hugging the rounded
   corner. Bright — brighter than anything else on the screen.
2. A **straight dark 1px line** at the top-left, running upwards past the point
   where the corner curves away and stopping abruptly against the wallpaper.

### The cream line — fixed

That is upstream's second outline: white at `ActiveSecondOutlineAlpha=85`, which
is 85 out of 255, the "33%" everybody quotes. Upstream's first outline is black
at full opacity, which against our wallpaper all but vanishes — so the only ring
you actually see is the white one.

Gap 3 above said these were left at upstream's defaults because numbers picked
without a screen are numbers nobody has checked. There is now a screen, so they
have been set:

| Key | Was (upstream) | Now | Why |
|---|---|---|---|
| `OutlineColor` | `black` | `237,239,247` | the design's hairline colour |
| `ActiveOutlineAlpha` | `255` | `36` | `border-2` is 14%; 14% of 255 is 35.7 |
| `InactiveOutlineColor` | `black` | `237,239,247` | same line |
| `InactiveOutlineAlpha` | `255` | `26` | 10%, the top bar's quieter hairline — a window you are not using recedes |
| `SecondOutlineThickness` | `1` | `0` | off |
| `InactiveSecondOutlineThickness` | `1` | `0` | off |

Every key name and default was read out of `src/kcm/options.kcfg` at the pinned
tag v0.10.0, and the exact lines are quoted in `kwinrc` next to the settings.
Two things about that file are worth repeating here because they are easy to get
wrong and fail silently:

- **The colour keys hold RGB only.** An alpha written into a colour is read and
  then overwritten by the separate `*Alpha` key
  (`color.setAlpha(alpha)` in `src/WindowConfig.cpp`). Writing
  `OutlineColor=237,239,247,36` gives a solid line, not a 14% one.
- **Active has no prefix; inactive does — but only on the colours.** The active
  colour is `OutlineColor`; there is no `ActiveOutlineColor`. The alphas are
  both prefixed. This asymmetry is the main trap in the file.

The second outline is off rather than dimmed because the design's 7% inner
highlight is a *top-edge* sheen, and this effect can only draw a complete ring.
A 7% ring is not a quieter version of the design; it is a different thing.

### The dark line past the corner — diagnosed, not fixed

Written down rather than guessed at, because the fix has a cost.

**Conclusion: it is most likely the effect's own corner reconstruction — the
shadow path — and not the outline.**

The reasoning, from the v0.10.0 source:

- *Not* the outline drawn on a square frame. The effect computes the outline and
  the window edge from one shared rounded distance field (`shapeCorner()`,
  `src/shaders/shapecorners.glsl`). A geometry mismatch would show at every
  corner in both directions, and the photo has a vertical stub with no
  horizontal twin.
- *Not* the second outline. It is clamped strictly inside the radius and cannot
  render outside the curve at all.
- **It fits `getNativeShadow()`** in `src/shaders/shapecorners_shadows.glsl`.
  With `UseNativeDecorationShadows=true` — which we set deliberately, to keep one
  shadow instead of two — the effect does not draw a shadow; it *rebuilds* what
  should sit behind the corner it rounded off, by sampling the window texture
  about three pixels outside the frame on each side and blending the two samples
  across the corner. Three pixels outside the frame is exactly where a window
  decoration paints its own dark border, so that dark pixel gets smeared along
  the corner. And the region it writes starts two pixels outside the frame, so
  the smear genuinely extends past the window edge onto the wallpaper.

Upstream says the same. Issue **#252**, "Remnant of outline despite it being
disabled in the settings": the reporter has both outlines switched off and still
sees a stub at the top-left corner; the maintainer's reply is *"Actually, it is
not the outline, but the shadow"*, and he adds that it shows on Wayland and not
on X11. Issue **#378** is the same artefact at 125% display scaling.

**Why it is not being changed here.** The fix is
`UseNativeDecorationShadows=false`, and that undoes the one-shadow decision
documented above: with it off, this effect draws its own shadow alongside
Breeze's, tuned by a different set of keys in a different file. Trading a
known 1px artefact for a possible doubled halo, without a screen to look at, is
the kind of change this document exists to argue against.

**The next bench test, in order:**

1. Look again with the outline colour already changed. If the stub is gone, it
   was the outline after all and there is nothing left to do.
2. If it is still there, set `UseNativeDecorationShadows=false` and set
   `ShadowSize` / `ActiveShadowAlpha` to match what `breezerc` asks for — then
   check the window shadow has not doubled.
3. Check the display scaling. At 125% or 150%, try 100% once: #378 says the
   sample offsets land on the wrong texels at fractional scales.

### Also worth recording

Gap 5 above — "do the two effects coexist perfectly?" — is partly answered. The
corners of the ordinary window in the photo are cleanly rounded and the blur
follows them, so the pairing works. Maximised and tiled windows were not in
frame and are still unchecked; both projects treat them as special cases.
