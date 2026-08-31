# The Aquarius Desktop — what a fully custom desktop environment would take

*Synthesized 2026-08-31 by Fable from three parallel research passes (case studies with primary
sources, a best-features survey of eight environments, and a full risk register — raw findings
preserved in the session transcript; every load-bearing claim below was VERIFIED against primary
sources by those passes). Companion file: `ice-theme-tokens.md` (the new color direction).
This branch is a PLAN — nothing here is scheduled work until it appears in ROADMAP.md.*

---

## The question, and the one-paragraph answer

**"What would it take to make my own fully custom desktop environment, using what works and
taking the best from KDE, GNOME, and everyone else?"**

The full from-scratch path (own compositor + own toolkit + own shell + own apps) is priced by
COSMIC: a funded team of ~6–12 expert engineers — including a maintainer of the compositor
library they used — took **3 years to reach an alpha and 4+ years to reach 1.0**, and the slow
parts (compositor correctness across GPUs, text rendering, input methods, accessibility,
XWayland) are validation-bound, not code-generation-bound, so AI agents compress them least.
**But the research also found a proven modern path that gets ~9 of your 12 design pillars with
1–3 builders in 6–18 months:** build the **Aquarius Shell** as one coherent QML application —
your bar, dock, overlays, search, notifications — speaking only *standardized* Wayland protocols,
riding an inherited compositor. A whole 2025–26 wave of small teams ships designed desktops
exactly this way (Quickshell shells; Budgie 10.10 runs its entire DE on someone else's
compositor; Deepin's Treeland is the corporate-scale version: wlroots underneath, all-QML shell
on top). The shell is where every one of your design pillars lives; the compositor is where
none of them do.

## What "a desktop environment" actually decomposes into

| Layer | What it is | Who has ever built one from scratch |
|---|---|---|
| Compositor | windows, input, displays, XWayland, HDR, NVIDIA | System76 (4 yrs, funded), Hyprland/niri (1–2 yrs, compositor ONLY) |
| **Shell** | **bar, dock, launcher/search, overlays, notifications UI, OSDs — everything the user sees** | **Small teams, routinely, in months — the 2025–26 pattern** |
| Services | settings app + the glue to NetworkManager/BlueZ/UPower/PipeWire, portals, polkit, keyring, lock, autostart, systray | The forgotten 70% — this is what separates a "rice" from a DE |
| Apps | files, settings, terminal, media | Tier 3 already plans these (Dolphin/Dragon/LocalSend bases) |

Your design system is ~entirely Shell + Apps. The brutal, undifferentiated work is
Compositor + Services — which is exactly what can be inherited.

## The five paths, priced by people who lived them

| # | Path | Precedent | Real cost | Verdict |
|---|---|---|---|---|
| 1 | Full from-scratch (compositor+toolkit+shell+apps) | COSMIC | ~10 experts × 4+ yrs to 1.0 | **Documented dead end for a solo operation** |
| 2 | Own compositor only | Hyprland, niri | 1–3 devs × 1–2 yrs — and you have a compositor, not a DE | Not a product by itself |
| 3 | Fork KWin/Mutter + own shell | Deepin (KWin fork → **abandoned after ~5 yrs**), UKUI, Cinnamon, Budgie v0 | Continuous "fork tax"; both flagship examples restructured to escape it | **Proven treadmill — avoid** |
| 4 | **Custom shell on an inherited compositor, via standardized protocols** | Budgie 10.10 on labwc; Sway ecosystem; Quickshell shells; Treeland (maximal) | **1–3 devs × 6–18 months to a designed, complete-feeling DE** | **The differentiation track** |
| 5 | Themed/extended Plasma (today's AquariusOS) | us, dozens of distros | weeks–months per increment | **The shipping track — keep it** |

Key case-study lesson shaping path 4: every team that built its shell against **KWin's private
seam** ended up forking KWin and later fleeing (Deepin's own words: third-party WM forks carry
"destructive adjustments, synchronization problems, and maintenance costs"). Every team that
built its shell against **standardized protocols** (layer-shell, ext-session-lock, SNI,
foreign-toplevel, the portals) kept a shell that runs on *any* modern compositor. **The shell
must be compositor-agnostic. That is the whole strategy.**

## The recommended strategy: two tracks, one hedge

### Track 1 — SHIP (unchanged): themed Plasma, Tiers 2–3 as planned
The current work (theme, Wave 2 widgets, Tier 3 apps) keeps shipping. It is real product today,
and per the risk register it inherits, for free, everything a creator OS cannot launch without:
the OBS/screen-recording portal, Resolve-grade HDR/ICC color (KWin is the ONLY mature base for
this in 2026), NVIDIA support, XWayland maturity for Steam and Resolve (both still X11 apps),
accessibility, input methods.

### Track 2 — PROTOTYPE: the Aquarius Shell (compositor-agnostic QML)
A new repo (`aquarius-shell`): one QML application (Quickshell or LayerShellQt as the base —
first engineering decision of the track) implementing the V2 design system's shell — top bar,
dock, Quick Settings, notifications, Flow Search palette — as layer-shell clients in the **Ice
theme** from day one. Two run targets from the start:
- **On the shipped OS**: layer-shell clients render fine on KWin — pieces of the shell can be
  A/B'd against their plasmoid twins on real hardware immediately.
- **In an experimental "Aquarius Session"**: the same shell on an inherited wlroots-world
  compositor (labwc = boring and Budgie-proven; niri = brings the scrollable-strip paradigm)
  as a second session on the login screen, next to Plasma. Nobody's daily driver until it earns it.

Wave 2's plasmoid work is NOT wasted by this: the widgets' QML internals (toggle logic, model
wiring, layouts) port; only the plasmoid packaging shell differs. The design system does not care
which host renders it.

### The hedge that makes this safe
Plasma stays installed as a **fallback session forever** (it's in the Bazzite base — keeping it
is free; *removing* it is the expensive direction). If the Aquarius Shell session breaks, a
creator drops to stock Plasma and keeps working. The compositor under the Aquarius Session can
be swapped later (labwc → niri → someday our own smithay compositor, the Treeland sequence run
in the safe order: shell first, compositor last) without rewriting the shell — that is what the
standardized-protocols rule buys.

## Best-of-everything: what we take and from whom (survey highlights)

| Pillar | Donor | The take |
|---|---|---|
| Seamless simplicity | elementary + ChromeOS | consent-based Secure-Session posture; plain human copy as a hard style rule |
| One search box | KRunner (engine) + Deepin Grand Search (ceiling) | Flow Search UI over KRunner's runner API now; local semantic index later — **AnalysisKit's aq1 store is the footage-search index nobody else has** |
| Overview/gestures | GNOME | the one pillar genuinely needing deeper compositor control — deferred to the Aquarius Session |
| Notifications | GNOME 48/49 | stacked-by-app model, inline actions |
| Quick Settings | GNOME 49 + elementary | contextual sliders, one consolidated panel |
| Tiling | COSMIC (per-workspace toggle) + Windows 11 (discoverable snap) + niri (strip, later/optional) | |
| Onboarding | **open field** — plasma-setup as raw material | Gamer/Creator/Both chooser: nobody does personas; we would define it |
| Creator-first desktop | **open field** | render-aware PiP, recording-privacy surfaced plainly, semantic footage search — no donor exists; this is the moat |
| Motion | Hyprland (vocabulary) | ~70% achievable in KWin effects; 90%+ in our own shell |

## Two findings that change the design regardless of path
1. **The global menu bar is a broken promise in 2026.** Only Qt apps export menus; GTK, Electron
   (OBS, Discord), and browsers export nothing — an empty File/Edit/View bar for exactly the apps
   creators live in, on every architecture. The V2 top bar should be redesigned to not depend on
   app-exported menus (app name + our own surfaces instead). → Claude Design project decision.
2. **Bazzite's Game↔Desktop switching hardcodes `plasma.desktop`** (`os-session-select`,
   `bazzite-autologin`). The Aquarius Session needs a small permanent patch to that machinery,
   re-verified each Bazzite update. Known cost, budgeted.

## The Ice direction
`ice-theme-tokens.md` holds the full extraction (Ice light + Midnight dark + 4 accents + the
25-swatch Zodiac palette) and four open questions for Royce — the big one: **Ice is a light
theme; adopting it as the main theme makes AquariusOS light-first** (near-unique in Linux) with
Midnight as dark mode. The Aquarius Shell prototype adopts Ice from day one either way; a cheap
near-term Ice/Midnight recolor of today's Plasma theme is also on the table independent of
everything above.

## Staged roadmap with decision gates

- **Phase P0 (now):** this plan. Royce answers the Ice questions + blesses/adjusts the strategy.
- **Phase P1 (~first month of the track):** scaffold `aquarius-shell`; pick Quickshell vs
  LayerShellQt (spike both for a week); ship ONE piece — the Ice top bar — running on the
  current OS beside plasmashell's. **Gate:** does it feel better than the themed panel?
- **Phase P2 (months 2–4):** dock, Quick Settings, notifications, Flow Search palette in the
  shell; the experimental Aquarius Session (labwc or niri) boots on the bench with the full
  shell + portals configured (`portals.conf` mixing -gtk + -wlr). **Gate:** OBS records, Steam
  desktop works, a full workday survives on the bench.
- **Phase P3 (months 4–9):** the Services layer — settings surfaces (plain-language, backed by
  NetworkManager/BlueZ/UPower directly), session polish, lock/idle, OSK for handheld, the
  Bazzite session-select patch, Flatpak theme extensions. **Gate:** a fresh install where a
  stranger never needs the Plasma fallback.
- **Phase P4 (later):** consider the session default flip per variant; consider the scrollable
  handheld mode; consider (only then) an own compositor under the stable shell.
- **Standing rule:** every phase ships behind the Plasma fallback; no burn-the-boats moments.

## What I would NOT do (and why, in one line each)
- Full from-scratch (path 1): COSMIC's 4 funded years, and our pillars don't live there.
- Fork KWin (path 3): Deepin spent five years proving it, then left.
- Replace plasmashell on unforked KWin: unsupported seam KDE may move any release.
- Remove Plasma from the image: the fallback is free insurance; removal is a permanent fight.
- Bet any feature on KDE Activities: upstream's own commitment is ambiguous.
