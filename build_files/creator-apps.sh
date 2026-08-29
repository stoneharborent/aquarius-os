#!/bin/bash
# ==============================================================================
# AquariusOS — the creator app layer  (Phase 2, Workstream A)
# ==============================================================================
# Plain English: this is the step that makes AquariusOS a *creator's* OS rather
# than "Bazzite with a new paint job".
#
# There are exactly THREE ways an app can reach a user, and which one an app
# gets is a real decision, not an implementation detail:
#
#   BAKED IN.    Aquarius Editor and Aquarius Writer. They are ours, they are on
#                no app store, so their Linux releases are downloaded HERE
#                during the build, checked against the checksums GitHub
#                published with them, and unpacked into the image. They are as
#                much a part of the OS as the file manager.
#
#   PREINSTALLED. Firefox and Google Chrome, and nothing else. A web browser is
#                the one app a computer is unusable without, so it should simply
#                be there. They are *listed* rather than baked, and a small
#                service installs them the first time the machine is online.
#
#   OFFERED.     OBS Studio, Audacity, Blender and DaVinci Resolve. One tick-box
#                window on the first login, everything pre-ticked, so saying yes
#                to all of it is one click — but three gigabytes of 3D suite is
#                still somebody's decision. Declining is never a dead end: the
#                same window lives in the app grid forever.
#
# DaVinci Resolve is a case of its own inside that last group: nobody except
# Blackmagic is allowed to hand out the installer, so all AquariusOS can offer
# is to walk you through it. No file of Blackmagic's is anywhere in this image.
#
# Nobody has to open a terminal for any of it.
#
# Called from build_files/build.sh. Everything it copies into place lives in
# system_files/ except the two Aquarius apps, which are downloaded here.
#
# The beginner-facing write-up of all of this: docs/creator-apps.md
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# WHICH RELEASES WE BAKE IN
# ------------------------------------------------------------------------------
# Each line is: <folder name in the OS> <GitHub repo> <release tag>
#
# We do NOT name the file, and we do NOT write down its checksum. Both are read
# out of the SHA256SUMS.txt that the release publishes, which means:
#   * tagging a new release only ever changes the tag below, and
#   * the checksum can never drift out of date, because there isn't one to
#     forget to update.
#
# The rule is one .AppImage per release. If a release ever publishes two, this
# script stops rather than guessing which one is the app.
#
# ⚠️ Aquarius Writer's v0.1.0 release was still being produced when this was
#    written (2026-08-28). If the build fails on the Writer with a 404, that is
#    what happened — the release is not published yet. Nothing here needs
#    changing; just re-run the build once it is.
#
# TODO (Phase 2, deliberate): nothing else gets baked in this way yet. Every
# other creator app is a Flatpak, on purpose — Flatpaks update on their own
# schedule and a broken one can never stop the OS from booting.
# ------------------------------------------------------------------------------

AQUARIUS_APPS=(
    "aquarius-editor stoneharborent/aquarius-editor v0.3.0"
    "aquarius-writer stoneharborent/aquarius-writer v0.1.0"
)

# Where the unpacked apps live inside the OS. /usr/lib is the normal home for
# "program files that are not meant to be run directly by typing their name" —
# the thing users actually run is the small launcher in /usr/bin.
APP_ROOT="/usr/lib/aquarius"

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------

# Print a loud, readable error and stop the whole build. `set -e` means nothing
# half-installed ever ships, but a bare "curl: (22)" tells you nothing, so every
# failure below goes through here with a sentence explaining itself.
die() {
    echo ""
    echo "=============================================================="
    echo "AquariusOS creator-app build step FAILED"
    echo "--------------------------------------------------------------"
    printf '%s\n' "$@"
    echo "=============================================================="
    echo ""
    exit 1
}

say() { echo ">> $*"; }

# ==============================================================================
# JOB 1 — bake in the Aquarius apps (Editor and Writer)
# ==============================================================================
# The releases are Linux "AppImages": one big file with the whole program inside
# it, compressed. Normally you double-click one and it mounts itself like a disc
# every time it runs, using a system component called FUSE.
#
# WE DELIBERATELY DO NOT DO THAT. We unpack the AppImage here, at build time,
# and ship the loose files. Reasons, in order of how much they matter:
#
#   1. Nothing can go missing at runtime. The self-mounting trick needs FUSE
#      present and working on the user's machine; when it isn't, the app dies
#      with "dlopen(): error loading libfuse.so.2", which is not a message a
#      beginner can act on. Unpacked, there is no such dependency at all.
#   2. We can turn Chrome's security sandbox back on. Aquarius Editor is an
#      Electron app; its sandbox helper has to be a special "setuid" file, and a
#      self-mounted AppImage is mounted in a way that forbids that. Unpacked, we
#      set it correctly below and the app runs sandboxed like a browser tab.
#   3. It starts faster. The AppImage's insides are xz-compressed, which is
#      excellent for download size and slow to read; unpacked files are just
#      files.
#
# The price is disk space: unpacked, these apps take roughly two to three times
# the size of the compressed download. That trade — a bigger image in exchange
# for an app that cannot fail to start — is the right way round for the flagship
# app of the OS. The exact numbers get printed in the build log below.
# ------------------------------------------------------------------------------

bake_appimage() {
    local name="$1" repo="$2" tag="$3"
    local base="https://github.com/${repo}/releases/download/${tag}"
    local work="/var/tmp/aquarius-bake-${name}"

    say "Baking in ${name} (${repo} ${tag})"
    rm -rf "$work"
    mkdir -p "$work"

    # --- the checksum file, first --------------------------------------------
    # This is fetched BEFORE the app itself on purpose: it is tiny, so if the
    # release does not exist we find out in a second instead of after a 600 MB
    # download.
    if ! curl --retry 3 --retry-delay 5 -fsSL -o "$work/SHA256SUMS.txt" "${base}/SHA256SUMS.txt"; then
        die "Could not download the checksum file for ${name}." \
            "" \
            "  Tried: ${base}/SHA256SUMS.txt" \
            "" \
            "The usual cause is that the release does not exist yet, or the tag" \
            "in build_files/creator-apps.sh does not match a published release." \
            "Check https://github.com/${repo}/releases and re-run this build."
    fi

    # --- work out which file is the Linux app --------------------------------
    # SHA256SUMS.txt looks like:  <64 hex characters>  ./SomeFile-x86_64.AppImage
    # We want the one and only .AppImage line. Two would mean the release
    # changed shape and a human needs to look at it.
    local matches count file sum
    matches="$(grep -E '\.AppImage[[:space:]]*$' "$work/SHA256SUMS.txt" || true)"
    count="$(printf '%s' "$matches" | grep -c . || true)"
    if [ "$count" -ne 1 ]; then
        die "Expected exactly one .AppImage in ${repo} ${tag}, found ${count}." \
            "" \
            "SHA256SUMS.txt said:" \
            "$(cat "$work/SHA256SUMS.txt")"
    fi
    sum="$(printf '%s' "$matches" | awk '{print $1}')"
    # Take the file name as "everything after the fingerprint", NOT as "the
    # second word". Release file names are allowed to contain spaces (some
    # toolkits name them after the product, e.g. "Aquarius Writer_0.1.0…"), and
    # word-splitting would silently chop such a name in half.
    # The optional "*" is sha256sum's marker for a binary file; the "./" is the
    # path prefix these files are written with.
    file="$(printf '%s' "$matches" | sed -E 's/^[0-9a-fA-F]+[[:space:]]+\*?//')"
    file="${file##*/}"

    # A release file name is allowed to contain spaces; a URL is not. Swap them
    # for the %20 that means "space" in a web address.
    local url_file="${file// /%20}"

    say "  file:     ${file}"
    say "  expected: ${sum}"

    if ! curl --retry 3 --retry-delay 5 -fL --progress-bar -o "$work/app.AppImage" "${base}/${url_file}"; then
        die "Could not download ${file} from ${repo} ${tag}." \
            "  Tried: ${base}/${url_file}"
    fi

    # --- verify before we trust it -------------------------------------------
    # If these two strings differ, the download is not the file the release
    # published — corrupted, truncated, or tampered with — and the build stops.
    local got
    got="$(sha256sum "$work/app.AppImage" | awk '{print $1}')"
    say "  actual:   ${got}"
    if [ "$got" != "$sum" ]; then
        die "CHECKSUM MISMATCH for ${file}." \
            "" \
            "  expected ${sum}" \
            "  actual   ${got}" \
            "" \
            "The downloaded file is not what the release says it should be." \
            "Nothing has been installed. Do not re-run until this is understood."
    fi
    say "  checksum OK"

    # --- unpack ---------------------------------------------------------------
    # "--appimage-extract" is the AppImage's own built-in unpack mode. It does
    # NOT need FUSE (that is only for the self-mounting mode), so it works fine
    # inside a container build.
    #
    # The chmod is not decoration. A GitHub release attachment always arrives
    # WITHOUT its "you may run this" flag, whatever it had when it was built, so
    # without this line the next command is "Permission denied".
    chmod +x "$work/app.AppImage"
    if ! ( cd "$work" && ./app.AppImage --appimage-extract >/dev/null ); then
        die "${name}: the AppImage refused to unpack." \
            "" \
            "The download's fingerprint was correct, so the file is not damaged." \
            "That leaves two likely causes: it is not really an AppImage, or it" \
            "was built for a different kind of processor than this build runs on" \
            "(AquariusOS is x86_64 only — see the standing decisions in CLAUDE.md)."
    fi
    [ -d "$work/squashfs-root" ] || die "${name}: --appimage-extract produced no squashfs-root."
    [ -x "$work/squashfs-root/AppRun" ] || die "${name}: no runnable AppRun inside the AppImage."

    mkdir -p "$APP_ROOT"
    rm -rf "${APP_ROOT:?}/${name}"
    mv "$work/squashfs-root" "${APP_ROOT}/${name}"

    # --- the Chrome sandbox, if this app has one ------------------------------
    # Electron apps ship a small helper called chrome-sandbox that has to be
    # owned by root and carry the "setuid" bit, or the app refuses to start its
    # security sandbox. This is exactly the fix that unpacking makes possible.
    if [ -f "${APP_ROOT}/${name}/chrome-sandbox" ]; then
        chown root:root "${APP_ROOT}/${name}/chrome-sandbox"
        chmod 4755 "${APP_ROOT}/${name}/chrome-sandbox"
        say "  chrome-sandbox enabled"
    fi

    # --- the icon -------------------------------------------------------------
    # Different app toolkits put their icon in different places under different
    # names, so instead of guessing we take the biggest PNG we can find and
    # install it under a name WE choose. The .desktop files in system_files/
    # then say Icon=aquarius-editor / Icon=aquarius-writer and always match.
    local icon
    icon="$(find "${APP_ROOT}/${name}" -maxdepth 6 -type f -name '*.png' \
              \( -path '*/icons/*' -o -path "${APP_ROOT}/${name}/*.png" \) \
              -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)"
    if [ -n "$icon" ]; then
        install -Dm0644 "$icon" "/usr/share/pixmaps/${name}.png"
        say "  icon installed from ${icon#"${APP_ROOT}/${name}/"}"
    else
        # Not fatal — the app still launches, it just shows a generic icon, and
        # a missing icon must never cost us a whole OS build.
        echo "  WARNING: no icon found inside ${name}; the app grid will show a placeholder."
    fi

    # --- window matching ------------------------------------------------------
    # Every window tells the desktop an internal "class" name. If our menu entry
    # does not know that name, the taskbar shows a running Aquarius Editor as a
    # SECOND, nameless icon next to the one you clicked. Rather than guess the
    # name, we read it out of the .desktop file the app ships inside itself, and
    # copy it into ours.
    local ours="/usr/share/applications/${name}.desktop"
    local upstream wmclass
    upstream="$(find "${APP_ROOT}/${name}" -maxdepth 4 -type f -name '*.desktop' | head -1 || true)"
    if [ -n "$upstream" ] && [ -f "$ours" ]; then
        wmclass="$(grep -m1 '^StartupWMClass=' "$upstream" | cut -d= -f2- || true)"
        if [ -n "$wmclass" ] && ! grep -q '^StartupWMClass=' "$ours"; then
            echo "StartupWMClass=${wmclass}" >>"$ours"
            say "  window class: ${wmclass}"
        fi
    fi

    # --- tidy up and report ---------------------------------------------------
    rm -rf "$work"
    say "  installed size: $(du -sh "${APP_ROOT}/${name}" | cut -f1) at ${APP_ROOT}/${name}"
}

for entry in "${AQUARIUS_APPS[@]}"; do
    # shellcheck disable=SC2086  # the entry is three known, space-free words
    bake_appimage $entry
done

# The launchers in /usr/bin and the app-grid entries in /usr/share/applications
# arrived with the system_files/ copy at the top of build.sh. Prove they line up
# with what we just unpacked, so a typo can never ship as a dead menu icon.
for name in aquarius-editor aquarius-writer; do
    [ -x "/usr/bin/${name}" ] || die "Launcher /usr/bin/${name} is missing or not executable."
    [ -f "/usr/share/applications/${name}.desktop" ] || die "App-grid entry for ${name} is missing."
    [ -x "${APP_ROOT}/${name}/AppRun" ] || die "${APP_ROOT}/${name}/AppRun is missing or not executable."
done

# ==============================================================================
# JOB 2 — queue the browsers for first boot
# ==============================================================================
# Exactly two Flatpaks arrive without being asked for: Firefox and Chrome. A
# browser is the one app a computer is unusable without. Everything else a
# creator might want is OFFERED instead, in a tick-box window on the first login
# (JOB 3 below), so that three gigabytes of Blender is always somebody's choice.
#
# The list itself is a plain text file that arrived with system_files/:
#     /usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall
# and the service that acts on it is:
#     /usr/lib/systemd/system/aquarius-flatpak-preinstall.service
#
# All that is left to do here is switch that service on. Why it is our own
# service and not Bazzite's: docs/creator-apps.md, "How the apps arrive".
# ------------------------------------------------------------------------------

systemctl enable aquarius-flatpak-preinstall.service

# ==============================================================================
# JOB 3 — the first-login "which creator apps do you want?" window
# ==============================================================================
# Nothing to switch on: it is an ordinary desktop start-up item, and it arrived
# with system_files/ like everything else. Listed here so that the three ways
# apps reach a user are all named in one place.
#
#   asks the question : /etc/xdg/autostart/aquarius-creator-apps-offer.desktop
#   does the work     : /usr/libexec/aquarius-creator-apps-offer
#   opens it again    : /usr/share/applications/aquarius-install-creator-apps.desktop
#
# Prove the pieces are all present, so a rename can never ship as a start-up
# item pointing at nothing.
# ------------------------------------------------------------------------------

[ -x /usr/libexec/aquarius-creator-apps-offer ] \
    || die "The creator-apps offer script is missing or not executable."
[ -f /etc/xdg/autostart/aquarius-creator-apps-offer.desktop ] \
    || die "The creator-apps offer is not wired into start-up."
[ -f /usr/share/applications/aquarius-install-creator-apps.desktop ] \
    || die "\"Install Creator Apps\" is missing from the app grid."

# ==============================================================================
# JOB 4 — make our `ujust` recipes visible
# ==============================================================================
# `ujust` is the friendly command menu Bazzite gives us — type `ujust` and you
# get a list of one-line jobs. The menu is assembled from a plain list of
# "import" lines in /usr/share/ublue-os/justfile, and a recipe file that isn't
# imported there simply does not exist as far as `ujust` is concerned.
#
# Our file is numbered 96 so it lands after all of Bazzite's (10 to 95) and can
# never be renumbered into the middle of theirs.
#
# The grep makes this safe to run twice: if the line is already there we leave
# it alone instead of adding a duplicate.
# ------------------------------------------------------------------------------

AQUARIUS_JUST="/usr/share/ublue-os/just/96-aquarius-creator.just"
[ -f "$AQUARIUS_JUST" ] || die "Missing ${AQUARIUS_JUST} — the system_files copy did not happen?"
if ! grep -qF "$AQUARIUS_JUST" /usr/share/ublue-os/justfile; then
    echo "import \"${AQUARIUS_JUST}\"" >>/usr/share/ublue-os/justfile
fi

say "Creator app layer done."
