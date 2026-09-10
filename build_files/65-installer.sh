#!/usr/bin/bash
# ==============================================================================
# STEP 7e — Aquarius Installer, the one app that installs anything
# ==============================================================================
# WHAT THIS IS, IN PLAIN ENGLISH
#
# On a Mac you double-click the thing you downloaded and it installs. This step
# puts that into AquariusOS. It adds one window and makes it the thing that
# opens every kind of downloaded app file, so the whole experience is:
#
#     download  →  double-click  →  one window  →  Install  →  it is in your apps
#
# ...the same three seconds whether the file was an .rpm, a .deb, an AppImage,
# a .flatpakref or a tarball with a program inside it.
#
# Three files are added:
#
#   /usr/lib/aquarius/python/aquarius_installer.py
#       THE PART THAT DECIDES. The sorter (what is this file?), the routes
#       (how does it land?) and the registry (what happened, so that removing
#       it is exact). It has no window in it at all, which is what lets the
#       window, `aq apps` and the tests all be one implementation.
#
#   /usr/libexec/aquarius-installer
#       The window. Python, GTK 4 and libadwaita, exactly like the app chooser
#       it sits beside, and it imports the same shared pieces.
#
#   /usr/share/applications/aquarius-installer.desktop
#       "Aquarius Installer" in the app grid, and — through its MimeType line
#       plus /etc/xdg/mimeapps.list — the thing that opens a download.
#
# ...and one small file of file-type names, /usr/share/mime/packages/
# aquarius-installer.xml, because Linux has no name at all for a `.run` and no
# useful one for a `.snap` or a `.pkg`, and a file the system cannot name is a
# file that does nothing at all when you double-click it.
#
# ------------------------------------------------------------------------------
# ⚠️ THE APP CHOOSER IS HIDDEN FROM THE APP GRID BY THIS STEP
# ------------------------------------------------------------------------------
# "Aquarius Apps" (step 7d) is still here, still the second step of the welcome,
# still the one catalogue behind the Installer's "AquariusOS suggests" list. It
# just no longer has its own icon in the grid, because two app-store-shaped
# icons is how somebody ends up in the wrong one. One visible app.
#
# ------------------------------------------------------------------------------
# WHAT THIS STEP CHECKS, AND WHY EACH CHECK IS HERE
# ------------------------------------------------------------------------------
# Every check reads CONTENT — a file's text, a command's answer — and never a
# timestamp, for the reason written at the top of aq-lib.sh.
#
# The two that matter most:
#
#   * IT ASKS THE DESKTOP'S OWN TOOL which app opens an .rpm, rather than
#     reading our own mimeapps.list back and calling that proof. A file that
#     lists the right answer in the wrong place looks perfect and does nothing,
#     and "double-clicking did nothing" is the exact experience this whole
#     feature exists to end.
#
#   * IT RUNS THE INSTALLER'S OWN REHEARSAL, which really unpacks a real
#     archive into a throwaway home folder, really writes a menu entry, really
#     reads it back and really removes it. A build that never runs its own code
#     against its own files is the fault this repository has shipped twice.
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

WINDOW=/usr/libexec/aquarius-installer
MODULE=/usr/lib/aquarius/python/aquarius_installer.py
SHARED=/usr/lib/aquarius/python/aquarius_ui.py
ENTRY=/usr/share/applications/aquarius-installer.desktop
CHOOSER_ENTRY=/usr/share/applications/aquarius-creator-apps.desktop
HELPER=/usr/libexec/aquarius-creator-apps-install
MIME_XML=/usr/share/mime/packages/aquarius-installer.xml
MIMEAPPS=/etc/xdg/mimeapps.list
AQ=/usr/bin/aq
TESTS=/ctx/tests

# ==============================================================================
# 1. The tools the routes need — asked for by name, never assumed
# ==============================================================================
# ⚠️ EVERY ONE OF THESE IS A ROUTE THAT SILENTLY STOPS WORKING WITHOUT IT.
#
#   cpio       opens an .rpm's files. Without it, every .rpm says "AquariusOS
#              could not open that file" and nothing anywhere says why.
#   dpkg       provides dpkg-deb, which opens a .deb the same way. There is a
#              fallback that uses `ar`, and it is a fallback, not a plan.
#   binutils   provides `ar`, which is that fallback.
#   rpm        provides rpm2cpio, and is already here because this is an
#              rpm-based image — asked for anyway, because "already here" is
#              exactly the assumption that breaks quietly one day.
#
# ⚠️ AND NONE OF THEM EVER RUNS A PACKAGE'S OWN SCRIPTS. `rpm2cpio | cpio` and
#    `dpkg-deb -x` take the FILES out of a package and nothing else. The
#    install-time scripts — which on any other Linux run as an administrator on
#    your computer — are never even read. That is the whole safety argument for
#    Route A and it is a property of these two commands, not of our code.
say "What the installer's routes are built out of"
aq_dnf install \
    cpio \
    dpkg \
    binutils \
    rpm \
    desktop-file-utils \
    shared-mime-info \
    python3-gobject \
    gtk4 \
    libadwaita

aq_installed cpio dpkg binutils desktop-file-utils shared-mime-info

say "...and they are all runnable in this image"
for cmd in cpio rpm2cpio dpkg-deb ar ldd flatpak curl update-mime-database \
    update-desktop-database desktop-file-validate; do
    if aq_have "${cmd}"; then
        ok "${cmd} is here"
    else
        bad "${cmd} is missing — a route or a check that needs it would fail silently"
    fi
done

# ==============================================================================
# 2. The three programs
# ==============================================================================
say "The installer, its shared decider, and the window's own pieces"
if [ -x "${WINDOW}" ]; then
    ok "$(basename "${WINDOW}") is here and is runnable"
else
    bad "$(basename "${WINDOW}") is missing or is not runnable"
fi
for path in "${MODULE}" "${SHARED}"; do
    if [ -r "${path}" ]; then
        ok "$(basename "${path}") is here"
    else
        bad "${path} is missing"
    fi
done

# ⚠️ NOT `python3 -m py_compile`, which would leave a __pycache__ folder sitting
#    in /usr/libexec forever, in the shipped image, as a souvenir of the build.
say "Python can read both of them"
for path in "${WINDOW}" "${MODULE}"; do
    if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-installer.pyc", doraise=True)' \
        "${path}"; then
        ok "$(basename "${path}") is valid Python"
    else
        bad "$(basename "${path}") is not valid Python"
    fi
done
rm -f /tmp/aq-installer.pyc

# The deciding half must import with NOTHING graphical present, because that is
# what lets `aq apps`, the tests and this build step use it on a machine with no
# screen. If it ever grows a GTK import at the top of the file, this says so.
say "The deciding half imports with no screen at all"
if python3 -c 'import sys; sys.path.insert(0, "/usr/lib/aquarius/python"); import aquarius_installer; print("  routes:", aquarius_installer.ROUTE_FLATPAK, aquarius_installer.ROUTE_APPIMAGE, aquarius_installer.ROUTE_ARCHIVE, aquarius_installer.ROUTE_PACKAGE, aquarius_installer.ROUTE_REFUSE)'; then
    ok "aquarius_installer imports cleanly on its own"
else
    bad "aquarius_installer cannot be imported — every route would fail"
fi
if grep -Eq '^import gi|^from gi' "${MODULE}"; then
    bad "the deciding half imports GTK at the top of the file — it must work with no screen"
else
    ok "it does not pull GTK in, so it works with no screen"
fi

say "The window knows where the shared pieces are"
aq_file_has "${WINDOW}" 'sys\.path\.insert\(0, "/usr/lib/aquarius/python"\)' \
    "the window adds the shared-window folder to its search path"
aq_file_has "${WINDOW}" 'hero = aquarius_ui\.hero' \
    "it draws the top of every page with the shared hero helper"
# ⚠️ THE SAME CHECK THE CHOOSER CARRIES, FOR THE SAME 2026-09-04 BENCH FAULT: an
# Adw.StatusPage cannot be given the Aquarius mark, so a page built out of one
# is a page that is blank at the top while every page before it has the logo.
if grep -q 'Adw\.StatusPage(' "${WINDOW}"; then
    bad "a page of the window is an Adw.StatusPage — it cannot show the Aquarius mark"
else
    ok "no Adw.StatusPage is built anywhere in the window"
fi
# And the import that has to stay late. Importing aquarius_ui pulls GTK in, and
# every headless mode above has to work in a build container with no screen.
if grep -n 'import aquarius_ui' "${WINDOW}" | grep -qv '^[0-9]*: *import aquarius_ui$'; then
    ok "aquarius_ui is imported inside the function that draws, not at the top"
else
    bad "aquarius_ui is imported at the top of the window — --sort and --dry-run would need a screen"
fi

# ==============================================================================
# 3. The rules this feature is not allowed to break
# ==============================================================================
say "It never runs sudo, and it refuses to install as an administrator"
# Printable lines only: a comment may say the word, a command line may not.
if grep -vE '^[[:space:]]*#' "${WINDOW}" "${MODULE}" | grep -qE '"sudo"|\bsudo '; then
    bad "something in the installer runs sudo — pkexec is the only way it may ever ask"
    grep -vE '^[[:space:]]*#' "${WINDOW}" "${MODULE}" | grep -nE '"sudo"|\bsudo ' | sed 's/^/       /' >&2
else
    ok "nothing in it runs sudo"
fi
aq_file_has "${MODULE}" 'def running_as_root' \
    "it knows how to tell whether it is running as an administrator"
aq_file_has "${MODULE}" 'if running_as_root\(\)' \
    "and it checks before it installs or removes anything"

say "Route C is off, and the window says so"
aq_file_has "${MODULE}" 'OS_MARKERS = \[' \
    "it recognises a package that wants to change the operating system"
aq_file_has "${MODULE}" 'does not allow that, so updates always work' \
    "and refuses it in Royce's own words"
if grep -q 'rpm-ostree' "${MODULE}" "${WINDOW}"; then
    bad "the installer mentions layering onto the operating system — Route C is OFF"
else
    ok "nothing in it can layer a package onto the operating system"
fi

say "No conversion, ever"
if grep -qi 'alien' "${MODULE}" "${WINDOW}"; then
    bad "the installer mentions converting one kind of package into another"
else
    ok "there is no conversion anywhere in it"
fi

# ------------------------------------------------------------------------------
# Nothing a person reads may name another Linux
# ------------------------------------------------------------------------------
# ⚠️ ROYCE'S RULE, from 62-resolve-runtime.sh. A person installing an app is not
# helped by being told which distribution a file was built for; it tells them
# nothing they can act on and gives them something new to worry about.
#
# The allowlist at the end is not a loophole. `application/vnd.debian.binary-
# package` is the name the whole Linux desktop uses for a .deb file — it is a
# machine identifier in a MimeType line, not a sentence — and `dpkg-deb` is the
# name of a command. Neither is ever shown to anybody.
say "Nothing a person reads names another Linux"
AQ_LEAK=0
for f in "${WINDOW}" "${MODULE}" "${ENTRY}" "${MIMEAPPS}"; do
    [ -r "${f}" ] || continue
    if grep -vE '^[[:space:]]*#' "${f}" \
        | grep -vE 'vnd\.debian\.binary-package|dpkg-deb|dpkg|debian-binary' \
        | grep -qiE 'debian|ubuntu|fedora|rocky|arch linux|distrobox|podman'; then
        bad "$(basename "${f}") names another Linux in something a person reads:"
        grep -vE '^[[:space:]]*#' "${f}" \
            | grep -vE 'vnd\.debian\.binary-package|dpkg-deb|dpkg|debian-binary' \
            | grep -inE 'debian|ubuntu|fedora|rocky|arch linux|distrobox|podman' \
            | sed 's/^/       /' >&2
        AQ_LEAK=1
    fi
done
[ "${AQ_LEAK}" -eq 0 ] && ok "nothing a person reads names another Linux"

# ==============================================================================
# 4. The menu entry
# ==============================================================================
say "The app grid entry"
if [ ! -r "${ENTRY}" ]; then
    bad "${ENTRY} is missing"
elif desktop-file-validate "${ENTRY}"; then
    ok "aquarius-installer.desktop is a well-formed menu entry"
else
    bad "aquarius-installer.desktop is not a well-formed menu entry"
fi
aq_file_has "${ENTRY}" '^Name=Aquarius Installer$' \
    "it is called Aquarius Installer"
aq_file_has "${ENTRY}" "^Exec=${WINDOW} %F\$" \
    "it opens the window, and hands it the file that was double-clicked"
aq_file_has "${ENTRY}" '^StartupWMClass=org\.aquariusos\.Installer$' \
    "its window class matches the one the window sets, so the dock can join them"
aq_file_has "${WINDOW}" 'APP_ID = "org\.aquariusos\.Installer"' \
    "...and the window really does set that name"
aq_file_has "${ENTRY}" '^Categories=System;PackageManager;$' \
    "it is filed where an app installer belongs"
aq_file_has "${ENTRY}" '^Icon=aquarius-installer$' \
    "it asks for its own icon"

say "Exactly one of the two app windows is in the app grid"
aq_file_has "${CHOOSER_ENTRY}" '^NoDisplay=true$' \
    "the older app chooser is hidden, so there is one visible app for installing things"
if grep -q '^NoDisplay' "${ENTRY}"; then
    bad "Aquarius Installer itself is hidden from the app grid"
else
    ok "Aquarius Installer is the one that shows"
fi
# ...and the chooser is still reachable, because the welcome's second step is it.
aq_file_has /usr/libexec/aquarius-welcome 'CHOOSER = "/usr/libexec/aquarius-creator-apps"' \
    "the welcome still opens the chooser by its full path, which NoDisplay cannot affect"

# ==============================================================================
# 5. The file types — and the check that actually counts
# ==============================================================================
say "The file types Linux has no name for"
if [ ! -r "${MIME_XML}" ]; then
    bad "${MIME_XML} is missing"
else
    ok "$(basename "${MIME_XML}") is in the shared file-type folder"
fi

# Fold every file-type description in that folder into the one list the whole
# desktop reads. This is also what step 62 does for DaVinci Resolve projects;
# running it again here is harmless and is what makes OUR names real.
say "Folding the new names into the shared list"
if update-mime-database /usr/share/mime; then
    ok "the shared file-type list rebuilt with our names in it"
else
    bad "the shared file-type list would NOT rebuild — this breaks EVERY file type on the machine"
fi
update-desktop-database /usr/share/applications || true

# Read it back: does the system now agree what these files are?
say "The system agrees what these files are"
check_type() {                  # check_type <filename> <expected type>
    local name="$1" want="$2" got
    got="$(python3 - "${name}" <<'PY'
import subprocess
import sys

# `gio info` needs a real file; the question here is only about the NAME, so a
# tiny empty file with the right ending is exactly the right stand-in.
import os
import tempfile

folder = tempfile.mkdtemp()
path = os.path.join(folder, sys.argv[1])
open(path, "wb").write(b"\0" * 8)
done = subprocess.run(["gio", "info", "-a", "standard::content-type", path],
                      capture_output=True, text=True)
for line in done.stdout.splitlines():
    if "content-type:" in line:
        print(line.split(":", 1)[1].strip())
        break
PY
)"
    if [ "${got}" = "${want}" ]; then
        ok "${name} is a ${want}"
    else
        bad "${name} came out as '${got}', expected '${want}'"
    fi
}
if aq_have gio; then
    check_type "thing.run" "application/x-aquarius-run-installer"
    check_type "thing.snap" "application/vnd.snap"
    check_type "thing.pkg" "application/x-apple-installer-package"
    check_type "thing.rpm" "application/x-rpm"
    check_type "thing.deb" "application/vnd.debian.binary-package"
else
    bad "gio is missing, so nothing could ask the system what a file is"
fi

# ------------------------------------------------------------------------------
# ...and double-clicking one really does open US
# ------------------------------------------------------------------------------
# ⚠️ THE CHECK THIS WHOLE STEP EXISTS FOR. Everything above can be perfect and a
# double-click can still do nothing, because "which app opens this type" is
# answered from a CHAIN of files read in a fixed order, and a right answer in
# the wrong file in that chain is worth nothing. So this asks the desktop's own
# tool, with the same folders set that a real session has.
say "Double-clicking a download really does open Aquarius Installer"
AQ_XDG_HOME="$(mktemp -d)"
AQ_XDG_DATA="$(mktemp -d)"
default_app() {                 # default_app <mime type>
    XDG_CURRENT_DESKTOP=GNOME \
        XDG_CONFIG_HOME="${AQ_XDG_HOME}" \
        XDG_DATA_HOME="${AQ_XDG_DATA}" \
        XDG_CONFIG_DIRS=/etc/xdg \
        XDG_DATA_DIRS=/usr/local/share:/usr/share \
        gio mime "$1" 2> /dev/null \
        | sed -n 's/^Default application for.*: //p' \
        | head -1
}
for type in application/x-rpm \
    application/vnd.debian.binary-package \
    application/vnd.appimage \
    application/vnd.flatpak.ref \
    application/vnd.flatpak \
    application/x-aquarius-run-installer \
    application/vnd.snap \
    application/x-apple-diskimage \
    application/x-apple-installer-package \
    application/x-msi \
    application/vnd.microsoft.portable-executable; do
    answer="$(default_app "${type}")"
    if [ "${answer}" = "aquarius-installer.desktop" ]; then
        ok "${type} opens with Aquarius Installer"
    else
        bad "${type} opens with '${answer:-nothing}', not Aquarius Installer"
    fi
done

# And the two we deliberately do NOT take over. A .zip is far more often a
# folder of footage than an app, and a .sh is a text file people edit; taking
# either would break a normal day's work to fix a rare one. Both are still one
# right-click away under "Open With", and dropping either ON the window works.
for type in application/zip application/x-shellscript; do
    answer="$(default_app "${type}")"
    if [ "${answer}" = "aquarius-installer.desktop" ]; then
        bad "${type} now opens with Aquarius Installer — that was a deliberate NO"
    else
        ok "${type} still opens with '${answer:-whatever it did before}', as intended"
    fi
done
aq_file_has "${ENTRY}" 'application/zip' \
    "a zip is still offered Aquarius Installer under Open With"
rm -rf "${AQ_XDG_HOME}" "${AQ_XDG_DATA}"

# ==============================================================================
# 6. The icon
# ==============================================================================
# ⚠️ IT IS THE APP CHOOSER'S DRAWING UNDER A SECOND NAME, ON PURPOSE AND FOR
#    NOW. Aquarius Installer and Aquarius Apps are two faces of one idea, and
#    drawing a second nearly identical plate to say so would be worse than
#    reusing one. A drawing of its own is an open design item, written down in
#    branding/icons/README.md.
say "The installer's icon, in both themes"
for theme in Aquarius-Ice Aquarius-Midnight; do
    svg="/usr/share/icons/${theme}/scalable/apps/aquarius-installer.svg"
    png="/usr/share/icons/${theme}/64x64/apps/aquarius-installer.png"
    for f in "${svg}" "${png}"; do
        if [ -s "${f}" ]; then
            ok "${f#/usr/share/icons/} is here"
        else
            bad "${f} is missing or empty — the app grid would draw a blank square"
        fi
    done
    if cmp -s "${svg}" "/usr/share/icons/${theme}/scalable/apps/aquarius-apps.svg"; then
        ok "${theme}: it is the app chooser's drawing, byte for byte, as intended"
    else
        bad "${theme}: it has drifted from the app chooser's drawing — they are one drawing"
    fi
done

# ==============================================================================
# 7. The privileged helper grew three jobs, and kept the one it had
# ==============================================================================
say "The app helper does all four jobs"
for mode in install install-file uninstall update; do
    aq_file_has "${HELPER}" "        ${mode})" \
        "the helper knows how to ${mode}"
done
aq_file_has "${MODULE}" 'FLATPAK_HELPER = "/usr/libexec/aquarius-creator-apps-install"' \
    "and the installer asks that same helper rather than a second one of its own"
aq_file_has "${MODULE}" 'argv\.append\("pkexec"\)' \
    "which it reaches through pkexec — one prompt, asked by the desktop itself"

# ⚠️ THE OLD BEHAVIOUR HAS TO BE EXACTLY THE OLD BEHAVIOUR. The app chooser
# calls this helper with no --mode at all, so a default that drifted would break
# the first login on every new machine, and nothing about the chooser would look
# wrong.
say "...and with no mode named, it is still the app chooser's installer"
REH="$(mktemp)"
"${HELPER}" --dry-run --progress-fd 2 org.kde.kdenlive//stable > "${REH}" 2>&1 || true
sed 's/^/       /' "${REH}"
aq_file_has "${REH}" '^STEP 1/1 org\.kde\.kdenlive$' \
    "it still announces each app on the progress channel"
aq_file_has "${REH}" '^PERCENT 100$' "it still reports how far along it is"
aq_file_has "${REH}" '^DONE$' "and still says when it has finished"
aq_file_has "${REH}" 'flatpak install --system -y --noninteractive flathub' \
    "and it is still an install, not one of the new jobs"
rm -f "${REH}"

for mode in uninstall update; do
    REH="$(mktemp)"
    "${HELPER}" --mode "${mode}" --dry-run --progress-fd 2 com.example.App \
        > "${REH}" 2>&1 || true
    aq_file_has "${REH}" "flatpak ${mode} --system -y --noninteractive" \
        "--mode ${mode} rehearses the right command"
    aq_file_has "${REH}" '^DONE$' "--mode ${mode} finishes cleanly"
    rm -f "${REH}"
done

REH="$(mktemp)"
"${HELPER}" --mode nonsense --dry-run whatever > "${REH}" 2>&1 || true
aq_file_has "${REH}" 'is not one of the four' \
    "a job it does not know is refused before anything privileged happens"
rm -f "${REH}"

# ==============================================================================
# 8. `aq apps` and the window are one implementation
# ==============================================================================
say "The terminal reaches the same installer"
aq_file_has "${AQ}" 'AQ_APPS_INSTALLER="/usr/libexec/aquarius-installer"' \
    "aq knows where the installer is"
aq_file_has "${AQ}" 'aq apps what FILE' "aq apps what — what is this file?"
aq_file_has "${AQ}" 'aq apps search TERM' "aq apps search — find an app"
aq_file_has "${AQ}" '[-]-update-all' "aq apps update --all — the Update All button, as a word"
aq_file_has "${AQ}" '[-]-with-data' "aq apps remove --with-data — the tick box, as a word"
if bash -n "${AQ}"; then
    ok "aq is still valid shell"
else
    bad "aq is not valid shell"
fi

# ==============================================================================
# 9. The rehearsal — the check that runs the real code against real files
# ==============================================================================
# ⚠️ NOT A SERIES OF `echo`s. This really unpacks a real archive into a
#    throwaway home folder, really refuses a payload that wants the operating
#    system, really writes a menu entry, really reads it back and really removes
#    it. A rehearsal of the printing would prove nothing, and that shape of
#    fault is exactly what let an image ship in September 2026 that could not
#    read its own shopping list.
say "The installer rehearses every route, for real, in a folder it throws away"
DRY="$(mktemp)"
if "${WINDOW}" --dry-run > "${DRY}" 2>&1; then
    ok "the rehearsal ran and every one of its own checks passed"
else
    bad "the rehearsal FAILED — read the lines below"
fi
sed 's/^/       /' "${DRY}"
aq_file_has "${DRY}" '^checks failed: 0$' \
    "every check inside the rehearsal passed"
aq_file_has "${DRY}" 'goes to the package route' \
    "an .rpm and a .deb both go to the same route — no conversion anywhere"
aq_file_has "${DRY}" 'the Path= naming a folder this computer lacks was dropped' \
    "the menu entry repair really ran"
aq_file_has "${DRY}" 'a package that wants the operating system is refused' \
    "and Route C really is off"
AQ_PASSED="$(sed -n 's/^checks passed: //p' "${DRY}")"
rm -f "${DRY}"

# The sorter's own test, with the fixtures it builds for itself — a fake .deb,
# a fake .rpm-shaped payload, an AppImage-shaped tarball, the ldd failure, the
# registry, and remove with and without settings. Run here as well as on the
# build runner, because the version that matters is the one in the image.
say "The sorter's own test, against the copy in this image"
if [ -r "${TESTS}/test-installer-sorter.py" ]; then
    if python3 "${TESTS}/test-installer-sorter.py" "${MODULE}"; then
        ok "the sorter test passed against the installed decider"
    else
        bad "the sorter test FAILED against the installed decider"
    fi
else
    bad "${TESTS}/test-installer-sorter.py is missing from the build context"
fi

# ==============================================================================
# 10. Write down how this image turned out
# ==============================================================================
say "Recording what this layer added"
install -d -m 0755 /usr/share/aquarius
{
    echo "# How Aquarius Installer turned out on this image."
    echo "# Written by build_files/65-installer.sh. Read by CI and by docs."
    echo "status=present"
    echo "window=${WINDOW}"
    echo "rehearsal_checks=${AQ_PASSED:-unknown}"
    echo "route_c=off"
    echo "conversion=never"
    echo "chooser_visible=no"
} > /usr/share/aquarius/installer.env
chmod 0644 /usr/share/aquarius/installer.env
sed 's/^/       /' /usr/share/aquarius/installer.env

aq_finish "Aquarius Installer"
