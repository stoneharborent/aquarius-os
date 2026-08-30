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
    "aquarius-writer stoneharborent/aquarius-writer v0.2.0"
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

    # --- FIX THE PERMISSIONS. THIS IS NOT OPTIONAL. ---------------------------
    # This is the single most important block in this file, and it was missing
    # from the first shipped image. It is the whole of the 2026-08-28 bug.
    #
    # WHAT WENT WRONG (RTX 4090 bench test, then confirmed by pulling the
    # published image apart layer by layer)
    #
    # Both apps shipped, both appeared in the app grid, and clicking either did
    # absolutely nothing — no window, no error. TWO DIFFERENT FAULTS, one per
    # app, and the numbers below are read out of the image that was on the
    # machine, not guessed:
    #
    #   AQUARIUS WRITER   one file, AppRun.wrapped — the program AppRun hands
    #                     over to — was mode 0770. Owner and group may run it,
    #                     nobody else may. In a terminal:
    #
    #                       AppRun: line 12: …/AppRun.wrapped: Permission denied
    #
    #                     The same AppImage also carried 85 files as 0777.
    #
    #   AQUARIUS EDITOR   nothing wrong with any file. ALL 3,097 OF ITS FOLDERS
    #                     were mode 0700, starting with the app folder itself.
    #                     A folder you may not enter makes every file inside it
    #                     read as missing, so the launcher of the day reported
    #
    #                       Aquarius Editor does not seem to be installed
    #                       (…/AppRun is missing)
    #
    #                     about a file that was present and perfectly formed.
    #
    # WHY THE TWO APPS DIFFER AT ALL: each AppImage carries its own copy of the
    # runtime that implements `--appimage-extract`, and they do not agree about
    # what permissions to give the folders they create. The Writer's (from
    # linuxdeploy) makes them 0755. The Editor's (from electron-builder) makes
    # them 0700. Neither is wrong for its own purposes; both are our problem.
    #
    # ⚠️ AND NOTE HOW EASY THIS IS TO MISS WHEN TESTING. Extracting the same
    #    AppImage with `unsquashfs` on a developer machine produces 0755 folders
    #    and hides the Editor fault completely. Only the app's own extractor
    #    reproduces it. That is why the check that matters most now runs against
    #    the finished, published image (the "Verify creator apps" step in
    #    .github/workflows/build.yml) rather than against a local unpack.
    #
    # WHY IT IS THE BUILD'S JOB TO FIX
    # An AppImage carries whatever permissions its build machine and its own
    # extractor happen to produce, and normally that never shows, because the
    # person running an AppImage is the person who downloaded it. The moment we
    # unpack one into /usr — which we do on purpose, for good reasons, three
    # comments above — those become SYSTEM permissions, shared by every account
    # on the computer. Making them sane is part of installing, exactly as it is
    # for a package.
    #
    # WHAT "SANE" MEANS IN /usr
    #   directories        0755  anyone may enter and list
    #   runnable files     0755  anyone may run
    #   everything else    0644  anyone may read
    #
    # and nothing, anywhere, writable by anyone but root — which is what closes
    # the Writer's 85 world-writable files. Symlinks are left alone: a symlink
    # is always 0777 and its permissions mean nothing.
    #
    # "Runnable" is decided by whether the OWNER could run it, which is how the
    # packaging tool recorded its intent. We are widening that intent to
    # everyone, never inventing it.
    #
    # ⚠️ This must run BEFORE the chrome-sandbox block below. These lines clear
    #    the setuid bit; the block below is what deliberately sets it, on the one
    #    file that is supposed to have it.
    find "${APP_ROOT}/${name}" -type d -exec chmod 0755 {} +
    find "${APP_ROOT}/${name}" -type f -perm -u+x -exec chmod 0755 {} +
    find "${APP_ROOT}/${name}" -type f ! -perm -u+x -exec chmod 0644 {} +
    say "  permissions normalised (dirs 0755, programs 0755, data 0644)"

    # --- WRITE DOWN WHICH VERSION THIS IS -------------------------------------
    # A plain text file containing one line, e.g. "0.3.0", next to the app.
    #
    # WHY THE OPERATING SYSTEM NEEDS TO KNOW ITS OWN APP'S VERSION
    # /usr is read-only on AquariusOS, so a baked-in app can never update itself
    # in place. Both apps are therefore allowed to download a newer copy of
    # themselves into the user's home folder, and at every launch the OS has to
    # answer one question: is that download actually NEWER than what I already
    # have? It cannot answer that without knowing what it has. This file is the
    # answer. The launcher reads it — see /usr/libexec/aquarius-app-overlay.
    #
    # WHERE THE NUMBER COMES FROM
    # The release tag, with its leading "v" removed. The tag is the version:
    # it is what the release is called, it is right there in the table at the top
    # of this file, and nothing has to be parsed out of anything.
    #
    # It is then CHECKED against the name of the file that was actually
    # downloaded (AquariusEditor-0.3.0-x86_64.AppImage), and the build stops if
    # the two disagree. That catches the one mistake this could make: a tag
    # pointing at a release whose attachment is a different build. Only the three
    # numbers are compared, because a file name is allowed to carry other
    # dash-separated words after them ("-x86_64") that are not part of a version.
    local version file_version
    version="${tag#v}"

    if ! printf '%s' "$version" \
         | grep -qE '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}(-[0-9A-Za-z.-]+)?$'; then
        die "${name}: the release tag '${tag}' is not a version number." \
            "" \
            "The tag has to read like v0.3.0 (optionally v0.4.0-beta.1), because" \
            "the number in it is written into ${APP_ROOT}/${name}/VERSION and the" \
            "launcher compares downloaded updates against it." \
            "" \
            "Fix the tag in the AQUARIUS_APPS table at the top of this file."
    fi

    file_version="$(printf '%s' "$file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ -n "$file_version" ] && [ "$file_version" != "${version%%-*}" ]; then
        die "${name}: the release tag and the downloaded file disagree about the version." \
            "" \
            "  tag says   ${version}" \
            "  file named ${file}  (which reads as ${file_version})" \
            "" \
            "One of the two is wrong, and baking the wrong number in would make the" \
            "app's updater compare against a version that was never shipped."
    fi
    if [ -z "$file_version" ]; then
        echo "  NOTE: ${file} carries no version number in its name, so the tag" \
             "(${version}) could not be cross-checked. Using it as it stands."
    fi

    printf '%s\n' "$version" >"${APP_ROOT}/${name}/VERSION"
    chmod 0644 "${APP_ROOT}/${name}/VERSION"
    say "  version stamped: ${version} → ${APP_ROOT}/${name}/VERSION"

    # A symlink pointing at a folder on the machine that built the AppImage is
    # dead weight in an OS image: it can never resolve, and it leaks the build
    # server's directory layout. Both of our apps ship at least one (the Writer's
    # .DirIcon points into /home/runner/work/…). Drop any that do not resolve.
    while IFS= read -r dangling; do
        [ -n "$dangling" ] || continue
        say "  removing broken symlink ${dangling#"${APP_ROOT}/${name}/"} -> $(readlink "$dangling")"
        rm -f "$dangling"
    done < <(find "${APP_ROOT}/${name}" -xtype l)

    # --- let our launcher have the last word on the window system -------------
    # Apps packaged with the "linuxdeploy GTK plugin" — Aquarius Writer is one —
    # carry a start-up snippet that the packaging tool generated, and one of its
    # lines is:
    #
    #     export GDK_BACKEND=x11
    #
    # unconditionally. That snippet is sourced AFTER whatever we set, so it
    # silently overwrites us: /usr/bin/aquarius-writer cannot influence the
    # window system at all while that line stands. It exists as a workaround for
    # an old crash on Wayland (tauri-apps/tauri#8541); upstream's own fix, in
    # tauri-apps/tauri#15786, is to make it a DEFAULT rather than an order:
    #
    #     export GDK_BACKEND="${GDK_BACKEND:-x11}"
    #
    # We apply exactly that, to the copy in our image. Note what this does NOT
    # do: it does not change the behaviour of the app one bit. With nothing set,
    # the value is still x11, still XWayland, still what the app was released
    # with. All it does is make the knob reachable, so that a future NVIDIA or
    # Wayland problem can be fixed in a launcher instead of in a rebuild.
    local gtk_hook="${APP_ROOT}/${name}/apprun-hooks/linuxdeploy-plugin-gtk.sh"
    if [ -f "$gtk_hook" ] && grep -q '^export GDK_BACKEND=x11' "$gtk_hook"; then
        # shellcheck disable=SC2016  # the ${GDK_BACKEND:-x11} must reach the file
        #                               unexpanded — that is the entire point.
        sed -i \
            's|^export GDK_BACKEND=x11.*|export GDK_BACKEND="${GDK_BACKEND:-x11}" # AquariusOS: a default, not an order|' \
            "$gtk_hook"
        say "  GDK_BACKEND is now overridable by the launcher"
    fi

    # --- the Chrome sandbox, if this app has one ------------------------------
    # Electron apps ship a small helper called chrome-sandbox. It is the OLD way
    # Chromium sandboxes itself, and it only works when the file is owned by root
    # and carries the "setuid" bit — which a self-mounting AppImage can never
    # have, and an unpacked one can. So we set it.
    #
    # WHAT THIS IS AND IS NOT WORTH
    # Chromium has preferred the newer user-namespace sandbox since 2015 and only
    # looks at this file when user namespaces are unavailable. Bazzite has them,
    # so on a normal AquariusOS machine this helper is never even consulted.
    # (Chromium's own order of preference is in content/browser/zygote_host/
    # zygote_host_impl_linux.cc.)
    #
    # It is still set correctly, for the case where it does get consulted, and
    # because the failure when it is wrong is unusually nasty: Electron does not
    # fall back, it aborts, with
    #
    #     The SUID sandbox helper binary was found, but is not configured
    #     correctly. Rather than run without sandboxing I'm aborting now.
    #
    # and from the app grid that abort is completely silent. /usr/bin/aquarius-editor
    # steers around it at launch time as well; belt and braces, on the one
    # failure mode that leaves no trace.
    if [ -f "${APP_ROOT}/${name}/chrome-sandbox" ]; then
        chown root:root "${APP_ROOT}/${name}/chrome-sandbox"
        chmod 4755 "${APP_ROOT}/${name}/chrome-sandbox"
        say "  chrome-sandbox enabled"
    fi

    # --- the icon -------------------------------------------------------------
    # Different app toolkits put their icon in different places under different
    # names, so we go looking. The .desktop files in system_files/ say
    # Icon=aquarius-editor / Icon=aquarius-writer, and whatever we find gets
    # installed under exactly that name, so the two can never disagree.
    #
    # ⚠️ THIS USED TO PICK THE WRONG PICTURE, and it is worth understanding why,
    #    because the mistake is an easy one to make again. The old search was
    #
    #        find … -maxdepth 6 -name '*.png' \
    #             \( -path '*/icons/*' -o -path "${APP_ROOT}/${name}/*.png" \)
    #
    #    which reads as "an icon from an icons folder, or a PNG sitting at the
    #    top of the app". It is neither. In `find`, the `*` in -path matches
    #    slashes too, so `…/aquarius-editor/*.png` matches EVERY png anywhere in
    #    the app — and then "biggest wins" handed Aquarius Editor a vendor logo
    #    out of resources/remotion-bundle/vendor-icons/. The depth limit of 6
    #    made it worse by hiding the real icon, which lives seven levels down at
    #    usr/share/icons/hicolor/1024x1024/apps/.
    #
    # So it now looks in named places, in order of how much they mean, and stops
    # at the first hit. No cleverness, no "biggest file anywhere".
    local icon=""

    #   1. The proper home for an application icon. Biggest resolution wins, and
    #      everything under here genuinely IS this app's icon.
    icon="$(find "${APP_ROOT}/${name}/usr/share/icons" -type f -name '*.png' \
              -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)"

    #   2. A PNG sitting loose at the top of the app folder — genuinely
    #      maxdepth 1 this time. Several packaging tools drop the icon there.
    if [ -z "$icon" ]; then
        icon="$(find "${APP_ROOT}/${name}" -maxdepth 1 -type f -name '*.png' \
                  -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)"
    fi

    #   3. .DirIcon — the AppImage format's own answer to "which one is the
    #      icon". Usually a symlink; [ -f ] follows it, so this only fires when
    #      it actually points at something.
    if [ -z "$icon" ] && [ -f "${APP_ROOT}/${name}/.DirIcon" ]; then
        icon="${APP_ROOT}/${name}/.DirIcon"
    fi

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

# ------------------------------------------------------------------------------
# PROVE IT — the check that should have existed the first time
# ------------------------------------------------------------------------------
# The build had checks before this. They all passed, and both apps still shipped
# broken. The reason is worth stating plainly, because it applies to every check
# anyone writes in this repo:
#
#     EVERY TEST IN THIS BUILD RUNS AS ROOT, AND ROOT IGNORES PERMISSIONS.
#
# `[ -x file ]` asked as root answers "is ANY execute bit set", which is true of
# a file nobody but root can run. So the old check — `[ -x AppRun ]` — was
# incapable of catching the exact bug that shipped.
#
# The rule below is therefore written the way a normal user experiences it: not
# "can I run this", but "could a person who is not root, and not in this file's
# group, run this". That question has an honest answer even when root asks it.
# ------------------------------------------------------------------------------

# `ls -l`-style listing of the offending files, for the error message. Kept to a
# handful of lines: if a hundred files are wrong they are all wrong for the same
# reason and five examples say so just as well.
show_some() { printf '%s\n' "$1" | head -8 | xargs -r ls -ld 2>/dev/null || true; }

for name in aquarius-editor aquarius-writer; do
    app="${APP_ROOT}/${name}"

    # --- the pieces exist and point at each other ----------------------------
    [ -x "/usr/bin/${name}" ] || die "Launcher /usr/bin/${name} is missing or not executable."
    [ -f "/usr/share/applications/${name}.desktop" ] || die "App-grid entry for ${name} is missing."
    [ -d "$app" ] || die "${app} is missing — the app did not unpack."
    [ -x "$app/AppRun" ] || die "${app}/AppRun is missing or not executable."
    [ -x /usr/libexec/aquarius-app-launch ] \
        || die "/usr/libexec/aquarius-app-launch is missing — both launchers call it."

    # --- the version stamp ---------------------------------------------------
    # Without this file the launcher cannot tell whether a downloaded update is
    # newer than what the OS already has, so it stops offering updates at all —
    # silently, and correctly, which is exactly the sort of quiet loss of a
    # feature that never gets noticed. So it is checked here instead.
    [ -f "$app/VERSION" ] || die \
        "${name}: ${app}/VERSION was not written." \
        "" \
        "The launcher compares downloaded updates against this file. Without it," \
        "an update the app downloads would never be started. It is written by the" \
        "\"WRITE DOWN WHICH VERSION THIS IS\" block earlier in this file."
    baked_version="$(cat "$app/VERSION")"
    printf '%s' "$baked_version" \
        | grep -qE '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}(-[0-9A-Za-z.-]+)?$' || die \
        "${name}: ${app}/VERSION does not contain a version number." \
        "" \
        "  it contains: ${baked_version}" \
        "" \
        "It must be one bare version number and nothing else — 0.3.0, not v0.3.0."
    say "${name}: version ${baked_version}."

    # --- could an ordinary person actually run this? -------------------------
    # 1. Everything must be readable by everyone. An unreadable data file inside
    #    an app is just as fatal as an unrunnable program, and far more confusing.
    unreadable="$(find "$app" \( -type f -o -type d \) ! -perm -o+r)"
    [ -z "$unreadable" ] || die \
        "${name}: some installed files cannot be READ by an ordinary account." \
        "" "$(show_some "$unreadable")" "" \
        "Everything under ${app} must be world-readable. Fix it where the app is" \
        "unpacked (the permission-normalising block in this file), not here."

    # 2. Anything the packager marked runnable must be runnable BY EVERYONE.
    #    This is the check that catches mode 0770 — the bug of 2026-08-28.
    notrunnable="$(find "$app" -type f -perm -u+x ! -perm -o+x)"
    [ -z "$notrunnable" ] || die \
        "${name}: a program inside the app cannot be RUN by an ordinary account." \
        "" "$(show_some "$notrunnable")" "" \
        "This is exactly the fault that shipped on 2026-08-28: AppRun.wrapped was" \
        "mode 0770, so every check passed as root and every real user got a silent" \
        "\"Permission denied\" when they clicked the icon." \
        "" \
        "Nothing needs fixing here — the permission-normalising block earlier in" \
        "this file exists to prevent it, so if this fires, that block did not run" \
        "or was changed."

    # 3. Directories must be enterable, or nothing inside them can be reached.
    noentry="$(find "$app" -type d ! -perm -o+x)"
    [ -z "$noentry" ] || die \
        "${name}: a folder inside the app cannot be opened by an ordinary account." \
        "" "$(show_some "$noentry")"

    # 4. Nothing in /usr may be writable by just anyone. The Writer's AppImage
    #    arrived with 53 world-writable files; on a shared computer that is a way
    #    for one account to replace another account's program.
    writable="$(find "$app" ! -type l -perm -o+w)"
    [ -z "$writable" ] || die \
        "${name}: files inside the app are writable by ANY account." \
        "" "$(show_some "$writable")" "" \
        "Nothing installed into /usr may be world-writable."

    # 5. No symlink may point at nothing. These are usually absolute paths left
    #    over from the machine that built the AppImage.
    broken="$(find "$app" -xtype l)"
    [ -z "$broken" ] || die \
        "${name}: the app contains symlinks that point at nothing." \
        "" "$(show_some "$broken")"

    say "${name}: permissions verified for ordinary accounts."
done

# --- the Electron sandbox helper, checked on the way out ----------------------
# Aquarius Editor refuses to start at all — instantly, with no window — if this
# file exists but is not root-owned with the setuid bit. Since we are the ones
# who set it, we are the ones who check it.
#
# DOES THE SETUID BIT SURVIVE PACKAGING? YES — checked, not assumed. The
# published image of 2026-08-28 was pulled apart layer by layer and this file
# reads `-rwsr-xr-x 0 0` in it, so `rpm-ostree compose build-chunked-oci` keeps
# it intact. That question is nevertheless re-asked on every build, on the
# finished image, by the "Verify creator apps" step in
# .github/workflows/build.yml — a thing that is true today and load-bearing
# forever is exactly the kind of thing to keep checking.
SANDBOX="${APP_ROOT}/aquarius-editor/chrome-sandbox"
if [ -e "$SANDBOX" ]; then
    mode="$(stat -c '%a' "$SANDBOX")"
    owner="$(stat -c '%U:%G' "$SANDBOX")"
    if [ "$mode" != "4755" ] || [ "$owner" != "root:root" ]; then
        die \
            "aquarius-editor: chrome-sandbox is ${owner} mode ${mode}, expected root:root mode 4755." \
            "" \
            "Electron aborts on startup with \"The SUID sandbox helper binary was found," \
            "but is not configured correctly\" when this is wrong — and from the app grid" \
            "that abort is completely silent."
    fi
    say "aquarius-editor: chrome-sandbox is root:root 4755."
fi

# --- the update-overlay library, and the sums it does --------------------------
# /usr/libexec/aquarius-app-overlay is the piece that decides, at every launch,
# whether a copy of the app downloaded into the user's home folder is newer than
# the one built into the OS. Two things are checked about it.
#
# FIRST, that it is there at all. It is sourced by both /usr/bin/aquarius-editor
# and /usr/bin/aquarius-writer, and a missing file does not crash anything — each
# launcher shrugs, starts the
# built-in copy and carries on. That is the right behaviour at run time and a
# terrible thing to ship, because the app would simply stop taking updates and
# nobody would ever see an error. So it is caught here.
#
# SECOND, that it works. Two test suites, both run HERE, inside the image,
# against the INSTALLED copy of the library — not against the one in the repo,
# which is a different question:
#
#   test-aquarius-semver.sh   the version comparison. Comparing "0.10.0" against
#                             "0.9.0" as ordinary text gives the wrong answer,
#                             and the wrong answer here means every machine pins
#                             itself to an old build forever.
#   test-aquarius-overlay.sh  what the launcher DOES with that answer: which copy
#                             it starts, and — the rule worth being nervous about
#                             — that it never deletes a download that is newer
#                             than the OS.
[ -r /usr/libexec/aquarius-app-overlay ] \
    || die "/usr/libexec/aquarius-app-overlay is missing." \
           "" \
           "Both Aquarius apps read it at every launch to find out whether a newer" \
           "copy has been downloaded. Without it they silently stop updating."

for aq_test in test-aquarius-semver.sh test-aquarius-overlay.sh; do
    [ -x "/ctx/tests/${aq_test}" ] || die \
        "tests/${aq_test} is missing from the build context." \
        "" \
        "The Containerfile copies the tests/ folder in with 'COPY tests /tests'." \
        "If that line was removed, this check cannot run and the update logic" \
        "would ship untested."

    say "Running tests/${aq_test} against the installed library..."
    "/ctx/tests/${aq_test}" /usr/libexec/aquarius-app-overlay || die \
        "tests/${aq_test} failed against the installed library." \
        "" \
        "See the output just above for which case gave the wrong answer. The" \
        "library is /usr/libexec/aquarius-app-overlay (in the repo:" \
        "system_files/usr/libexec/aquarius-app-overlay)."
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
[ -x /usr/libexec/aquarius-install-resolve ] \
    || die "The DaVinci Resolve walkthrough is missing or not executable."
[ -x /usr/libexec/aquarius-resolve-launch ] \
    || die "The DaVinci Resolve launcher is missing or not executable."
[ -f /usr/share/applications/aquarius-install-resolve.desktop ] \
    || die "\"Install DaVinci Resolve\" is missing from the app grid."

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

# ------------------------------------------------------------------------------
# NAME COLLISIONS IN THE ujust MENU — the check that has to exist
# ------------------------------------------------------------------------------
# We are the last import in a menu assembled from a dozen files we do not own,
# and `just` handles a name we share with an earlier file in one of two ways:
#
#   collides with a RECIPE   silently resolved in favour of the EARLIER import.
#                            Ours never runs, and nothing anywhere says so. This
#                            is what happened to `install-resolve` on 2026-08-28.
#
#   collides with an ALIAS   a HARD ERROR — "recipe X is redefined as an alias" —
#                            which `allow-duplicate-recipes` does not cover, and
#                            which takes down the WHOLE menu. Not just that
#                            recipe: `ujust`, `ujust --list`, and every unrelated
#                            recipe on the machine.
#
# The second one would ship an OS where `ujust` does not work at all, so it is
# checked here and it is fatal. The first is only a wasted recipe, so it is a
# warning — but a loud one, because a recipe that can never run is a lie in the
# menu and should be either renamed or deleted.
# ------------------------------------------------------------------------------
#
# LC_ALL=C throughout: `comm` compares two streams that `sort` produced, and the
# two only agree about what "sorted" means if they are using the same collation.
export LC_ALL=C

our_recipes="$(grep -oE '^[a-z][a-z0-9-]*:' "$AQUARIUS_JUST" | tr -d ':' | sort -u || true)"
[ -n "$our_recipes" ] || die \
    "No recipes found in ${AQUARIUS_JUST}." \
    "Either the file is empty or its recipes are no longer written in the shape" \
    "this check looks for (a name at the start of a line, ending in a colon)."
say "Our ujust recipes: $(echo "$our_recipes" | tr '\n' ' ')"

for other in /usr/share/ublue-os/just/*.just; do
    [ "$other" = "$AQUARIUS_JUST" ] && continue
    [ -f "$other" ] || continue

    # An alias line looks like:  alias install-davinci := install-resolve
    their_aliases="$(grep -oE '^alias[[:space:]]+[a-z0-9-]+' "$other" \
                       | awk '{print $2}' | sort -u || true)"
    their_recipes="$(grep -oE '^[a-z][a-z0-9-]*[[:space:]]*[A-Z_a-z0-9="]*:' "$other" \
                       | sed -E 's/[[:space:]].*//; s/:$//' | sort -u || true)"

    clash="$(comm -12 <(printf '%s\n' "$our_recipes") <(printf '%s\n' "$their_aliases") || true)"
    [ -z "$clash" ] || die \
        "A ujust recipe name in ${AQUARIUS_JUST} collides with an ALIAS in ${other}:" \
        "" "  ${clash}" "" \
        "That is a hard error in \`just\`, and it does not break only that one" \
        "recipe — it breaks the ENTIRE ujust menu on the shipped image. Rename" \
        "our recipe. See the header of 96-aquarius-creator.just."

    clash="$(comm -12 <(printf '%s\n' "$our_recipes") <(printf '%s\n' "$their_recipes") || true)"
    if [ -n "$clash" ]; then
        echo "  WARNING: these recipe names already exist in ${other}:"
        printf '%s\n' "$clash" | sed 's/^/           /'
        echo "           ${other} is imported BEFORE ours, and \`just\` resolves a"
        echo "           duplicate in favour of the earlier import — so OUR version"
        echo "           can never run. Rename it or delete it."
    fi
done

say "Creator app layer done."
