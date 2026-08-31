#!/usr/bin/bash
# ==============================================================================
# AquariusOS — the GNOME desktop layer
# ==============================================================================
# WHAT THIS FILE DOES
#   Everything that makes a Bazzite GNOME image into an AquariusOS GNOME image,
#   apart from the dock (that is build_files/gnome-extensions.sh, which runs
#   just before this one).
#
#   1. Installs the two small packages the GNOME versions of our own tools need.
#   2. Trims the handheld-only settings file off the images that are not the
#      handheld.
#   3. Puts the AquariusOS logo on Settings > System > About.
#   4. Puts the AquariusOS logo on the button in the top-left of the screen.
#   5. Puts the AquariusOS logo on the login screen.
#   6. Compiles the settings defaults — WITHOUT this last step, every single
#      thing in our override files is a file nobody reads.
#
#   Steps 3 and 4 were added on 2026-08-31, after the first bench boot came up
#   with Bazzite's logo in both places. Each one explains, where it happens, why
#   the obvious thing (setting LOGO= in os-release) was not enough.
#
# HOW OUR DEFAULTS REACH THE DESKTOP, IN PLAIN ENGLISH
#   GNOME keeps a compiled index of every setting on the machine at
#   /usr/share/glib-2.0/schemas/gschemas.compiled. Text files ending
#   .gschema.override in that folder change what the factory value of a setting
#   is — but only when that index is rebuilt. Drop the files in and do nothing
#   else and NOTHING happens, with no error anywhere. Rebuilding the index is
#   the last thing this script does.
#
#   ⚠️ THIS IS NOT THE SAME MECHANISM THE KDE LINE USES, and the difference is
#   worth understanding. On KDE we ship a folder of settings files and put it on
#   Plasma's own search path (system_files/etc/xdg/plasma-workspace/env/
#   zz-aquarius.sh), so KDE reads our answers as one more layer underneath the
#   user's. On GNOME there is no such cascade: there is one settings database,
#   and the override mechanism changes what "untouched" means inside it.
#
#   What the two have in common is the part that matters: in both, a person's
#   own choice always wins. Nothing here is a lock, and nothing here will ever
#   overwrite a setting somebody has changed.
#
# Called from build_files/build.sh, GNOME images only.
# Beginner-facing write-up: docs/gnome-variants.md
# ==============================================================================

set -euo pipefail

AQ_IMAGE_NAME="${IMAGE_NAME:-aquarius-os-gnome}"

SCHEMA_DIR="/usr/share/glib-2.0/schemas"
BACKGROUNDS_DIR="/usr/share/backgrounds/aquarius"
BACKGROUND_XML="/usr/share/gnome-background-properties/aquarius.xml"
NAUTILUS_EXT="/usr/share/nautilus-python/extensions/aquarius_editor_ready.py"
HANDHELD_OVERRIDE="${SCHEMA_DIR}/zz1-aquarius-40-handheld.gschema.override"
LOGO_PNG="/usr/share/aquarius/branding/aquarius-logo.png"

# The one logo ICON on the machine. os-release's LOGO field names it (see
# build_files/image-info.sh) and the top-bar button below points straight at it.
LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg"

# The two pictures the About page shows, and the two places Fedora's copy of
# gnome-control-center has been compiled to look for them. Step 3 explains.
ABOUT_LOGO_SRC_LIGHT="/usr/share/aquarius/branding/aquarius-about-logo.png"
ABOUT_LOGO_SRC_DARK="/usr/share/aquarius/branding/aquarius-about-logo-white.png"
ABOUT_LOGO_DEST_LIGHT="/usr/share/pixmaps/fedora_logo_med.png"
ABOUT_LOGO_DEST_DARK="/usr/share/pixmaps/fedora_whitelogo_med.png"
CONTROL_CENTER="/usr/bin/gnome-control-center"

# The top-bar logo button's settings, and the folder they live in.
DISTRO_KEYFILE_DIR="/etc/dconf/db/distro.d"
LOGOMENU_KEYFILE="${DISTRO_KEYFILE_DIR}/zz1-aquarius-logomenu"
LOGOMENU_EXT="/usr/share/gnome-shell/extensions/logomenu@aryan_k"

say() { echo; echo "=== $* ==="; }

# ==============================================================================
# 1 — The two packages the GNOME versions of our own tools need
# ==============================================================================
# Both are small, both are permanent, and both are here because a piece of
# AquariusOS does not work without them.
#
#   zenity           How a script asks a question with a window on GNOME.
#                    kdialog is the KDE equivalent and is not on a GNOME image,
#                    so without this the first-login "set up your creator apps"
#                    window would simply never appear — and the way that script
#                    is written (correctly), it would not even complain: it
#                    exits quietly rather than failing in front of a new user.
#                    Bazzite's GNOME images do usually carry zenity already, so
#                    this line often costs a second and changes nothing. It is
#                    here as insurance, exactly like the libnotify line in
#                    build.sh.
#
#   nautilus-python  What lets a Python file add an item to the right-click menu
#                    in Files. Our "Make Editor-Ready" menu item is that file.
#                    Nothing else on the machine provides this, and without it
#                    the ingest tool is terminal-only on GNOME.
# ------------------------------------------------------------------------------

say "Installing the GNOME-side packages"
dnf5 install -y zenity nautilus-python

# ==============================================================================
# 2 — Handheld-only settings: kept on the handheld, deleted from the others
# ==============================================================================
# Same shape as the KDE line's /usr/share/aquarius/xdg-handheld trim in
# build.sh, and for the same reason: shipping the file everywhere and removing
# it again is the arrangement that cannot fail quietly. The file is always in
# the repo, always reviewed, always in one place, and the only image-specific
# thing is one `rm -f`.
#
# What is in it, and why only the handheld wants it, is written at the top of
# system_files/usr/share/glib-2.0/schemas/zz1-aquarius-40-handheld.gschema.override.
# ------------------------------------------------------------------------------

say "Handheld-only settings"
case "${AQ_IMAGE_NAME}" in
*deck*)
    echo "OK: '${AQ_IMAGE_NAME}' is the GNOME handheld image — keeping the handheld settings."
    # Prove it is really there. A file that quietly stopped being copied would
    # otherwise ship a handheld with two on-screen keyboards fighting each
    # other, and nothing would go red.
    test -r "${HANDHELD_OVERRIDE}"
    grep -q "block-caribou-36@lxylxy123456.ercli.dev" "${HANDHELD_OVERRIDE}"
    ;;
*)
    echo "NOTE: '${AQ_IMAGE_NAME}' is a desktop image — removing the handheld-only settings."
    rm -f "${HANDHELD_OVERRIDE}"
    ;;
esac

# ==============================================================================
# 3 — The AquariusOS logo on Settings > System > About
# ==============================================================================
# THE BUG THIS FIXES
#   On the first bench boot of a GNOME image (2026-08-31) the About page showed
#   a big BAZZITE wordmark, with the line "Operating System: AquariusOS" sitting
#   right underneath it. So the name was ours and the picture was not.
#
# WHY SETTING LOGO= IN os-release WAS NOT ENOUGH
#   Every write-up you will find says GNOME's About page reads the LOGO field
#   out of os-release and looks up an icon by that name. That is true of GNOME's
#   own source code — but only of the half that Fedora does not use.
#
#   The function is setup_os_logo() in
#   gnome-control-center/panels/system/about/cc-about-page.c, and the whole thing
#   is wrapped in a compile-time switch:
#
#       #ifdef DISTRIBUTOR_LOGO
#           ... show that exact file, and RETURN ...
#       #else
#           ... the os-release LOGO lookup everybody writes about ...
#       #endif
#
#   Fedora builds with the switch turned on. From its RPM recipe
#   (src.fedoraproject.org/rpms/gnome-control-center, gnome-control-center.spec):
#
#       -Ddistributor_logo=%{_datadir}/pixmaps/fedora_logo_med.png
#       -Ddark_mode_distributor_logo=%{_datadir}/pixmaps/fedora_whitelogo_med.png
#
#   Those two paths are baked into the program. On a Fedora-derived system the
#   About page NEVER looks at os-release's LOGO at all, which is why our correct
#   LOGO=aquarius-logo changed nothing there.
#
#   (The field is still right and still worth having: plenty of other things do
#   read it — fastfetch, KDE's Info Centre, GNOME's own code on non-Fedora
#   builds. It is simply not what this page uses.)
#
# WHAT WE DO INSTEAD, AND WHY IT IS THE HONEST FIX
#   We replace the two files the program was told to open. That is not a hack we
#   invented: it is exactly what Bazzite does — their repo ships replacements for
#   the same four Fedora logo pixmaps under system_files/overrides/usr/share/
#   pixmaps/ — and it is the only way to change this without rebuilding
#   gnome-control-center ourselves. We are not going to fork a GNOME app to
#   change a picture.
#
#   Two files because the About page picks a different one in dark mode. Both
#   ship in this repo and are drawn by branding/render-about-logo.sh; the
#   "-white" one is the white-ink version for dark backgrounds.
#
# WE DO NOT TRUST THE TWO PATHS — WE CHECK THEM
#   They come from a spec file for a package we do not build, and a future
#   Fedora could move them. So rather than assume, we read the compiled program
#   itself: the paths are plain text inside the binary, so they can simply be
#   looked for. If they are ever not there, this fails the build and prints
#   every /usr/share/pixmaps path the program DOES mention, which is exactly the
#   information the next person needs.
# ------------------------------------------------------------------------------

say "The About page logo"

for f in "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_SRC_DARK}"; do
    if [ ! -s "$f" ]; then
        echo "AQUARIUS ERROR: ${f} is missing or empty." >&2
        echo "                This is one of the two About-page logos. Re-draw them" >&2
        echo "                with: bash branding/render-about-logo.sh" >&2
        exit 1
    fi
done

if [ ! -x "${CONTROL_CENTER}" ]; then
    echo "AQUARIUS ERROR: ${CONTROL_CENTER} is not in this image, so there is no" >&2
    echo "                Settings app and no About page. That should be impossible" >&2
    echo "                on a GNOME image — something is very wrong." >&2
    exit 1
fi

# The paths the Settings app was compiled to open. `grep -a` treats the binary
# as text; `-o` prints just the matching path rather than a screenful of noise.
echo "Paths under /usr/share/pixmaps named inside ${CONTROL_CENTER}:"
CC_PIXMAP_PATHS="$(grep -a -o -E '/usr/share/pixmaps/[A-Za-z0-9._+-]+' "${CONTROL_CENTER}" | sort -u || true)"
if [ -z "${CC_PIXMAP_PATHS}" ]; then
    echo "  (none)"
else
    echo "${CC_PIXMAP_PATHS}" | sed 's/^/  /'
fi

for want in "${ABOUT_LOGO_DEST_LIGHT}" "${ABOUT_LOGO_DEST_DARK}"; do
    if ! printf '%s\n' "${CC_PIXMAP_PATHS}" | grep -qx "${want}"; then
        echo "AQUARIUS ERROR: this image's Settings app does not mention ${want}." >&2
        echo "                That is the file we replace to brand the About page, so" >&2
        echo "                replacing it would now do nothing and the page would keep" >&2
        echo "                showing Bazzite's logo." >&2
        echo "                Fedora has probably moved the picture. The paths this" >&2
        echo "                build of Settings DOES name are listed above — pick the" >&2
        echo "                light and dark ones and update the two DEST paths at the" >&2
        echo "                top of this script." >&2
        exit 1
    fi
done
echo "OK: the Settings app really does read those two files."

# Now put ours there. `install -D` creates /usr/share/pixmaps if this image
# somehow did not have it, so a missing folder cannot fail the build.
install -D -m 0644 "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_DEST_LIGHT}"
install -D -m 0644 "${ABOUT_LOGO_SRC_DARK}" "${ABOUT_LOGO_DEST_DARK}"

# And prove the copies landed, byte for byte. `cmp -s` is a stronger claim than
# "the file exists": it says the file that is there is OUR file, which is the
# thing that was wrong before.
if cmp -s "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_DEST_LIGHT}" \
    && cmp -s "${ABOUT_LOGO_SRC_DARK}" "${ABOUT_LOGO_DEST_DARK}"; then
    echo "OK: the About page now shows the AquariusOS logo in both light and dark."
else
    echo "AQUARIUS ERROR: the About-page logos did not copy correctly." >&2
    ls -l "${ABOUT_LOGO_DEST_LIGHT}" "${ABOUT_LOGO_DEST_DARK}" >&2 || true
    exit 1
fi

# ==============================================================================
# 4 — The AquariusOS logo on the button in the top-left corner
# ==============================================================================
# WHAT THAT BUTTON IS
#   The small logo at the far left of GNOME's top bar, which opens a menu (App
#   Grid, Files, Steam, Lutris, …). It is not part of GNOME. It comes from an
#   extension called Logo Menu that Bazzite installs, that we keep, and that our
#   own zz1-aquarius-20-shell.gschema.override switches on. On the first bench
#   boot it was still showing Bazzite's purple logo.
#
# WHY THIS ONE NEEDS A DIFFERENT MECHANISM FROM EVERY OTHER SETTING WE CHANGE
#   Our other GNOME defaults are .gschema.override files, which change what a
#   setting's factory value is. That only works when the setting's description
#   is installed system-wide in /usr/share/glib-2.0/schemas. Logo Menu keeps its
#   description inside its own extension folder, so there is nothing there for
#   an override to attach to — and section 6 below compiles our overrides with
#   --strict, which turns "that setting does not exist" into a failed build.
#
#   The mechanism that does work is dconf, and it is the one Bazzite uses for
#   this very extension: a plain text file in /etc/dconf/db/distro.d/, baked
#   into a database by `dconf update`, read by every account underneath its own
#   choices. Our file is system_files/etc/dconf/db/distro.d/zz1-aquarius-logomenu
#   and its own header explains the setting in detail.
#
# THE ORDER RULE, AND WHY WE CHECK IT INSTEAD OF TRUSTING IT
#   When two files in that folder set the same thing, the one that sorts LAST
#   wins. Straight from dconf's own source (bin/dconf.c, read_directory):
#   "FILES-PRECEDENCE: When a path is found in multiple files, value from the
#   file lexicographically latest takes precedence."
#
#   Bazzite's files start 00-, 01- and 10-. Ours starts zz1-, so it wins today.
#   A convention that quietly stops holding is exactly how branding breaks, so
#   the check below compares the real filenames rather than believing the note.
# ------------------------------------------------------------------------------

say "The top-bar logo button"

if [ ! -d "${LOGOMENU_EXT}" ]; then
    echo "AQUARIUS ERROR: ${LOGOMENU_EXT} is missing, so there is no logo button" >&2
    echo "                in the top bar for these settings to change. Our" >&2
    echo "                enabled-extensions list still names it, which would leave" >&2
    echo "                GNOME trying to load an extension that is not installed." >&2
    exit 1
fi

if [ ! -r "${LOGOMENU_KEYFILE}" ]; then
    echo "AQUARIUS ERROR: ${LOGOMENU_KEYFILE} is missing." >&2
    echo "                It ships from system_files/etc/dconf/db/distro.d/ — check" >&2
    echo "                the system_files copy at the top of build_files/build.sh." >&2
    exit 1
fi

# The icon the file points at has to be a real file. If it is not, the extension
# silently shows a generic grey icon and nothing anywhere says why.
if ! grep -q "custom-icon-path='${LOGO_SVG}'" "${LOGOMENU_KEYFILE}"; then
    echo "AQUARIUS ERROR: ${LOGOMENU_KEYFILE} does not point at ${LOGO_SVG}." >&2
    echo "                The file says:" >&2
    grep -E '^(use-custom-icon|custom-icon-path)' "${LOGOMENU_KEYFILE}" >&2 || true
    echo "                Either the icon moved or the setting was edited. They must" >&2
    echo "                name the same file." >&2
    exit 1
fi
if [ ! -s "${LOGO_SVG}" ]; then
    echo "AQUARIUS ERROR: ${LOGO_SVG} does not exist, so the top-bar button would" >&2
    echo "                fall back to a generic grey icon — silently." >&2
    exit 1
fi

# Ours must sort after everybody else's in that folder. Compared, not assumed.
echo "Everything in ${DISTRO_KEYFILE_DIR}:"
ls -l "${DISTRO_KEYFILE_DIR}"
AQ_LAST_KEYFILE="$(find "${DISTRO_KEYFILE_DIR}" -maxdepth 1 -type f -printf '%f\n' | sort | tail -1)"
if [ "${AQ_LAST_KEYFILE}" = "$(basename "${LOGOMENU_KEYFILE}")" ]; then
    echo "OK: our settings file sorts last in that folder, so our answer wins."
else
    echo "AQUARIUS ERROR: '${AQ_LAST_KEYFILE}' sorts AFTER our file, so its answer" >&2
    echo "                would win and the top bar would keep Bazzite's logo." >&2
    echo "                Rename ours to sort last." >&2
    exit 1
fi

# Everyone's settings reach an account through /etc/dconf/profile/user, which
# Fedora's dconf package ships. Same defensive shape as the GDM profile below:
# if it is there we leave it alone and only insist it really reads the database
# our file goes into; if it is somehow missing we write the standard one.
if [ -f /etc/dconf/profile/user ]; then
    echo "OK: /etc/dconf/profile/user already exists — leaving it alone."
    if ! grep -q '^system-db:distro$' /etc/dconf/profile/user; then
        echo "AQUARIUS ERROR: /etc/dconf/profile/user does not read the 'distro'" >&2
        echo "                database, so the setting above would never be seen." >&2
        echo "                The file:" >&2
        cat /etc/dconf/profile/user >&2
        exit 1
    fi
else
    echo "NOTE: writing /etc/dconf/profile/user (this image did not have one)."
    install -d -m 0755 /etc/dconf/profile
    cat > /etc/dconf/profile/user <<'EOF'
# Written at build time by build_files/gnome-desktop.sh.
# Fedora's own dconf package normally ships this file; this is a copy of it.
# Read top to bottom: a person's own choices first, then the system defaults.
user-db:user
system-db:local
system-db:site
system-db:distro
EOF
fi

if ! command -v dconf > /dev/null 2>&1; then
    echo "AQUARIUS ERROR: the 'dconf' command is not in this image, so these" >&2
    echo "                settings cannot be compiled." >&2
    exit 1
fi

# A dry run into a throwaway database FIRST. `dconf compile` reads the same
# folder and writes somewhere harmless, so a typo — a missing quote, a mangled
# section header — becomes an error here, with the filename in it, instead of a
# silently ignored file on somebody's machine.
AQ_DCONF_TEST="$(mktemp -d)"
if ! dconf compile "${AQ_DCONF_TEST}/distro" "${DISTRO_KEYFILE_DIR}"; then
    echo "AQUARIUS ERROR: one of the files in ${DISTRO_KEYFILE_DIR} is not valid." >&2
    echo "                Read the message above — it names the file." >&2
    rm -rf "${AQ_DCONF_TEST}"
    exit 1
fi
rm -rf "${AQ_DCONF_TEST}"
echo "OK: every settings file in that folder is valid."

# Now the real thing.
dconf update

if [ ! -s /etc/dconf/db/distro ]; then
    echo "AQUARIUS ERROR: /etc/dconf/db/distro was not written, so the top bar" >&2
    echo "                would keep Bazzite's logo." >&2
    exit 1
fi
# Content, not just existence: the compiled database stores the text of the
# setting, so the path we asked for can be read straight back out of it. This is
# the check that would catch a database built before our file arrived.
if grep -a -q "${LOGO_SVG}" /etc/dconf/db/distro; then
    echo "OK: the compiled settings database points the top-bar button at our logo."
else
    echo "AQUARIUS ERROR: /etc/dconf/db/distro does not mention ${LOGO_SVG}," >&2
    echo "                so it was built without our file." >&2
    exit 1
fi

# ==============================================================================
# 5 — The AquariusOS logo on the login screen
# ==============================================================================
# GDM is GNOME's login screen. It reads its settings from its OWN settings
# database rather than from the one every other account uses — which makes
# sense (it runs before anybody has logged in) and means the override files
# above do not reach it. The supported way to change something about it is the
# one used here, and it is GNOME's own documented sysadmin recipe:
#
#   /etc/dconf/profile/gdm      says where GDM's settings come from
#   /etc/dconf/db/gdm.d/…       the settings themselves, as plain text
#   dconf update                turns that folder into the database GDM reads
#
# ⚠️ NOT ON THE HANDHELD, AND THIS IS NOT AN OVERSIGHT. Bazzite's handheld
# images use SDDM as their login screen, not GDM — even the GNOME ones. That is
# not an accident on their side either: SDDM is what Valve's Game Mode session
# is wired into, and /usr/libexec/bazzite-autologin writes SDDM configuration to
# decide whether the machine boots into Game Mode or the desktop. Writing GDM
# settings on that image would be writing a file nothing reads. Branding the
# handheld's login screen is a separate job for a later phase.
# ------------------------------------------------------------------------------

say "The login screen logo"
case "${AQ_IMAGE_NAME}" in
*deck*)
    echo "NOTE: the GNOME handheld uses SDDM, not GDM — skipping the GDM logo."
    ;;
*)
    if [ ! -r "${LOGO_PNG}" ]; then
        echo "AQUARIUS ERROR: ${LOGO_PNG} is missing." >&2
        echo "                GDM's logo setting takes a path to a real picture file," >&2
        echo "                and a path pointing at nothing gives a login screen with" >&2
        echo "                a blank space where the logo should be — silently." >&2
        echo "                Re-render it with: bash branding/render-logo-png.sh" >&2
        exit 1
    fi

    # The profile file. Fedora's gdm package usually ships one already, and if
    # it does we leave it exactly alone — it is not ours and replacing it could
    # take other GDM defaults with it. All we insist on is that it really does
    # read the gdm database, because that is the line our settings arrive
    # through.
    if [ -f /etc/dconf/profile/gdm ]; then
        echo "OK: /etc/dconf/profile/gdm already exists — leaving it alone."
        if ! grep -q '^system-db:gdm$' /etc/dconf/profile/gdm; then
            echo "AQUARIUS ERROR: /etc/dconf/profile/gdm does not read the 'gdm' database," >&2
            echo "                so the logo setting below would never be seen. The file:" >&2
            cat /etc/dconf/profile/gdm >&2
            exit 1
        fi
    else
        echo "NOTE: writing /etc/dconf/profile/gdm (this image did not have one)."
        install -d -m 0755 /etc/dconf/profile
        cat > /etc/dconf/profile/gdm <<'EOF'
# Written at build time by build_files/gnome-desktop.sh.
# This is GNOME's standard login-screen settings profile, read top to bottom.
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
    fi

    install -d -m 0755 /etc/dconf/db/gdm.d
    cat > /etc/dconf/db/gdm.d/01-aquarius-logo <<EOF
# Written at build time by build_files/gnome-desktop.sh — do not edit by hand.
# The picture GDM shows under the clock on the login screen.
[org/gnome/login-screen]
logo='${LOGO_PNG}'
EOF

    # Turn the text file above into the database GDM actually reads. Without
    # this, the file sits there and the login screen never changes.
    if ! command -v dconf > /dev/null 2>&1; then
        echo "AQUARIUS ERROR: the 'dconf' command is not in this image, so the login" >&2
        echo "                screen settings cannot be compiled." >&2
        exit 1
    fi
    dconf update

    # And prove the compiled database really came out, rather than assuming.
    if [ -s /etc/dconf/db/gdm ]; then
        echo "OK: the login screen database was rebuilt."
    else
        echo "AQUARIUS ERROR: /etc/dconf/db/gdm was not written. The login screen" >&2
        echo "                would keep Bazzite's logo." >&2
        exit 1
    fi

    # The whole chain, end to end, checked by content rather than by existence.
    # There are four links — the profile, the text file, the compiled database
    # and the picture itself — and a break in any one of them gives a login
    # screen with a blank space and no error anywhere. Added 2026-08-31 after
    # the bench boot showed how quietly this kind of thing fails elsewhere.
    if grep -a -q "${LOGO_PNG}" /etc/dconf/db/gdm; then
        echo "OK: the compiled login-screen database really names our logo."
    else
        echo "AQUARIUS ERROR: /etc/dconf/db/gdm does not mention ${LOGO_PNG}, so it" >&2
        echo "                was built without our file." >&2
        exit 1
    fi
    ;;
esac

# ==============================================================================
# 6 — Compile the settings defaults  (THE STEP EVERYTHING ELSE DEPENDS ON)
# ==============================================================================
# This is the line that makes every override file real. It has to be last,
# because anything installed after it that adds a settings description would not
# be in the index.
#
# It is done in two passes, and the first one is the important one:
#
#   PASS 1, in a throwaway copy, with --strict, and with ONLY OUR OVERRIDES.
#     --strict turns warnings into errors. In particular it turns "this override
#     mentions a setting that does not exist" — a typo in one of our files, or a
#     setting GNOME renamed in a new release — from a warning nobody reads into
#     a failed build.
#
#     ⚠️ The copy contains every schema in the image but ONLY the zz1-aquarius-*
#     override files, and that scoping is the whole point. Bazzite and several
#     Fedora packages ship overrides of their own; one of THOSE emitting a
#     warning is not our business and must not be able to stop AquariusOS
#     shipping. Copying only ours means a failure here is unambiguously ours,
#     and points at a file we can fix. Do not "simplify" this to copy them all.
#
#   PASS 2, for real, on the real folder, without --strict.
#     Writes the index the machine actually uses, from everybody's overrides.
#
# The `rm` first is not superstition. glib-compile-schemas will refuse to
# overwrite an index it thinks is newer than its inputs, and in a container
# where every file has a build timestamp that is a real possibility. Deleting it
# means the second line cannot be a silent no-op. This is the same order Bluefin
# uses in its own extension build script.
# ------------------------------------------------------------------------------

say "Compiling the GNOME settings defaults"

# Show what we are actually applying, in the build log, so a person reading a
# failed build can see the files without downloading the image.
echo "AquariusOS override files in ${SCHEMA_DIR}:"
ls -l "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override

if ! command -v glib-compile-schemas > /dev/null 2>&1; then
    echo "AQUARIUS ERROR: glib-compile-schemas is not in this image, so the GNOME" >&2
    echo "                defaults cannot be applied." >&2
    exit 1
fi

AQ_SCHEMA_TEST="$(mktemp -d)"
# Every schema description, so the overrides have something to attach to.
# TWO globs, not one: some of GNOME's schemas keep their enum definitions in a
# separate `.enums.xml` file (GWeather is one). Copy only the `.gschema.xml`
# half and --strict fails on GNOME's OWN files with "enum not (yet) defined" —
# which is exactly how the first six-variant CI run died (run 33422024053).
cp "${SCHEMA_DIR}"/*.gschema.xml "${AQ_SCHEMA_TEST}/"
cp "${SCHEMA_DIR}"/*.enums.xml "${AQ_SCHEMA_TEST}/" 2> /dev/null || true
# ...but only OUR overrides. See the note above.
cp "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override "${AQ_SCHEMA_TEST}/"
if ! glib-compile-schemas --strict "${AQ_SCHEMA_TEST}"; then
    echo "AQUARIUS ERROR: one of the AquariusOS settings override files is wrong." >&2
    echo "                Read the message above: it names the file, the setting and" >&2
    echo "                the problem. The usual cause is a misspelled setting name," >&2
    echo "                or a setting that this version of GNOME has renamed." >&2
    rm -rf "${AQ_SCHEMA_TEST}"
    exit 1
fi
rm -rf "${AQ_SCHEMA_TEST}"
echo "OK: every override file names real settings with valid values."

rm -f "${SCHEMA_DIR}/gschemas.compiled"
glib-compile-schemas "${SCHEMA_DIR}"

if [ ! -s "${SCHEMA_DIR}/gschemas.compiled" ]; then
    echo "AQUARIUS ERROR: ${SCHEMA_DIR}/gschemas.compiled was not written." >&2
    echo "                Every AquariusOS default would be ignored." >&2
    exit 1
fi
echo "OK: the settings index was rebuilt."

# ==============================================================================
# 7 — Prove the rest of the GNOME layer really shipped
# ==============================================================================
# Cheap checks on things whose absence is silent. Each one is a file that, if it
# went missing, would produce a desktop that looks slightly wrong and says
# nothing about why.
# ------------------------------------------------------------------------------

say "Checking the GNOME layer"

AQ_GNOME_FAILS=0
bad() { echo "  FAIL $*"; AQ_GNOME_FAILS=1; }
ok() { echo "  OK   $*"; }

for f in "${SCHEMA_DIR}/zz1-aquarius-10-look.gschema.override" \
    "${SCHEMA_DIR}/zz1-aquarius-20-shell.gschema.override" \
    "${SCHEMA_DIR}/zz1-aquarius-30-dash-to-dock.gschema.override"; do
    if [ -r "$f" ]; then ok "$(basename "$f") is installed"
    else bad "$f is missing"; fi
done

# The wallpapers the -10- file names. A picture-uri pointing at nothing gives a
# flat coloured desktop and no error.
for f in "${BACKGROUNDS_DIR}/the-pour-ice-3840x2160.png" \
    "${BACKGROUNDS_DIR}/the-pour-midnight-3840x2160.png"; do
    if [ -s "$f" ]; then ok "$(basename "$f") is installed"
    else bad "$f is missing — the desktop would come up a flat colour"; fi
done

# And the two paths written into the settings file really are these two files.
# Comparing the text to the filesystem is the only way to catch a rename that
# updated one and not the other.
for want in the-pour-ice-3840x2160.png the-pour-midnight-3840x2160.png; do
    if grep -q "${want}" "${SCHEMA_DIR}/zz1-aquarius-10-look.gschema.override"; then
        ok "the settings file points at ${want}"
    else
        bad "the settings file does not mention ${want} — the paths have drifted apart"
    fi
done

# The wallpaper picker's listing.
if [ -r "${BACKGROUND_XML}" ]; then ok "the wallpaper appears in Settings > Appearance"
else bad "${BACKGROUND_XML} is missing — our wallpaper would not be listed in Settings"; fi

# The right-click menu item in Files.
if [ -r "${NAUTILUS_EXT}" ]; then ok "the 'Make Editor-Ready' menu item is installed"
else bad "${NAUTILUS_EXT} is missing — there would be no right-click ingest on GNOME"; fi
if python3 -m py_compile "${NAUTILUS_EXT}" 2> /dev/null; then
    ok "the menu item's code has no typos in it"
else
    bad "${NAUTILUS_EXT} does not compile — Files would ignore it silently"
fi
# py_compile leaves a __pycache__ folder next to the file. Nothing imports from
# that folder, so those files would never be read again.
rm -rf "$(dirname "${NAUTILUS_EXT}")/__pycache__"

# zenity, which is how every AquariusOS script asks a question on GNOME.
if command -v zenity > /dev/null 2>&1; then ok "zenity is installed"
else bad "zenity is missing — the first-login creator-apps window would never appear"; fi

if [ "${AQ_GNOME_FAILS}" -ne 0 ]; then
    echo "::error::The GNOME desktop layer is not complete in this image. See above."
    exit 1
fi

say "The AquariusOS GNOME layer is in place."
