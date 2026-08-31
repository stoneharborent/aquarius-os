# The Aquarius Plasma Style — the glass desktop

*Written 2026-08-30. Tier 2, track T2-A. The research this implements is
`docs/v2-shell-tier2-research.md`, "Layer 1".*

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
fixes regardless of palette: the smoked-glass fills, the hairline borders and the
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

1. **One blur radius for the whole system.** The design asks for `blur(20px)`
   behind the panels and `blur(24px)` behind the popups. KWin has a single
   global blur strength, so those collapse into one value. It is set in
   `kwinrc`, which belongs to the KWin effects track (T2-B), not to this theme.

2. **Saturation moved out of the theme.** The design's `saturate(1.3)` used to be
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
     solid behind it.

## Open questions for the first hardware test

- Does the dock's 16px corner line up with the icon spacing once the dock fork
  (T2-F) changes icon size? The panel's content margins are set to 6px inside the
  floating variant and may want tuning against real icons.
- Is a 16px content inset right for KRunner, which draws its own padding on top of
  ours?
- With blur switched off entirely (some handheld power profiles do this), the
  62%-opacity panel has no glass behind it. Is that acceptable, or should the
  theme grow a `translucent/` folder so the blur-on and blur-off cases can carry
  different opacities? The mechanism exists; we have not used it.
