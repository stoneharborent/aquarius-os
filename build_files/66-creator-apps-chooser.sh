#!/usr/bin/bash
# ==============================================================================
# STEP 7d — the creator apps chooser ("Your creator apps")
# ==============================================================================
# WHAT THIS IS, IN PLAIN ENGLISH
#
# Step 7c put a list of creator apps into the image and the machinery to install
# them. This step adds the WINDOW that offers them to a person, and makes sure
# it opens by itself the first time somebody logs in.
#
# ⚠️ THE DESIGN DECISION THIS STEP IMPLEMENTS, 2026-09-04 (Royce's call):
#    NOTHING IS INSTALLED AUTOMATICALLY ANY MORE. The first login shows a window
#    that showcases every creator app AquariusOS can set up, with a sentence
#    about each, and the person ticks what they want.
#
#    The old behaviour spent fifteen gigabytes of somebody's internet connection
#    on their behalf before asking them anything, and hid the best thing about
#    the operating system — how much is here — inside a progress notification.
#
# Two programs are added:
#
#   /usr/libexec/aquarius-creator-apps
#       The window. Python, GTK 4 and libadwaita, exactly like the DaVinci
#       Resolve installer window it sits beside. Runs as you, has no special
#       powers, and installs nothing itself.
#
#   /usr/libexec/aquarius-creator-apps-install
#       The part that does install, one app at a time, as an administrator. The
#       window starts it through pkexec, which is where the single password
#       prompt comes from.
#
# ...and one menu entry: "Aquarius Apps" in the app grid.
#
# ⚠️ IT USED TO ADD A SECOND ONE — a hidden /etc/xdg/autostart entry that opened
#    this window at the first login. That is gone as of 2026-09-04 (roadmap
#    Phase R5). The first login now opens /usr/libexec/aquarius-welcome, which
#    asks about the keyboard first and then opens THIS window as its second
#    step. Section 4 below checks the old entries really are gone, because two
#    things opening this window at a first login is a fault nobody would see
#    until the one moment it matters.
#
# ------------------------------------------------------------------------------
# WHAT THIS STEP CHECKS, AND WHY EACH CHECK IS HERE
# ------------------------------------------------------------------------------
# Every check below reads CONTENT — a file's text, a command's answer — and
# never a timestamp, for the reason written at the top of aq-lib.sh.
#
# The most important one is the last group. On 2026-09-04 the creator apps did
# not install on the bench, and the reason was that nothing in the build had
# ever run the real parser against the real shipped file. A window that draws a
# list it cannot read is the same fault in a nicer typeface, so this step runs
# the window's own reading code, against the real list in this image, and
# insists the answers are sane.
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

CHOOSER=/usr/libexec/aquarius-creator-apps
HELPER=/usr/libexec/aquarius-creator-apps-install
APP_ENTRY=/usr/share/applications/aquarius-creator-apps.desktop
OLD_AUTOSTART=/etc/xdg/autostart/aquarius-creator-apps-firstrun.desktop
LABWC_AUTOSTART=/usr/share/aquarius/labwc/autostart
FIXTURE=/ctx/tests/creator-apps-catalog.fixture

# ==============================================================================
# 1. What the window is built out of
# ==============================================================================
# GTK 4 and libadwaita are already in this image, because the GNOME fallback
# session is built on them. What is NOT necessarily here is the piece that lets
# a Python program use them — python3-gobject — and the description files
# (called "typelibs") it reads to find out what GTK can do.
#
# They are asked for by name anyway, rather than assumed. An image that quietly
# stopped shipping GNOME would otherwise ship a window that cannot start, and
# the first person to find out would be somebody logging in for the first time.
say "What the app chooser is built out of"
aq_dnf install \
    python3-gobject \
    gtk4 \
    libadwaita

# ==============================================================================
# 2. Are the two programs here, and can they run?
# ==============================================================================
say "The app chooser and its installer"

for path in "${CHOOSER}" "${HELPER}"; do
    if [ -x "${path}" ]; then
        ok "$(basename "${path}") is here and is runnable"
    else
        bad "$(basename "${path}") is missing or is not runnable"
    fi
done

# ⚠️ pkexec REFUSES TO RUN A PROGRAM ANYBODY COULD HAVE EDITED, and it is right
# to. The helper must be owned by root and must not be writable by anyone else,
# or the single password prompt this whole feature depends on never appears —
# it fails with a message about permissions that means nothing to a beginner.
if [ -e "${HELPER}" ]; then
    helper_mode="$(stat -c '%a %U %G' "${HELPER}")"
    case "${helper_mode}" in
        7[0-5][0-5]\ root\ root)
            ok "the installer is root-owned and not writable by others (${helper_mode}) — pkexec will run it"
            ;;
        *)
            bad "the installer is ${helper_mode}; pkexec will refuse to run it unless it is root-owned and 0755 or tighter"
            ;;
    esac
fi

# ⚠️ AND IT HAS TO SAY WHERE THE SHARED PIECES ARE. Since 2026-09-04 the step
# rows and the Details log live in /usr/lib/aquarius/python/aquarius_ui.py,
# shared with the two DaVinci Resolve windows. Without this line the window
# fails on its first widget and the first-login window never appears.
say "The window knows where the shared pieces are"
aq_file_has "${CHOOSER}" 'sys\.path\.insert\(0, "/usr/lib/aquarius/python"\)' \
    "the chooser adds the shared-window folder to its search path"
if python3 -c 'import sys; sys.path.insert(0, "/usr/lib/aquarius/python"); import aquarius_ui; print("  aquarius_ui imported")'; then
    ok "the shared window pieces import cleanly"
else
    bad "aquarius_ui cannot be imported — this window would fail to open"
fi

say "Python can build the window"
# Two separate questions, because they fail for different reasons and a build
# log that says which is a build log worth reading.
# ⚠️ NOT `python3 -m py_compile`, which would leave a __pycache__ folder sitting
#    in /usr/libexec forever, in the shipped image, as a souvenir of the build.
#    Compiling to a named file in /tmp asks the same question and leaves nothing.
if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-chooser.pyc", doraise=True)' \
    "${CHOOSER}"; then
    ok "the window is valid Python"
else
    bad "the window is not valid Python"
fi
rm -f /tmp/aq-chooser.pyc
if bash -n "${HELPER}"; then
    ok "the installer is valid shell"
else
    bad "the installer is not valid shell"
fi

# The real question: can a Python program on THIS image reach GTK 4 and
# libadwaita? This is the check that catches a missing typelib, which is the way
# this particular thing breaks — the packages are installed, the import fails.
if python3 - <<'PY'; then
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango  # noqa: F401

print("Gtk %d.%d.%d, Adw %d.%d.%d"
      % (Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version(),
         Adw.get_major_version(), Adw.get_minor_version(), Adw.get_micro_version()))
PY
    ok "Python can load GTK 4, libadwaita and Pango"
else
    bad "Python cannot load GTK 4 or libadwaita — the window would not open"
fi

# ==============================================================================
# 2b. The last page — the one Royce landed on with a blank top
# ==============================================================================
# ⚠️ THE 2026-09-04 BENCH FAULT, PART TWO. The "All set." page was an
# Adw.StatusPage, which draws a small system symbol and cannot be given the
# Aquarius mark, so the page you land on after installing was empty at the top
# while the two pages before it both carry the logo.
#
# These checks are text checks, and that is a deliberate limitation: building a
# GTK window needs a screen, and there is no screen in a build container, so the
# only thing a build can ask is "is the window still written the way we fixed
# it". It is worth asking. The fault it guards against is somebody reaching for
# Adw.StatusPage again because it is the obvious widget for a page like this.
say "The last page carries the Aquarius mark"
# The hero helper moved into the shared window pieces on 2026-09-04, when the
# two DaVinci Resolve windows turned out to have the identical blank last page
# for the identical reason. So there is now ONE of it, in one file, and this
# window takes a name for it rather than carrying a copy.
aq_file_has /usr/lib/aquarius/python/aquarius_ui.py 'def hero\(' \
    "the shared window pieces own the hero helper (the mark, the heading, the line under it)"
aq_file_has /usr/lib/aquarius/python/aquarius_ui.py 'mark_image\(pixel_size\)' \
    "the hero helper gets the mark from the same place every window does"
aq_file_has "${CHOOSER}" 'hero = aquarius_ui\.hero' \
    "the chooser uses that shared helper rather than a copy of its own"
aq_file_has "${CHOOSER}" 'mark, self\.done_title, self\.done_blurb = hero\(' \
    "the done page is built from that same helper, so the mark is on it"
aq_file_has "${CHOOSER}" 'mark, title, blurb = hero\(' \
    "and so is the first page, which is what makes them match"
# Looking for the CALL — "Adw.StatusPage(" with its bracket — and not for the
# name, because the comments in that file explain at length why it is not one.
if grep -q 'Adw\.StatusPage(' "${CHOOSER}"; then
    bad "the done page is an Adw.StatusPage again — it cannot show the Aquarius mark"
else
    ok "no Adw.StatusPage is built anywhere in the window"
fi
# That page has three wordings — everything worked, you stopped it, some of them
# failed — and all three fill in the SAME heading and line, under the same mark.
# Three of each is how we know no variant was left drawing its own thing.
for part in done_title done_blurb; do
    count="$(grep -cF "self.${part}.set_label" "${CHOOSER}" || true)"
    if [ "${count}" -ge 3 ]; then
        ok "all ${count} wordings of the done page fill in ${part}"
    else
        bad "only ${count} wording(s) fill in ${part} — one variant of the done page is not filled in"
    fi
done

say "The last page offers 'Open apps'"
aq_file_has "${CHOOSER}" 'pill_button\("Open apps", suggested=True\)' \
    "the suggested button says 'Open apps', not 'Open <one app>'"
if grep -q 'first_app' "${CHOOSER}"; then
    bad "the done page still opens whichever app happened to be installed first"
else
    ok "it no longer picks one app to open on the person's behalf"
fi
# The two desktops AquariusOS ships, and the way out if neither answers.
aq_file_has "${CHOOSER}" '"qs", "ipc", "call", "search", "toggle"' \
    "in the Aquarius Session it opens the search palette (the Super+Space one)"
aq_file_has "${CHOOSER}" '"ShowApplications"' \
    "in GNOME it asks GNOME Shell for the app grid"
# Again the call and not the name: "Eval" in quotes is a D-Bus method being
# asked for; Eval in a sentence is the comment saying why we do not ask for it.
if grep -q '"Eval"' "${CHOOSER}"; then
    bad "it calls GNOME Shell's Eval, which modern GNOME refuses unless the session is in unsafe mode"
else
    ok "it does not call Eval, which would be refused"
fi
aq_file_has "${CHOOSER}" 'def _back_to_the_list' \
    "and if neither desktop answers it goes back to the app list instead"
aq_file_has "${CHOOSER}" 'self\.footer\.set_visible\(True\)' \
    "which puts the footer back, so that page still has its buttons"

# ==============================================================================
# 3. The menu entry
# ==============================================================================
say "The app grid entry"
if ! aq_have desktop-file-validate; then
    echo "desktop-file-validate is not here yet; installing desktop-file-utils."
    aq_dnf install desktop-file-utils
fi
if [ ! -r "${APP_ENTRY}" ]; then
    bad "${APP_ENTRY} is missing"
elif desktop-file-validate "${APP_ENTRY}"; then
    ok "$(basename "${APP_ENTRY}") is a well-formed menu entry"
else
    bad "$(basename "${APP_ENTRY}") is not a well-formed menu entry"
fi

aq_file_has "${APP_ENTRY}" '^Name=Aquarius Apps$' \
    "the app grid entry is called Aquarius Apps"
aq_file_has "${APP_ENTRY}" "^Exec=${CHOOSER}\$" \
    "and it opens the chooser"

# ==============================================================================
# 4. This window no longer starts itself at login — the welcome does
# ==============================================================================
# ⚠️ THE 2026-09-04 CHANGE (roadmap Phase R5). Until this branch, the first
# login opened THIS window and nothing else. Now it opens
# /usr/libexec/aquarius-welcome, which asks about the keyboard first and then
# opens this window as its second step.
#
# So the two old first-login entries must be GONE, not merely unused. A stale
# /etc/xdg/autostart entry would open this window a second time, ten seconds
# after the welcome had already opened it — the sort of fault that only shows up
# on somebody's very first login, which is the worst possible time.
#
# The welcome's own entries are checked by build_files/67-welcome.sh, which runs
# straight after this step.
say "Nothing opens this window at login any more"
if [ -e "${OLD_AUTOSTART}" ]; then
    bad "${OLD_AUTOSTART} is still here — the chooser would open twice at a first login, once by itself and once inside the welcome"
else
    ok "the old first-login entry for this window is gone"
fi
if grep -q 'aquarius-creator-apps --first-run' "${LABWC_AUTOSTART}" 2> /dev/null; then
    bad "the Aquarius session's autostart still opens this window directly at login — the welcome should be what opens"
else
    ok "the Aquarius session's autostart does not open this window directly either"
fi

# ==============================================================================
# 4b. ...but it knows how to BE the welcome's second step
# ==============================================================================
# --embedded-flow is the flag the welcome passes. It changes three cosmetic
# things — always open, "Step 2 of 3" beside the title, "Continue" instead of
# "Close" on the last page — and nothing else, which is why every other check in
# this file still runs the window exactly as it always did.
say "It knows how to be step 2 of the welcome"
aq_file_has "${CHOOSER}" '[-]-embedded-flow' \
    "the window understands --embedded-flow"
aq_file_has "${CHOOSER}" 'def run_window\(first_run, embedded=False\)' \
    "and carries that answer into the window it draws"
aq_file_has "${CHOOSER}" 'subtitle="Step 2 of 3" if embedded else ""' \
    "in the welcome it says which step of the welcome it is"
aq_file_has "${CHOOSER}" 'close_button\.set_label\("Continue"\)' \
    "and its last page offers Continue rather than Close, because the welcome is still waiting"
aq_file_has "${CHOOSER}" 'if first_run or embedded:' \
    "going through the welcome counts as having been asked, so it is not asked again"
# The flag must not leak into the ordinary window. If it did, somebody opening
# Aquarius Apps from the app grid would be told they were on "step 2 of 3" of
# something they never started.
if "${CHOOSER}" --dry-run > /dev/null 2>&1; then
    ok "run with no flags at all, it still reads its list exactly as before"
else
    bad "the --embedded-flow change broke the ordinary window"
fi

# ==============================================================================
# 5. Nothing installs itself any more
# ==============================================================================
# The whole point of this step. If this service were enabled, a machine would
# still go and fetch every app on its own at the first boot, and the window
# would be decoration.
#
# ⚠️ THIS IS DELIBERATELY NOT `systemctl is-enabled`, AND THE REASON IS A TRAP.
#    `systemctl is-enabled` EXITS ZERO — success — for a unit whose state is
#    "static", which is exactly the state this unit is in now that its [Install]
#    section has been removed. Written the obvious way, this check would report
#    that the service is switched on, on every single build, forever.
#
#    So we read the files instead, which is this repo's rule anyway: a unit is
#    started at boot if it has an [Install] section saying so, or if something
#    has linked it into a .wants folder. Both are things you can look at.
say "Nothing installs creator apps on its own"
AQ_UNIT=/usr/lib/systemd/system/aquarius-flatpak-preinstall.service
if [ ! -r "${AQ_UNIT}" ]; then
    bad "${AQ_UNIT} is missing — 'aq apps install --all' would have nothing to run"
elif grep -q '^\[Install\]' "${AQ_UNIT}"; then
    bad "the installer service has an [Install] section — apps would still install themselves at boot"
else
    ok "the installer service has no [Install] section, so nothing switches it on"
fi

# The `|| true` is not decoration: under `set -e` with `pipefail`, a find that
# is handed a folder that does not exist exits non-zero, the whole pipeline is
# judged failed, and the assignment takes the script down with it — a build that
# dies with no message at all rather than a check that says something.
AQ_WANTS="$(find /etc/systemd/system /usr/lib/systemd/system \
    -name 'aquarius-flatpak-preinstall.service' -path '*.wants/*' 2> /dev/null \
    | sort || true)"
if [ -n "${AQ_WANTS}" ]; then
    bad "something has linked the installer service into a .wants folder, which starts it at boot:"
    printf '%s\n' "${AQ_WANTS}" | sed 's/^/       /' >&2
else
    ok "nothing has linked it into a .wants folder either"
fi

# And the state systemd itself reports, printed rather than judged — because the
# word it prints ("static") is the useful thing in a build log, and its exit code
# is the misleading thing.
echo "  note   systemd calls it: $(systemctl is-enabled aquarius-flatpak-preinstall.service 2>&1 || true)"

# ==============================================================================
# 6. The window can read a catalogue — the fault that started all this
# ==============================================================================
# Two readings, and both matter.
#
#   (a) Against a small made-up file in tests/, which is how the READING itself
#       is tested: a deliberately broken line has to be skipped and counted, and
#       choosing OBS on its own has to pull its plug-ins along.
#
#   (b) Against THE REAL LIST IN THIS IMAGE, read with the real parser. This is
#       the check whose absence let a machine ship in September 2026 that could
#       not read its own shopping list.
say "Reading a catalogue: a made-up one, to test the reading"

if [ ! -r "${FIXTURE}" ]; then
    bad "the test catalogue ${FIXTURE} is missing from the build context"
else
    FIX_OUT="$(mktemp)"
    if "${CHOOSER}" --dry-run --catalog-from "${FIXTURE}" > "${FIX_OUT}" 2> /dev/null; then
        ok "the window read the test catalogue"
    else
        bad "the window could not read the test catalogue"
    fi
    sed 's/^/       /' "${FIX_OUT}"

    aq_file_has "${FIX_OUT}" '^apps offered: 8$' \
        "it found the eight apps in the test catalogue"
    aq_file_has "${FIX_OUT}" '^plug-ins hidden: 2$' \
        "it kept the two plug-ins out of the choices"
    aq_file_has "${FIX_OUT}" '^unreadable lines: 1$' \
        "it skipped the one deliberately broken line instead of guessing at it"
    aq_file_has "${FIX_OUT}" '^preselected by default: 6$' \
        "it ticked the six recommended ones"
    aq_file_has "${FIX_OUT}" '^orphaned plug-ins: 0$' \
        "every plug-in in the test catalogue belongs to an app somebody can pick"

    # ⚠️ THE TWO KINDS OF APP, ADDED 2026-09-04. The test catalogue carries one
    # entry of the new kind — thirteen fields instead of nine — so this is what
    # proves the window reads the extra fields rather than skipping the line as
    # unreadable, which is exactly what an older parser would do.
    aq_file_has "${FIX_OUT}" '^flatpak entries: 9$' \
        "it read the nine Flathub entries"
    aq_file_has "${FIX_OUT}" '^appimage entries: 1$' \
        "and the one app of ours, with its four extra fields"
    rm -f "${FIX_OUT}"

    # THE PLUG-IN RULE, PROVED. Choosing OBS Studio and nothing else must produce
    # three things to install: OBS, its capture plug-in, and the Vulkan layer
    # that goes inside the game — the piece everybody forgets, which makes game
    # recording silently record nothing when it is missing.
    say "Choosing OBS on its own still brings its plug-ins"
    OBS_OUT="$(mktemp)"
    "${CHOOSER}" --dry-run --catalog-from "${FIXTURE}" \
        --select com.obsproject.Studio > "${OBS_OUT}" 2> /dev/null || true
    sed 's/^/       /' "${OBS_OUT}"
    aq_file_has "${OBS_OUT}" '^would install: 3$' \
        "picking OBS alone installs three things, not one"
    aq_file_has "${OBS_OUT}" '^  com\.obsproject\.Studio//stable$' \
        "OBS Studio itself"
    aq_file_has "${OBS_OUT}" '^  com\.obsproject\.Studio\.Plugin\.OBSVkCapture//stable$' \
        "its game-capture plug-in comes too"
    aq_file_has "${OBS_OUT}" '^  org\.freedesktop\.Platform\.VulkanLayer\.OBSVkCapture//25\.08$' \
        "and the Vulkan layer, at its own branch, which is the piece everyone forgets"
    # Only Flatpaks were chosen, so only one installer runs and there is exactly
    # one password prompt — the way it always worked.
    aq_file_has "${OBS_OUT}" '^installer runs: 1$' \
        "picking only Flathub apps runs one installer, as it always did"
    aq_file_has "${OBS_OUT}" '^password prompts: 1$' \
        "and asks for a password once"
    rm -f "${OBS_OUT}"

    # ==========================================================================
    # THE PASSWORD SPLIT — the design decision of 2026-09-04, proved
    # ==========================================================================
    # ⚠️ THIS IS THE CHECK THAT MATTERS MOST IN THIS FILE. Aquarius Editor goes
    #    into the person's OWN HOME FOLDER, so installing it needs no
    #    administrator permission at all — and asking for a password to write
    #    inside somebody's home folder would be theatre. Worse than theatre: the
    #    password prompt is the one part of this whole feature that has actually
    #    failed on the bench (2026-09-04, no polkit agent in the Aquarius
    #    session), so every route that avoids needing one is a route that
    #    cannot fail that way.
    #
    #    Somebody who ticks ONLY our own app must therefore get NO prompt, and
    #    that is not something a screenshot could ever tell us.
    say "Picking only one of our own apps asks for no password at all"
    OURS_OUT="$(mktemp)"
    "${CHOOSER}" --dry-run --catalog-from "${FIXTURE}" \
        --select os.example.testapp > "${OURS_OUT}" 2> /dev/null || true
    sed 's/^/       /' "${OURS_OUT}"
    aq_file_has "${OURS_OUT}" '^would install: 1$' \
        "one app, and no plug-ins tagging along"
    aq_file_has "${OURS_OUT}" '^installer runs: 1$' \
        "one installer runs"
    aq_file_has "${OURS_OUT}" '^password prompts: 0$' \
        "and it asks for NO password, because nothing outside the home folder is touched"
    aq_file_has "${OURS_OUT}" '^  appimage: 1 app\(s\), steps 1-1 of 1' \
        "the app of ours goes to the home-folder installer"
    rm -f "${OURS_OUT}"

    # And the mixed case: two installers, one bar, steps numbered straight
    # through. Without --step-offset the bar would jump back to the start half
    # way through, which is the thing this arrangement exists to avoid.
    say "Picking both kinds runs two installers behind ONE progress bar"
    MIX_OUT="$(mktemp)"
    "${CHOOSER}" --dry-run --catalog-from "${FIXTURE}" \
        --select org.kde.kdenlive,os.example.testapp > "${MIX_OUT}" 2> /dev/null || true
    sed 's/^/       /' "${MIX_OUT}"
    aq_file_has "${MIX_OUT}" '^installer runs: 2$' \
        "two installers, because the two kinds are installed in different ways"
    aq_file_has "${MIX_OUT}" '^password prompts: 1$' \
        "and still only one password prompt, for the Flathub half"
    aq_file_has "${MIX_OUT}" '^  flatpak: 1 app\(s\), steps 1-1 of 2' \
        "the Flathub app is step 1 of 2 — the password comes first, while the person is watching"
    aq_file_has "${MIX_OUT}" '^  appimage: 1 app\(s\), steps 2-2 of 2' \
        "and ours is step 2 of 2, counted on the same scale rather than starting again at one"
    rm -f "${MIX_OUT}"
fi

# ==============================================================================
# 6b. The other installer
# ==============================================================================
# The window now has two of them. The Flatpak one is checked above; this is the
# one that installs our own apps into a home folder. Its own rehearsal is run by
# build_files/64-creator-apps.sh, which is where the app it installs is
# described — what is checked HERE is only that the window and it agree about
# how they talk to each other.
say "The window and the home-folder installer agree"
AQ_APPIMAGE_INSTALLER=/usr/libexec/aquarius-appimage-install
if [ -x "${AQ_APPIMAGE_INSTALLER}" ]; then
    ok "$(basename "${AQ_APPIMAGE_INSTALLER}") is here and is runnable"
else
    bad "${AQ_APPIMAGE_INSTALLER} is missing — the window would offer an app nobody can install"
fi
aq_file_has "${CHOOSER}" "APPIMAGE_INSTALLER = \"${AQ_APPIMAGE_INSTALLER}\"" \
    "the window knows where the home-folder installer is"
# ⚠️ pkexec MUST NOT APPEAR ON THAT PATH. If it ever did, installing Aquarius
#    Editor would ask for a password to write inside somebody's own home folder
#    — and would fail outright in the Aquarius session on a machine with no
#    polkit agent, which is the exact bench fault of 2026-09-04.
if grep -n 'pkexec' "${CHOOSER}" | grep -q 'APPIMAGE_INSTALLER'; then
    bad "the window sends the home-folder installer through pkexec — it must not"
else
    ok "the home-folder installer is never sent through pkexec"
fi
# The pattern is written [-]-step-offset rather than --step-offset because a
# pattern that begins with two dashes is read by grep as an option, not as
# something to look for. The square brackets are a character class of one.
for opt in step-offset step-total; do
    aq_file_has "${CHOOSER}" "[-]-${opt}" \
        "the window tells each installer which part of the whole job it is (--${opt})"
    aq_file_has "${HELPER}" "[-]-${opt}" \
        "the Flatpak installer understands --${opt}"
    aq_file_has "${AQ_APPIMAGE_INSTALLER}" "[-]-${opt}" \
        "the home-folder installer understands --${opt}"
done

say "Reading the REAL list this image ships"
REAL_OUT="$(mktemp)"
if "${CHOOSER}" --dry-run > "${REAL_OUT}" 2> /dev/null; then
    ok "the window read the list this image actually ships"
else
    bad "the window could NOT read the list this image ships — this is the September 2026 bench fault, back again"
fi
sed 's/^/       /' "${REAL_OUT}"

# The numbers are checked as "more than none", not as exact counts, on purpose:
# adding an app to AquariusOS must not mean editing this file.
AQ_OFFERED="$(sed -n 's/^apps offered: //p' "${REAL_OUT}")"
AQ_TICKED="$(sed -n 's/^preselected by default: //p' "${REAL_OUT}")"
AQ_UNREADABLE="$(sed -n 's/^unreadable lines: //p' "${REAL_OUT}")"
AQ_ORPHANS="$(sed -n 's/^orphaned plug-ins: //p' "${REAL_OUT}")"

if [ "${AQ_OFFERED:-0}" -ge 1 ] 2> /dev/null; then
    ok "${AQ_OFFERED} apps are offered to choose from"
else
    bad "the window would show an EMPTY list of apps"
fi

# ⚠️ AN EMPTY RECOMMENDED SET WOULD BE A SILENT DISASTER: the window would open
# with nothing ticked, most people would press Install on nothing, and the
# operating system would look like it comes with no creator apps at all.
if [ "${AQ_TICKED:-0}" -ge 1 ] 2> /dev/null; then
    ok "${AQ_TICKED} of them are ticked when the window opens"
else
    bad "NOTHING would be ticked when the window opens"
fi

if [ "${AQ_UNREADABLE:-1}" -eq 0 ] 2> /dev/null; then
    ok "every line of the real list was understood"
else
    bad "${AQ_UNREADABLE} line(s) of the real list could not be understood"
fi

if [ "${AQ_ORPHANS:-1}" -eq 0 ] 2> /dev/null; then
    ok "every plug-in belongs to an app somebody can actually choose"
else
    bad "${AQ_ORPHANS} plug-in(s) belong to an app nobody can choose, so they would never be installed"
fi
rm -f "${REAL_OUT}"

# ==============================================================================
# 7. The installer rehearses without touching anything
# ==============================================================================
say "The installer's rehearsal"
REH_OUT="$(mktemp)"
"${HELPER}" --dry-run --progress-fd 2 org.kde.kdenlive//stable \
    > "${REH_OUT}" 2>&1 || true
sed 's/^/       /' "${REH_OUT}"
aq_file_has "${REH_OUT}" '^STEP 1/1 org\.kde\.kdenlive$' \
    "it announces each app on the progress channel"
aq_file_has "${REH_OUT}" '^PERCENT 100$' \
    "it reports how far along it is"
aq_file_has "${REH_OUT}" '^DONE$' \
    "and says when it has finished"
rm -f "${REH_OUT}"

# It must refuse to install as an ordinary person rather than half-trying. The
# message is the point: "you are not an administrator" is something a person can
# act on; Flatpak's own wording for the same thing is not.
say "It refuses to install without permission, politely"
REF_OUT="$(mktemp)"
if aq_have runuser && id nobody > /dev/null 2>&1; then
    runuser -u nobody -- "${HELPER}" org.kde.kdenlive//stable > "${REF_OUT}" 2>&1 || true
    if grep -q 'administrator' "${REF_OUT}"; then
        ok "run without permission, it explains itself instead of failing obscurely"
    else
        bad "run without permission, it does not say why it stopped"
    fi
    sed 's/^/       /' "${REF_OUT}"
else
    echo "  note   no runuser or no 'nobody' account in this image; skipping"
fi
rm -f "${REF_OUT}"

# ==============================================================================
# 8. Write down how this image turned out
# ==============================================================================
say "Recording what this layer added"
install -d -m 0755 /usr/share/aquarius
{
    echo "# How the AquariusOS creator apps chooser turned out on this image."
    echo "# Written by build_files/66-creator-apps-chooser.sh. Read by CI and by docs."
    echo "status=present"
    echo "apps_offered=${AQ_OFFERED:-unknown}"
    echo "preselected=${AQ_TICKED:-unknown}"
    echo "auto_install=off"
} > /usr/share/aquarius/creator-apps-chooser.env
chmod 0644 /usr/share/aquarius/creator-apps-chooser.env
sed 's/^/       /' /usr/share/aquarius/creator-apps-chooser.env

aq_finish "Creator apps chooser"
