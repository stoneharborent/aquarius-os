#!/usr/bin/bash
# ==============================================================================
# STEP 6c — the creator layer
# ==============================================================================
# PLAIN ENGLISH: this is the step that makes AquariusOS a CREATOR'S operating
# system rather than a nicely branded Fedora.
#
# There are exactly TWO ways an app reaches a person on this machine, and which
# one an app gets is a real decision, not an implementation detail.
#
#   BAKED IN       Aquarius Editor and Aquarius Writer. They are ours, they are
#                  on no app store, so their Linux releases are downloaded HERE
#                  during the build, checked against the fingerprints GitHub
#                  published with them, and unpacked into the image. They are
#                  as much a part of the operating system as the file manager,
#                  and they work on a machine that has never seen the internet.
#
#   PREINSTALLED   OBS, Kdenlive, Krita, GIMP, Inkscape, Blender, Ardour,
#                  Audacity, Obsidian, LocalSend, Chrome, and the OBS plug-ins.
#                  They are LISTED in the image
#                  (/usr/share/flatpak/preinstall.d/) and fetched from Flathub
#                  the first time the machine is online. That is standing
#                  decision 4 of this project, and the reasons are worth
#                  keeping in view:
#
#                    * a Blender release from next Tuesday reaches you next
#                      Tuesday, not on our build schedule;
#                    * a broken app update can never stop the OS from booting;
#                    * the installer stays about four gigabytes instead of
#                      about fifteen.
#
#                  The price is that a brand-new machine spends ten to twenty
#                  minutes downloading them. It says so on screen while it
#                  happens, and it is written down in the docs rather than
#                  hidden.
#
# Nobody has to open a terminal for any of it, and nobody is asked a question
# they cannot answer. Anything on the list can be removed in the app store, and
# Flatpak remembers the removal forever.
#
# DaVinci Resolve is not here at all. It is a case of its own — nobody except
# Blackmagic may hand out the installer — and it belongs to its own build step.
#
# This step also promotes the INGEST HELPER, which has been in the image since
# R1, from "a command and a right-click menu" to a proper feature with its own
# `aq ingest` front door and an optional watch folder.
#
# Called from the Containerfile after step 6b.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

APP_ROOT="/usr/lib/aquarius"
PREINSTALL_FILE="/usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall"
OVERRIDE_DIR="/usr/share/aquarius/flatpak-overrides"
PREINSTALL_SERVICE="aquarius-flatpak-preinstall.service"
CATALOG_FILE="/usr/share/aquarius/apps/catalog.ini"

# ------------------------------------------------------------------------------
# WHICH VERSION OF OUR OWN APPS THIS IMAGE SHIPS
# ------------------------------------------------------------------------------
# One line each: <folder name> <GitHub repository> <release tag>.
#
# Changing a tag here is how AquariusOS takes a new Aquarius Editor or Writer.
# It is meant to be a deliberate act with a build behind it, exactly like the
# pinned commits at the top of the Containerfile.
#
# ⚠️ HOW BIG THESE ARE, AND WHY IT IS WRITTEN DOWN. Aquarius Editor is a large
#    download and lands at roughly two and a half gigabytes unpacked, because
#    since v0.5.0 it carries its speech-recognition and footage-analysis models
#    INSIDE the app so that a machine with no internet can still transcribe.
#    That is a deliberate trade and it is the reason this image is what it is.
#    The build log prints the free space either side of each bake, so an
#    out-of-space failure reads as an out-of-space failure and not as a mystery.
AQUARIUS_APPS=(
    "aquarius-editor stoneharborent/aquarius-editor v0.7.2"
    "aquarius-writer stoneharborent/aquarius-writer v0.5.5"
)

die() {
    echo ""
    echo "=============================================================="
    echo "AquariusOS creator layer FAILED"
    echo "--------------------------------------------------------------"
    printf '%s\n' "$@"
    echo "=============================================================="
    echo ""
    exit 1
}

# ==============================================================================
# JOB 1 — bake in Aquarius Editor and Aquarius Writer
# ==============================================================================
# The releases are Linux "AppImages": one file with the whole program inside it,
# compressed. Normally you double-click one and it mounts itself like a disc
# every time it runs, using a system component called FUSE.
#
# WE DELIBERATELY DO NOT DO THAT. We unpack the AppImage here, at build time,
# and ship the loose files. Reasons, in the order they matter:
#
#   1. Nothing can go missing at runtime. Self-mounting needs FUSE present and
#      working; when it is not, the app dies with "dlopen(): error loading
#      libfuse.so.2", which is not a message a beginner can act on. Unpacked,
#      there is no such dependency at all.
#   2. We can turn Chrome's security sandbox back on. Aquarius Editor is an
#      Electron app; its sandbox helper has to be a special "setuid" file, and
#      a self-mounted AppImage is mounted in a way that forbids that.
#   3. It starts faster. An AppImage's insides are compressed, which is
#      excellent for download size and slow to read.
#
# The price is disk space: two to three times the compressed download. For the
# flagship apps of the operating system that is the right way round.
# ------------------------------------------------------------------------------

bake_appimage() {
    local name="$1" repo="$2" tag="$3"
    local base="https://github.com/${repo}/releases/download/${tag}"
    local work="/var/tmp/aquarius-bake-${name}"

    say "Baking in ${name} (${repo} ${tag})"
    rm -rf "$work"
    mkdir -p "$work"

    # --- the fingerprints, first ---------------------------------------------
    # Fetched BEFORE the app on purpose: it is tiny, so a release that does not
    # exist is discovered in a second instead of after a two-gigabyte download.
    if ! curl --retry 3 --retry-delay 5 -fsSL -o "$work/SHA256SUMS.txt" "${base}/SHA256SUMS.txt"; then
        die "Could not download the checksum file for ${name}." \
            "" \
            "  Tried: ${base}/SHA256SUMS.txt" \
            "" \
            "The usual cause is that the release does not exist yet, or the tag" \
            "in the AQUARIUS_APPS table at the top of this file does not match a" \
            "published release." \
            "Check https://github.com/${repo}/releases and build again."
    fi

    # --- which file is the Linux app? ----------------------------------------
    # SHA256SUMS.txt looks like:  <64 hex characters>  ./SomeFile-x86_64.AppImage
    # We want the one and only .AppImage line. Two would mean the release
    # changed shape and a person needs to look at it.
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
    # The file name is "everything after the fingerprint", NOT "the second
    # word": release file names are allowed to contain spaces, and splitting on
    # spaces would silently chop such a name in half. The optional "*" is
    # sha256sum's marker for a binary file.
    file="$(printf '%s' "$matches" | sed -E 's/^[0-9a-fA-F]+[[:space:]]+\*?//')"
    file="${file##*/}"
    local url_file="${file// /%20}"

    say "  file:     ${file}"
    say "  expected: ${sum}"
    say "  free space here before the download: $(df -h --output=avail "$work" | tail -1 | tr -d ' ')"

    # --- the download --------------------------------------------------------
    # ⚠️ --speed-limit / --speed-time are NOT decoration. `--retry` only fires
    # on a connection that FAILS. A connection that goes QUIET never fails, so
    # curl would sit and wait, and the whole job would burn its six-hour ceiling
    # before anybody was told anything. These two words say "if less than a
    # kilobyte has moved in the last minute, give up on this attempt", which
    # turns a silent hang into an ordinary error that --retry then retries.
    if ! curl --retry 3 --retry-delay 5 \
        --speed-limit 1024 --speed-time 60 \
        -fL --progress-bar -o "$work/app.AppImage" "${base}/${url_file}"; then
        die "Could not download ${file} from ${repo} ${tag}." \
            "  Tried: ${base}/${url_file}" \
            "" \
            "This file is large, so the two likeliest causes are a transfer that" \
            "stalled — curl gives up on any attempt moving less than 1 KB in 60" \
            "seconds — or a build machine that ran out of disk space. The free" \
            "space at the moment before the download started is printed above."
    fi

    # --- verify before we trust it -------------------------------------------
    local got
    got="$(sha256sum "$work/app.AppImage" | awk '{print $1}')"
    say "  actual:   ${got}"
    if [ "$got" != "$sum" ]; then
        die "CHECKSUM MISMATCH for ${file}." \
            "" \
            "  expected ${sum}" \
            "  actual   ${got}" \
            "" \
            "The downloaded file is not what the release says it should be —" \
            "corrupted, truncated, or tampered with. Nothing has been installed." \
            "Do not build again until this is understood."
    fi
    say "  checksum OK"

    # --- unpack --------------------------------------------------------------
    # --appimage-extract is the AppImage's own built-in unpack mode. It does NOT
    # need FUSE (that is only the self-mounting mode), so it works inside a
    # container build. The chmod is not decoration: a GitHub release attachment
    # always arrives WITHOUT its "you may run this" flag.
    chmod +x "$work/app.AppImage"
    if ! (cd "$work" && ./app.AppImage --appimage-extract > /dev/null); then
        die "${name}: the AppImage refused to unpack." \
            "" \
            "Its fingerprint was correct, so the file is not damaged. That leaves" \
            "two likely causes: it is not really an AppImage, or it was built for" \
            "a different kind of processor (AquariusOS is x86_64 only)."
    fi
    [ -d "$work/squashfs-root" ] || die "${name}: --appimage-extract produced no squashfs-root."
    [ -x "$work/squashfs-root/AppRun" ] || die "${name}: no runnable AppRun inside the AppImage."

    mkdir -p "$APP_ROOT"
    rm -rf "${APP_ROOT:?}/${name}"
    mv "$work/squashfs-root" "${APP_ROOT}/${name}"

    # --- FIX THE PERMISSIONS. THIS IS NOT OPTIONAL. --------------------------
    # This block is the whole of the bug of 2026-08-28, when both apps shipped,
    # both appeared in the app grid, and clicking either did absolutely nothing.
    # Two different faults, one per app, read out of the published image:
    #
    #   AQUARIUS WRITER   AppRun.wrapped was mode 0770 — owner and group may
    #                     run it, nobody else may. Every real user got
    #                     "Permission denied" from a script, with no window.
    #   AQUARIUS EDITOR   nothing wrong with any file, and ALL 3,097 OF ITS
    #                     FOLDERS were mode 0700. A folder you may not enter
    #                     makes every file inside it read as missing.
    #
    # The two differ because each AppImage carries its own copy of the runtime
    # that implements --appimage-extract, and they do not agree about what
    # permissions to give the folders they create.
    #
    # ⚠️ AND NOTE HOW EASY THIS IS TO MISS. Extracting the same AppImage with
    #    `unsquashfs` on a developer machine produces 0755 folders and hides the
    #    Editor fault completely. Only the app's own extractor reproduces it.
    #
    # WHAT "SANE" MEANS IN /usr:
    #   directories        0755  anyone may enter and list
    #   runnable files     0755  anyone may run
    #   everything else    0644  anyone may read
    # and nothing writable by anyone but root. Symlinks are left alone — a
    # symlink is always 0777 and its permissions mean nothing.
    #
    # ⚠️ This must run BEFORE the chrome-sandbox block below, which deliberately
    #    sets the one bit these lines clear.
    find "${APP_ROOT}/${name}" -type d -exec chmod 0755 {} +
    find "${APP_ROOT}/${name}" -type f -perm -u+x -exec chmod 0755 {} +
    find "${APP_ROOT}/${name}" -type f ! -perm -u+x -exec chmod 0644 {} +
    say "  permissions normalised (folders 0755, programs 0755, data 0644)"

    # --- write down which version this is ------------------------------------
    # /usr is read-only on AquariusOS, so a baked-in app can never update itself
    # in place. Both apps are therefore allowed to download a newer copy of
    # themselves into the user's home folder, and at every launch the OS has to
    # answer one question: is that download actually NEWER than what I have?
    # This file is the answer. See /usr/libexec/aquarius-app-overlay.
    local version file_version
    version="${tag#v}"

    if ! printf '%s' "$version" \
        | grep -qE '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}(-[0-9A-Za-z.-]+)?$'; then
        die "${name}: the release tag '${tag}' is not a version number." \
            "" \
            "It has to read like v0.7.2, because the number in it is written into" \
            "${APP_ROOT}/${name}/VERSION and the launcher compares downloaded" \
            "updates against it. Fix the tag in AQUARIUS_APPS at the top of this file."
    fi

    # Cross-check against the name of the file actually downloaded. This catches
    # the one mistake this could make: a tag pointing at a release whose
    # attachment is a different build. Only the three numbers are compared,
    # because a file name may carry other words after them ("-x86_64").
    file_version="$(printf '%s' "$file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ -n "$file_version" ] && [ "$file_version" != "${version%%-*}" ]; then
        die "${name}: the release tag and the downloaded file disagree about the version." \
            "" \
            "  tag says   ${version}" \
            "  file named ${file}  (which reads as ${file_version})" \
            "" \
            "Baking the wrong number in would make the app's updater compare" \
            "against a version that was never shipped."
    fi
    if [ -z "$file_version" ]; then
        echo "  NOTE: ${file} carries no version number in its name, so the tag" \
            "(${version}) could not be cross-checked. Using it as it stands."
    fi

    printf '%s\n' "$version" > "${APP_ROOT}/${name}/VERSION"
    chmod 0644 "${APP_ROOT}/${name}/VERSION"
    say "  version stamped: ${version} -> ${APP_ROOT}/${name}/VERSION"

    # A symlink pointing at a folder on the machine that built the AppImage is
    # dead weight: it can never resolve, and it leaks the build server's layout.
    while IFS= read -r dangling; do
        [ -n "$dangling" ] || continue
        say "  removing broken symlink ${dangling#"${APP_ROOT}/${name}/"} -> $(readlink "$dangling")"
        rm -f "$dangling"
    done < <(find "${APP_ROOT}/${name}" -xtype l)

    # --- let our launcher have the last word on the window system ------------
    # Apps packaged with the "linuxdeploy GTK plugin" — Aquarius Writer is one —
    # carry a start-up snippet with an unconditional `export GDK_BACKEND=x11`.
    # That snippet is read AFTER whatever we set, so it silently overwrites us,
    # and /usr/bin/aquarius-writer cannot influence the window system at all
    # while that line stands. Upstream's own fix (tauri-apps/tauri#15786) is to
    # make it a DEFAULT rather than an order, and that is what we apply.
    #
    # Note what this does NOT do: it does not change the app's behaviour at all.
    # With nothing set the value is still x11. All it does is make the knob
    # reachable, so a future problem can be fixed in a launcher.
    local gtk_hook="${APP_ROOT}/${name}/apprun-hooks/linuxdeploy-plugin-gtk.sh"
    if [ -f "$gtk_hook" ] && grep -q '^export GDK_BACKEND=x11' "$gtk_hook"; then
        # shellcheck disable=SC2016  # ${GDK_BACKEND:-x11} must reach the file
        #                               unexpanded — that is the entire point.
        sed -i \
            's|^export GDK_BACKEND=x11.*|export GDK_BACKEND="${GDK_BACKEND:-x11}" # AquariusOS: a default, not an order|' \
            "$gtk_hook"
        say "  GDK_BACKEND is now overridable by the launcher"
    fi

    # --- the Chrome sandbox, if this app has one -----------------------------
    # Electron apps ship a small helper called chrome-sandbox. It is the OLD way
    # Chromium sandboxes itself and it only works when the file is owned by root
    # and carries the setuid bit — which a self-mounting AppImage can never
    # have, and an unpacked one can.
    #
    # Chromium has preferred the newer user-namespace sandbox since 2015 and
    # only consults this file when user namespaces are unavailable, which on
    # this image they are not. It is still set correctly, because the failure
    # when it is wrong is unusually nasty: Electron does not fall back, it
    # aborts, and from the app grid that abort is completely silent.
    if [ -f "${APP_ROOT}/${name}/chrome-sandbox" ]; then
        chown root:root "${APP_ROOT}/${name}/chrome-sandbox"
        chmod 4755 "${APP_ROOT}/${name}/chrome-sandbox"
        say "  chrome-sandbox enabled"
    fi

    # --- the icon ------------------------------------------------------------
    # Different toolkits put their icon in different places under different
    # names, so we go looking — in NAMED places, in order of how much they mean,
    # stopping at the first hit.
    #
    # ⚠️ THIS USED TO PICK THE WRONG PICTURE. The old search asked for "a PNG
    #    from an icons folder, or a PNG at the top of the app", written as
    #    -path "${APP_ROOT}/${name}/*.png" — and in `find`, the * in -path
    #    matches slashes too, so that matched EVERY png anywhere in the app.
    #    "Biggest wins" then handed Aquarius Editor a vendor logo out of a
    #    bundled web asset folder. No cleverness here, and no "biggest file
    #    anywhere".
    local icon=""

    #   1. The proper home for an application icon. Biggest resolution wins, and
    #      everything under here genuinely IS this app's icon.
    icon="$(find "${APP_ROOT}/${name}/usr/share/icons" -type f -name '*.png' \
        -printf '%s %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)"

    #   2. A PNG sitting loose at the top of the app folder — genuinely
    #      maxdepth 1 this time.
    if [ -z "$icon" ]; then
        icon="$(find "${APP_ROOT}/${name}" -maxdepth 1 -type f -name '*.png' \
            -printf '%s %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)"
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

    # --- window matching -----------------------------------------------------
    # Every window tells the desktop an internal "class" name. If our menu entry
    # does not know that name, the dock shows a running Aquarius Editor as a
    # SECOND, nameless icon next to the one you clicked. Rather than guess, we
    # read it out of the .desktop file the app ships inside itself.
    local ours="/usr/share/applications/${name}.desktop"
    local upstream wmclass
    upstream="$(find "${APP_ROOT}/${name}" -maxdepth 4 -type f -name '*.desktop' | head -1 || true)"
    if [ -n "$upstream" ] && [ -f "$ours" ]; then
        wmclass="$(grep -m1 '^StartupWMClass=' "$upstream" | cut -d= -f2- || true)"
        if [ -n "$wmclass" ] && ! grep -q '^StartupWMClass=' "$ours"; then
            echo "StartupWMClass=${wmclass}" >> "$ours"
            say "  window class: ${wmclass}"
        fi
    fi

    # --- tidy up and report --------------------------------------------------
    # The downloaded AppImage is deleted here, not at the end: it has already
    # been unpacked, so keeping it would mean carrying two copies of the same
    # app through the rest of the build for no reason.
    rm -rf "$work"
    say "  installed size: $(du -sh "${APP_ROOT}/${name}" | cut -f1) at ${APP_ROOT}/${name}"
    say "  free space here after the bake: $(df -h --output=avail "$APP_ROOT" | tail -1 | tr -d ' ')"
}

for entry in "${AQUARIUS_APPS[@]}"; do
    # shellcheck disable=SC2086  # the entry is three known, space-free words
    bake_appimage $entry
done

# ------------------------------------------------------------------------------
# PROVE IT — the check that should have existed the first time
# ------------------------------------------------------------------------------
# The build had checks before the bug of 2026-08-28. They all passed, and both
# apps still shipped broken. The reason applies to every check anybody writes in
# this repository:
#
#     EVERY TEST IN THIS BUILD RUNS AS ROOT, AND ROOT IGNORES PERMISSIONS.
#
# `[ -x file ]` asked as root answers "is ANY execute bit set", which is true of
# a file nobody but root can run. So the old check was incapable of catching the
# exact bug that shipped.
#
# The rules below are therefore written the way a normal person experiences
# them: not "can I run this", but "could somebody who is not root, and not in
# this file's group, run this". That question has an honest answer even when
# root asks it.
# ------------------------------------------------------------------------------
say "Could an ordinary account really run these apps?"

show_some() { printf '%s\n' "$1" | head -8 | xargs -r ls -ld 2> /dev/null || true; }

for name in aquarius-editor aquarius-writer; do
    app="${APP_ROOT}/${name}"

    [ -x "/usr/bin/${name}" ] || die "Launcher /usr/bin/${name} is missing or not executable."
    [ -f "/usr/share/applications/${name}.desktop" ] || die "App-grid entry for ${name} is missing."
    [ -d "$app" ] || die "${app} is missing — the app did not unpack."
    [ -x "$app/AppRun" ] || die "${app}/AppRun is missing or not executable."
    [ -x /usr/libexec/aquarius-app-launch ] \
        || die "/usr/libexec/aquarius-app-launch is missing — both launchers call it."

    [ -f "$app/VERSION" ] || die \
        "${name}: ${app}/VERSION was not written." \
        "" \
        "The launcher compares downloaded updates against this file. Without it," \
        "an update the app downloads would never be started."
    baked_version="$(cat "$app/VERSION")"
    printf '%s' "$baked_version" \
        | grep -qE '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}(-[0-9A-Za-z.-]+)?$' || die \
        "${name}: ${app}/VERSION does not contain a version number." \
        "  it contains: ${baked_version}" \
        "It must be one bare version number and nothing else — 0.7.2, not v0.7.2."
    ok "${name}: version ${baked_version}"

    # 1. Everything must be READABLE by everyone. An unreadable data file inside
    #    an app is as fatal as an unrunnable program and far more confusing.
    unreadable="$(find "$app" \( -type f -o -type d \) ! -perm -o+r)"
    [ -z "$unreadable" ] || die \
        "${name}: some installed files cannot be READ by an ordinary account." \
        "" "$(show_some "$unreadable")" "" \
        "Everything under ${app} must be world-readable. Fix it in the" \
        "permission-normalising block earlier in this file, not here."

    # 2. Anything the packager marked runnable must be runnable BY EVERYONE.
    #    This is the check that catches mode 0770 — the bug of 2026-08-28.
    notrunnable="$(find "$app" -type f -perm -u+x ! -perm -o+x)"
    [ -z "$notrunnable" ] || die \
        "${name}: a program inside the app cannot be RUN by an ordinary account." \
        "" "$(show_some "$notrunnable")" "" \
        "This is exactly the fault that shipped on 2026-08-28: every check passed" \
        "as root and every real user got a silent Permission denied when they" \
        "clicked the icon."

    # 3. Folders must be enterable, or nothing inside them can be reached.
    noentry="$(find "$app" -type d ! -perm -o+x)"
    [ -z "$noentry" ] || die \
        "${name}: a folder inside the app cannot be opened by an ordinary account." \
        "" "$(show_some "$noentry")"

    # 4. Nothing in /usr may be writable by just anyone. On a shared computer
    #    that is a way for one account to replace another account's program.
    writable="$(find "$app" ! -type l -perm -o+w)"
    [ -z "$writable" ] || die \
        "${name}: files inside the app are writable by ANY account." \
        "" "$(show_some "$writable")"

    # 5. No symlink may point at nothing.
    broken="$(find "$app" -xtype l)"
    [ -z "$broken" ] || die \
        "${name}: the app contains symlinks that point at nothing." \
        "" "$(show_some "$broken")"

    ok "${name}: permissions verified for ordinary accounts"
done

# --- the Electron sandbox helper, checked on the way out ----------------------
SANDBOX="${APP_ROOT}/aquarius-editor/chrome-sandbox"
if [ -e "$SANDBOX" ]; then
    mode="$(stat -c '%a' "$SANDBOX")"
    owner="$(stat -c '%U:%G' "$SANDBOX")"
    if [ "$mode" != "4755" ] || [ "$owner" != "root:root" ]; then
        die "aquarius-editor: chrome-sandbox is ${owner} mode ${mode}, expected root:root 4755." \
            "" \
            "Electron aborts on startup with \"The SUID sandbox helper binary was found," \
            "but is not configured correctly\" when this is wrong — and from the app grid" \
            "that abort is completely silent."
    fi
    ok "aquarius-editor: chrome-sandbox is root:root 4755"
fi

# --- the update-overlay library, and the sums it does ------------------------
# /usr/libexec/aquarius-app-overlay is the piece that decides, at every launch,
# whether a copy of the app downloaded into the user's home folder is newer than
# the one built into the OS. Two things are checked.
#
# FIRST, that it is there at all. It is read by both launchers, and a missing
# file does not crash anything — each launcher shrugs, starts the built-in copy
# and carries on. That is right at run time and terrible to ship, because the
# app would simply stop taking updates and nobody would ever see an error.
#
# SECOND, that it WORKS. Both test suites run HERE, inside the image, against
# the INSTALLED copy of the library — not against the one in the repository,
# which is a different question.
[ -r /usr/libexec/aquarius-app-overlay ] \
    || die "/usr/libexec/aquarius-app-overlay is missing." \
        "Both Aquarius apps read it at every launch to find out whether a newer" \
        "copy has been downloaded. Without it they silently stop updating."

for aq_test in test-aquarius-semver.sh test-aquarius-overlay.sh; do
    [ -x "/ctx/tests/${aq_test}" ] || die \
        "tests/${aq_test} is missing from the build context." \
        "" \
        "The Containerfile gathers it with 'COPY tests /tests' in the ctx stage." \
        "Without it the update logic would ship untested."

    say "Running tests/${aq_test} against the installed library"
    "/ctx/tests/${aq_test}" /usr/libexec/aquarius-app-overlay || die \
        "tests/${aq_test} failed against the installed library." \
        "" \
        "See the output above for which case gave the wrong answer. The library" \
        "is /usr/libexec/aquarius-app-overlay."
done

# --- are the menu entries well-formed? ---------------------------------------
# A .desktop file with a mistake in it is IGNORED, silently, and the app simply
# never appears in the app grid. desktop-file-validate is the freedesktop
# project's own checker, so this is not our opinion of the file.
say "Are the app-grid entries well-formed?"
if ! aq_have desktop-file-validate; then
    echo "desktop-file-validate is not here yet; installing desktop-file-utils."
    aq_dnf install desktop-file-utils
fi
for d in /usr/share/applications/aquarius-editor.desktop /usr/share/applications/aquarius-writer.desktop; do
    if desktop-file-validate "$d"; then
        ok "$(basename "$d") is valid"
    else
        bad "$(basename "$d") is not a valid desktop entry — the app would not appear in the app grid"
    fi
done

# The app grid is built from an index, and an entry added without rebuilding it
# is invisible until something else happens to rebuild it.
if aq_have update-desktop-database; then
    update-desktop-database /usr/share/applications || true
    ok "the app-grid index was rebuilt"
fi

# ==============================================================================
# JOB 2 — the shopping list of Flatpaks, checked against reality
# ==============================================================================
# A typo in an app ID is completely silent: the app never appears, and nothing
# anywhere says why. So the build ASKS FLATHUB whether each name is real.
#
# ⚠️ THE OBVIOUS TEST DOES NOT WORK. https://flathub.org/apps/<id> answers 200
#    for absolutely anything, because that page is drawn in your browser after
#    it loads. The honest question is the API:
#
#        https://flathub.org/api/v2/appstream/<id>
#
#    which returns the app's details for a real name and 404 for one that does
#    not exist.
#
# HOW A NETWORK PROBLEM IS TOLD APART FROM A WRONG NAME, WHICH MATTERS:
#   Flathub answered "no such app"      -> the build FAILS. This is a mistake in
#                                          our file and shipping it would ship a
#                                          promise we cannot keep.
#   Flathub could not be reached at all -> a WARNING and the build carries on.
#                                          A build machine's network trouble is
#                                          not evidence about our file, and
#                                          failing on it would mean an OS that
#                                          cannot be built when Flathub is down.
# ------------------------------------------------------------------------------
say "The list of creator apps"

[ -r "${PREINSTALL_FILE}" ] || die \
    "${PREINSTALL_FILE} is missing." \
    "" \
    "It ships in system_files/ and is copied in at step 5. Without it the OS" \
    "advertises a creator suite and installs nothing."

# Pull the IDs out of the file, honouring Install=false.
AQ_IDS="$(awk '
    /^\[Flatpak Preinstall / { id = $3; sub(/\]$/, "", id); cur = id; want[id] = 1; next }
    /^[[:space:]]*Install[[:space:]]*=/ {
        v = tolower($0); sub(/.*=[[:space:]]*/, "", v); gsub(/[[:space:]]/, "", v)
        if (cur != "" && (v == "false" || v == "0" || v == "no")) delete want[cur]
    }
    END { for (id in want) print id }
' "${PREINSTALL_FILE}" | sort)"

AQ_ID_COUNT="$(printf '%s\n' "${AQ_IDS}" | grep -c . || true)"
echo "${AQ_ID_COUNT} apps and plug-ins are on the list:"
printf '%s\n' "${AQ_IDS}" | sed 's/^/  /'

if [ "${AQ_ID_COUNT}" -lt 1 ]; then
    die "No app IDs could be read out of ${PREINSTALL_FILE}." \
        "Either the file is empty or its blocks are no longer written in the" \
        "shape this check looks for ([Flatpak Preinstall <id>])."
fi

# Every block must name a branch. Leaving Branch= out makes Flatpak look for a
# branch called "master", which Flathub apps do not have, and the install then
# quietly finds nothing.
say "Every app on the list names a branch"
AQ_BLOCKS="$(grep -c '^\[Flatpak Preinstall ' "${PREINSTALL_FILE}" || true)"
AQ_BRANCHES="$(grep -c '^Branch=' "${PREINSTALL_FILE}" || true)"
if [ "${AQ_BLOCKS}" -eq "${AQ_BRANCHES}" ]; then
    ok "all ${AQ_BLOCKS} entries name a branch"
else
    bad "${AQ_BLOCKS} entries but only ${AQ_BRANCHES} Branch= lines — an entry without one installs nothing, silently"
    grep -n '^\[Flatpak Preinstall \|^Branch=' "${PREINSTALL_FILE}" | sed 's/^/       /'
fi

say "Ask Flathub whether these apps are real"
AQ_UNREACHABLE=0
AQ_FAKE=""
for id in ${AQ_IDS}; do
    http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 --retry 2 --retry-delay 3 \
        "https://flathub.org/api/v2/appstream/${id}" 2> /dev/null || echo "000")"
    case "${http}" in
        200)
            ok "Flathub has ${id}"
            ;;
        404)
            bad "Flathub has NO app called ${id} — this name is wrong"
            AQ_FAKE="${AQ_FAKE} ${id}"
            ;;
        *)
            echo "  ??   could not ask Flathub about ${id} (it answered '${http}')"
            AQ_UNREACHABLE=$((AQ_UNREACHABLE + 1))
            ;;
    esac
done

if [ "${AQ_UNREACHABLE}" -gt 0 ]; then
    echo ""
    echo "  NOTE: ${AQ_UNREACHABLE} name(s) could not be checked because Flathub could not"
    echo "        be reached from this build machine. That is not evidence about our"
    echo "        file, so the build carries on. If this happens on every build,"
    echo "        something is blocking the network, not something is wrong with"
    echo "        ${PREINSTALL_FILE}."
fi
if [ -n "${AQ_FAKE}" ]; then
    echo ""
    echo "  Flathub says these do not exist:${AQ_FAKE}"
    echo "  Fix the names in ${PREINSTALL_FILE}. A wrong name is silent on the"
    echo "  finished machine — the app simply never appears."
fi

# ==============================================================================
# JOB 3 — the extra permissions, checked with Flatpak's own parser
# ==============================================================================
# We ship a handful of permission files so that OBS can see a camera and an
# editor can reach an external drive. A malformed one is IGNORED silently, so
# they are not eyeballed here: each is handed to Flatpak itself and we read back
# what Flatpak says it means.
#
# HOW THIS IS POSSIBLE INSIDE A BUILD. Flatpak reads system-wide overrides from
# exactly one folder — /var/lib/flatpak/overrides/ — and nowhere else. That was
# read out of Flatpak's own source (flatpak_save_override_keyfile() in
# common/flatpak-dir.c), because the two folders one would GUESS,
# /usr/share/flatpak/overrides/ and /etc/flatpak/overrides/, are not read at all
# and writing to them does nothing, silently.
#
# /var belongs to the machine rather than to the image, so anything we put there
# during a build is thrown away on first boot. That is exactly what makes it
# safe to use as a scratch space here: copy a file in, ask Flatpak to read it
# back, take it out again. The finished image carries the files only in their
# read-only home under /usr/share/aquarius/, and
# /usr/libexec/aquarius-flatpak-preinstall installs them on the machine.
# ------------------------------------------------------------------------------
say "The extra permissions creator apps need"

[ -d "${OVERRIDE_DIR}" ] || die "${OVERRIDE_DIR} is missing — it ships in system_files/."

AQ_SCRATCH="/var/lib/flatpak/overrides"
mkdir -p "${AQ_SCRATCH}"

# ------------------------------------------------------------------------------
# FIRST: can Flatpak do this here AT ALL?
# ------------------------------------------------------------------------------
# A build container is not a running desktop, and it would be easy to write a
# check that fails for that reason and then to "fix" a perfectly good
# permission file. So before judging any of our files, a KNOWN-GOOD one is put
# through exactly the same command. If even that fails, the tool is what is
# missing, not our files, and the check says so and falls back to a plainer one
# rather than failing the build on a wrong conclusion.
AQ_CONTROL="com.aquariusos.OverrideSelfTest"
printf '[Context]\nshared=network;\n' > "${AQ_SCRATCH}/${AQ_CONTROL}"
if flatpak override --system "${AQ_CONTROL}" > /tmp/aq-control.txt 2>&1; then
    AQ_FLATPAK_CAN_READ=1
    ok "Flatpak can read permission files in this build, so it is the judge"
else
    AQ_FLATPAK_CAN_READ=0
    echo "  NOTE: Flatpak cannot read permission files inside this build container:"
    sed 's/^/         /' /tmp/aq-control.txt
    echo "        Falling back to a plainer check of the file format. This is a"
    echo "        weaker check and it is worth knowing which one ran."
fi
rm -f "${AQ_SCRATCH}/${AQ_CONTROL}" /tmp/aq-control.txt

AQ_OVERRIDE_COUNT=0
for f in "${OVERRIDE_DIR}"/*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "${base}" in *.md) continue ;; esac
    AQ_OVERRIDE_COUNT=$((AQ_OVERRIDE_COUNT + 1))

    if [ "${AQ_FLATPAK_CAN_READ}" -eq 1 ]; then
        cp "$f" "${AQ_SCRATCH}/${base}"

        # ⚠️ NO --show ON THIS FIRST CALL, AND THAT IS THE WHOLE POINT.
        # `flatpak override --show` prints the file back and checks almost
        # nothing. Running it WITHOUT --show is what makes Flatpak actually
        # interpret every key and value — and that is the path that rejects a
        # misspelt permission (`xdg-vidoes`) or a device that does not exist.
        # A typo of that kind is otherwise completely silent on a real machine.
        if ! out="$(flatpak override --system "${base}" 2>&1)"; then
            bad "${base}: Flatpak refuses this permission file"
            printf '%s\n' "${out}" | sed 's/^/         /'
            rm -f "${AQ_SCRATCH}/${base}"
            continue
        fi

        shown="$(flatpak override --system --show "${base}" 2>&1)"
        if printf '%s' "${shown}" | grep -q '^\[Context\]'; then
            ok "${base}: Flatpak accepts it, and it grants:"
            printf '%s\n' "${shown}" | grep -v '^\[' | grep -v '^$' | sed 's/^/         /'
        else
            bad "${base}: Flatpak read it and found no permissions — the [Context] heading is probably misspelled"
            printf '%s\n' "${shown}" | sed 's/^/         /'
        fi
        rm -f "${AQ_SCRATCH}/${base}"
    else
        # The fallback: is it at least a settings file with a [Context] heading
        # and nothing but known keys in it?
        if python3 - "$f" << 'PYEOF'; then
import configparser, sys
p = configparser.ConfigParser(comment_prefixes=("#", ";"), interpolation=None)
p.optionxform = str
p.read(sys.argv[1], encoding="utf-8")
if "Context" not in p:
    raise SystemExit("no [Context] heading")
known = {"shared", "sockets", "devices", "filesystems", "persistent", "features"}
unknown = sorted(set(p["Context"]) - known)
if unknown:
    raise SystemExit("keys Flatpak does not know: " + ", ".join(unknown))
for key, value in p["Context"].items():
    if not value.strip().endswith(";"):
        raise SystemExit(f"{key} does not end in a semicolon, so its last item is dropped")
print("   ", {k: v for k, v in p["Context"].items()})
PYEOF
            ok "${base}: reads as a valid permission file"
        else
            bad "${base}: is not a valid permission file"
        fi
    fi
done

# ------------------------------------------------------------------------------
# ⚠️ PUT /var BACK EXACTLY AS WE FOUND IT
# ------------------------------------------------------------------------------
# THIS BLOCK IS NOT HOUSEKEEPING. It is the price of the check above, and the
# first build of this step failed on it, which is the check doing its job.
#
# Asking Flatpak to really interpret a permission file makes Flatpak set itself
# up first, and setting itself up means creating its system repository at
# /var/lib/flatpak/repo. That is state, in /var, made during a build.
#
# On this operating system /var belongs to the MACHINE, not to the image.
# Anything left there is shipped once, written to disk on the first boot, and
# then becomes a fossil that no future image can ever remove — so both
# 30-session.sh and 90-cleanup.sh refuse to ship an image with Flatpak state in
# it, and they are right to.
#
# So the folder is emptied back to what the flatpak package ships: an empty
# /var/lib/flatpak. Emptied rather than deleted, because the directory itself
# belongs to that package.
say "Putting /var back as we found it"
if [ -d /var/lib/flatpak ]; then
    echo "What the permission check left behind:"
    find /var/lib/flatpak -mindepth 1 -maxdepth 1 -printf '  %f\n' 2> /dev/null || true
    find /var/lib/flatpak -mindepth 1 -delete 2> /dev/null || true
fi

AQ_VAR_LEFTOVERS="$(find /var/lib/flatpak -mindepth 1 2> /dev/null | head -5 || true)"
if [ -z "${AQ_VAR_LEFTOVERS}" ]; then
    ok "no Flatpak state left in /var (correct — an image must ship none)"
else
    bad "Flatpak state is still in /var, and it would be shipped and then be unremovable:"
    printf '%s\n' "${AQ_VAR_LEFTOVERS}" | sed 's/^/       /'
fi

# ==============================================================================
# JOB 4 — switch the first-boot installer on
# ==============================================================================
# Fedora's flatpak package creates /usr/share/flatpak/preinstall.d/ and provides
# the `flatpak preinstall` command, and ships NOTHING THAT EVER RUNS IT. (Read
# its spec file: flatpak-system-helper.service, flatpak-portal.service,
# flatpak-add-fedora-repos.service, and no preinstall unit.) On Fedora
# Workstation the app store does it in the background. This image has two
# sessions, one of which is our own desktop with no app store running, so
# waiting for somebody else to do it would mean a machine that never installs
# the apps it advertises.
#
# So we supply the trigger, and only the trigger. The list format, the reading
# of it, the installing, and the rule that a removed app stays removed are all
# Flatpak's.
#
# ⚠️ CHANGED 2026-09-04 — THE TRIGGER IS NO LONGER PULLED AUTOMATICALLY. This
#    service used to be enabled here, so a new machine downloaded all sixteen
#    apps on its first boot without being asked. It is now deliberately NOT
#    enabled: the app chooser at first login asks the person which of them they
#    want, and installs those. The service remains as the "install the lot"
#    path, started by hand or by `aq apps install --all`.
#
#    The check below therefore asserts the OPPOSITE of what it used to. An
#    image that ships this service enabled is a regression, and the build says
#    so, because the symptom on a real machine — ten gigabytes of unasked-for
#    downloading — is one nobody would thank us for.
# ------------------------------------------------------------------------------
say "The app installer (present, and deliberately not switched on)"

[ -x /usr/libexec/aquarius-flatpak-preinstall ] \
    || die "/usr/libexec/aquarius-flatpak-preinstall is missing or not executable."

if systemctl is-enabled "${PREINSTALL_SERVICE}" > /dev/null 2>&1; then
    bad "${PREINSTALL_SERVICE} is switched on — it would download every app before anybody was asked; the chooser is supposed to ask first"
else
    ok "${PREINSTALL_SERVICE} is not switched on (correct — the chooser asks first)"
fi

# The parser, run against the real shipped list, exactly as it will run on a
# machine. This is the check that would have caught the 2026-09-04 fault, in
# which an unreadable file pattern made the reading return nothing at all and
# the service concluded there was nothing to install.
say "Reading the shopping list with the real parser"
# `|| true` because this script runs under `set -e` with `pipefail`: if the
# reader fails we want the plain-English FAIL below, not the build dying on an
# assignment with no explanation of what it was trying to do.
AQ_PARSED="$(/usr/libexec/aquarius-flatpak-preinstall --list | wc -l || true)"
AQ_BLOCKS="$(grep -c '^\[Flatpak Preinstall ' "${PREINSTALL_FILE}")"
if [ "${AQ_PARSED}" -eq "${AQ_BLOCKS}" ] && [ "${AQ_PARSED}" -gt 0 ]; then
    ok "the parser finds all ${AQ_PARSED} apps on the list"
else
    bad "the parser found ${AQ_PARSED} apps but the list has ${AQ_BLOCKS} — the reading is broken, and a machine would install nothing"
fi

# ------------------------------------------------------------------------------
# The words the chooser puts on screen
# ------------------------------------------------------------------------------
# The catalog carries the name, sentence and category for each app. It has to
# describe exactly the apps on the shopping list — no more, no fewer — or the
# chooser either shows an app nobody can install or silently hides one that is
# about to be.
say "The app catalog (the names and descriptions the chooser shows)"
[ -r "${CATALOG_FILE}" ] \
    || die "${CATALOG_FILE} is missing — it ships in system_files/ and the chooser cannot be drawn without it."

AQ_CATALOGUED="$(/usr/libexec/aquarius-flatpak-preinstall --catalog 2>/dev/null | wc -l || true)"
if [ "${AQ_CATALOGUED}" -eq "${AQ_BLOCKS}" ]; then
    ok "all ${AQ_CATALOGUED} apps have a name and a description"
else
    bad "only ${AQ_CATALOGUED} of ${AQ_BLOCKS} apps have a catalog entry — these are the ones with no name or description:"
    /usr/libexec/aquarius-flatpak-preinstall --catalog 2>&1 >/dev/null | sed 's/^/       /' || true
fi

# The other direction: an entry describing an app that is not on the list.
comm -13 \
    <(printf '%s\n' "${AQ_IDS}") \
    <(grep '^\[' "${CATALOG_FILE}" | tr -d '[]' | sort) > /tmp/aq-catalog-extra.txt
if [ -s /tmp/aq-catalog-extra.txt ]; then
    bad "the catalog describes apps that are not on the shopping list, so nobody can install them:"
    sed 's/^/       /' /tmp/aq-catalog-extra.txt
else
    ok "the catalog describes nothing that is not on the list"
fi

# Every entry must sit on one of the five shelves the chooser knows how to draw.
AQ_BAD_CATEGORY="$(/usr/libexec/aquarius-flatpak-preinstall --catalog 2>/dev/null \
    | awk -F'\t' '$4 !~ /^(Video|Audio|Design|Streaming|Utilities)$/ {print $1 " -> " $4}' || true)"
if [ -z "${AQ_BAD_CATEGORY}" ]; then
    ok "every app is on one of the five shelves the chooser draws"
else
    bad "these apps name a category the chooser does not know:"
    printf '%s\n' "${AQ_BAD_CATEGORY}" | sed 's/^/       /'
fi

# The command the service depends on. Fedora 44 ships flatpak 1.18, which has
# it; asked rather than assumed, because the fallback path in the service
# cannot honour the "a removed app stays removed" rule and should never be the
# one that runs.
say "Does this image's Flatpak have the preinstall command?"
flatpak --version
if flatpak preinstall --help > /dev/null 2>&1; then
    ok "'flatpak preinstall' is available — the proper mechanism will be used"
else
    bad "this Flatpak has no 'preinstall' command; the service would fall back to a loop that cannot tell an app you removed from one never installed"
fi

# ==============================================================================
# JOB 5 — the ingest helper, promoted
# ==============================================================================
# The command and the right-click menu have been in the image since R1 and are
# checked in step 5. What is added here is the front door (`aq ingest`) and the
# optional watch folder, and what is CHECKED here is that the whole feature
# really works end to end in this image — including the one thing it cannot do
# without, which is an ffmpeg that can actually encode.
# ------------------------------------------------------------------------------
say "The ingest helper"

/usr/bin/aq-ingest --version
ok "aq-ingest runs"

# The front door. Asked by running it, because a case statement with a typo in
# it is invisible until somebody types the command on a real machine.
if /usr/bin/aq ingest --help | grep -q 'make camera files open in a video editor'; then
    ok "'aq ingest' is wired up"
else
    bad "'aq ingest --help' does not print its own help — the subcommand is not wired up"
fi
if /usr/bin/aq --help | grep -q 'aq ingest'; then
    ok "'aq --help' tells people the ingest command exists"
else
    bad "'aq --help' does not mention ingest — a command nobody can discover is a command nobody uses"
fi

# The watch folder. Off by default, which is the specification's own choice, so
# what is checked is that the parts exist and that the helper runs.
say "The ingest watch folder (off by default)"
[ -x /usr/libexec/aquarius-ingest-watch ] \
    || die "/usr/libexec/aquarius-ingest-watch is missing or not executable."
# Asked with ast.parse rather than py_compile: the answer is the same and it
# writes no __pycache__ folder into /usr, which is meant to be read-only and
# tidy.
python3 -c "import ast,sys; ast.parse(open('/usr/libexec/aquarius-ingest-watch').read())" \
    || die "/usr/libexec/aquarius-ingest-watch is not valid Python — the watch folder would never run."

for unit in aq-ingest-watch.path aq-ingest-watch.service; do
    if [ -r "/usr/lib/systemd/user/${unit}" ]; then
        ok "${unit} is installed"
    else
        bad "/usr/lib/systemd/user/${unit} is missing"
    fi
done

# It must be OFF. A watch folder that switched itself on would convert
# everything anybody ever put in ~/Videos/Ingest without being asked.
if [ -e /usr/lib/systemd/user/default.target.wants/aq-ingest-watch.path ]; then
    bad "the watch folder is switched on by default — it must not be"
else
    ok "the watch folder is off until somebody runs 'aq ingest watch on' (correct)"
fi

# systemd's own reader, on our unit files. A mistake in one is otherwise only
# discovered on somebody's machine.
if aq_have systemd-analyze; then
    if systemd-analyze verify --user /usr/lib/systemd/user/aq-ingest-watch.path > /tmp/aq-unit-check.txt 2>&1; then
        ok "systemd is happy with aq-ingest-watch.path"
    else
        echo "  NOTE: systemd-analyze had something to say about the watch units:"
        sed 's/^/         /' /tmp/aq-unit-check.txt
    fi
    rm -f /tmp/aq-unit-check.txt
fi

# The helper's own answer on a fresh account, asked with a throwaway home
# folder so nothing in the image is touched. This is the real proof that the
# Python runs on THIS image with THIS Python, rather than on a laptop.
say "What the watch folder says on a brand-new account"
AQ_FAKE_HOME="$(mktemp -d)"
if HOME="${AQ_FAKE_HOME}" XDG_CONFIG_HOME="${AQ_FAKE_HOME}/.config" \
    /usr/libexec/aquarius-ingest-watch --status > /tmp/aq-watch-status.txt 2>&1; then
    sed 's/^/       /' /tmp/aq-watch-status.txt
    if grep -q 'Watching  : nothing' /tmp/aq-watch-status.txt; then
        ok "a new account watches nothing, as intended"
    else
        bad "a new account is watching something — the default must be off"
    fi
else
    bad "'aquarius-ingest-watch --status' failed on a fresh account:"
    sed 's/^/       /' /tmp/aq-watch-status.txt
fi
rm -rf "${AQ_FAKE_HOME}" /tmp/aq-watch-status.txt

# ffmpeg is what aq-ingest actually is, underneath. Step 2 checks the encoders
# it needs; this checks the two programs are on the path where aq-ingest looks
# for them, and that the HEIC tools an iPhone photo needs are here.
for tool in ffmpeg ffprobe; do
    if aq_have "${tool}"; then ok "${tool} is on the path"; else bad "${tool} is missing — aq-ingest refuses to run without it"; fi
done
if aq_have heif-convert; then
    ok "heif-convert is here (iPhone HEIC photos)"
else
    echo "  NOTE: heif-convert is not on the path. aq-ingest converts HEIC through"
    echo "        ffmpeg's libheif support instead, which step 2 installs."
fi

# ==============================================================================
# JOB 6 — write down what this layer put in the image
# ==============================================================================
# One small file that answers "what creator software is on this machine?"
# without anybody having to run six commands. The docs point at it and `aq`
# can print it.
say "Recording what this layer installed"
install -d -m 0755 /usr/share/aquarius
{
    echo "# The AquariusOS creator layer, as built."
    echo "# Written by build_files/64-creator-apps.sh."
    echo ""
    echo "[baked into the image]"
    for entry in "${AQUARIUS_APPS[@]}"; do
        read -r aq_name _ aq_tag <<< "${entry}"
        echo "${aq_name} ${aq_tag}"
    done
    echo ""
    echo "[installed from Flathub on first boot]"
    printf '%s\n' "${AQ_IDS}"
} > /usr/share/aquarius/creator-apps.txt
chmod 0644 /usr/share/aquarius/creator-apps.txt
cat /usr/share/aquarius/creator-apps.txt | sed 's/^/       /'

# ------------------------------------------------------------------------------
# One last sweep of /var, on the way out
# ------------------------------------------------------------------------------
# The clean-up after the permission check is not enough on its own, because any
# `flatpak` command AFTER it could set the repository up again. Rather than
# reason about which flatpak commands do that, the last thing this step does is
# look, and empty it if there is anything there. Cheap, and it cannot be got
# wrong by somebody adding a line later.
if [ -n "$(find /var/lib/flatpak -mindepth 1 2> /dev/null | head -1 || true)" ]; then
    echo "A later command put Flatpak state back into /var. Emptying it again:"
    find /var/lib/flatpak -mindepth 1 -maxdepth 1 -printf '  %f\n' 2> /dev/null || true
    find /var/lib/flatpak -mindepth 1 -delete 2> /dev/null || true
fi
if [ -z "$(find /var/lib/flatpak -mindepth 1 2> /dev/null | head -1 || true)" ]; then
    ok "this step ships no Flatpak state in /var"
else
    bad "Flatpak state remains in /var and would be shipped into the image"
    find /var/lib/flatpak -mindepth 1 2> /dev/null | head -10 | sed 's/^/       /'
fi

aq_finish "The creator layer"
