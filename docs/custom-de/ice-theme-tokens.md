# The Ice theme — extracted from Aquarius Writer, prepared for the OS

*Extracted 2026-08-31 by Fable from `Branches/Apps/AquariusWriter/swift/AquariusWriter/Theme/Theme.swift`
(the app's single source of truth for color). This file is the OS-side reference: the raw values,
what they mean, and the open design questions before any OS surface adopts them. It lives on the
`research/custom-de` branch — nothing on main uses these values yet.*

## What Ice is

Aquarius Writer ships two companion themes built from one 25-color brand palette (the
"Aquarius Zodiac" set): **Ice** — a cool LIGHT theme ("soft azure-tinted papers … with deep-ocean
navy ink for crisp contrast") — and **Midnight** — its dark twin ("near-black navy/indigo grounds
with ice-blue ink, so the electric accents read like light under water"). Royce named **Ice** as
the source for the OS's new main color theme (2026-08-31). Both are recorded here because an OS
needs a dark mode, and Midnight is Ice's designed counterpart from the same palette.

## Ice (light) — surfaces and ink

| Role (Writer's name) | Hex | Meaning for an OS |
|---|---|---|
| `bg` | `#EAF1F8` | The ground — desktop-adjacent surfaces, window backgrounds |
| `bgSoft` | `#DFEAF4` | Slightly recessed areas |
| `surface` | `#F7FBFE` | Cards, popups — the brightest paper |
| `surfaceAlt` | `#E4EDF6` | Alternate/secondary cards |
| `panel` | `#F0F6FC` | Panels/chrome |
| `sidebar` | `#EAF1F8` @ 86% | (Writer uses translucency here — the OS went opaque; composite if adopted) |
| `ink` | `#16273A` | Primary text — deep navy, not black |
| `inkProse` | `#0E1B2A` | Long-form text (deepest) |
| `inkSoft` | `#47586B` | Secondary text |
| `inkMute` | `#7C90A4` | Tertiary/disabled |
| `line` | `#16273A` @ 10% | Hairlines |
| `lineStrong` | `#16273A` @ 18% | Emphasized hairlines |
| semantic | success `#1F9E8C` · warn `#C2792E` · danger `#C8463B` · starred `#C28B22` | tuned for light ground |

## Midnight (dark twin) — surfaces and ink

| Role | Hex | Note |
|---|---|---|
| `bg` | `#0B1220` | Deep-ocean navy (vs. today's OS void `#06070C` — bluer, slightly lighter) |
| `bgSoft` | `#111A2B` | |
| `surface` | `#121C2E` | |
| `surfaceAlt` | `#1B2940` | |
| `panel` | `#152033` | |
| `ink` | `#DCE9F4` | Ice-blue text |
| `inkSoft` / `inkMute` | `#93A7BC` / `#5C6E82` | |
| `line` / `lineStrong` | `#DCF3FF` @ 8% / 16% | Hairlines are tinted ice, not white |
| semantic | success `#5FC9B0` · warn `#E0A35A` · danger `#E07B7B` · starred `#E6B947` | |

## Accents (theme-aware pairs — light variant deepened for contrast on paper)

| Accent | On Ice | On Midnight |
|---|---|---|
| **Aquarius Blue** (default) | `#2C8FC4` | `#00BFFF` (Deep Sky Blue) |
| Indigo | `#6E2BE0` | `#9B82FF` |
| Turquoise | `#0E9AA0` | `#40E0D0` |
| Aquamarine | `#12A07C` | `#7FFFD4` |

## The full Aquarius Zodiac palette (brand source-of-truth, 25 swatches)

electricBlue `#7DF9FF` · turquoise `#40E0D0` · aquamarine `#7FFFD4` · aquariusBlue `#3AA2D6`
(Pantone "Aquarius Blue") · palatinateBlue `#2949FF` · electricIndigo `#6F00FF` · deepSkyBlue
`#00BFFF` · azure `#007FFF` · cerulean `#00A4E4` · robinEgg `#00CCCC` · cyan `#00FFFF` ·
babyBlue `#89CFF0` · powderBlue `#B0E0E6` · iceBlue `#DCF3FF` · silver `#C0C0C0` · platinum
`#E5E4E2` · whiteSmoke `#F5F5F5` · mintCream `#F5FFFA` · seafoamGreen `#9FE2BF` · paleTurquoise
`#AFEEEE` · lightCyan `#E0FFFF` · azureishWhite `#DBE9F4` · moonstoneBlue `#73A9C2` · mediumTurq
`#48D1CC` · electricPurple `#BF00FF`

## Open design questions (for Royce, before anything adopts Ice)

1. **Light-first?** Ice is a light theme. Today's OS identity (Flow State: Starlight `#8AB4FF`
   on near-black) is dark-first. Adopting Ice as the MAIN theme means a light-first OS —
   genuinely distinctive (almost no Linux desktop leads with light), and a real brand statement —
   with Midnight as the dark mode. Confirm that reading, or whether "from my Ice theme" means
   the Ice/Midnight *family* with Midnight leading.
2. **Relationship to the V2 design system.** The V2 tokens (Starlight/Nebula/void) are the locked
   identity of record in the Claude Design project. An Ice-based OS theme supersedes or forks
   that identity — a design-project decision, not just a code change. The Vault rule stands:
   design is decided in Claude Design; this doc only stages the raw material.
3. **Accent default.** Writer defaults conceptually to Aquarius Blue. Today's OS accent is
   Starlight `#8AB4FF` (which is close to babyBlue `#89CFF0` in the Zodiac set). Pick: Aquarius
   Blue `#2C8FC4`/`#00BFFF` as the OS accent, or keep Starlight and fold it into the Zodiac story.
4. **Where Ice lands first.** Options: (a) the custom-DE plan only (this branch's purpose);
   (b) also retrofit today's Plasma theme with an Ice light scheme + Midnight dark scheme as a
   nearer-term drop — cheap now that the theme pipeline exists (color scheme + solid SVG recolors).
