# Design-system mirror — what this folder is

This folder is a **local copy of the Claude Design project "AquariusOS Design System"**
(claude.ai/design project `ba3a45ce-472d-45eb-b017-0ea0bddc62c1`), so the designs live
beside the code that implements them.

- First pulled down **2026-08-25** (V1 — identity only).
- Re-synced **2026-08-30** to **V2**, which is the whole desktop experience: the shell and
  its overlays, five first-party apps, a rebuilt handheld mode, and one token change.

**The rules, in plain language:**

1. **The design is decided in the Claude Design project.** This folder is a snapshot,
   not a place to design. If you want to change how something looks, change it in the
   design project first, then re-sync this folder.
2. **`../tokens.md` is still the law for values.** The token CSS files in `tokens/`
   here agree with `tokens.md` exactly (re-verified at the V2 sync). If they ever
   disagree, the design project wins — update both `tokens.md` and this mirror in the
   same sitting.
3. **These HTML files are design artboards, not app code.** Open them in a browser to
   see the design. Nothing in the OS build reads them; they exist so an agent (or
   Royce) can look at the intended screen while building the real thing.

## What each file is

| File | What it shows |
|---|---|
| `AquariusOS Desktop Shell.html` | **The live shell.** Glass top bar, centred dock, drive tiles down the right edge, and every overlay — click the search, clock, tray or Drop icons; Esc closes. This is the master reference for the desktop. |
| `AquariusOS Shell Quick Settings.html` | The tray panel — Wi-Fi / Bluetooth / Focus / Game Mode toggles and the sound and brightness sliders. It is a one-line file that just opens the Desktop Shell at that overlay. |
| `AquariusOS Shell Notifications.html` | The clock panel — notification rows, "Clear all", and the big clock footer. Same trick: it opens the Desktop Shell at that overlay. |
| `AquariusOS Shell Search.html` | "Flow Search" — KRunner with every scrap of command syntax hidden. Same trick again. |
| `AquariusOS App Files v2.html` | Files, built on Dolphin: sidebar, info panel, Miller columns, split view, the Quick View overlay and the filter bar. The toolbar toggles in the mock really work. |
| `AquariusOS App Settings.html` | Settings, built on KDE System Settings, reorganised into plain-language categories. Shows the Look & Feel page. |
| `AquariusOS App Console.html` | The terminal. **Design fiction warning:** the friendly `aq` commands in this artboard are not being built. Royce ruled on 2026-08-30 that Console ships as a themed Konsole only. Read this file for the *look*, not the feature list. |
| `AquariusOS App Media v3.html` | Media, built on Dragon Player — one QuickTime-style window with a floating glass control bar. |
| `AquariusOS App Drop.html` | Drop, built on LocalSend — the radar view and the receiving/sending rail. Device to device on your own network. |
| `AquariusOS Handheld Mode.html` | The handheld/tablet home screen — touch-first, and the same layout drives touch AND controller. Plain-language spec: `../../docs/handheld-mode-design.md` (in the project root's `docs/`). |
| `AquariusOS First Boot Chooser.html` | First-boot "What will you do with this machine?" — Gamer / Creator / Both. Feeds the first-boot task. |
| `AquariusOS Core Identity.html` | The master identity sheet: logo, palette, type, surface stacks, wallpapers (The Pour + the Still Water / Overdrive mood variants), and the boot-to-desktop journey (GRUB → Plymouth → SDDM → first boot → desktop). |
| `AquariusOS Identity Exploration.html` | Historical: the 3 competing directions (Deep Water, Constellation, Flow State). Flow State won. Kept for the record — it is **not** part of V2. |
| `styles.css` + `tokens/*.css` | The design tokens as CSS. Same values as `../tokens.md`. `tokens/fonts.css` loads Google Fonts for browser preview only — the OS ships its fonts locally. |
| `assets/logo.svg`, `assets/logo-mono.svg` | Same marks as `../logo.svg` / `../logo-mono.svg` (re-verified at the V2 sync — identical apart from a trailing newline). |
| `_ds_manifest.json`, `_adherence.oxlintrc.json` | Machine files the Claude Design app maintains (a token index, and lint rules that forbid raw hex/px values). Don't hand-edit — see the note at the bottom about the V2 sync. |

## Two things V2 settled

**Sora stays the display font.** The V2 handoff notes carried a line saying "the locked
identity spec is Outfit for display — audit and reconcile". Royce settled it on
**2026-08-30: Sora wins.** No font anywhere changes. Treat any future mention of Outfit
as closed unless Royce reopens it.

**The token change.** V2 brightens the dark theme's text and changes nothing else:

| Token | V1 | V2 |
|---|---|---|
| `text-1` | `#EDEFF7` | `#FFFFFF` |
| `text-2` | `#8A90A6` | `#B4BACD` |
| `text-3` | `#565C72` | `#848CA6` |

Light theme, typography, spacing and effects are **byte-identical** to V1 (checked with a
diff, not assumed). Note the trap: the border tokens are written as
`rgba(237,239,247,…)`, which is the *old* `text-1` in decimal — but borders did **not**
change. If you are hunting for old values, only text roles move.

## One place we deliberately differ from the design

The V2 Desktop Shell marks the top-bar Aquarius logo as **inert** — the app launcher was
removed from the design. AquariusOS **keeps** a launcher behind that logo (KDE's
`kickerdash`, the full-screen app grid). It looks identical to the design — same mark,
same place — and it preserves the GNOME-flow decision of 2026-08-26 that an app grid is
how you find things you have not pinned. It costs nothing to remove later. The same note
is written where the launcher is added, in
`../../system_files/usr/share/plasma/look-and-feel/org.aquariusos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js`.

## What changed in this folder at the V2 sync (2026-08-30)

- **Added**: the Desktop Shell, the three shell state-cards, and the five app artboards.
- **Replaced**: `AquariusOS Handheld Mode.html`, `AquariusOS First Boot Chooser.html` and
  `AquariusOS Core Identity.html` — the V2 versions supersede the V1 ones.
- **Kept**: `AquariusOS Identity Exploration.html` (history), `assets/`, and
  `tokens/fonts.css`. The V2 bundle ships no `fonts.css`, but its `styles.css` still
  imports one, so ours stays. Its font list — Sora, Inter, JetBrains Mono — was checked
  against every V2 file and still matches; no file asks for a fourth font.
- **Deleted**: `_ds_bundle.js` and `thumbnail.html`. Both were V1 canvas artifacts from
  the old export, neither exists in the V2 bundle, and nothing reads them.
- **`_adherence.oxlintrc.json` left exactly as it was.** It was checked line by line: it
  contains no colour values at all, only token *names* and the three font families, and
  every one of those is still correct after V2. Nothing in it went stale.
- **`_ds_manifest.json` hand-patched, minimally.** The V2 bundle ships no manifest, and
  the V1 one had the old text hex values in it — which would have broken rule 2 above.
  Three things were changed and nothing else: the three dark-theme text values, the card
  index (rebuilt from the `@dsCard` comment at the top of each artboard), and
  `hasThumbnailHtml` → `false` now that `thumbnail.html` is gone. The next real export
  from the design project will overwrite it properly.

## How to re-sync

From a Claude session: read the project with the DesignSync tool (project id above) and
copy every file here byte-for-byte, then re-verify `tokens/` still matches `tokens.md`.
Keep `AquariusOS Identity Exploration.html`, `assets/` and `tokens/fonts.css` — the
export does not include them.
