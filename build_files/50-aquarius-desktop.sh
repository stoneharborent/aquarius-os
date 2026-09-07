#!/usr/bin/bash
# ==============================================================================
# STEP 5 — Making it look and feel like AquariusOS
# ==============================================================================
# Up to here we have assembled a competent, completely anonymous Fedora GNOME
# machine. This step is where it becomes ours:
#
#   * our files are copied in (wallpaper, logos, fonts, settings)
#   * GNOME's factory defaults are replaced with ours: Ice light theme,
#     Aquarius blue, Inter and JetBrains Mono, our wallpaper, our dock
#   * the Settings > About page shows our logo instead of Fedora's
#   * the login screen shows our logo
#   * the "Make Editor-Ready" right-click menu is installed in Files
#
# ⚠️ THE POSTURE, WHICH IS A DECISION AND NOT LAZINESS
#
# We work WITH GNOME's grain. Accent colour, wallpaper, fonts, a small set of
# extensions, and then we stop. No GNOME Shell theme, no GTK theme, no
# libadwaita patching. Every theme we do not ship is a theme that cannot break
# on the next GNOME release, and chasing GNOME's internals is a treadmill that
# has eaten entire distributions.
#
# ⚠️ TWO NAMED EXCEPTIONS SINCE 2026-09-06, BOTH NARROW ON PURPOSE.
#
# EXCEPTION 2 — TWO PROPERTIES OF GTK CSS, IN DARK MODE ONLY.
# This is the one place AquariusOS colours somebody else's windows, and it is
# two lines long:
#
#     window    { background-color: #0B1220; }   Midnight `bg`
#     headerbar { background-color: #152033; }   Midnight `panel`
#
# WHY. In dark mode the Aquarius shell turns Midnight, a deep navy, and
# libadwaita's own dark theme is a neutral near-black. Put a Files window on a
# Midnight desktop and the window is grey against navy — not broken, plainly
# from a different design. Two colours fix it.
#
# WHY IT IS NOT A TREADMILL. There is nothing of GNOME's here to keep up with.
# No text colours, no buttons, no borders, no widget styling, no selectors that
# name a libadwaita internal — the two most stable selectors in GTK, set to two
# colours out of our own palette. If libadwaita changes everything else about
# how a window is drawn, these two lines are still either right or harmless.
#
# WHY IT IS NOT SHIPPED AS A FILE IN /etc. Because it must apply in DARK ONLY,
# and GTK's CSS has no "only when dark" selector — a stylesheet is loaded or it
# is not. A file shipped system-wide would be on all the time, and a navy window
# on the Ice light desktop is the same mistake in the other direction. So the
# file is WRITTEN when the machine goes dark and REMOVED when it goes light, by
# /usr/share/aquarius/labwc/generate-theme, into ~/.config/gtk-4.0/gtk.css and
# its gtk-3.0 twin. That program also refuses to touch a gtk.css it did not
# write, so somebody's own GTK customisation is left alone.
#
# The colours come from the shell's theme/Midnight.qml, like every other colour
# in this project. build_files/55-aquarius-session.sh reads the generated file
# back and fails the build if it is ever more than those two rules.
#
# EXCEPTION 1 — THE APP ICONS.
# This list used to say "no icon theme" as well, and now AquariusOS does ship
# one — but it is not an icon theme in the sense that sentence meant. It is
# EIGHT icons: the Editor, the Writer, Files, Settings, the app chooser, the
# welcome window and the two DaVinci Resolve buttons. Both Aquarius themes say
# Inherits=Adwaita,hicolor, so every other icon on the machine — the several
# thousand of them — still comes from GNOME and still tracks GNOME. There is no
# treadmill here, because there is nothing of GNOME's to keep up with: these are
# our own apps' icons, and nobody else was ever going to draw them.
# See build_files/56-aquarius-icons.sh and branding/icons/README.md.
#
# The one thing we would like and cannot have is the exact Aquarius Blue
# (#2C8FC4) as the accent. GNOME accepts nine fixed words for that setting and
# a hex colour is not one of them. Patching libadwaita to add a tenth would mean
# owning a fork of the library every GTK app draws itself with, forever, and
# Ubuntu has been paying that bill for years. So: 'blue', which is the nearest
# of the nine and a good match.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

SCHEMA_DIR="/usr/share/glib-2.0/schemas"
BACKGROUNDS_DIR="/usr/share/backgrounds/aquarius"
BACKGROUND_XML="/usr/share/gnome-background-properties/aquarius.xml"
NAUTILUS_EXT="/usr/share/nautilus-python/extensions/aquarius_editor_ready.py"
LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg"
LOGO_PNG="/usr/share/aquarius/branding/aquarius-logo.png"
ABOUT_LOGO_SRC_LIGHT="/usr/share/aquarius/branding/aquarius-about-logo.png"
ABOUT_LOGO_SRC_DARK="/usr/share/aquarius/branding/aquarius-about-logo-white.png"
ABOUT_LOGO_DEST_LIGHT="/usr/share/pixmaps/fedora_logo_med.png"
ABOUT_LOGO_DEST_DARK="/usr/share/pixmaps/fedora_whitelogo_med.png"
CONTROL_CENTER="/usr/bin/gnome-control-center"

# ==============================================================================
# 1. Copy our own files into the image
# ==============================================================================
# Everything under system_files/ is laid out exactly as it will sit on the
# finished system, so this is a straight copy from the root of that folder to
# the root of the image. Adding a file to the OS means putting it in the right
# place under system_files/ — there is no list to update.
say "Copying the AquariusOS files into the image"
cp -avf /ctx/system_files/. /

# ==============================================================================
# 2. Sora, the headline typeface
# ==============================================================================
# Sora is not packaged by anybody, so it ships as a font file in system_files/
# and was copied in just now. Fonts are not found by being present — they are
# found by being in an index, and the index has to be rebuilt after anything is
# added. Skipping this gives a machine with the font file on disk and no
# application able to see it.
say "Rebuilding the font index"
fc-cache --system-only --force
if aq_output_has "Sora" fc-list; then
    ok "Sora is installed and findable"
else
    bad "Sora is on disk but no application can find it — the font index did not rebuild"
fi
for want in Inter "JetBrains Mono"; do
    if aq_output_has "${want}" fc-list; then
        ok "${want} is installed and findable"
    else
        bad "${want} is not findable — the interface would fall back to a default face"
    fi
done

# ==============================================================================
# 3. The About page logo
# ==============================================================================
# ⚠️ THIS ONE COST US A DAY, SO READ IT BEFORE CHANGING IT.
#
# Every guide on the internet says the logo on GNOME's About page comes from the
# LOGO= line in os-release. On Fedora that is not true. Fedora compiles
# gnome-control-center with two picture paths hardcoded into the program — one
# for light mode, one for dark — and the os-release branch is dead code that
# never runs. So the ONLY way to brand that page is to replace those two files.
#
# That is what Bazzite does too, and it is what we do. The check below greps the
# actual compiled program for the paths, so that if Fedora ever moves the
# pictures the build stops and says so, instead of shipping an image that
# quietly shows Fedora's logo on the About page.
#
# The two pictures are 279x80 and that size is load-bearing: the page lays out
# around the image's own dimensions, so a differently-shaped logo pushes the
# text around.
say "The About page logo"

for f in "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_SRC_DARK}"; do
    if [ ! -s "$f" ]; then
        echo "AQUARIUS ERROR: ${f} is missing or empty." >&2
        echo "                It is one of the two About-page logos. Re-draw them with:" >&2
        echo "                    bash branding/render-about-logo.sh" >&2
        exit 1
    fi
done

if [ ! -x "${CONTROL_CENTER}" ]; then
    echo "AQUARIUS ERROR: ${CONTROL_CENTER} is not in this image, so there is no" >&2
    echo "                Settings app and no About page. Step 4 should have" >&2
    echo "                installed gnome-control-center." >&2
    exit 1
fi

echo "Paths under /usr/share/pixmaps named inside ${CONTROL_CENTER}:"
CC_PIXMAP_PATHS="$(grep -a -o -E '/usr/share/pixmaps/[A-Za-z0-9._+-]+' "${CONTROL_CENTER}" | sort -u || true)"
if [ -z "${CC_PIXMAP_PATHS}" ]; then
    echo "  (none)"
else
    echo "${CC_PIXMAP_PATHS}" | sed 's/^/  /'
fi

for want in "${ABOUT_LOGO_DEST_LIGHT}" "${ABOUT_LOGO_DEST_DARK}"; do
    if printf '%s\n' "${CC_PIXMAP_PATHS}" > /tmp/aq-cc-paths.txt && grep -qx "${want}" /tmp/aq-cc-paths.txt; then
        ok "the Settings app really does read ${want}"
    else
        echo "AQUARIUS ERROR: this image's Settings app does not mention ${want}." >&2
        echo "                That is the file we replace to brand the About page, so" >&2
        echo "                replacing it would now do nothing and the page would keep" >&2
        echo "                showing Fedora's logo. Fedora has probably moved the" >&2
        echo "                picture — the paths this build DOES name are listed above." >&2
        echo "                Pick the light and dark ones and update the two DEST paths" >&2
        echo "                at the top of this script." >&2
        exit 1
    fi
done

install -D -m 0644 "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_DEST_LIGHT}"
install -D -m 0644 "${ABOUT_LOGO_SRC_DARK}" "${ABOUT_LOGO_DEST_DARK}"

if cmp -s "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_DEST_LIGHT}" \
    && cmp -s "${ABOUT_LOGO_SRC_DARK}" "${ABOUT_LOGO_DEST_DARK}"; then
    ok "the About page now shows the AquariusOS logo, light and dark"
else
    bad "the About-page logos did not copy correctly"
    ls -l "${ABOUT_LOGO_DEST_LIGHT}" "${ABOUT_LOGO_DEST_DARK}" || true
fi

# ==============================================================================
# 4. The login screen
# ==============================================================================
# ⚠️ READ THIS BEFORE CHANGING ANYTHING IN THIS SECTION — 2026-09-04.
#
# Royce photographed the bench machine booting and asked a fair question: why
# does the screen I log in at look like stock Fedora, when the screen I unlock
# at looks like AquariusOS?
#
# THE ANSWER IS THAT THEY ARE TWO DIFFERENT PROGRAMS.
#
#   THE LOGIN SCREEN is GDM. It runs before anybody has logged in, as its own
#   user, with its own settings database, and it is GNOME's program, not ours.
#   Everything we can change about it, we change from this section.
#
#   THE LOCK SCREEN is drawn inside a running session by that session's own
#   desktop, with that person's wallpaper and screen size. It looks like
#   AquariusOS because it IS AquariusOS.
#
# WHAT WE CAN AND CANNOT DO TO GDM, having checked (2026-09-04):
#
#   CAN   the logo, the screen SIZE (see below), light-vs-dark, the typefaces,
#         the mouse pointer, the icon set. All through GDM's own dconf
#         database, which is a supported, documented mechanism.
#
#   CANNOT  the background. There is no setting for it. GNOME's login screen
#         paints its background from a CSS rule (#lockDialogGroup) compiled
#         into gnome-shell's own resource bundle, and through GNOME 50 there is
#         still no key that overrides it. The only ways round it are patching
#         that bundle or loading a GNOME Shell extension into the greeter, and
#         both are exactly the theme treadmill this project refuses to walk
#         (see the posture note at the top of this file).
#
#         So GDM stays a clean, correctly-sized, light GNOME login screen with
#         our logo on it — and the REAL branded login screen is a different
#         thing entirely: our own greeter, drawn by the Aquarius Shell, shipped
#         alongside greetd. That is Part B, in docs/restart/login.md.
#
# THE SIZE PROBLEM, AND WHY WE STOPPED TRYING TO FIX IT HERE
#   GDM had no idea the bench monitor runs at 125%, so it drew everything at
#   100% on a 55" 4K screen. The scale of a monitor is not a dconf key; it
#   lives in a file called monitors.xml, and the copy that has the answer is
#   inside a home folder that the "gdm" user is not allowed to read.
#
#   ⚠️ THE OBVIOUS FIX — copy that file somewhere GDM can read it — BLACK-
#   SCREENED THE BENCH TWICE, on 4 and 5 September 2026, and nobody worked out
#   why. So as of 2026-09-05 (Royce's call) THE LOGIN SCREEN IS GIVEN NO COPIED
#   DISPLAY FILE. It runs at GNOME's own 100% and looks small on a 4K screen,
#   which is the deliberate trade: a small login screen is annoying, a black one
#   is a computer nobody can get into.
#
#   The messenger below still ships, switched off, for two reasons. It is the
#   thing that REMOVES a copy left behind by an older AquariusOS — which is what
#   heals Royce's bench on its first boot of this image — and it is how somebody
#   tests the idea again on one machine (`sudo aq login scale on`).
#
#   The real answer is our own login screen, which reads the session's scale
#   itself and needs nothing copied anywhere. That is Part B of
#   docs/restart/login.md and it is the R5 job.
#
#   What we deliberately do NOT do is set text-scaling-factor here instead —
#   that makes GNOME's text bigger without fixing the monitor scale, so the
#   login screen would end up wrong in a different direction, and it would be
#   wrong on every machine rather than only the 4K ones.
# ==============================================================================
# GDM reads its settings from its own dconf database, which is separate from
# every user's. Two files are needed and neither does anything on its own:
#
#   /etc/dconf/profile/gdm   tells GDM which databases to read
#   /etc/dconf/db/gdm.d/…    the setting itself
#
# and then `dconf update` has to bake the folder into a binary database. Drop
# the file in and run nothing, and nothing happens, with no error anywhere.
#
# The setting takes a path to a real picture. A path pointing at nothing gives a
# login screen with a blank space where the logo should be — silently. So the
# file is checked first.
say "The login screen logo"

if [ ! -r "${LOGO_PNG}" ]; then
    echo "AQUARIUS ERROR: ${LOGO_PNG} is missing." >&2
    echo "                Re-render it with: bash branding/render-logo-png.sh" >&2
    exit 1
fi

install -d -m 0755 /etc/dconf/profile
if [ -f /etc/dconf/profile/gdm ]; then
    ok "/etc/dconf/profile/gdm already exists — leaving it alone"
    aq_file_has /etc/dconf/profile/gdm '^system-db:gdm$' "GDM reads its own settings database"
else
    echo "NOTE: writing /etc/dconf/profile/gdm (this image did not have one)."
    cat > /etc/dconf/profile/gdm << 'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
fi

install -d -m 0755 /etc/dconf/db/gdm.d
cat > /etc/dconf/db/gdm.d/01-aquarius-logo << EOF
[org/gnome/login-screen]
logo='${LOGO_PNG}'
EOF

# ------------------------------------------------------------------------------
# The login screen's appearance
# ------------------------------------------------------------------------------
# A second file rather than more lines in the first, because these are a
# different KIND of setting: the one above is GDM's own (org.gnome.login-screen),
# and these are the ordinary desktop appearance settings, which the greeter
# reads because the greeter is itself a GNOME Shell wearing the "gdm" user's
# settings.
#
# EVERY VALUE HERE MATCHES THE ONE A REAL ACCOUNT GETS from
# zz1-aquarius-10-look.gschema.override. That is the whole point: the login
# screen should not be a different-looking place you pass through on the way to
# AquariusOS.
#
#   color-scheme      'prefer-light'. GNOME 47 made the login screen dark by
#                     default; AquariusOS is Ice, and Ice is light. Note the
#                     value is NOT 'default' (which is what a user account gets)
#                     — for the greeter, 'default' means "GNOME decides", and
#                     GNOME decides dark. 'prefer-light' is the one that asks.
#                     Honest limitation, reported upstream by others: even in
#                     light mode a few pieces of GNOME's own top bar can stay
#                     dark. We are not chasing those.
#   accent-color      'blue' — the nearest of GNOME's nine fixed words to
#                     Aquarius Blue. Same compromise, same reason, as the
#                     desktop: see the note at the top of this file.
#   font-name         Inter, the interface typeface, so the person's name under
#                     their picture is set in ours and not Fedora's.
#   cursor-theme      the pointer. Adwaita — and as of Phase R5 (2026-09-05)
#                     that is a settled decision, not a placeholder: AquariusOS
#                     ships GNOME's own cursor rather than a hand-drawn one for
#                     now, and the same choice is made for the desktop session
#                     in zz1-aquarius-10-look.gschema.override, so the pointer
#                     does not change shape the instant you log in. Written down
#                     explicitly so that the day real Aquarius cursor artwork
#                     exists, this is the one login-screen line that changes and
#                     it does not get forgotten. Full story + swap-in recipe:
#                     docs/restart/desktop-identity.md.
#   icon-theme        the app icons. 'Aquarius-Ice' — OUR OWN, since
#                     2026-09-06 — matching the desktop session exactly, which
#                     is the whole point of this file. The same value is set for
#                     a real account in zz1-aquarius-10-look.gschema.override,
#                     and if the two ever differ the icons visibly change the
#                     instant you log in. Only eight icons are ours; the theme
#                     inherits Adwaita for everything else. See
#                     build_files/56-aquarius-icons.sh and branding/icons/.
#
# NOT SET, ON PURPOSE: text-scaling-factor. See the long note above — the screen
# size is fixed by monitors.xml, and doing it twice makes it wrong the other way.
cat > /etc/dconf/db/gdm.d/02-aquarius-look << 'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-light'
accent-color='blue'
font-name='Inter 11'
document-font-name='Inter 11'
monospace-font-name='JetBrains Mono 10'
cursor-theme='Adwaita'
icon-theme='Aquarius-Ice'
EOF

# ------------------------------------------------------------------------------
# ⛔ THE FILE THAT USED TO BE HERE — 03-aquarius-scale — AND WHY IT IS GONE
# ------------------------------------------------------------------------------
# There used to be a third file here. It set ONE login-screen key:
#
#     [org/gnome/mutter]
#     experimental-features=['scale-monitor-framebuffer', 'xwayland-native-scaling']
#
# It was added on the theory that part sizes (125%, 150%) needed switching on
# for the login screen's own user. It is removed, 2026-09-05, and nothing
# replaces it. Do not put it back.
#
# WHY IT IS GONE — reason one: BOTH VALUES WERE DELETED FROM GNOME.
# Not "deprecated". Deleted. mutter merge request 4877, "Make framebuffer and
# Xwayland native scaling non-experimental", merged 3 February 2026, milestone
# GNOME 50 — https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/4877 . It
# removed BOTH scale-monitor-framebuffer AND xwayland-native-scaling from
# mutter's list of experimental features, because both behaviours became
# unconditional. In its own words: "Unmark these as experimental. This is
# already done in various downstreams, so it has been extensively tested, and
# generally provides a better experience."
#
# On GNOME 50 the whole list of experimental features is exactly two names, and
# neither of them is ours:
#
#     kms-modifiers        autoclose-xwayland
#
# (https://gitlab.gnome.org/GNOME/mutter/-/raw/gnome-50/data/org.gnome.mutter.gschema.xml.in)
#
# ⚠️ A TRAP FOR WHOEVER CHECKS THIS. That same schema file still contains an
# unused <flags> block near the top listing all four old names, including both
# of ours. It is vestigial — no key refers to it. Reading it and concluding the
# names are still valid is the wrong answer, and it is an easy wrong answer.
#
# WHY IT IS GONE — reason two: GNOME SAID SO OUT LOUD, ON THE BENCH.
# The login screen's own GNOME Shell printed this into the journal:
#
#     gnome-shell[2542]: Unknown experimental feature 'xwayland-native-scaling'
#
# That is mutter's own words for "you gave me a name I do not have".
#
# WHY IT IS GONE — reason three: IT BREAKS ON THE NEXT FEDORA.
# GNOME 51 deletes the experimental-features KEY itself (merge request 4893,
# merged 1 August 2026), replacing it with individual booleans under a new
# schema, org.gnome.mutter.experimental. On Fedora 45 this file would be naming
# a key that does not exist at all.
#
# ------------------------------------------------------------------------------
# ⚠️ WHAT THIS FILE IS *NOT*: THE PROVEN CAUSE OF THE BLACK SCREEN
# ------------------------------------------------------------------------------
# READ THIS BEFORE YOU TELL ANYONE THE BLACK SCREEN IS FIXED.
#
# There is a real correlation. On the night of 2026-09-05 Royce booted three
# images, and the first login screen after each boot went:
#
#     image 6fa7062   did NOT have this file   FINE
#     image 11e90fa   ADDED this file          BLACK
#     image 7068874   still had this file      BLACK
#
# On both black boots `systemctl restart gdm` brought the login screen straight
# back, and the copied display files that were blamed for two days were provably
# not on the machine — the boot-time cleanup had already removed them and said
# "No such file".
#
# AND THE CORRELATION IS PROBABLY A COINCIDENCE. Here is the evidence against
# our own theory, which matters more than the evidence for it:
#
#   mutter WARNS AND CARRIES ON. An unrecognised name in this list does not stop
#   anything. Its code reads the list, fails to match the name, prints "Unknown
#   experimental feature", ORs zero into the feature flags and moves to the next
#   entry — src/backends/meta-settings.c, experimental_features_handler().
#   There is no path from an unknown name to a screen that does not draw.
#
# So: this file is removed because it was junk — two names GNOME deleted, a key
# the next Fedora will not have, warned about in the journal on every start. That
# is reason enough on its own and needs no black screen to justify it.
#
# ⚠️ IF THE NEXT IMAGE STILL BLACK-SCREENS ON ITS FIRST START, THAT IS NOT A
# FAILURE OF THIS CHANGE. It is the answer to a question, and a useful one: it
# clears this file and leaves the driver-and-timing explanation, which is written
# out with the commands to prove it in docs/restart/login.md, section "Black
# screen with a cursor at boot". Write down which way it went, either way.
#
# WHAT REPLACES IT: nothing here, plus a check below and one in CI that refuse to
# build an image setting ANY login-screen key GNOME does not have. Because the
# real bug is not this one key. It is that we could invent a setting, ship it to
# a machine nobody could log in to, and have every build pass.
#
# ------------------------------------------------------------------------------
# ⚠️ NO LOGIN-SCREEN KEY WE SET MAY BE ONE GNOME DOES NOT HAVE
# ------------------------------------------------------------------------------
# Every key written above is read back against the schemas actually compiled
# into THIS image. `dconf update` does not do this for you: it will bake any
# name at all into the database without a word, which is exactly how
# 'xwayland-native-scaling' reached Royce's bench.
#
# The group name is the schema with slashes instead of dots — [org/gnome/mutter]
# is the schema org.gnome.mutter — so the check is: does that schema exist, and
# does it list that key?
#
# It reports through bad(), like every other check in this file, so one build
# tells you about every wrong key at once instead of only the first.
aq_check_gdm_keys_are_real() {
    local aq_file aq_schema aq_key aq_line

    if ! aq_have gsettings; then
        bad "the 'gsettings' command is not in this image — login-screen keys cannot be checked"
        return
    fi

    for aq_file in /etc/dconf/db/gdm.d/*; do
        [ -f "${aq_file}" ] || continue
        aq_schema=""
        while IFS= read -r aq_line; do
            case "${aq_line}" in
                # [org/gnome/mutter] -> org.gnome.mutter
                \[*\])
                    aq_schema="${aq_line#[}"
                    aq_schema="${aq_schema%]}"
                    aq_schema="$(printf '%s' "${aq_schema}" | tr '/' '.')"
                    ;;
                '' | \#*) : ;;
                *=*)
                    aq_key="${aq_line%%=*}"
                    # trim spaces around the key name
                    aq_key="$(printf '%s' "${aq_key}" | tr -d '[:space:]')"
                    [ -n "${aq_key}" ] || continue
                    if [ -z "${aq_schema}" ]; then
                        bad "$(basename "${aq_file}"): '${aq_key}' is not under any [group] — dconf would ignore it"
                        continue
                    fi
                    if ! gsettings list-keys "${aq_schema}" > /dev/null 2>&1; then
                        bad "$(basename "${aq_file}"): the schema ${aq_schema} is not in this image"
                        continue
                    fi
                    if gsettings list-keys "${aq_schema}" 2> /dev/null \
                        | grep -qx "${aq_key}"; then
                        ok "${aq_schema} really has a key called '${aq_key}'"
                    else
                        bad "${aq_schema} has NO key called '${aq_key}' — this is the 2026-09-05 class of bug"
                    fi
                    ;;
            esac
        done < "${aq_file}"
    done

    # ⚠️ AND THE ONE KEY WE WILL NOT SET AGAIN, BY NAME. The generic check above
    # would pass experimental-features happily: it IS a real mutter key. What
    # made it harmful is that its VALUE is a list of names nothing validates.
    # Removed 2026-09-05; if it ever comes back it comes back deliberately, with
    # this line deleted by the person who decided that.
    if grep -rq 'experimental-features' /etc/dconf/db/gdm.d/ 2> /dev/null; then
        bad "a login-screen file sets experimental-features — removed 2026-09-05, see docs/restart/login.md"
    else
        ok "no login-screen file sets experimental-features (removed 2026-09-05)"
    fi
}

if ! aq_have dconf; then
    echo "AQUARIUS ERROR: the 'dconf' command is not in this image." >&2
    exit 1
fi
dconf update

if [ -s /etc/dconf/db/gdm ]; then
    ok "the login screen settings database was built"
else
    bad "/etc/dconf/db/gdm was not written — the login screen would keep Fedora's logo"
fi
if grep -a -q "${LOGO_PNG}" /etc/dconf/db/gdm 2> /dev/null; then
    ok "the built database really names our logo"
else
    bad "/etc/dconf/db/gdm does not mention ${LOGO_PNG} — it was built without our file"
fi

# The appearance keys, read back out of the BUILT database rather than out of
# the file we just wrote. dconf update can skip a file it dislikes without
# saying anything, so "the file exists" proves nothing at all.
#
# 'Adwaita' here is the CURSOR theme; 'Aquarius-Ice' is the icon theme. Both are
# in the file above, and both have to survive into the database.
for aq_want in prefer-light 'Inter 11' 'JetBrains Mono 10' Adwaita Aquarius-Ice; do
    if grep -a -q "${aq_want}" /etc/dconf/db/gdm 2> /dev/null; then
        ok "the login screen database carries '${aq_want}'"
    else
        bad "/etc/dconf/db/gdm does not contain '${aq_want}' — the login screen would keep GNOME's own value"
    fi
done

# ⚠️ AND THE THINGS THAT MUST NOT BE IN IT. Read out of the BUILT database, for
# the same reason as above: the keyfile being gone does not prove the database
# is. This is the 2026-09-05 removal, checked by looking.
for aq_never in experimental-features scale-monitor-framebuffer xwayland-native-scaling; do
    if grep -a -q "${aq_never}" /etc/dconf/db/gdm 2> /dev/null; then
        bad "/etc/dconf/db/gdm still contains '${aq_never}' — removed 2026-09-05, see docs/restart/login.md"
    else
        ok "the login screen database has no '${aq_never}' in it"
    fi
done

# Every key we DO set has to be a key GNOME actually has.
aq_check_gdm_keys_are_real

# ------------------------------------------------------------------------------
# The login screen's SIZE — the messenger, and the two things that run it
# ------------------------------------------------------------------------------
say "Telling the login screen what size the screen is"

AQ_GDM_DISPLAY="/usr/libexec/aquarius-gdm-display"
chmod 0755 "${AQ_GDM_DISPLAY}"

if [ -x "${AQ_GDM_DISPLAY}" ]; then
    ok "$(basename "${AQ_GDM_DISPLAY}") is installed and executable"
else
    bad "${AQ_GDM_DISPLAY} is missing — the login screen would stay at 100% on a 4K monitor"
fi

# It has to be valid shell before it is worth enabling anything that runs it.
if bash -n "${AQ_GDM_DISPLAY}"; then
    ok "it is valid shell"
else
    bad "${AQ_GDM_DISPLAY} does not parse as shell"
fi

aq_unit_is_on_from_usr aquarius-gdm-display.service \
    "it runs at every boot, before the login screen starts"

# ⚠️ THE SWITCH IS OFF IN EVERY IMAGE WE PUBLISH, AND THAT IS A BUILD RULE.
# Shipping either marker would push a behaviour that has black-screened a real
# machine twice onto every computer that installs AquariusOS, with nobody having
# chosen it. They are created by hand, on one machine, by `aq login scale on`.
for aq_marker in /var/lib/aquarius/gdm-display-optin \
    /var/lib/aquarius/gdm-fractional-ok; do
    if [ -e "${aq_marker}" ]; then
        bad "${aq_marker} is baked into the image — this must be opt-in, per machine"
    else
        ok "$(basename "${aq_marker}") is not in the image (the copy stays off by default)"
    fi
done

# And the program itself has to AGREE that it is off. A messenger that copies
# regardless of the marker would make the marker decoration.
aq_file_has "${AQ_GDM_DISPLAY}" 'gdm-display-optin' \
    "the messenger checks the switch before copying anything"
aq_file_has "${AQ_GDM_DISPLAY}" 'rm -f "\$\{aq_leftover\}"' \
    "and it removes a copy left behind by an older AquariusOS"

# ------------------------------------------------------------------------------
# The safety check that stands between that file and the login screen
# ------------------------------------------------------------------------------
# ⚠️ THE MESSENGER MUST NOT RUN WITHOUT THIS. 2026-09-05: the bench booted to a
# black screen with a mouse pointer and no login screen, because the messenger
# had faithfully handed the login screen a display arrangement asking for 125%.
# The sanitiser rounds part sizes to whole ones before anything is copied. If it
# is missing, the messenger refuses to copy at all — which is safe, but means a
# login screen stuck at 100% forever, so a missing sanitiser is a build failure
# and not a warning.
say "The safety check on what the login screen is given"

AQ_SANITIZER="/usr/libexec/aquarius-monitors-sanitize"
chmod 0755 "${AQ_SANITIZER}"

if [ -x "${AQ_SANITIZER}" ]; then
    ok "$(basename "${AQ_SANITIZER}") is installed and executable"
else
    bad "${AQ_SANITIZER} is missing — the messenger would refuse to copy anything and the login screen would stay at 100%"
fi

if aq_have python3; then
    ok "python3 is in this image (the sanitiser is written in it)"
else
    echo "AQUARIUS ERROR: python3 is not in this image, so ${AQ_SANITIZER}" >&2
    echo "                could never run and the login screen size fix is dead." >&2
    exit 1
fi

# ⚠️ compile() AND NOT `python3 -m py_compile`. py_compile WRITES: it leaves a
# __pycache__ folder next to the file, which would be baked into /usr/libexec on
# every machine that ever installs AquariusOS. Nothing would read it — Python
# only uses __pycache__ for imported modules, not for programs run directly —
# so it is pure litter shipped forever. compile() does the identical syntax
# check in memory and writes nothing.
if python3 -c "import sys; compile(open(sys.argv[1]).read(), sys.argv[1], 'exec')" \
    "${AQ_SANITIZER}"; then
    ok "it is valid python"
else
    bad "${AQ_SANITIZER} does not compile"
fi

# Prove the RULE, not just the file. A sanitiser that is present and does
# nothing is exactly as bad as one that is absent, and much harder to notice.
# Royce's own case is the fixture: one 4K screen asking for 125%.
aq_scale_fixture="$(mktemp -d)"
cat > "${aq_scale_fixture}/in.xml" << 'EOF'
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x><y>0</y><scale>1.25</scale><primary>yes</primary>
      <monitor>
        <monitorspec><connector>DP-1</connector></monitorspec>
        <mode><width>3840</width><height>2160</height><rate>59.997</rate></mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
EOF
if "${AQ_SANITIZER}" "${aq_scale_fixture}/in.xml" "${aq_scale_fixture}/out.xml" > /dev/null 2>&1 \
    && grep -q '<scale>1</scale>' "${aq_scale_fixture}/out.xml"; then
    ok "a 4K screen asking for 125% really does come out as 100%"
else
    bad "${AQ_SANITIZER} did not turn 125% into 100% — the black screen of 2026-09-05 could happen again"
fi
rm -rf "${aq_scale_fixture}"

# ------------------------------------------------------------------------------
# The self-healing guard
# ------------------------------------------------------------------------------
# The sanitiser removes the cause we THINK we found. This removes any cause at
# all: if no login screen has appeared 45 seconds into a boot, it takes the
# copied files away and restarts the login screen once. Its own header has the
# exact trigger and the three separate reasons it cannot loop.
say "The guard that rescues the login screen if it never appears"

AQ_GDM_GUARD="/usr/libexec/aquarius-gdm-guard"
chmod 0755 "${AQ_GDM_GUARD}"

if [ -x "${AQ_GDM_GUARD}" ]; then
    ok "$(basename "${AQ_GDM_GUARD}") is installed and executable"
else
    bad "${AQ_GDM_GUARD} is missing — a login screen that failed to draw would stay failed"
fi

if bash -n "${AQ_GDM_GUARD}"; then
    ok "it is valid shell"
else
    bad "${AQ_GDM_GUARD} does not parse as shell"
fi

aq_unit_is_on_from_usr aquarius-gdm-guard.service \
    "it watches every boot"

AQ_GUARD_UNIT="/usr/lib/systemd/system/aquarius-gdm-guard.service"

# ⚠️ After= AND NOT Requires=/Wants=. This service exists to rescue the login
# screen; a dependency the other way round would let a broken rescuer stop the
# thing it is meant to rescue. Checked as a string because it is the one line in
# the file that could turn a safety net into a hazard.
aq_file_has "${AQ_GUARD_UNIT}" '^After=display-manager\.service' \
    "the guard runs after the login screen is started, and never blocks it"
if grep -Eq '^(Requires|BindsTo|Requisite)=.*display-manager' "${AQ_GUARD_UNIT}"; then
    bad "${AQ_GUARD_UNIT} makes the login screen depend on the guard — the rescuer must never be able to stop the rescue"
else
    ok "the guard is not something the login screen depends on"
fi

# systemd's own opinion of the file. Advisory: inside a container it often
# cannot start a manager at all, and a confident tick over a tool that did
# nothing is worse than no tick, so which of the two happened is said out loud.
# Same treatment as build_files/75-aquarius-keys.sh — see the long note there.
if aq_have systemd-analyze; then
    aq_guard_verify="$(systemd-analyze verify "${AQ_GUARD_UNIT}" 2>&1 || true)"
    printf '%s\n' "${aq_guard_verify}" | sed 's/^/  /'
    if printf '%s' "${aq_guard_verify}" | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  NOTE: systemd-analyze could not start inside this container, so it did"
        echo "        not read the file. The line checks above are what guard this unit."
    elif printf '%s' "${aq_guard_verify}" | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of ${AQ_GUARD_UNIT} — a setting it cannot read does nothing, silently"
    else
        ok "systemd read the guard's service file and understood every line"
    fi
fi

# ------------------------------------------------------------------------------
# The logout half
# ------------------------------------------------------------------------------
# ⚠️ WE REPLACE A FILE THE gdm PACKAGE OWNS, AND HERE IS WHY THAT IS THE ONLY
# WAY TO DO IT.
#
# GDM runs exactly ONE script when a session ends: /etc/gdm/PostSession/Default
# (or one named after the display, which nothing here creates). It is not a
# folder of drop-ins — there is no way to add a step without editing that file.
# Appending to it does not work either: Fedora's copy is two lines and the
# second is `exit 0`, so anything added after it never runs.
#
# So we write our own, and we keep Fedora's out of harm's way at
# /usr/share/aquarius/gdm-PostSession-Default.orig so that the difference is a
# readable fact rather than a memory.
#
# THE ONE RULE THIS SCRIPT MUST OBEY: it must always succeed. GDM runs it while
# a person is logging out; a script that fails or hangs there is a machine that
# will not let go of a session.
say "The logout half of the login-screen size fix"

install -d -m 0755 /etc/gdm/PostSession
if [ -f /etc/gdm/PostSession/Default ]; then
    install -D -m 0755 /etc/gdm/PostSession/Default \
        /usr/share/aquarius/gdm-PostSession-Default.orig
    ok "Fedora's own PostSession script kept at /usr/share/aquarius/gdm-PostSession-Default.orig"
else
    echo "NOTE: this image had no /etc/gdm/PostSession/Default to keep."
fi

cat > /etc/gdm/PostSession/Default << 'EOF'
#!/bin/sh
# =============================================================================
# GDM runs this, as root, every time somebody logs out.
# =============================================================================
# AquariusOS replaced Fedora's copy of this file, which was two lines long and
# did nothing. The original is kept at
# /usr/share/aquarius/gdm-PostSession-Default.orig if you ever want to compare.
#
# ⚠️ BY DEFAULT THIS SCRIPT ALSO DOES NOTHING, and that is deliberate. It only
# has an effect on a machine where somebody has run `sudo aq login scale on`.
#
# WHY THE TEST IS HERE AND NOT ONLY INSIDE THE PROGRAM. On 2026-09-05 the bench
# black-screened a second time, and the file that did it was almost certainly
# written by THIS HOOK at the previous shutdown — the old version of it, from
# the old image, because an update's new /etc does not exist yet at the moment
# you log out of the old one. So the last thing a machine does before its first
# boot on a new image is run the OLD logout hook. The lesson: a hook that copies
# by default is a hook that copies once more after you have stopped wanting it
# to. This one copies only when asked.
#
# What it is for when it IS switched on: you change Scale in Settings >
# Displays, you log out, and this carries the answer across to the login screen
# you are about to be looking at, rather than making you reboot for it.
#
# THE RULE: this script must always finish, and always succeed. A logout that
# hangs or fails here is a computer that will not let go of your session, so
# every line is fenced with `|| true` and the last line is `exit 0`.
# =============================================================================
if [ -e /var/lib/aquarius/gdm-display-optin ] \
    && [ -x /usr/libexec/aquarius-gdm-display ]; then
    /usr/libexec/aquarius-gdm-display || true
fi

exit 0
EOF
chmod 0755 /etc/gdm/PostSession/Default

aq_file_has /etc/gdm/PostSession/Default '/usr/libexec/aquarius-gdm-display' \
    "the logout hook runs the login-screen size messenger"
# ⚠️ AND ONLY WHEN ASKED. An unguarded call here is how the bench got a second
# black screen: the OLD hook ran at the shutdown before the fix arrived.
aq_file_has /etc/gdm/PostSession/Default 'gdm-display-optin' \
    "the logout hook does nothing unless somebody switched the copy on"
aq_file_has /etc/gdm/PostSession/Default '^exit 0$' \
    "the logout hook always succeeds (a failing one would trap a session)"
if bash -n /etc/gdm/PostSession/Default; then
    ok "the logout hook is valid shell"
else
    bad "/etc/gdm/PostSession/Default does not parse as shell — every logout would print an error"
fi
if [ -x /etc/gdm/PostSession/Default ]; then
    ok "the logout hook is executable (GDM ignores it silently otherwise)"
else
    bad "/etc/gdm/PostSession/Default is not executable — GDM would skip it without a word"
fi

# ==============================================================================
# 5. The GNOME defaults
# ==============================================================================
# The three .gschema.override files copied in at the top of this script are what
# make a brand-new account come up as Ice-light AquariusOS instead of stock
# Fedora. Read the long header inside zz1-aquarius-10-look.gschema.override for
# what an override file is and why it is only a default that a user always beats.
#
# Two things have to happen and the second is the one people forget:
#
#   1. check the files name real settings with valid values
#   2. rebuild the settings index, or every one of them is ignored
say "The AquariusOS GNOME defaults"

echo "Override files in ${SCHEMA_DIR}:"
ls -l "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override

if ! aq_have glib-compile-schemas; then
    echo "AQUARIUS ERROR: glib-compile-schemas is not in this image (it belongs to" >&2
    echo "                the glib2 package), so the defaults cannot be applied." >&2
    exit 1
fi

# --strict rejects a setting name that does not exist, or a value of the wrong
# shape. It is run in a copy of the folder first, because --strict on the real
# folder would leave the index half-written if it failed.
#
# ⚠️ The *.enums.xml files have to be copied too. Some GNOME settings are
# "one of these words" and the list of words lives in a separate enums file; a
# strict compile without them fails on settings that are perfectly correct.
AQ_SCHEMA_TEST="$(mktemp -d)"
cp "${SCHEMA_DIR}"/*.gschema.xml "${AQ_SCHEMA_TEST}/"
cp "${SCHEMA_DIR}"/*.enums.xml "${AQ_SCHEMA_TEST}/" 2> /dev/null || true
cp "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override "${AQ_SCHEMA_TEST}/"
if ! glib-compile-schemas --strict "${AQ_SCHEMA_TEST}"; then
    echo "AQUARIUS ERROR: one of the AquariusOS override files is wrong." >&2
    echo "                Read the message above — it names the file, the setting" >&2
    echo "                and the problem. The usual cause is a misspelled setting" >&2
    echo "                name, or one this version of GNOME has renamed." >&2
    rm -rf "${AQ_SCHEMA_TEST}"
    exit 1
fi
rm -rf "${AQ_SCHEMA_TEST}"
ok "every override file names real settings with valid values"

rm -f "${SCHEMA_DIR}/gschemas.compiled"
glib-compile-schemas "${SCHEMA_DIR}"
if [ -s "${SCHEMA_DIR}/gschemas.compiled" ]; then
    ok "the settings index was rebuilt"
else
    bad "${SCHEMA_DIR}/gschemas.compiled was not written — every AquariusOS default would be ignored"
fi

# The real proof: ask GNOME what the settings ARE now, in this image. This is
# the "trust content, never timestamps" rule in its most literal form — the
# check does not look at our file at all, it asks the system the same question
# a freshly created user account will ask on first login.
#
# GSETTINGS_BACKEND=memory means "do not look for a running dconf daemon, just
# read the compiled defaults", which is the only thing that can work inside a
# build with no desktop session running.
say "Asking GNOME what the defaults are now"
if aq_have gsettings; then
    want() { # want <group> <setting> <expected>
        got="$(GSETTINGS_BACKEND=memory gsettings get "$1" "$2" 2> /dev/null || echo '<error>')"
        if [ "${got}" = "$3" ]; then
            ok "$1 $2 = ${got}"
        else
            bad "$1 $2 is ${got}, expected $3"
        fi
    }
    want org.gnome.desktop.interface color-scheme "'default'"
    want org.gnome.desktop.interface accent-color "'blue'"
    want org.gnome.desktop.interface font-name "'Inter 11'"
    want org.gnome.desktop.interface document-font-name "'Inter 11'"
    want org.gnome.desktop.interface monospace-font-name "'JetBrains Mono 10'"
    want org.gnome.desktop.background picture-options "'zoom'"
    want org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
    want org.gnome.shell.extensions.dash-to-dock dock-fixed "true"
    want org.gnome.shell.extensions.dash-to-dock intellihide "false"
    want org.gnome.shell.extensions.dash-to-dock extend-height "false"

    echo "  ---- for the log ----"
    GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri || true
    GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri-dark || true
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps || true
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell enabled-extensions || true

    # ----------------------------------------------------------------------
    # Every app pinned to the dock must actually be installed
    # ----------------------------------------------------------------------
    # A name in favorite-apps that does not match a real .desktop file is
    # silent: the icon simply does not appear. So the list is read back out of
    # GNOME and every entry is checked against the applications folder. This is
    # what keeps the dock honest as apps come and go between phases.
    #
    # ------------------------------------------------------------------------
    # ⚠️ THE ONE DELIBERATE EXCEPTION, ADDED 2026-09-04
    # ------------------------------------------------------------------------
    # Aquarius Editor is pinned to this dock and is NOT in this image. That is
    # not an oversight and it is not a hole in the check.
    #
    # It stopped being baked in on 2026-09-04 — it is four gigabytes, and it is
    # now offered in the app chooser and installed into each person's own home
    # folder. Its menu entry therefore lands in
    # ~/.local/share/applications/aquarius-editor.desktop, which does not exist
    # while this image is being built and never will.
    #
    # It stays pinned ON PURPOSE. A name GNOME cannot resolve is simply not
    # drawn — no gap, no dead square, no error — and the moment somebody
    # installs the app, the same name resolves in their own folder and the icon
    # appears in the place it has always belonged, with no logging out. Taking
    # it off this line would mean the flagship app arriving with no seat on the
    # dock, which is worse for everybody who does install it.
    #
    # The exception is named, not a wildcard, so a genuine typo in any other
    # name still fails the build exactly as it did before.
    AQ_FAV_FROM_HOME="aquarius-editor.desktop"
    say "Checking every app pinned to the dock is really installed"
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps \
        | tr -d "[]' " | tr ',' '\n' | grep -v '^$' > /tmp/aq-favorites.txt || true
    while read -r fav; do
        if [ -r "/usr/share/applications/${fav}" ]; then
            ok "dock: ${fav}"
        elif printf '%s\n' "${AQ_FAV_FROM_HOME}" | grep -qx "${fav}"; then
            ok "dock: ${fav} (installed into each person's home folder on request — see the note above)"
        else
            bad "dock: ${fav} is pinned but /usr/share/applications/${fav} does not exist — the icon would just be missing"
        fi
    done < /tmp/aq-favorites.txt
    rm -f /tmp/aq-favorites.txt

    # ----------------------------------------------------------------------
    # Every extension switched on must actually be installed
    # ----------------------------------------------------------------------
    # Same trap, same silence: GNOME simply does not load an extension it
    # cannot find, and says nothing.
    say "Checking every extension switched on is really installed"
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell enabled-extensions \
        | tr -d "[]' " | tr ',' '\n' | grep -v '^$' > /tmp/aq-extensions.txt || true
    while read -r ext; do
        if [ -r "/usr/share/gnome-shell/extensions/${ext}/metadata.json" ]; then
            ok "extension: ${ext}"
        else
            bad "extension: ${ext} is switched on but is not installed — GNOME would ignore it silently"
        fi
    done < /tmp/aq-extensions.txt
    rm -f /tmp/aq-extensions.txt
else
    bad "gsettings is not in this image, so the defaults could not be read back"
fi

# ==============================================================================
# 6. The wallpaper
# ==============================================================================
# "The Pour" ships in two colourways — Ice for the light appearance, Midnight
# for dark — and GNOME swaps between them by itself.
#
# Two separate things have to be true and it is easy to do one and forget the
# other:
#   * it is the wallpaper on a new machine   → the override file, checked above
#   * it is IN THE LIST in Settings          → the XML file, checked here
#
# The paths are written in both places, so they are compared rather than
# remembered: a rename that only updates one gives a desktop that comes up a
# flat colour, with no error.
say "The wallpaper"

for f in "${BACKGROUNDS_DIR}/the-pour-ice-3840x2160.png" \
    "${BACKGROUNDS_DIR}/the-pour-midnight-3840x2160.png"; do
    if [ -s "$f" ]; then
        ok "$(basename "$f") is installed ($(stat -c '%s' "$f") bytes)"
    else
        bad "$f is missing — the desktop would come up a flat colour"
    fi
done

for want in the-pour-ice-3840x2160.png the-pour-midnight-3840x2160.png; do
    aq_file_has "${SCHEMA_DIR}/zz1-aquarius-10-look.gschema.override" "${want}" \
        "the defaults point at ${want}"
    aq_file_has "${BACKGROUND_XML}" "${want}" \
        "Settings > Appearance lists ${want}"
done

# ==============================================================================
# 7. The "Make Editor-Ready" right-click menu
# ==============================================================================
# The ingest helper is the flagship creator feature of this operating system and
# it is worth saying why, because it looks like a small utility.
#
# Free DaVinci Resolve on Linux cannot open a file from a camera or a phone. Not
# "opens it badly" — cannot open it. H.264 and H.265 decoding is Studio-only and
# NVIDIA-only, and AAC audio is not supported at all, in any version. Every
# person who tries Resolve on Linux hits this on their first import and most of
# them conclude Linux is not for editing.
#
# `aq-ingest` fixes it at the operating-system level: it rewraps the audio to
# PCM and makes an edit-friendly video copy, so the file opens. Nobody else
# ships this. In R1 it is the command and the right-click menu; R3 makes it a
# proper service with the Resolve container behind it.
say "The ingest helper and its right-click menu"

if ! aq_have python3; then
    echo "AQUARIUS ERROR: this image has no python3, so aq-ingest cannot be installed." >&2
    exit 1
fi

AQ_PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
AQ_INGEST_SITE="/usr/lib/python${AQ_PYTHON_VERSION}/site-packages"
if ! python3 -c "import sys; sys.exit(0 if '${AQ_INGEST_SITE}' in sys.path else 1)"; then
    echo "AQUARIUS ERROR: ${AQ_INGEST_SITE} is not on this image's Python search path," >&2
    echo "                so installing there would produce a broken command. Python" >&2
    echo "                looks in:" >&2
    python3 -c "import sys; print('\n'.join('                  ' + p for p in sys.path if p))" >&2
    exit 1
fi

install -d -m 0755 "${AQ_INGEST_SITE}"
rm -rf "${AQ_INGEST_SITE:?}/aq_ingest"
cp -a /ctx/ingest/aq_ingest "${AQ_INGEST_SITE}/aq_ingest"
find "${AQ_INGEST_SITE}/aq_ingest" -name '__pycache__' -type d -prune -exec rm -rf {} +
python3 -m compileall -q "${AQ_INGEST_SITE}/aq_ingest"
install -D -m 0755 /ctx/ingest/aq-ingest /usr/bin/aq-ingest

# Actually run it. A Python package can install perfectly and fail to start
# because of one missing import, and this is the cheapest possible way to find
# that out here rather than on Royce's machine.
/usr/bin/aq-ingest --version
/usr/bin/aq-ingest --help > /dev/null
ok "aq-ingest runs"

# The Files right-click menu. nautilus-python loads any .py file in this folder
# and ignores, silently, any that does not compile — so it is compiled here.
#
# ⚠️ COMPILING IS NOT RUNNING, and on 2026-09-04 that difference cost a bench
# session: this file compiled perfectly and then stopped on its first line when
# Files actually ran it, so the menu item was missing with no error anywhere.
# The check that catches that kind of failure cannot live here — it needs the
# finished image — so it runs in .github/workflows/build.yml, in the step
# called "Check the 'Make Editor-Ready' menu really loads in Files". It loads
# this file the way Files does and insists on getting a menu item back for a
# video. Do not treat the compile below as proof the menu works.
if [ -r "${NAUTILUS_EXT}" ]; then
    ok "the 'Make Editor-Ready' menu item is installed"
    if python3 -m py_compile "${NAUTILUS_EXT}" 2> /dev/null; then
        ok "its code compiles — Files will load it"
    else
        bad "${NAUTILUS_EXT} does not compile — Files would ignore it silently"
    fi
    rm -rf "$(dirname "${NAUTILUS_EXT}")/__pycache__"
else
    bad "${NAUTILUS_EXT} is missing — there would be no right-click ingest"
fi

# aq-ingest is ffmpeg wearing a menu. Without these two it refuses to run.
for tool in ffmpeg ffprobe; do
    if aq_have "${tool}"; then
        ok "${tool} is present (aq-ingest needs it)"
    else
        bad "${tool} is missing — aq-ingest would refuse to run"
    fi
done

# ==============================================================================
# 8. Odds and ends
# ==============================================================================
say "The AquariusOS icon"
if [ -s "${LOGO_SVG}" ]; then
    ok "$(basename "${LOGO_SVG}") is installed"
else
    bad "${LOGO_SVG} is missing — os-release names it and the About page would be blank"
fi

# ------------------------------------------------------------------------------
# WHICH GTK THIS IMAGE ACTUALLY HAS
# ------------------------------------------------------------------------------
# The narrow exception at the top of this file — two properties of GTK CSS, in
# dark mode only — is written against GTK and libadwaita as they are IN THIS
# IMAGE, not as they were in whatever version somebody remembered. So the
# versions are printed here, into the build log, where a person looking at a
# window that came out the wrong colour six months from now can see exactly what
# the assumption was made against.
#
# It is a version READ-BACK, not a version requirement: nothing here pins GTK,
# and the two selectors used (`window` and `headerbar`) are the two most stable
# ones in GTK. This exists so that if they ever DO stop working, the log says
# what changed.
say "Which GTK the two-property dark-mode exception is written against"
for aq_pkg in gtk4 gtk3 libadwaita; do
    aq_ver="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' "${aq_pkg}" 2> /dev/null || true)"
    if [ -n "${aq_ver}" ]; then
        echo "  ${aq_pkg}: ${aq_ver}"
    else
        echo "  ${aq_pkg}: not installed"
    fi
done
if rpm -q gtk4 > /dev/null 2>&1 && rpm -q libadwaita > /dev/null 2>&1; then
    ok "GTK 4 and libadwaita are both here, which is what the dark-mode exception styles"
else
    bad "gtk4 or libadwaita is missing from this image — GNOME's own applications could not run, so something far bigger than the window colour is wrong"
fi

# Nothing in system_files/ should be writable by everybody: /usr is meant to be
# read-only and a world-writable file there is a security hole that `bootc
# container lint` will not catch.
say "Permissions on the files we shipped"
find /usr/share/aquarius /usr/share/backgrounds/aquarius \
    ! -type l -perm -o+w > /tmp/aq-world-writable.txt 2> /dev/null || true
if [ ! -s /tmp/aq-world-writable.txt ]; then
    ok "nothing we shipped is world-writable"
else
    bad "world-writable files under /usr:"
    sed 's/^/       /' /tmp/aq-world-writable.txt
fi
rm -f /tmp/aq-world-writable.txt

aq_finish "The AquariusOS desktop layer"
