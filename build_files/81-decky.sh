#!/usr/bin/bash
# ==============================================================================
# STEP 7h — Decky Loader, OFFERED (Phase G3)
# ==============================================================================
# WHAT DECKY IS, IN PLAIN ENGLISH
#
# Game Mode (step 71) is Steam owning the whole screen. Inside it there is a
# button marked "..." on the right — Steam calls it the quick-access menu — and
# **Decky Loader** adds one more tab to that menu, with a plug on it. Behind
# the plug is a small shop of add-ons other people wrote: a battery readout, a
# per-game power profile, a screen recorder, a music player.
#
# ⚠️ IT ONLY EXISTS IN GAME MODE. Decky works by talking to Steam's own
# interface while Steam is drawing the whole screen. Open Steam in a window on
# the desktop and Decky is simply not there. Nothing can be configured to
# change that; it is what Decky is, and every message this feature prints says
# so.
#
# ------------------------------------------------------------------------------
# ⚠️ THIS STEP DOES NOT INSTALL DECKY, AND MOST OF IT EXISTS TO PROVE THAT
# ------------------------------------------------------------------------------
# Standing decision 4 is "apps live outside the image where they can", and
# Decky is the clearest case of it there has been:
#
#   * it is somebody else's program, downloaded from GitHub;
#   * it runs as a background service AS THE ADMINISTRATOR, because some
#     plugins change things only the administrator can change;
#   * the file that starts it names ONE person's home folder, so it could not
#     be baked into an image that many people share even if we wanted to.
#
# So this step puts THREE things in the image and not one byte more:
#
#   1. `jq`, a small program that reads GitHub's answer about which Decky is
#      newest. `aq decky` cannot work without it and nothing else in this image
#      had pulled it in;
#   2. the `aq decky install | update | remove | status` command — which
#      already arrived with system_files at step 5, and is read back here;
#   3. the "Decky Loader" launcher in the app grid — likewise.
#
# And then it proves the absence of everything else: no plugin_loader.service
# baked into /etc, no /home/deck, no downloaded loader, no ~/homebrew. If any
# of those ever appears in an image, this step stops the build. That is the
# whole safety of "offered, never baked".
#
# ⚠️ NOTHING HERE TOUCHES THE NETWORK. A build step that downloaded Decky would
# pin every machine to whatever version was newest on the day the image was
# built, and would put a program we did not review into the operating system.
# The download happens on a real machine, when a person asks for it.
#
# ------------------------------------------------------------------------------
# WHY THIS STEP IS NOT GATED, AND 78-handheld.sh IS
# ------------------------------------------------------------------------------
# Step 78 reads a HANDHELD switch and installs nothing at all unless it is 1,
# because the handheld layer must be unable to change the computer Royce edits
# on. Decky is the opposite: it is three files and a 400 KB package, it is
# offered on every image, and it is useful on all of them — the desktop PCs
# have Game Mode too (step 71) and Decky is a Game Mode feature. A person on
# any AquariusOS decides for themselves whether they want it. So there is no
# switch here, deliberately.
#
# Plain-language guide: docs/restart/decky.md
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source /ctx/build_files/aq-lib.sh

AQ_DECKY_DESKTOP="/usr/share/applications/aquarius-decky.desktop"
AQ_DECKY_UNIT="/etc/systemd/system/plugin_loader.service"

# ==============================================================================
# 1. jq — the one package this feature needs
# ==============================================================================
# GitHub answers "what is your newest release?" with a large block of JSON.
# `jq` is the standard small program for picking one value out of that, it is
# what Decky's own installer uses, and it is not in this image: `grep -rn jq
# build_files` found nothing before this step existed. It is about 400 KB and
# it is useful to anybody who ever touches a web API from a terminal.
say "jq — the small program that reads GitHub's answer"

aq_dnf install jq

aq_installed jq

# Installed is not the same as runnable. Ask the program itself.
if aq_have jq; then
    ok "jq runs in this image ($(jq --version 2>&1))"
else
    bad "jq is not on PATH — 'aq decky install' could never find out which Decky is newest"
fi

# ==============================================================================
# 2. The `aq decky` command, read back out of the finished image
# ==============================================================================
# `aq` is one file, it arrived at step 5 with everything else in system_files,
# and adding a subcommand to it is the easiest possible way to break every
# OTHER subcommand — one unbalanced quote and `aq keys`, `aq resolve`, `aq
# game` all stop working at once. So the first question is not "is decky
# there", it is "does this file still parse at all".
say "The aq command still parses, with the decky part in it"

if bash -n /usr/bin/aq 2> /tmp/aq-decky-syntax.txt; then
    ok "/usr/bin/aq is valid shell"
else
    sed 's/^/       /' /tmp/aq-decky-syntax.txt >&2
    bad "/usr/bin/aq does not parse — EVERY aq command is broken, not just decky"
fi
rm -f /tmp/aq-decky-syntax.txt

# ⚠️ THE FILE'S OWN WARNING, ENFORCED. The top of /usr/bin/aq says: "IF YOU ADD
# A SUBCOMMAND, ADD IT TO usage() TOO. A command nobody can discover is a
# command nobody uses." Nothing enforced that until now. This does: the plain
# `aq --help` a person types must mention decky.
say "A person can find 'aq decky' without being told it exists"

if /usr/bin/aq --help > /tmp/aq-decky-usage.txt 2>&1; then
    ok "'aq --help' runs"
else
    sed 's/^/       /' /tmp/aq-decky-usage.txt >&2
    bad "'aq --help' does not run"
fi
aq_file_has /tmp/aq-decky-usage.txt 'aq decky' \
    "'aq --help' lists 'aq decky', so it is discoverable"
aq_file_has /tmp/aq-decky-usage.txt 'Game Mode' \
    "and says, in the usage itself, that Decky is a Game Mode thing"
rm -f /tmp/aq-decky-usage.txt

say "All four things 'aq decky' can do are really there"

if /usr/bin/aq decky --help > /tmp/aq-decky-help.txt 2>&1; then
    ok "'aq decky --help' runs"
    sed 's/^/       /' /tmp/aq-decky-help.txt
else
    sed 's/^/       /' /tmp/aq-decky-help.txt >&2
    bad "'aq decky --help' does not run"
fi

for aq_verb in install update status remove; do
    aq_file_has /tmp/aq-decky-help.txt "aq decky ${aq_verb}" \
        "'aq decky ${aq_verb}' is offered in the help"
done

# The two warnings a person has to meet BEFORE they install, not afterwards:
# that this only works in Game Mode, and that it runs as the administrator.
aq_file_has /tmp/aq-decky-help.txt 'ONLY EXISTS IN GAME MODE' \
    "the help says plainly that Decky only appears in Game Mode"
aq_file_has /tmp/aq-decky-help.txt 'administrator' \
    "and that it runs as an administrator in the background"
rm -f /tmp/aq-decky-help.txt

# ==============================================================================
# 3. The launcher in the app grid
# ==============================================================================
# A .desktop file is the whole contract with the app grid. A missing key, or a
# key the desktop does not understand, and the entry either does not appear or
# appears and does nothing — both of which look like a broken operating system
# rather than a broken file.
say "The 'Decky Loader' entry in the app grid"

if [ -r "${AQ_DECKY_DESKTOP}" ]; then
    ok "${AQ_DECKY_DESKTOP} is installed"
    sed 's/^/       /' "${AQ_DECKY_DESKTOP}"
else
    bad "${AQ_DECKY_DESKTOP} is missing — there would be no way to install Decky except a terminal"
fi

aq_file_has "${AQ_DECKY_DESKTOP}" '^Type=Application$' \
    "it is an application entry"
aq_file_has "${AQ_DECKY_DESKTOP}" '^Name=Decky Loader$' \
    "it is called 'Decky Loader' — the name the person will search for"
aq_file_has "${AQ_DECKY_DESKTOP}" '^Exec=/usr/bin/aq decky install$' \
    "clicking it runs 'aq decky install'"
aq_file_has "${AQ_DECKY_DESKTOP}" '^Terminal=true$' \
    "and it opens a terminal, because the install prints things and asks for a password"
aq_file_has "${AQ_DECKY_DESKTOP}" '^Comment=' \
    "it has a one-sentence description under the name"
aq_file_has "${AQ_DECKY_DESKTOP}" '^Icon=' \
    "it has an icon"
aq_file_has "${AQ_DECKY_DESKTOP}" '^Categories=Game;' \
    "and a shelf in the menu (Games)"

# What it points at has to exist, or the entry is a button that does nothing.
if [ -x /usr/bin/aq ]; then
    ok "/usr/bin/aq is there and can be run, so the entry is not a dead button"
else
    bad "/usr/bin/aq is missing or not runnable"
fi

# The desktop's OWN opinion of the file, where the tool for it exists. This is
# the same check step 65 runs on Aquarius Installer's entry, and it catches the
# mistakes a grep never can — a key in the wrong section, a bad encoding, a
# list without its trailing semicolon.
if aq_have desktop-file-validate; then
    if desktop-file-validate "${AQ_DECKY_DESKTOP}" > /tmp/aq-decky-dfv.txt 2>&1; then
        ok "the desktop's own validator is happy with the entry"
    else
        sed 's/^/       /' /tmp/aq-decky-dfv.txt >&2
        bad "desktop-file-validate rejected ${AQ_DECKY_DESKTOP}"
    fi
    rm -f /tmp/aq-decky-dfv.txt
else
    echo "  (desktop-file-validate is not in this image — the key checks above stand alone)"
fi

# The icon is Steam's own, which arrived with step 68. This is information
# rather than a build failure: a missing icon is an entry with a grey square on
# it, not an entry that does nothing, and which exact file an icon theme picks
# is not something a build step can answer honestly.
say "The icon the entry asks for"
AQ_DECKY_ICON="$(sed -n 's/^Icon=//p' "${AQ_DECKY_DESKTOP}" 2> /dev/null | head -n 1)"
echo "  the entry asks for the icon named: ${AQ_DECKY_ICON:-(none)}"
if [ -n "${AQ_DECKY_ICON}" ] \
    && find /usr/share/icons /usr/share/pixmaps -name "${AQ_DECKY_ICON}.*" -print -quit 2> /dev/null | grep -q .; then
    ok "an icon file with that name is in the image (it came with Steam, step 68)"
else
    echo "  NOTE: no file named '${AQ_DECKY_ICON}' was found under /usr/share/icons or"
    echo "        /usr/share/pixmaps. The entry still works; it would show a plain"
    echo "        square. Not a build failure — see the comment above this check."
fi

# ==============================================================================
# 4. ⚠️ NONE OF DECKY ITSELF IS IN THIS IMAGE
# ==============================================================================
# THIS SECTION IS THE POINT OF THE STEP. Everything above is plumbing; this is
# the promise. Decky is offered, never baked (standing decision 4), and the
# only way that promise stays true a year from now is a check that stops the
# build the day somebody breaks it.
#
# Four things would each be a breach, and each is asked separately so that a
# failure names exactly which one:
say "Decky itself is NOT in this image — it is offered, never baked"

# 1. The service file. If this were in the image, every machine following these
#    images would run a background service as the administrator that nobody
#    asked for, pointed at a home folder that may not exist.
if [ -e "${AQ_DECKY_UNIT}" ]; then
    sed 's/^/       /' "${AQ_DECKY_UNIT}" || true
    bad "${AQ_DECKY_UNIT} is baked into this image — every machine would run Decky as root without being asked"
else
    ok "no ${AQ_DECKY_UNIT} — nothing starts Decky on a machine that did not ask for it"
fi

# 2. And it must not be switched on from /usr either, which is the OTHER way
#    AquariusOS starts things (see aq-lib.sh). A link there would start a
#    service whose program does not exist.
for aq_dir in /usr/lib/systemd/system /etc/systemd/system; do
    if find "${aq_dir}" -name 'plugin_loader*' -print -quit 2> /dev/null | grep -q .; then
        find "${aq_dir}" -name 'plugin_loader*' | sed 's/^/       /'
        bad "something called plugin_loader is under ${aq_dir}"
    else
        ok "nothing called plugin_loader is under ${aq_dir}"
    fi
done

# 3. /home/deck. Decky's install makes this signpost ON A MACHINE, for the
#    plugins that were written for a Steam Deck and have that name typed into
#    them. In an IMAGE it would be a folder in everybody's /home that belongs
#    to nobody.
if [ -e "/home/deck" ] || [ -L /home/deck ]; then
    bad "/home/deck is baked into this image — that signpost is made on a real machine, by a real person's install, or not at all"
else
    ok "no /home/deck in the image"
fi

# 4. The downloaded program, anywhere at all. 26 MB of somebody else's Python,
#    which nothing in this repository reviewed.
if find / -xdev -name 'PluginLoader' -print -quit 2> /dev/null | grep -q .; then
    find / -xdev -name 'PluginLoader' 2> /dev/null | sed 's/^/       /'
    bad "a downloaded Decky PluginLoader is in this image — a build step downloaded it, and no build step may"
else
    ok "no PluginLoader anywhere in the image — nothing was downloaded at build time"
fi

if [ -d /var/home ] && find /var/home -maxdepth 2 -name 'homebrew' -print -quit 2> /dev/null | grep -q .; then
    bad "a ~/homebrew folder is baked into the image — Decky's folders belong to a person, not to an image"
else
    ok "no ~/homebrew folder is baked in"
fi

aq_finish "Decky Loader (offered, never baked)"
