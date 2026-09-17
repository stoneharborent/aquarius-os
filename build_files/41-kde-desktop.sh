#!/usr/bin/bash
# ==============================================================================
# STEP 4b — The second desktop: a short list of KDE Plasma, chosen on purpose
# ==============================================================================
# WHY THERE ARE TWO DESKTOPS NOW
#
# Until 15 September 2026 AquariusOS was building its OWN desktop — the Aquarius
# Session, a shell we wrote on the labwc window manager. On that day Royce
# stopped that work:
#
#   "I want the OS to no longer try and make its own DE and instead rely on both
#    GNOME and KDE Plasma. I want both included so I can test which will work
#    better for the final version."
#
# So this image now ships TWO complete, stock desktops side by side, and the
# login screen offers both. Everything else AquariusOS does — the automount, the
# Installer, the Updater, the welcome, Resolve, the Mac keyboard, the gaming
# layer, the boot branding — sits UNDERNEATH the desktop and is the same on
# either one. The desktop is a layer, not the product.
#
# The decision, with the full feature map:
#   ../docs/decision-2026-09-15-two-desktops.md
# The plain-language guide for a person using the machine:
#   docs/restart/desktops.md
#
# ------------------------------------------------------------------------------
# WHY THIS IS A LIST AND NOT `dnf group install "KDE Plasma Workspaces"`
# ------------------------------------------------------------------------------
# The same reason as GNOME in step 4 (40-gnome-desktop.sh — read that one first,
# this file is written to match it). Fedora's KDE group is enormous: a mail
# client, a calendar, an address book, a chat app, a music player, a games
# collection, an education collection, a web browser of its own. On a machine
# whose job is editing video, every one of those is something to uninstall,
# something to update, and something to wonder about in the app launcher.
#
# The rule for adding to this list is step 4's rule: does the machine fail at
# something a person will actually do without this? A file manager and a
# terminal pass that test. A card game does not.
#
# ⚠️ WHAT IS DELIBERATELY MISSING, so nobody thinks it was forgotten:
#
#   sddm                  KDE's own login screen. AquariusOS has ONE login
#                         screen — GDM — and it lists both desktops. Two login
#                         managers fighting over the screen is a black screen
#                         with no way in, which this project has already lived
#                         through twice. This step FAILS THE BUILD if sddm ever
#                         arrives, even as somebody else's dependency.
#   plasma-discover       KDE's app store. Aquarius Installer is the app store
#                         on this machine (step 7e), and 65-installer.sh already
#                         hides the older chooser for exactly this reason: two
#                         app-store-shaped icons is how somebody ends up in the
#                         wrong one. This step fails the build if it appears.
#   plasma-welcome        KDE's own welcome wizard. AquariusOS has its own
#                         welcome (step 7d-bis) and it opens at the first login.
#                         Two welcome windows at the one login that matters is a
#                         fault nobody would see until it was too late. It is a
#                         *recommended* package of plasma-workspace, so it is
#                         excluded by name below and then read back.
#   plasma-workspace-x11  The X11 half of Plasma. AquariusOS is a Wayland
#                         machine; X11-only apps (DaVinci Resolve) run through
#                         XWayland, which step 3 installs.
#   plasma-print-manager  Printing is not on this machine's job list — the same
#                         call step 4 makes for CUPS.
#   kdepim, kdegames, kdeedu, kmail, korganizer, kontact, elisa, juk, dragon
#                         All in Fedora's KDE group. None of them are why
#                         anybody would install this operating system.
#
# ⚠️ TWO PACKAGE NAMES THAT NO LONGER EXIST IN FEDORA 44, AND THE TRAP IN THEM.
#
# Every guide on the internet, and the first draft of this file, asks for
# `plasma-workspace-wayland` and `kwin-wayland`. Neither is a package in Fedora
# 44 any more:
#
#   plasma-workspace-wayland   gone. Wayland is now IN `plasma-workspace`, which
#                              is what owns /usr/bin/startplasma-wayland and
#                              /usr/share/wayland-sessions/plasma.desktop. The
#                              split that survives is the other way round:
#                              `plasma-workspace-x11` is the optional extra.
#   kwin-wayland               gone. `kwin` owns /usr/bin/kwin_wayland.
#
# Asking for a package that does not exist makes `dnf install` stop with
# "no match", so this is a loud failure rather than a quiet one — but it would
# cost a fifteen-minute build to find out. Checked against Fedora 44's own
# package metadata on 2026-09-15; if a later Fedora splits them apart again,
# the read-back at the bottom of this file is what will say so.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# ------------------------------------------------------------------------------
# The desktop itself
# ------------------------------------------------------------------------------
#   plasma-desktop          the Plasma shell: the panel, the task bar, the
#                           application launcher, the widgets, and the settings
#                           pages for keyboard, mouse, theme and workspace
#                           behaviour. This is the thing a person means when
#                           they say "KDE".
#   plasma-workspace        the part that STARTS a session. It owns
#                           /usr/bin/startplasma-wayland and the file GDM reads,
#                           /usr/share/wayland-sessions/plasma.desktop. Without
#                           it the login screen has no Plasma to offer.
#                           (Fedora 44: Wayland lives here, not in a -wayland
#                           package. See the warning at the top of this file.)
#   kwin                    the compositor — the program that actually draws
#                           windows, handles Alt-Tab, and does the animations.
#                           Owns /usr/bin/kwin_wayland.
#   plasma-systemsettings   the Settings app (`systemsettings`). Plasma's
#                           equivalent of gnome-control-center.
#   kscreen                 monitor arrangement, resolution and SCALE. This is
#                           how a person sets a 4K screen to 125% on Plasma —
#                           the job aquarius-display-scale used to do by hand in
#                           the Aquarius Session.
#   plasma-nm               the Wi-Fi / network applet in the panel.
#   plasma-pa               the volume applet in the panel.
#   bluedevil               Bluetooth: pairing, the applet, the settings page.
#   powerdevil              battery, sleep, screen blanking and brightness keys.
#   kde-cli-tools           kcmshell6, kioclient, kdesu — the small commands the
#                           Settings pages and many KDE menu entries call. A
#                           missing one shows up as a settings link that does
#                           nothing at all.
#   kdeplasma-addons        the extra panel widgets (colour picker, timer,
#                           dictionary, weather, notes, the window-list applet).
#                           16 MB, which is inside the "is it small?" test this
#                           file is allowed to apply.
#   kf6-kconfig             supplies /usr/bin/kreadconfig6 and kwriteconfig6,
#                           which is how one of OUR programs reads and clears a
#                           Plasma setting: /usr/libexec/aquarius-keys-run
#                           removes the window-button layout that `aq keys`
#                           used to write into kwinrc before 2026-09-17, so
#                           existing accounts get Plasma's own stock, right-hand
#                           buttons back. It arrives as a dependency of Plasma
#                           anyway — it is named here because a feature of ours
#                           depends on it, and "it comes in anyway" is exactly
#                           the kind of accident this repository asks for by
#                           name instead.
say "KDE Plasma"
aq_dnf install --exclude=plasma-welcome \
    plasma-desktop \
    plasma-workspace \
    kwin \
    plasma-systemsettings \
    kscreen \
    plasma-nm \
    plasma-pa \
    bluedevil \
    powerdevil \
    kde-cli-tools \
    kdeplasma-addons \
    kf6-kconfig

# ------------------------------------------------------------------------------
# The look — and why GTK apps need three of these
# ------------------------------------------------------------------------------
#   plasma-breeze       Breeze: the widget style, the window decorations, the
#                       colour schemes and the cursors. This is the surface our
#                       design tokens will be written onto in Workstream C — a
#                       Plasma colour scheme generated from the same Ice /
#                       Midnight palette GNOME already uses.
#   breeze-icon-theme   the icons KDE's own applications ask for BY NAME. Our
#                       Aquarius icon themes say Inherits=Adwaita,hicolor, which
#                       covers GNOME; a Dolphin or a Spectacle with no Breeze
#                       underneath it shows empty squares in its toolbars.
#   kf6-qqc2-desktop-style
#                       makes QtQuick applications draw with the desktop's real
#                       widget style instead of Qt's plain default. Without it
#                       half of Plasma's own windows look like a different
#                       operating system.
#
# ⚠️ AND THE TWO THAT ARE ABOUT OUR OWN APPS. Aquarius Installer, the Updater,
# the welcome and the creator-apps chooser are GTK 4 / libadwaita windows. On
# GNOME they fit in for free. On Plasma, a GTK app draws with whatever GTK theme
# it is told about — and if nobody tells it, that is Adwaita's light theme, in a
# dark Plasma, with the wrong accent colour and the wrong fonts.
#
#   breeze-gtk          the Breeze theme, translated into something GTK can read
#   kde-gtk-config      the piece that TELLS GTK about it, every session, and
#                       keeps it in step when somebody flips Plasma to dark
#
# Installing breeze-gtk without kde-gtk-config is the common mistake: the theme
# is on the disk and nothing ever selects it.
say "The Breeze look — including for our own GTK windows"
aq_dnf install \
    plasma-breeze \
    breeze-icon-theme \
    kf6-qqc2-desktop-style \
    breeze-gtk \
    kde-gtk-config

# ------------------------------------------------------------------------------
# Portals — the doorway sandboxed apps use
# ------------------------------------------------------------------------------
# Step 3 installed the portal itself and GNOME's backend. This is Plasma's
# backend: the KDE file picker a Flatpak sees when it says "Open…", and — the
# one that matters on this machine — screen sharing and screen recording, which
# on Wayland go through the portal and nothing else. OBS records a black screen
# without it.
#
# ⚠️ NOTHING CHOOSES BETWEEN THE TWO BACKENDS BY HAND ANY MORE. The Aquarius
# Session needed a written rule (/usr/share/xdg-desktop-portal/aquarius-portals.conf)
# because it was a session xdg-desktop-portal had never heard of. GNOME and KDE
# are two sessions it has shipped rules for since 2021: it reads
# XDG_CURRENT_DESKTOP, picks -gnome inside GNOME and -kde inside Plasma, and our
# file is gone. That is one of the things this change DELETES rather than ports.
say "Plasma's portal backend (file pickers, screen sharing, recording)"
aq_dnf install xdg-desktop-portal-kde

# ------------------------------------------------------------------------------
# The small handful of apps
# ------------------------------------------------------------------------------
# The same test as step 4's list, answered with KDE's programs so that a person
# who logs into Plasma has a working machine rather than a panel and nothing to
# click.
#
#   dolphin               the file manager. Also the "Files" a KDE portal file
#                         picker is modelled on, and where an automounted drive
#                         appears in the sidebar on this desktop.
#   konsole               the terminal.
#   spectacle             screenshots AND screen recording. This is what
#                         replaces the screenshot buttons the Aquarius Session's
#                         bar used to carry (FEATURES 017) — it is a better tool
#                         than ours was and it is already maintained.
#   ark                   archives: opening a .zip, making one.
#   gwenview              the image viewer.
#   okular                the PDF and document reader. Creator-relevant: it is
#                         what a delivery spec or a client PDF opens in.
#   plasma-systemmonitor  "what is using my machine" — the Plasma equivalent of
#                         gnome-system-monitor, and worth having on a machine
#                         that exports video for an hour at a time.
#
# ⚠️ NO WEB BROWSER HERE. Firefox is installed once, by step 4, as a plain
# system package and it is the browser on BOTH desktops. Falkon is not added.
say "The small handful of KDE apps"
aq_dnf install \
    dolphin \
    konsole \
    spectacle \
    ark \
    gwenview \
    okular \
    plasma-systemmonitor

# ------------------------------------------------------------------------------
# The password store
# ------------------------------------------------------------------------------
# KWallet is Plasma's keyring — where Wi-Fi passwords, an app's saved login and
# an ssh passphrase are kept. GNOME's equivalent (gnome-keyring) is installed by
# step 4; each desktop uses its own and they do not fight, because only one
# session runs at a time.
#
#   kf6-kwallet       the wallet itself (kwalletd6) and `kwallet-query`
#   kwalletmanager5   the window for looking inside it and forgetting something.
#                     ⚠️ THE "5" IN THAT NAME IS A LIE. Fedora 44's
#                     kwalletmanager5 is version 25.12.3 and is the KDE Frameworks
#                     6 build; the package name simply never changed. There is no
#                     kwalletmanager6 to ask for.
#
# ⚠️ THERE IS NO kwallet-pam PACKAGE IN FEDORA 44. Every older guide tells you to
# install it so the wallet unlocks with your login password. It does not exist
# here any more, and asking for it stops the build with "no match". If a person
# wants the wallet unlocked at login on Plasma, that is a setting inside
# KWalletManager, not a package.
say "KWallet (Plasma's password store)"
aq_dnf install \
    kf6-kwallet \
    kwalletmanager5

# ------------------------------------------------------------------------------
# Which desktop a brand-new person lands in
# ------------------------------------------------------------------------------
# GDM remembers, per person, which session they last logged into. It keeps that
# in AccountsService, one small file per account under /var/lib/AccountsService.
# A brand-new account has no such file yet, and what fills it in the first time
# is a TEMPLATE at /usr/share/accountsservice/user-templates/standard.
#
# AquariusOS says GNOME there, on purpose and for now:
#
#   * it is the desktop Royce approved the look of on the bench (2026-08-31);
#   * every AquariusOS window — the welcome, the app chooser, the Installer, the
#     Updater — is GTK 4, and those are exactly the windows a brand-new person
#     meets in their first three minutes;
#   * Plasma is here to be TESTED against it (that is the whole point of this
#     change), and testing means deliberately choosing it, once, at the login
#     screen. It is one click and GDM remembers it forever after.
#
# ⚠️ THIS IS A DEFAULT, NOT A LOCK. Nothing here prevents Plasma; picking it at
# the login screen is described in docs/restart/desktops.md. And if a future
# template already names a session, we leave it alone rather than overruling it.
say "GNOME as the desktop a brand-new account lands in"
AQ_TEMPLATE_DIR="/usr/share/accountsservice/user-templates"
AQ_TEMPLATE="${AQ_TEMPLATE_DIR}/standard"
if [ -r "${AQ_TEMPLATE}" ] && grep -Eq '^[[:space:]]*Session[[:space:]]*=[[:space:]]*[^[:space:]]' "${AQ_TEMPLATE}"; then
    echo "  a session is already named in ${AQ_TEMPLATE} — leaving it alone:"
    sed 's/^/       /' "${AQ_TEMPLATE}"
else
    mkdir -p "${AQ_TEMPLATE_DIR}"
    cat > "${AQ_TEMPLATE}" << 'AQ_TEMPLATE_EOF'
# AquariusOS — what a brand-new account starts in.
#
# AccountsService copies this into /var/lib/AccountsService/users/<name> the
# first time somebody logs in, and GDM reads it to decide which session to
# preselect. After that first login GDM remembers whatever the person actually
# chose, and this file is never consulted for them again.
#
# Session=gnome  means the GNOME Wayland session (/usr/share/wayland-sessions/
# gnome.desktop). To land in KDE Plasma instead, pick it once at the login
# screen — see docs/restart/desktops.md.
[User]
Session=gnome
XSession=
SystemAccount=false
AQ_TEMPLATE_EOF
fi

# ==============================================================================
# Check the second desktop is really in there
# ==============================================================================
say "Checking KDE Plasma"

aq_installed \
    plasma-desktop \
    plasma-workspace \
    kwin \
    plasma-systemsettings \
    kscreen \
    plasma-nm \
    plasma-pa \
    bluedevil \
    powerdevil \
    kde-cli-tools \
    kdeplasma-addons \
    kf6-kconfig \
    plasma-breeze \
    breeze-icon-theme \
    kf6-qqc2-desktop-style \
    breeze-gtk \
    kde-gtk-config \
    xdg-desktop-portal-kde \
    dolphin \
    konsole \
    spectacle \
    ark \
    gwenview \
    okular \
    plasma-systemmonitor \
    kf6-kwallet \
    kwalletmanager5

# The programs a session is actually made of. A package can install and put its
# program somewhere nothing looks; this asks the PATH.
for aq_cmd in startplasma-wayland kwin_wayland plasmashell systemsettings dolphin konsole spectacle kwriteconfig6; do
    if aq_have "${aq_cmd}"; then ok "${aq_cmd} is on the path"; else bad "${aq_cmd} is missing"; fi
done

echo "This image has Plasma: $(plasmashell --version 2>&1 | tr -d '\n')"
echo "            and KWin: $(kwin_wayland --version 2>&1 | tr -d '\n')"

# ------------------------------------------------------------------------------
# ⚠️ THE THREE PACKAGES THAT MUST NOT BE HERE
# ------------------------------------------------------------------------------
# Each of these arrives as somebody else's dependency or recommendation rather
# than because anybody asked for it, and each one breaks a decision this project
# has already made. Reading them back is the only way to know.
say "Checking the three packages that must NOT be in this image"
for aq_forbidden in sddm plasma-discover plasma-welcome; do
    if rpm -q "${aq_forbidden}" > /dev/null 2>&1; then
        case "${aq_forbidden}" in
            sddm)
                bad "sddm is installed. AquariusOS has ONE login screen (GDM). If a Fedora update has made this a HARD dependency of plasma-workspace, install it but leave it switched off, say so here, and tell Royce — do not simply delete this check." ;;
            plasma-discover)
                bad "plasma-discover is installed — a second app store beside Aquarius Installer. Exclude it by name from the install above." ;;
            plasma-welcome)
                bad "plasma-welcome is installed — a second welcome window at the first login, beside ours (step 7d-bis). The --exclude above stopped working." ;;
        esac
        echo "       pulled in by: $(rpm -q --whatrequires "${aq_forbidden}" 2> /dev/null | tr '\n' ' ')"
    else
        ok "${aq_forbidden} is not in the image"
    fi
done

# Even if sddm somehow arrives, it must never be switched on. Two login managers
# is a black screen with no way in — and this project has had that twice.
if systemctl is-enabled sddm.service > /dev/null 2>&1; then
    bad "sddm.service is switched ON. GDM is the login screen on this machine; two of them fight over the display."
else
    ok "sddm is not switched on"
fi

# ------------------------------------------------------------------------------
# The login screen offers BOTH desktops
# ------------------------------------------------------------------------------
# This is the check the whole change is about. GDM lists one entry per file in
# /usr/share/wayland-sessions/. If the Plasma one is missing, the login screen
# looks perfectly normal and simply has no Plasma in its menu — a symptom that
# reads like "KDE did not install" when in fact everything else did.
say "The login screen offers both desktops"
for aq_session in gnome.desktop plasma.desktop; do
    aq_path="/usr/share/wayland-sessions/${aq_session}"
    if [ -r "${aq_path}" ]; then
        ok "${aq_session} — $(grep -m1 '^Name=' "${aq_path}" 2> /dev/null || echo 'no Name= line')"
    else
        bad "${aq_path} is missing — the login screen would not offer that desktop"
    fi
done

# GNOME ships its session file under two names on different Fedora releases
# (gnome.desktop and gnome-wayland.desktop). Either satisfies the check above
# only if it is the one named; say which ones are really there, so a rename
# upstream is visible in the log rather than a surprise.
echo "Everything GDM can offer:"
ls -l /usr/share/wayland-sessions/ 2> /dev/null || true
echo "X11 sessions (there should be none of ours):"
ls -l /usr/share/xsessions/ 2> /dev/null || echo "  (no /usr/share/xsessions — correct, this is a Wayland machine)"

# The Aquarius Session's own entry must be GONE. It was retired on 2026-09-15
# and a leftover file would put a third, broken choice on the login screen that
# drops a person straight back to it.
if [ -e /usr/share/wayland-sessions/aquarius.desktop ]; then
    bad "/usr/share/wayland-sessions/aquarius.desktop is still here — the retired Aquarius Session would appear at the login screen and fail to start"
else
    ok "the retired Aquarius Session is not offered at the login screen"
fi

# ------------------------------------------------------------------------------
# GDM is still the login screen, and the machine still boots to a desktop
# ------------------------------------------------------------------------------
# Step 4 set both of these. This step installs a desktop that ships its own
# login manager, so this is where we prove it did not take them over.
say "GDM is still the login screen"
AQ_DEFAULT_TARGET="$(systemctl get-default)"
if [ "${AQ_DEFAULT_TARGET}" = "graphical.target" ]; then
    ok "the machine still boots to a desktop (default target is graphical.target)"
else
    bad "default target is '${AQ_DEFAULT_TARGET}' — this machine would boot to a text prompt"
fi
if systemctl is-enabled gdm.service > /dev/null 2>&1; then
    ok "GDM is switched on"
else
    bad "GDM is not switched on — nothing would draw a login screen"
fi

# ------------------------------------------------------------------------------
# The new-account default reads back
# ------------------------------------------------------------------------------
aq_file_has "${AQ_TEMPLATE}" '^Session=' \
    "a brand-new account is given a desktop to start in"
echo "  ${AQ_TEMPLATE} says:"
sed 's/^/       /' "${AQ_TEMPLATE}"
AQ_TEMPLATE_SESSION="$(grep -m1 '^Session=' "${AQ_TEMPLATE}" | cut -d= -f2-)"
if [ -r "/usr/share/wayland-sessions/${AQ_TEMPLATE_SESSION}.desktop" ]; then
    ok "it names '${AQ_TEMPLATE_SESSION}', and that session really exists"
else
    bad "it names '${AQ_TEMPLATE_SESSION}', but /usr/share/wayland-sessions/${AQ_TEMPLATE_SESSION}.desktop is not in this image — a brand-new account would be sent to a session that is not there"
fi

# ------------------------------------------------------------------------------
# GTK apps have something to follow on Plasma
# ------------------------------------------------------------------------------
# Our own windows are the reason this matters. A theme is a NAMED FOLDER on
# disk; if it is missing, GTK falls back without a word and the Installer looks
# like it came from a different operating system.
say "Checking the Breeze pieces our GTK windows need are on disk"
# (`breeze-gtk` is a metapackage: it requires breeze-gtk-gtk2, -gtk3 and -gtk4,
# and those are what actually write /usr/share/themes/Breeze. Checking the
# folder rather than the metapackage is the point.)
for aq_dir in \
    /usr/share/themes/Breeze \
    /usr/share/themes/Breeze-Dark \
    /usr/share/icons/breeze \
    /usr/share/icons/breeze-dark; do
    if [ -d "${aq_dir}" ]; then
        ok "${aq_dir} exists"
    else
        bad "${aq_dir} is missing — Plasma's look would silently fall back"
    fi
done

aq_finish "The KDE Plasma desktop"
