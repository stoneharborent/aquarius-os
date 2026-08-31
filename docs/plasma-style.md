# The Aquarius Plasma Style — the desktop shell's artwork

*Written 2026-08-30. Tier 2, track T2-A. The research this implements is
`docs/v2-shell-tier2-research.md`, "Layer 1".*

> **⚠️ This document was written when the theme was glass. It no longer is.**
> The transparency was removed on 2026-08-30 — the reasons, and exactly what
> changed, are in **"Glass removed — 2026-08-30"** at the bottom of this file.
> Read that section first, then read the rest knowing that wherever the older
> text says "glass" or "see-through", the surfaces are now solid. Everything
> else it describes — the nine-piece system, the masks, the version stamp, the
> `metadata.desktop` trap — is unchanged and still correct.

## What this is, in one paragraph

The glass look of the AquariusOS desktop — the smoked top bar, the floating dock,
and every popup that drops out of them — is not code. It is a folder of pictures
and a settings file, sitting at
`system_files/usr/share/plasma/desktoptheme/aquarius/`. KDE calls that a **Plasma
Style**. Because it is pure data, it cannot crash, it cannot fail to compile
against a new KDE, and it needs no rebuild when Bazzite moves to a newer Plasma.
That is why it is the first thing we built: it delivers most of the visible
transformation and carries almost no risk.

It is switched on by exactly one line, in our global theme's defaults file:

```
[plasmarc][Theme]
name=aquarius
```

in `system_files/usr/share/plasma/look-and-feel/org.aquariusos.desktop/contents/defaults`.

## Which file controls what

Everything lives under `system_files/usr/share/plasma/desktoptheme/aquarius/`.

| File | Controls |
|---|---|
| `widgets/panel-background.svg` | **The top bar and the dock.** One file, two looks — see below. |
| `widgets/tasks.svg` | **The tile behind a dock icon.** The faint square under the pointer, the stronger one under the app you are using, the mark under a running app. Added after the first bench boot; see below. |
| `dialogs/background.svg` | **Every popup.** Tray popups, the calendar, notifications, applet popups, and the search box (KRunner) all share this one drawing. Change it once and they all change. |
| `widgets/tooltip.svg` | The small tooltip that follows the pointer. |
| `widgets/background.svg` | A card: a widget placed on the desktop itself. Mostly solid, so it reads as an object lying on the wallpaper. |
| `widgets/translucentbackground.svg` | The see-through version of that card. |
| `widgets/plasmoidheading.svg` | The quiet title strip at the top (`header-`) or bottom (`footer-`) of a popup. |
| `solid/widgets/panel-background.svg`<br>`solid/dialogs/background.svg` | Opaque copies of the two big ones, used when somebody turns transparency off. |
| `plasmarc` | The theme's behaviour settings. Every line in it is explained in place. |
| `metadata.json` | Name, id, version. |
| `metadata.desktop` | Looks redundant, is not. See "the stale picture problem" below. |
| `README.md` | The short version of this document, kept beside the artwork. |

Any Plasma artwork we do **not** ship — about forty more SVGs for sliders,
checkmarks, progress bars and so on — falls back to KDE's Breeze, which already
follows our AquariusDark colours. That fallback is written out explicitly as
`FallbackTheme=default` in `plasmarc` so it is visible rather than implied.

### One file, two bars

The top bar and the dock look different but come from the same file, because
Plasma will read two different sets of shapes out of it:

- **plain names** (`top`, `center`, `topleft`, …) → the top bar
- **`floating-` names** (`floating-top`, `floating-center`, …) → the dock

The top bar is bolted to the top edge of the screen, so Plasma switches its top,
left and right edges **off**. Its rounded corners are simply never drawn, and it
reads as a flat full-width strip — exactly as the design has it. The dock floats,
so all four edges are on and all four 16px corners appear.

The hairline differs on purpose, matching the V2 design: 10% white along the top
bar, 14% around the dock.

### The design values, and where they came from

From `branding/design-system` (the "AquariusOS Desktop Shell" artboard) and
`branding/tokens.md`:

| | Top bar & dock | Popups |
|---|---|---|
| Fill | `#06070C` at 62% | `#0D0F18` at 76% |
| Hairline border | `#EDEFF7` at 10% / 14% | `#EDEFF7` at 14% |
| Sheen along the top edge | `#EDEFF7` at 7% | `#EDEFF7` at 7% |
| Corner radius | 16px (dock only) | 16px |
| Shadow | softer, pooled below | large and soft, pooled below |

Text colours are **not** set here — see "no colours file" below.

## How a Plasma background drawing actually works

You do not need to know SVG to maintain these, but you do need this one idea.

Plasma never shows the drawing as a picture. It hunts through the file for shapes
with particular `id="..."` names and uses each one as a tile:

```
topleft      top       topright
left         center    right
bottomleft   bottom    bottomright
```

The four corners are painted at their real size, the four edges are stretched
along the sides, and `center` is stretched to fill the middle. That is how one
48×48 drawing becomes a panel 3840 pixels wide.

Each file then repeats those nine names three more times:

- **`mask-…`** — a solid black copy of the same shape.
- **`shadow-…`** — the eight tiles of the drop shadow, drawn *outside* the window
  by the compositor, which is why it can be bigger than the window.
- **`hint-…`** — invisible markers. Nothing is painted; only their **size** is
  read. `hint-top-margin` being 8 pixels tall is how the file says "inset content
  8 pixels from the top". Without those markers, Plasma insets content by the
  full 16px artwork thickness and every popup gets a fat empty gutter.

The files are laid out in labelled bands with a long comment at the top, so open
one and read it before editing.

### The mask, and why it is the thing most likely to break

> **Updated 2026-08-30.** The masks are unchanged and still matter, but their
> job is narrower now: with the glass gone the theme no longer requests blur,
> so the `mask-` shapes are read as the window's shape region rather than as a
> blur region. Keeping them in step with the visible drawing is still the rule.
> The original text is kept below because it explains *why* the rule exists and
> because it is the text to come back to if the glass ever returns.

**The blur follows the mask, not the picture.**

When Plasma asks KWin to blur the wallpaper behind a panel, it hands over the
black `mask-` shape as the region to blur. If the black copy has squarer corners
than the visible glass, blurred wallpaper pokes out past the rounded corners as
four pale squares. If it has rounder corners, you get four unblurred notches.

Either way it looks like a graphics-driver bug rather than a drawing mistake,
which is exactly why it wastes an afternoon. **Change a corner radius in one,
change it in the other.** Same for the `floating-` set, which has its own
`mask-floating-` copy.

## No `colors` file — on purpose

A Plasma Style may ship a `colors` file that overrides the palette for panels and
popups. We deliberately do not.

AquariusOS sets its palette once, system-wide, in
`system_files/usr/share/color-schemes/AquariusDark.colors`, and the whole desktop
follows it. A second palette inside this theme would mean two sources of truth —
change the accent in one place and the panels would keep the old one. Worse, a
theme `colors` file *wins over* the system scheme, so anyone who picked a
different colour scheme in Settings would find their panels stubbornly ignoring
it.

The only colours written literally into the drawings are the ones the design
fixes regardless of palette: the surface fills, the hairline borders and the
sheen. Those are design constants, not palette entries.

## The stale-picture problem, and the version stamp

Turning drawings into pixels is slow, so Plasma does it once and keeps the result
in a cache in the user's home folder:

```
~/.cache/plasma_theme_aquarius_v<version>.kcache
```

Note the version number in the filename. That is the whole invalidation
mechanism: ship a new version number, Plasma builds a fresh cache and deletes
every older one. Ship the same number with new artwork and people update the OS
and keep seeing the old panels, with nothing on screen to explain why.

Plasma's fallback check is "is the theme file newer than the cache?" — and that
one does not help us. AquariusOS is built as an image, and this style of OS
flattens file timestamps so that two builds of identical content are identical
byte for byte. The timestamps carry no information. **The version number is the
only signal we have.**

So it is stamped automatically, on every single build, by
`build_files/plasma-style-version.sh`, which build.sh calls with one line. It
writes something like `1.20260830.174231` — the UTC date and time of the build —
into both `metadata.json` and `metadata.desktop`, then checks its own work and
fails the build if either write missed.

### Why `metadata.desktop` exists next to `metadata.json`

This is the non-obvious part, and it is the reason that file must not be tidied
away.

Checked against KDE's own source (`ksvg`, `imageset_p.cpp`, function
`configFileForImageSet`): Plasma only bothers reading the theme's version number
if it can first find a file named `config` **or** a file named `metadata.desktop`
in the theme folder. It does **not** look for `metadata.json` at that step — that
file is read later, for the theme's details. No `metadata.desktop`, no version in
the cache filename, and the entire mechanism above quietly does nothing.

Nothing conflicts: where both files exist, KDE reads `metadata.json` for details
and `plasmarc` for settings, and this one is consulted only for its existence.
The build script keeps both version numbers in step so they can never disagree.

## Known limits — things no theme can fix

These come straight from the Tier 2 research (`docs/v2-shell-tier2-research.md`)
and are accepted, not bugs to file.

1. ~~**One blur radius for the whole system.**~~ **Moot since 2026-08-30 — the
   glass was removed and nothing here requests blur any more.** The original
   limit: the design asks for `blur(20px)` behind the panels and `blur(24px)`
   behind the popups; KWin has a single global blur strength, so those collapse
   into one value. It would matter again only if frost ever came back.

2. **Saturation moved out of the theme** — and is now moot twice over, because
   since 2026-08-30 there is nothing translucent for it to act on either. The
   finding below is still correct on its own terms and is kept for that reason.

   **Saturation moved out of the theme.** The design's `saturate(1.3)` used to be
   a per-theme setting. Verified 2026-08-30 against KDE source: Plasma 6.5 folded
   the old background-contrast effect into the blur effect, and by 6.7 the
   separate effect is gone — there is no `contrast` plugin left in KWin and the
   Wayland protocol that carried it (`ext-background-effect-v1`) advertises blur
   only. Saturation is now one system-wide KWin setting:
   `kwinrc  [Effect-blur]  Saturation=130`. The `[ContrastEffect]` block still in
   our `plasmarc` is therefore **inert today**; it is kept, with the correct
   values, in case KDE restores per-theme control. If the desktop does not look
   saturated enough, the fix is in `kwinrc`, not here.

3. **One text colour per surface.** KDE's colour system has a single foreground
   colour per group, so the design's three-tier text (`#FFFFFF` / `#B4BACD` /
   `#848CA6`) cannot be expressed for stock applets. Inside KDE's own popups,
   dimmer text is done by fading the main colour. Our exact three tiers only
   arrive on surfaces we build ourselves (Tier 2 wave 2).

4. **The shadow is symmetric-ish.** The design specifies `0 24px 80px` — a big
   soft shadow pushed 24px downwards. Ours is pushed down (the tiles below the
   window are taller than the ones above) but at a smaller overall spread, to
   keep the shadow tiles a sensible size. It reads correctly; it is not
   pixel-identical.

5. **Structure is out of scope.** Anything about *layout* rather than *surface* —
   the clock's arrangement, the width of the search box, what is inside a tray
   popup — is Tier 2 wave 3 (custom widgets), not this theme.

## Testing it

### What can be checked without a Linux machine

- Every SVG is well-formed XML (`xmllint --noout`).
- `metadata.json` is valid JSON.
- No absolute paths anywhere in the theme.
- The nine-piece assembly can be previewed by hand in a browser, which is how the
  corner geometry and the mask/shape agreement were checked while building this.

### What cannot

**Nothing here can actually be rendered on macOS.** Plasma, KWin and the blur are
Linux-only. CI proves the files ship; a real x86 machine is the only place the
glass can be seen.

### On real hardware

1. Boot the image and log in. The top bar and dock should already be glass —
   `LookAndFeelPackage=org.aquariusos.desktop` is set in the settings cascade, so
   the defaults file above is applied on a fresh account.

2. Confirm the theme is selected:
   **Settings → Colours & Themes → Plasma Style** should show *Aquarius*.

3. If you changed the artwork and the desktop still looks old, clear the cache by
   hand and restart the shell:

   ```
   rm -rf ~/.cache/plasma*
   plasmashell --replace &
   ```

   Needing this on an *installed update* is a bug — it means the version stamp
   did not change. Needing it while you are editing files by hand on a live
   machine is normal.

4. Things worth looking at specifically:
   - **The rounded corners of a popup.** Open the calendar. If there are four
     pale squares just outside the corners, the mask and the shape disagree.
   - **The panel opacity setting.** Right-click the dock →
     Enter Edit Mode → Opacity → Opaque. It must go solid *and stay ours* — if it
     suddenly looks like stock KDE, the `solid/` folder is not being found.
   - **Fractional scaling.** Set the display to 125% or 150% and look at the
     hairlines; Plasma 6.6-era reports mention softness at fractional scales.
   - **A maximised window.** With Adaptive transparency the panel should go
     solid behind it. (Since 2026-08-30 this is solid-to-solid and invisible —
     there is nothing to watch for. Kept in the list only so nobody reports its
     absence as a fault.)

## First bench findings — 2026-08-30

The image booted on real x86 hardware for the first time. Four photographs came
back: the whole desktop, a close-up of the dock, a close-up of a window corner,
and the calendar popup. This is what they showed and what was done about it.

**What was already right, and is not to be touched:** the theme is selected and
loads, the cache version stamp works, the KWin effects compile and load, the
settings cascade reaches KWin, and the clock reads correctly.

### 1. The dock's active app was a bright light box

The running, focused Steam icon sat in a glaring pale-blue rectangle that ran
the full height of the dock and painted straight over its hairline border. The
other icons looked washed out.

Nothing was broken. The theme shipped **no `widgets/tasks.svg`**, so Plasma fell
back to Breeze's, which paints those tiles in colours taken from the system
colour scheme — checked in libplasma, Plasma/6.7,
`src/desktoptheme/breeze/widgets/tasks.svg`:

| Breeze tile | Colour it borrows | Opacity |
|---|---|---|
| `focus-center` (the app you are using) | `ColorScheme-ButtonFocus` | **45%** |
| `normal-center` (running) | `ColorScheme-Text` | 15% |
| `hover-center` | `ColorScheme-ButtonHover` | 34% |

Our scheme sets the focus colour to starlight (`#8AB4FF`), a bright light blue.
Bright light blue at 45%, filling the whole tile, is the box in the photograph.

**Fixed** by writing our own `widgets/tasks.svg`. Its states, their names and
the way Plasma chooses between them are all documented at length in the file
itself; the short version is that the fills are literal design values instead of
scheme colours, they run from 4% to 16% white with a starlight tint reserved for
"this app is asking for you", and the artwork carries its own 4px inset so it
can never paint over the dock's border again.

Two things learned while doing it, both worth knowing before anyone touches that
file:

- **The task manager does not honour the panel's content margins.** It takes the
  full panel thickness. That is why the inset had to go into the artwork.
- **The design's centred 4px running dot cannot be drawn by a Plasma Style.**
  Plasma stretches the middle three of the nine pieces, so anything drawn there
  becomes as wide as the tile, and anything drawn in a corner piece keeps its
  size but is pinned to that corner. There is no piece that is both fixed-size
  and centred. (It is not drawn in code either — `Task.qml` in Plasma 6.7 has no
  `Rectangle` and no `Canvas`; Breeze's own running mark is likewise just the
  bottom edge of its `normal` frame.) Ours is a 2px starlight underline the
  width of the tile. If the dot matters, it needs the dock fork (T2-F), not this
  file.

### 2. The dock's outline had notches, and dark blocks sat around its ends

Two separate faults in `widgets/panel-background.svg`.

**The notches.** At every point where a rounded end met a straight run, the
hairline visibly changed thickness — a soft fat arc butting into a thin crisp
line. The corner pieces drew their hairline as a 1px *stroke* along a curve; the
edge pieces drew theirs as a 1px *filled rect* on whole-number coordinates. A
stroke along a curve is anti-aliased on both sides and spreads over about two
pixels of partial coverage, so the two never match. The top corners also carried
the 7% sheen all the way round, doubling their thickness against the plain
left and right edges they ran into.

**Fixed** by drawing every hairline as a filled band between two arcs — outer
radius 16, inner radius 15 — so corner and edge meet at the same whole-number
coordinate with nothing left to round differently, and by fading the sheen out
across the corner with a gradient, which is what the design's CSS `inset 0 1px 0`
highlight does anyway.

**The blocks.** All four *edge* pieces of the drop shadow faded the wrong way:
clear next to the panel, 45% black at the far edge, ending in a hard cut against
the wallpaper. The four *corner* pieces were correct. A correct corner meeting an
inside-out edge is why it read as blocks at the ends rather than as one uniformly
wrong shadow.

**Fixed** by swapping the four gradients. The same fault was in all seven
drawings in the theme, and all seven are fixed. The rule, written into each file:
**the gradient's solid end points at the window.**

**Content margins.** Icons were also crowding the glass. The floating variant's
`hint-*-margin` markers were 6px all round; they are now 9px down and 13px
across, which is the padding the V2 design actually draws on the dock
(`branding/design-system/AquariusOS Desktop Shell.html`, `padding: 9px 13px`).

### What was checked locally, and how

Everything above was verified in a browser before committing, by assembling the
nine pieces the way Plasma does — corners at natural size, edges stretched,
centre stretched — reading each piece's rectangle from its own bounding box, the
same measurement Plasma makes. Four assemblies:

- the **floating** variant at real dock proportions (620×54) and again zoomed 6×
  on each rounded end, which is what the square assembly used during the original
  build had missed;
- the **blur mask** over a red field — no red anywhere inside the corners, no
  black overhang, so mask and glass still agree;
- the **shadow** alone at 6×, confirming it now hugs the panel and fades outward
  with no step where corner meets edge;
- the **eight dock-tile states** side by side at a 54px dock height, confirming
  the borders come out at 15px all round (i.e. the invisible bounding-box
  rectangles are doing their job and the 4px inset survives).

The harness is a throwaway; what it proved is above. As ever, **nothing here can
be rendered by Plasma on macOS** — this checks geometry, not the real thing.

### Still open after this pass

- **How big the dock icons actually come out.** This is worth understanding
  before anyone changes either number, because the two margins do different
  jobs. The panel's 13px ends are visible — the dock is set to fit its content,
  so they are the padding at each end of the pill, and they match the design.
  The panel's 9px top and bottom are *not* what sizes the icons, because the
  task manager ignores the panel's margins; the icon height comes from
  `tasks.svg`'s own `normal-hint-*` markers instead. On the current 54px dock
  that works out at 54 − 4 − 7 = 43px, which is within a pixel of the design's
  44px icons. Confirm that on the bench with a ruler on a screenshot rather
  than trusting the arithmetic.
- Whether the 4px artwork inset in `tasks.svg` is the right amount at that icon
  size, and whether the running underline wants to be thinner.
- The dock's pinned icons — Files, Console, Settings — render as pale, flat
  squares. The desktop-file ids in the layout script (`org.kde.dolphin.desktop`,
  `org.kde.konsole.desktop`, `systemsettings.desktop`, `steam.desktop`) are all
  correct and all five slots do resolve to an icon, so this is not a naming
  problem. `kdeglobals` asks for `breeze-dark`. Whether that theme is actually
  present in the image, and what it draws at dock size, needs a look at the
  running machine — `ls /usr/share/icons` and the dock at 200% zoom. Not guessed
  at here.
- Is a 16px content inset right for KRunner, which draws its own padding on top of
  ours?
- ~~With blur switched off entirely (some handheld power profiles do this), the
  62%-opacity panel has no glass behind it. Is that acceptable, or should the
  theme grow a `translucent/` folder so the blur-on and blur-off cases can carry
  different opacities?~~ **Answered on 2026-08-30, and not in the way this
  question expected.** It turned out to be the situation on *every* machine, not
  just power-saving handhelds — the blur was never rendering anywhere — and the
  answer was no, it is not acceptable, so the transparency was removed instead.
  See "Glass removed" at the end of this document. No `translucent/` folder was
  needed.

---

## Glass removed — 2026-08-30

Royce's decision, taken the same evening the blur investigation closed. This
section is the record of it, and it overrides anything above that describes the
theme as see-through.

### What changed

Every background surface this theme draws is now **fully opaque**:

- the top bar and the dock (`widgets/panel-background.svg`)
- every popup — tray popups, the calendar, notifications, KRunner
  (`dialogs/background.svg`)
- the tooltip (`widgets/tooltip.svg`)
- the desktop card and its "translucent" twin (`widgets/background.svg`,
  `widgets/translucentbackground.svg`)
- the `solid/` copies of the first two, which are now byte-identical to them

`plasmarc` stopped asking for blur: `[BlurBehindEffect] enabled=false`.

### Why

The theme was designed as frosted glass — partly see-through, with the
compositor blurring whatever sat behind it. **The blur half never worked.** On
Bazzite 44 / Plasma 6.7, KWin does not draw the frost, and an evening of
systematic elimination on real hardware cleared every layer we can inspect: our
Plasma Style, our KWin effects, our whole settings cascade, the NVIDIA driver,
HDR, fractional scaling. A Wayland protocol trace showed the blur request going
out and being accepted. The one link nobody can observe from a terminal is
inside KWin itself. The full chart is in `docs/blur-known-issue.md`.

Frost and transparency are two halves of one effect, and only one of them
shipped. What a person actually saw was raw see-through: wallpaper and other
windows' text legible straight through the panel and, worse, through popups —
and popups are almost entirely words. That is not premium, it is unfinished.

Given a choice between "wait for an upstream fix that may never come" and
"ship a design that is complete without it", Royce chose the second.

### What stayed

Everything except the transparency, deliberately:

| Kept | Where |
|---|---|
| 16px rounded corners on panels and popups | theme artwork |
| 16px rounded corners on windows | KDE-Rounded-Corners, `kwinrc` |
| Drop shadows, all seven drawings | theme artwork, `breezerc` |
| Hairline borders (10% / 14%) and the 1px top sheen | theme artwork |
| Dark surface colours, radii, spacing, content-inset markers | theme artwork |
| The window outline at the design's hairline | `kwinrc [Round-Corners]` |
| The aurora wallpaper ("The Pour") | `branding/wallpapers/` |
| The masks, unchanged | theme artwork |

The design language is intact. One property of it is gone.

### The colours, and the arithmetic behind them

No colour was re-picked by eye. Each opaque fill is the surface's own recipe
finished off: the translucent design colour mixed with the desktop it sat on —
`void` = `#06070C`, from `branding/tokens.md` — computed channel by channel and
written into the SVG that uses it.

| Surface | Recipe | Sum | Result |
|---|---|---|---|
| top bar, dock | `#06070C` at 62% over `#06070C` | a colour mixed with itself | `#06070C` (unchanged) |
| popup, tooltip, "translucent" card | `#0D0F18` at 76% over `#06070C` | R 13·0.76 + 6·0.24 = 11.32 → 11 · G 15·0.76 + 7·0.24 = 13.08 → 13 · B 24·0.76 + 12·0.24 = 21.12 → 21 | `#0B0D15` |
| desktop card | `#10121C` at 86% over `#06070C` | R 16·0.86 + 6·0.14 = 14.60 → 15 · G 18·0.86 + 7·0.14 = 16.46 → 16 · B 28·0.86 + 12·0.14 = 25.76 → 26 | `#0F101A` |

Two of the three land a step or two **below** the token they started from, and
that is correct rather than a rounding accident: the very dark desktop showing
through was always pulling those surfaces down towards it. Freezing the
composite keeps what a person already saw, instead of quietly brightening the
whole shell by snapping back to the token.

### What deliberately kept its transparency

`widgets/tasks.svg` (the dock tiles, 4–16% white) and
`widgets/plasmoidheading.svg` (the 4% wash on a popup's title strip) are
**highlights, not glass**. They are painted on top of a surface that is itself
now solid, so they mix with that surface and never with the wallpaper — which
is what they visually did all along. Freezing them would hard-code today's
panel and popup colours into two more files for no visible gain, and they would
drift apart the first time either changed. Each file explains this at the top.

The same applies to every hairline and sheen: they keep their alpha because
they layer on the opaque fill inside the same drawing. Same pixels either way.

### `solid/` is now a byte-identical copy

That folder exists so the panel's **Opacity → Opaque** setting has AquariusOS
artwork to load instead of stock Breeze. It used to be the opaque version of
two see-through drawings. Both are opaque now, so there is nothing left for it
to express differently, and keeping two near-identical files in step by hand is
a bug waiting to happen. It is a straight copy.

**Do not delete it.** With nothing there, "Opaque" drops the user into Breeze
mid-session. If you edit either root file, copy it over its `solid/` twin in
the same change — both files say so at the top, and this is why the paths in
their comments are written from the repo root rather than as `../..`.

### The layout script still says "translucent", on purpose

`org.kde.plasma.desktop-layout.js` sets `topBar.opacity = "translucent"` and
`dock.opacity = "translucent"`. That was left alone.

The value is not a transparency amount; it is a **choice of artwork folder**.
Plasma's `Panel.qml` maps `translucent` to the theme's root drawings and
`opaque` to its `solid/` folder. Since the root drawings are now opaque, that
line already produces a solid panel — and since `solid/` is a byte-identical
copy, all three settings now land on the same pixels. There is nothing to fix,
and changing it would be churn that reads like a behaviour change.

### The design mirror still shows glass, and is not to be edited

`branding/design-system/` is a **mirror** of the Claude Design project
"AquariusOS Core Identity", direction "Flow State". It still draws the shell
with `backdrop-filter` glass, because the design has not been re-cut.

**That divergence is deliberate and the mirror stays as it is.** Design changes
are made in the Claude Design project and re-exported here; editing the mirror
by hand would create a second source of truth and break the one rule
`branding/tokens.md` opens with ("if they ever disagree, the design project
wins"). What has happened is narrower than a design change: an implementation
found that one property of the design cannot be delivered on this platform, and
shipped without it.

So, precisely: **the artwork in `system_files/.../desktoptheme/aquarius/` is
what ships; the mirror is the design of record.** They disagree about exactly
one thing — transparency — and this is it. If the design is ever re-cut without
glass, the mirror gets re-exported and this paragraph can go.

### If the glass ever comes back

The retest habit stands: after any Bazzite rebase that bumps Plasma, click the
clock and look at the calendar popup — see `docs/blur-known-issue.md`. If frost
ever renders again, restoring it takes **three** things, and none of them alone
does anything:

1. **The theme's translucency** — revert this branch's theme commits (the
   opaque fills and the `plasmarc` change). Opaque artwork with blur switched
   on stays opaque.
2. **`[BlurBehindEffect] enabled=true`** in `plasmarc`, which is half of step 1
   but worth naming separately because it is the half people forget.
3. **The window-glass effect**, if application windows are meant to be frosted
   too — that is Better Blur DX, removed from the image on the same day. Its
   recipe is in this branch's history and its rationale is written up in
   `docs/kwin-effects-layer.md`, "Glass removed".

### What still needs a bench

Nothing in this section was seen on a screen. Everything below the surface
maths was checked in a browser by assembling the nine pieces the way Plasma
does, which proves geometry and opacity and nothing else. **Plasma cannot be
rendered on macOS.** The checklist for the next boot is in this document's
"Testing it" section, plus:

- the popup surface at `#0B0D15` against the wallpaper — is it dark enough to
  read against, and does it still read as a distinct layer above the panel?
- the dock and top bar now being exactly the desktop's own colour: does the
  dock still separate from the wallpaper by its hairline and shadow alone, or
  does it disappear over the wallpaper's dark corners?
- the card at `#0F101A` on the desktop.
- the panel's Opacity menu: all three settings should now look identical.
