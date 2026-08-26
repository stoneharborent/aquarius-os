# Design-system mirror — what this folder is

This folder is a **local copy of the Claude Design project "AquariusOS Design System"**
(claude.ai/design project `ba3a45ce-472d-45eb-b017-0ea0bddc62c1`), pulled down on
2026-08-25 so the designs live beside the code that implements them.

**The rules, in plain language:**

1. **The design is decided in the Claude Design project.** This folder is a snapshot,
   not a place to design. If you want to change how something looks, change it in the
   design project first, then re-sync this folder.
2. **`../tokens.md` is still the law for values.** The token CSS files in `tokens/`
   here agree with `tokens.md` exactly (verified at import). If they ever disagree,
   the design project wins — update both `tokens.md` and this mirror in the same
   sitting.
3. **These HTML files are design artboards, not app code.** Open them in a browser to
   see the design. Nothing in the OS build reads them; they exist so an agent (or
   Royce) can look at the intended screen while building the real thing.

## What each file is

| File | What it shows |
|---|---|
| `AquariusOS Core Identity.html` | The master identity sheet: logo, palette, type, surface stacks, wallpapers (The Pour + the Still Water / Overdrive mood variants), and the boot-to-desktop journey (GRUB → Plymouth → SDDM → first boot → desktop). |
| `AquariusOS Handheld Mode.html` | The handheld/tablet home screen — touch-first, same layout drives touch AND controller. Plain-language spec: `../../docs/handheld-mode-design.md` (in the project root's `docs/`). |
| `AquariusOS First Boot Chooser.html` | First-boot "What will you do with this machine?" — Gamer / Creator / Both. Feeds the Phase 2 first-boot task. |
| `AquariusOS Identity Exploration.html` | Historical: the 3 competing directions (Deep Water, Constellation, Flow State). Flow State won. Kept for the record. |
| `styles.css` + `tokens/*.css` | The design tokens as CSS. Same values as `../tokens.md`. `tokens/fonts.css` loads Google Fonts for browser preview only — the OS ships its fonts locally. |
| `assets/logo.svg`, `assets/logo-mono.svg` | Same marks as `../logo.svg` / `../logo-mono.svg` (verified identical at import). |
| `_ds_manifest.json`, `_adherence.oxlintrc.json`, `_ds_bundle.js`, `thumbnail.html` | Machine files the Claude Design app maintains (token index, lint rules that forbid raw hex/px values, canvas bundle, project thumbnail). Don't hand-edit. |

## How to re-sync

From a Claude session: read the project with the DesignSync tool (project id above) and
copy every file here byte-for-byte, then re-verify `tokens/` still matches `tokens.md`.
